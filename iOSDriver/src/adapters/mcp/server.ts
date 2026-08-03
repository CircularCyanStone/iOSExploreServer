/**
 * iOSDriver 的 stdio MCP adapter：把 28 个静态工具暴露给 AI 客户端（Claude Code 等）。
 *
 * 分层：本模块只绑定 SDK 的 request/response（`tools/list`、`tools/call`）；工具目录
 * （toolCatalog）、runtime、能力探测、workflow 都通过 SDK 无关接口注入——测试可直接
 * 调用 handlers，不碰 stdio。
 *
 * **通道纪律**：stdout 被 `StdioServerTransport` 独占（MCP 协议帧走这里），所有
 * 生命周期日志必须写 stderr——任何一行普通日志混入 stdout 都会破坏 JSON-RPC 帧解析。
 *
 * 协议流程：initialize（握手）→ tools/list（静态目录，离线可用）→ tools/call
 * （deviceAction 直接转发 / hostOperation 先校验再执行）。
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

/** workflow 总预算中的固定调度余量（毫秒）：覆盖阶段切换与运行时开销。 */
const WORKFLOW_FIXED_MARGIN_MS = 5_000;
/** workflow 总预算中的 inspect 阶段余量（毫秒）：ui.inspect 的读取时间。 */
const WORKFLOW_INSPECT_BUDGET_MS = 5_000;

/** MCP server 自我介绍（initialize 响应的 serverInfo）；版本从 package.json 读取。 */
export const MCP_SERVER_INFO = Object.freeze({
  name: "iOSDriver",
  version: packageVersion()
});

/** MCP adapter 调用 DriverRuntime 所需的最小边界（只暴露 invoke）。 */
export interface MCPRuntime {
  /**
   * 调用一个 device action。
   *
   * @param action action 名（如 "ui.tap"）。
   * @param data 原始 JSON data（App 端负责字段校验）。
   * @param options 可选取消信号与已验证的 per-call 策略。
   * @returns runtime 统一结果（成功或分类失败）。
   */
  invoke(action: string, data?: JSONObject, options?: InvocationOptions): Promise<InvocationResult>;
}

/** MCP adapter 调用显式 capability 探针所需的最小边界。 */
export interface MCPCapabilityProbe {
  /** @returns health 模式的显式探针报告（MCP `health_check` 工具）。 */
  health(): Promise<CapabilityReport>;
  /** @returns capabilities 模式的显式探针报告（MCP `check_capabilities` 工具）。 */
  capabilities(): Promise<CapabilityReport>;
  /**
   * 读取最近一次可信 help 为 action 提供的策略（供动态 call_action 使用）。
   *
   * @param action action 名。
   * @returns 严格校验过的策略；未知/非法返回 undefined（runtime 按保守策略不自动重试）。
   */
  invocationPolicy(action: string): InvocationPolicy | undefined;
}

/** MCP adapter 调用 WorkflowRunner 所需的最小边界。 */
export interface MCPWorkflowRunner {
  /**
   * 在绝对截止时间内运行 workflow。
   *
   * @param operation workflow 名（wait_and_inspect/tap_and_inspect）。
   * @param input 已按 host contract 校验的输入。
   * @param options 所有阶段共享的总 deadline（绝对时间戳）。
   * @returns workflow 统一结果。
   */
  run(
    operation: WorkflowOperation,
    input: JSONObject,
    options: { readonly deadlineAtMs: number }
  ): Promise<InvocationResult>;
}

/** MCP adapter 的依赖；均为 SDK 无关接口（可注入 fake 测试）。 */
export interface MCPAdapterOptions {
  /** 所有 device action（含动态 call_action）的统一执行入口。 */
  readonly runtime: MCPRuntime;
  /** 只在显式 health/capabilities 或动态策略查询时访问。 */
  readonly capabilityProbe: MCPCapabilityProbe;
  /** 两个 host workflow 的总 deadline 执行入口。 */
  readonly workflowRunner: MCPWorkflowRunner;
  /** workflow 绝对 deadline 的时钟基准；测试可替换固定时间。 */
  readonly now?: () => number;
  /** MCP 生命周期与工具调用 logger；默认固定写 stderr。 */
  readonly logger?: HostLogger;
}

/**
 * 可直接绑定 SDK 或供单元测试调用的 MCP handlers（SDK 无关）。
 */
export interface MCPToolHandlers {
  /** @returns 不访问网络的固定 tools/list 响应（28 个工具）。 */
  listTools(): Promise<{ tools: Tool[] }>;
  /**
   * 调用一个固定 MCP 工具。
   *
   * @param name 历史工具名（如 "ui_tap"）。
   * @param args 工具参数（JSON 对象）。
   * @returns 渲染后的 MCP tool result（content + isError）。
   */
  callTool(name: string, args?: JSONObject): Promise<CallToolResult>;
}

/**
 * 创建静态 MCP handlers（SDK 无关）。
 *
 * 构造和 `listTools` 都**不会**执行 ping/help 或其他 runtime 调用——工具发现与
 * 设备状态完全解耦。`callTool` 对未知工具名返回稳定错误，对未预料的异常兜底返回
 * "unexpected"（不让 SDK 层看到原始异常）。
 *
 * @param options runtime、capability probe 与 workflow runner。
 * @returns 只处理 tools/list 与 tools/call 语义的 handlers。
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
 * 创建并启动 stdio MCP server（`iosdriver mcp` 命令的最终去向）。
 *
 * 绑定 SDK 的 `Server` 到 `StdioServerTransport`（stdin/stdout）；此后进程生命周期
 * 由 transport 持有——`connect` 完成后本函数返回，但进程会一直等 stdin 上的对话，
 * 直到客户端断开或 Ctrl-C。
 *
 * @param options runtime、capability probe 与 workflow runner。
 * @returns transport 连接完成后的 Promise（不表示进程结束）。
 * @throws 连接失败时抛出（上层记录日志）。
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

/**
 * 从随包发布的 package.json 读取 server 版本（避免源码常量与 npm version 漂移）。
 *
 * @returns 版本字符串（如 "1.0.0"）。
 * @throws {Error} manifest 缺失、非对象或版本非法时抛出（启动期暴露）。
 */
function packageVersion(): string {
  const manifest: unknown = createRequire(import.meta.url)("../../../package.json");
  if (typeof manifest !== "object" || manifest === null || !("version" in manifest)) {
    throw new Error("package.json 缺少 version");
  }
  const version = (manifest as { readonly version?: unknown }).version;
  if (typeof version !== "string" || version.length === 0) throw new Error("package.json version 必须是非空字符串");
  return version;
}

/**
 * 按目录项的映射执行一次工具调用，返回渲染后的 MCP 结果。
 *
 * 路由规则：
 * - kind="deviceAction"：直接 `runtime.invoke`（字段由 App typed input factory 校验，
 *   host 不重复解释 schema）；
 * - kind="hostOperation"：先在 Mac 侧按 generated host schema 校验包装层字段，
 *   再按 operation 分流：health/capabilities → probe；call_action → runtime +
 *   probe 缓存的策略；wait_and_inspect/tap_and_inspect → workflow runner（总 deadline）。
 *
 * @param entry 工具目录项。
 * @param input 客户端传入的原始参数。
 * @param options adapter 依赖。
 * @param now 时钟基准（计算 workflow deadline）。
 * @returns 渲染后的 MCP tool result。
 */
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

/** 把目录项转成 MCP SDK 的 Tool 对象（tools/list 响应元素）。 */
function toMCPTool(entry: ToolCatalogEntry): Tool {
  return {
    name: entry.name,
    description: entry.description,
    inputSchema: entry.inputSchema as Tool["inputSchema"]
  };
}

/**
 * 从 generated 默认值推导 workflow 的总 host 预算（毫秒）。
 *
 * 组成：业务等待（wait_and_inspect 的 timeoutMs，或 tap_and_inspect 的 stable 等待）
 * + 5 秒固定调度余量 + 5 秒 inspect 余量。这不是给每个子 action 各加一份预算——
 * runner 会把总值转换为所有阶段共享的**绝对 deadline**。
 *
 * @param operation workflow 名。
 * @param input 已校验的 workflow 输入。
 * @returns 总预算毫秒数。
 * @throws {Error} 生成的合同缺失或默认值缺失时抛出（编程错误，启动期暴露）。
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

/**
 * 取用户值或 generated 合同默认值（数字版）：用户值合法则优先，否则用合同默认。
 *
 * @param value 用户输入值（可能 undefined）。
 * @param defaultValue 合同 schema 中的 default。
 * @param field 字段名（仅用于错误信息）。
 * @returns 数字毫秒值。
 * @throws {Error} 两者都缺失或非法时抛出（合同默认值缺失 = 构建期错误）。
 */
function numberOrGeneratedDefault(value: unknown, defaultValue: unknown, field: string): number {
  if (typeof value === "number" && Number.isFinite(value) && value >= 0) return value;
  if (typeof defaultValue === "number") return defaultValue;
  throw new Error(`Generated workflow contract is missing numeric default for ${field}`);
}

/**
 * 取用户值或 generated 合同默认值（布尔版）：语义同 `numberOrGeneratedDefault`。
 *
 * @param value 用户输入值（可能 undefined）。
 * @param defaultValue 合同 schema 中的 default。
 * @param field 字段名（仅用于错误信息）。
 * @returns 布尔值。
 * @throws {Error} 两者都缺失时抛出。
 */
function booleanOrGeneratedDefault(value: unknown, defaultValue: unknown, field: string): boolean {
  if (typeof value === "boolean") return value;
  if (typeof defaultValue === "boolean") return defaultValue;
  throw new Error(`Generated workflow contract is missing boolean default for ${field}`);
}
