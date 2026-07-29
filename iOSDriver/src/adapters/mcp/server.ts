/**
 * iOSDriver 的 stdio MCP adapter。
 *
 * 本模块只绑定 SDK request/response；工具目录、runtime、能力探测和 workflow 都通过
 * SDK 无关接口注入。stdout 由 `StdioServerTransport` 独占，所有生命周期日志必须写
 * stderr，否则任何普通日志都会破坏 MCP 帧。
 */
import { createRequire } from "node:module";
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
  type CallToolResult,
  type Tool
} from "@modelcontextprotocol/sdk/types.js";
import { HOST_OPERATION_SPECS } from "../../generated/hostOperationSpecs.js";
import type { CapabilityReport } from "../../runtime/capabilityProbe.js";
import type { InvocationOptions, InvocationPolicy } from "../../runtime/driverRuntime.js";
import type { InvocationResult } from "../../runtime/types.js";
import { defaultHostLogger, type HostLogger } from "../../runtime/hostLogger.js";
import {
  HostOperationInputValidationError,
  validateHostOperationInput
} from "../../runtime/hostOperationInput.js";
import type { JSONObject } from "../../types.js";
import type { WorkflowOperation } from "../../workflows/types.js";
import { renderAdapterError, renderInvocationResult, renderJSONData } from "./resultRenderer.js";
import { TOOL_CATALOG, type ToolCatalogEntry } from "./toolCatalog.js";

const WORKFLOW_FIXED_MARGIN_MS = 5_000;
const WORKFLOW_INSPECT_BUDGET_MS = 5_000;

export const MCP_SERVER_INFO = Object.freeze({
  name: "iOSDriver",
  version: packageVersion()
});

/** MCP adapter 调用 DriverRuntime 所需的最小边界。 */
export interface MCPRuntime {
  /**
   * 调用一个 device action。
   *
   * @param action action 名称。
   * @param data 原始 JSON data。
   * @param options 可选取消信号和已验证的 per-call 策略。
   * @returns runtime 统一结果。
   */
  invoke(action: string, data?: JSONObject, options?: InvocationOptions): Promise<InvocationResult>;
}

/** MCP adapter 调用显式 capability 探针所需的最小边界。 */
export interface MCPCapabilityProbe {
  /** @returns health 模式的显式探针报告。 */
  health(): Promise<CapabilityReport>;
  /** @returns capabilities 模式的显式探针报告。 */
  capabilities(): Promise<CapabilityReport>;
  /**
   * 读取最近一次合法 help 为 action 提供的策略。
   *
   * @param action action 名称。
   * @returns 严格校验过的策略；未知或非法 metadata 返回 undefined。
   */
  invocationPolicy(action: string): InvocationPolicy | undefined;
}

/** MCP adapter 调用 WorkflowRunner 所需的最小边界。 */
export interface MCPWorkflowRunner {
  /**
   * 在绝对截止时间内运行 workflow。
   *
   * @param operation workflow 名称。
   * @param input host contract 输入。
   * @param options 总 deadline。
   * @returns workflow 统一结果。
   */
  run(
    operation: WorkflowOperation,
    input: JSONObject,
    options: { readonly deadlineAtMs: number }
  ): Promise<InvocationResult>;
}

/** MCP adapter 的依赖；均为 SDK 无关 runtime/workflow 接口。 */
export interface MCPAdapterOptions {
  /** 所有 device action（含动态 call_action）的统一执行入口。 */
  readonly runtime: MCPRuntime;
  /** 只在显式 health/capabilities 或动态策略查询时访问。 */
  readonly capabilityProbe: MCPCapabilityProbe;
  /** 两个 host workflow 的总 deadline 执行入口。 */
  readonly workflowRunner: MCPWorkflowRunner;
  /** workflow 绝对 deadline 的时钟基准，测试可替换。 */
  readonly now?: () => number;
  /** MCP 生命周期与工具调用 logger；默认固定写 stderr。 */
  readonly logger?: HostLogger;
}

/** 可直接绑定 SDK 或供单元测试调用的 MCP handlers。 */
export interface MCPToolHandlers {
  /** @returns 不访问网络的固定 tools/list 响应。 */
  listTools(): Promise<{ tools: Tool[] }>;
  /**
   * 调用一个固定 MCP 工具。
   *
   * @param name 历史工具名。
   * @param args 工具参数。
   * @returns 渲染后的 MCP tool result。
   */
  callTool(name: string, args?: JSONObject): Promise<CallToolResult>;
}

/**
 * 创建静态 MCP handlers；构造和 listTools 都不会执行 ping/help 或其他 runtime 调用。
 *
 * @param options runtime、capability probe 与 workflow runner。
 * @returns 只处理 tools/list 和 tools/call 语义的 handlers。
 */
export function createMCPToolHandlers(options: MCPAdapterOptions): MCPToolHandlers {
  const entries = new Map(TOOL_CATALOG.map(entry => [entry.name, entry] as const));
  const now = options.now ?? Date.now;
  const logger = options.logger ?? defaultHostLogger;
  return {
    async listTools() {
      // listTools 只读取进程内目录；设备离线、App 未启动时仍返回相同集合。
      return { tools: TOOL_CATALOG.map(toMCPTool) };
    },
    async callTool(name: string, args: JSONObject = {}) {
      logger.emit("info", "mcp.tool.start", { tool: name });
      const entry = entries.get(name);
      if (entry === undefined) {
        logger.emit("warn", "mcp.tool.complete", { tool: name, outcome: "failure", code: "unknown_tool" });
        return renderAdapterError("unknown_tool", "Unknown MCP tool");
      }
      try {
        const result = await invokeEntry(entry, args, options, now);
        logger.emit(result.isError === true ? "warn" : "info", "mcp.tool.complete", {
          tool: name,
          outcome: result.isError === true ? "failure" : "success"
        });
        return result;
      } catch (error) {
        logger.emit("error", "mcp.tool.unexpected", {
          tool: name,
          errorType: error instanceof Error ? error.name : typeof error
        });
        return renderAdapterError("unexpected", "Unexpected host error");
      }
    }
  };
}

/**
 * 创建并启动 stdio MCP server。
 *
 * @param options runtime、capability probe 与 workflow runner。
 * @returns server transport 连接完成后的 Promise。
 */
export async function startMCPStdioServer(options: MCPAdapterOptions): Promise<void> {
  const logger = options.logger ?? defaultHostLogger;
  logger.emit("info", "mcp.server.start", { transport: "stdio" });
  const server = new Server(
    MCP_SERVER_INFO,
    { capabilities: { tools: {} } }
  );
  const handlers = createMCPToolHandlers(options);

  server.setRequestHandler(ListToolsRequestSchema, async () => handlers.listTools());
  server.setRequestHandler(CallToolRequestSchema, async request => {
    const args = (request.params.arguments ?? {}) as JSONObject;
    return handlers.callTool(request.params.name, args);
  });

  try {
    await server.connect(new StdioServerTransport());
    logger.emit("info", "mcp.server.connected", { transport: "stdio" });
  } catch (error) {
    logger.emit("error", "mcp.server.unexpected", {
      transport: "stdio",
      errorType: error instanceof Error ? error.name : typeof error
    });
    throw error;
  }
}

/** 从随包发布的 manifest 读取 server 版本，避免源码常量与 npm version 漂移。 */
function packageVersion(): string {
  const manifest: unknown = createRequire(import.meta.url)("../../../package.json");
  if (typeof manifest !== "object" || manifest === null || !("version" in manifest)) {
    throw new Error("package.json 缺少 version");
  }
  const version = (manifest as { readonly version?: unknown }).version;
  if (typeof version !== "string" || version.length === 0) throw new Error("package.json version 必须是非空字符串");
  return version;
}

async function invokeEntry(
  entry: ToolCatalogEntry,
  input: JSONObject,
  options: MCPAdapterOptions,
  now: () => number
): Promise<CallToolResult> {
  // device action 的字段由 App typed input factory 校验，host 不重复解释 schema。
  if (entry.mapping.kind === "deviceAction") {
    return renderInvocationResult(
      await options.runtime.invoke(entry.mapping.action, input),
      "deviceAction"
    );
  }

  // host operation 在 Mac 上执行，必须先按 generated host schema 校验包装层字段。
  let validatedInput: JSONObject;
  try {
    validatedInput = validateHostOperationInput(entry.mapping.operation, input);
  } catch (error) {
    if (error instanceof HostOperationInputValidationError) {
      return renderAdapterError("invalid_data", error.message);
    }
    throw error;
  }
  if (entry.mapping.operation === "call_action" && (validatedInput.action as string).length === 0) {
    return renderAdapterError("invalid_data", "call_action requires a non-empty action field");
  }

  switch (entry.mapping.operation) {
    case "health":
      return renderJSONData(await options.capabilityProbe.health() as unknown as JSONObject);
    case "capabilities":
      return renderJSONData(await options.capabilityProbe.capabilities() as unknown as JSONObject);
    case "call_action": {
      const action = validatedInput.action as string;
      const data = (validatedInput.data ?? {}) as JSONObject;
      // 只使用最近一次可信 help 的策略；没有策略时 runtime 对未知 action 不做自动重试。
      const policy = options.capabilityProbe.invocationPolicy(action);
      return renderInvocationResult(
        await options.runtime.invoke(action, data, policy === undefined ? {} : { policy }),
        "callAction"
      );
    }
    case "wait_and_inspect":
    case "tap_and_inspect":
      return renderInvocationResult(
        await options.workflowRunner.run(entry.mapping.operation, validatedInput, {
          deadlineAtMs: now() + workflowBudgetMs(entry.mapping.operation, validatedInput)
        }),
        "workflow"
      );
  }
}

function toMCPTool(entry: ToolCatalogEntry): Tool {
  return {
    name: entry.name,
    description: entry.description,
    inputSchema: entry.inputSchema as Tool["inputSchema"]
  };
}

/**
 * 从 generated 默认值推导 workflow 的总 host 预算。
 *
 * 业务等待之外固定预留 5 秒调度余量和 5 秒 inspect 余量；这不是给每个子 action 各加
 * 一份预算，runner 会把总值转换为所有阶段共享的绝对 deadline。
 */
function workflowBudgetMs(operation: WorkflowOperation, input: JSONObject): number {
  const spec = HOST_OPERATION_SPECS.find(candidate => candidate.operation === operation);
  if (spec === undefined) throw new Error(`Missing generated workflow contract: ${operation}`);
  const schema = spec.inputSchema as unknown as {
    readonly properties: Readonly<Record<string, { readonly default?: unknown }>>;
  };
  if (operation === "wait_and_inspect") {
    const businessTimeoutMs = numberOrGeneratedDefault(input.timeoutMs, schema.properties.timeoutMs?.default, "timeoutMs");
    return businessTimeoutMs + WORKFLOW_FIXED_MARGIN_MS + WORKFLOW_INSPECT_BUDGET_MS;
  }
  const stableTimeMs = numberOrGeneratedDefault(input.stableTimeMs, schema.properties.stableTimeMs?.default, "stableTimeMs");
  const waitForStable = booleanOrGeneratedDefault(input.waitForStable, schema.properties.waitForStable?.default, "waitForStable");
  const stableWaitBudgetMs = waitForStable ? stableTimeMs + 1_000 : 0;
  return stableWaitBudgetMs + WORKFLOW_FIXED_MARGIN_MS + WORKFLOW_INSPECT_BUDGET_MS;
}

function numberOrGeneratedDefault(value: unknown, defaultValue: unknown, field: string): number {
  if (typeof value === "number" && Number.isFinite(value) && value >= 0) return value;
  if (typeof defaultValue === "number") return defaultValue;
  throw new Error(`Generated workflow contract is missing numeric default for ${field}`);
}

function booleanOrGeneratedDefault(value: unknown, defaultValue: unknown, field: string): boolean {
  if (typeof value === "boolean") return value;
  if (typeof defaultValue === "boolean") return defaultValue;
  throw new Error(`Generated workflow contract is missing boolean default for ${field}`);
}
