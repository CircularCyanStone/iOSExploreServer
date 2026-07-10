import { IOSExploreStructuredError } from "./errors.js";
import { errorResult, jsonResult } from "./result.js";
import type { IOSExploreCaller } from "./toolRegistry.js";
import type { JSONObject, MCPToolResult, StructuredError } from "./types.js";

// ui.inspect 合法可选字段（used for inspectOptions whitelist）。
// Task 3 已从 Swift inputSchema 删除 includeDisabled/includeStaticText/includeContainers，
// 此处同步移除，避免 pickAllowedFields 把 App 不认识的键透传过去。
const inspectOptionKeys = [
  "includeHidden",
  "maxDepth",
  "accessibilityIdentifier",
  "accessibilityIdentifierPrefix",
  "textLimit",
  "maxTargets"
] as const;

// ui.waitAny 合法字段（used for waitAny input whitelist）。
// 等同于 waitAndInspectSchema().properties 的顶层键名，
// 与 App 端 ui.waitAny inputSchema additionalProperties:false 保持一致。
const waitAnyKeys = [
  "conditions",
  "timeoutMs",
  "intervalMs",
  "stableMs",
  "includeHidden"
] as const;

type RegistryLike = {
  refresh(): Promise<{ toolCount: number; conflicts: unknown[]; error?: unknown }>;
  tools(): unknown[];
  conflicts(): unknown[];
  refreshError(): StructuredError | undefined;
};

type StaticTool = {
  name: string;
  description: string;
  inputSchema: JSONObject;
  handler(input: JSONObject): Promise<MCPToolResult>;
};

export function createStaticTools(options: { client: IOSExploreCaller; registry: RegistryLike }): Record<string, StaticTool> {
  const { client, registry } = options;
  return {
    health_check: {
      name: "health_check",
      description: "检查 Mac MCP server 是否能连到 iOSExplore App 的 ping/help。",
      inputSchema: { type: "object", properties: {} },
      handler: async () => {
        try {
          const ping = await client.call("ping");
          await client.call("help");
          return jsonResult({ ok: true, ping, dynamicToolCount: registry.tools().length, conflicts: registry.conflicts() });
        } catch (error) {
          return jsonResult({ ok: false, error: normalizeError(error), dynamicToolCount: registry.tools().length }, false);
        }
      }
    },
    refresh_tools: {
      name: "refresh_tools",
      description: "重新读取 iOSExplore help 输出并刷新动态 MCP tools。",
      inputSchema: { type: "object", properties: {} },
      handler: async () => {
        const result = await registry.refresh();
        // 与 health_check 对齐：统一用 dynamicToolCount 表达"动态工具数量"，
        // 不再混用 toolCount/dynamicToolCount 两套字段名（之前 health_check 用
        // dynamicToolCount 而 refresh_tools 返回 toolCount，调用方难以一致消费）。
        return jsonResult({
          dynamicToolCount: result.toolCount,
          conflicts: result.conflicts,
          ...(result.error ? { error: result.error } : {})
        });
      }
    },
    call_action: {
      name: "call_action",
      description: "兜底转发任意 iOSExplore action。优先使用固定工具或动态工具；排障时使用本工具。",
      inputSchema: {
        type: "object",
        properties: {
          action: { type: "string" },
          data: { type: "object" }
        },
        required: ["action"]
      },
      handler: async input => {
        const action = String(input.action ?? "");
        if (!action) {
          return errorResult({ source: "mcp_server" as const, code: "missing_action", message: "call_action requires an 'action' field" });
        }
        const data = objectValue(input.data);
        try {
          return jsonResult(await client.call(action, data));
        } catch (error) {
          // transport 失败做一次重试，仍失败就附上 healthCheck + nextSteps，
          // 与动态工具（server.ts:callTool）的 transport 错误模式对齐，
          // 让 Agent 在兜底工具上也能拿到相同的排障上下文（不再是裸的 connection_failed）。
          if (isTransportError(error)) {
            await sleep(200);
            try {
              return jsonResult(await client.call(action, data));
            } catch (retryError) {
              if (isTransportError(retryError)) {
                return errorResult(await enrichTransportError(retryError, client));
              }
              return resultForFailure(normalizeError(retryError));
            }
          }
          return resultForFailure(normalizeError(error));
        }
      }
    },
    wait_and_inspect: {
      name: "wait_and_inspect",
      description: "先调用 ui.waitAny，再调用 ui.inspect。wait_timeout 后仍尽量返回最新 observation。",
      inputSchema: waitAndInspectSchema(),
      handler: async input => {
        const inspectOptions = pickAllowedFields(objectValue(input.inspectOptions), inspectOptionKeys);
        try {
          const wait = await client.call("ui.waitAny", pickAllowedFields(input, waitAnyKeys));
          const observation = await client.call("ui.inspect", inspectOptions);
          return jsonResult({ wait, observation });
        } catch (error) {
          const normalized = normalizeError(error);
          if (normalized.source === "ios_envelope" && normalized.code === "wait_timeout") {
            const observation = await client.call("ui.inspect", inspectOptions);
            return jsonResult({ wait: normalized, observation }, false);
          }
          return errorResult(normalized as StructuredError);
        }
      }
    }
  };
}

function waitAndInspectSchema(): JSONObject {
  return {
    type: "object",
    properties: {
      conditions: {
        type: "array",
        minItems: 1,
        maxItems: 16,
        description: "每项必须包含 id/mode；targetExists/targetGone 需要 accessibilityIdentifier 或 path；textExists 需要 text；snapshotChanged 需要 viewSnapshotID；idle 无额外字段。"
      },
      timeoutMs: { type: "number" },
      intervalMs: { type: "number" },
      stableMs: { type: "number" },
      includeHidden: { type: "boolean" },
      inspectOptions: {
        type: "object",
        description:
          "传给 ui.inspect 的可选参数。只能传 ui.inspect 真实字段（includeHidden / maxDepth / accessibilityIdentifier / accessibilityIdentifierPrefix / textLimit / maxTargets），不接受 ui.topViewHierarchy 专用的 detailLevel 或 ui.waitAny 专用的 conditions 等字段。",
        properties: {
          includeHidden: { type: "boolean" },
          maxDepth: { type: "integer" },
          accessibilityIdentifier: { type: "string" },
          accessibilityIdentifierPrefix: { type: "string" },
          textLimit: { type: "integer" },
          maxTargets: { type: "integer" }
        },
        additionalProperties: false
      }
    },
    required: ["conditions"]
  };
}

function objectValue(value: unknown): JSONObject {
  return typeof value === "object" && value !== null && !Array.isArray(value) ? (value as JSONObject) : {};
}

function withoutKey(input: JSONObject, key: string): JSONObject {
  const copy: JSONObject = { ...input };
  delete copy[key];
  return copy;
}

function pickAllowedFields(input: JSONObject, keys: readonly string[]): JSONObject {
  const allowed = new Set(keys);
  return Object.fromEntries(Object.entries(input).filter(([key]) => allowed.has(key)));
}

function resultForFailure(error: StructuredError): MCPToolResult {
  // ios_envelope 来源的错误是 App 端的业务失败（如 unknown_action, alert_unavailable,
  // wait_timeout 等），属于正常的业务响应而非通信/系统错误。
  // 标记为 isError=false 避免 Agent 把"正常业务反馈"误判为"工具调用出错了"。
  if (error.source === "ios_envelope") {
    return jsonResult(error as unknown as JSONObject, false);
  }
  return errorResult(error);
}

function normalizeError(error: unknown): StructuredError {
  if (error instanceof IOSExploreStructuredError) {
    return error.toJSON();
  }
  // 有明确 source 的对象，保留原始 source（transport/http/ios_envelope），
  // 不全部覆盖为 ios_envelope。只在没有 source 时默认 ios_envelope。
  if (typeof error === "object" && error !== null && "source" in error && "code" in error) {
    const err = error as { source?: string; code: string; message?: string };
    if (err.source === "transport" || err.source === "http" || err.source === "ios_envelope") {
      return { source: err.source, code: err.code, message: err.message ?? String(error) } as StructuredError;
    }
    return { source: "ios_envelope" as const, code: err.code, message: err.message ?? String(error) };
  }
  return {
    source: "mcp_server" as const,
    code: "unexpected_error",
    message: error instanceof Error ? error.message : String(error)
  };
}

// transport 错误判定与 server.ts 中动态工具路径一致，避免兜底工具走另一套判定。
function isTransportError(error: unknown): error is IOSExploreStructuredError {
  return error instanceof IOSExploreStructuredError && error.source === "transport";
}

function sleep(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms));
}

// 与 server.ts 中 enrichTransportError 对齐：兜底工具的 transport 失败也带
// retry/healthCheck/nextSteps 三段排障上下文，调用方拿到的错误结构在不同入口上一致。
async function enrichTransportError(error: IOSExploreStructuredError, caller: IOSExploreCaller): Promise<StructuredError & JSONObject> {
  const normalized = error.toJSON();
  return {
    ...normalized,
    retry: { attempted: true, delayMs: 200, succeeded: false },
    healthCheck: await pingHealthCheck(caller),
    nextSteps: [
      "iOSExplore App 当前不可达；如果是真机调试，请确认 App 仍在运行、iproxy 仍在监听 38321，并用 XcodeBuildMCP launch_app_device 以 IOS_EXPLORE_AUTOSTART=1 重启后再试。"
    ]
  };
}

async function pingHealthCheck(caller: IOSExploreCaller): Promise<JSONObject> {
  try {
    return { ok: true, ping: await caller.call("ping") };
  } catch (error) {
    return { ok: false, error: normalizeError(error) };
  }
}
