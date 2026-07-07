import { IOSExploreStructuredError } from "./errors.js";
import { errorResult, jsonResult } from "./result.js";
import type { IOSExploreCaller } from "./toolRegistry.js";
import type { JSONObject, MCPToolResult, StructuredError } from "./types.js";

const topViewHierarchyOptionKeys = ["includeHidden", "detailLevel", "maxDepth", "accessibilityIdentifier", "accessibilityIdentifierPrefix"] as const;
const viewTargetsOptionKeys = [
  "includeHidden",
  "includeDisabled",
  "includeStaticText",
  "includeContainers",
  "maxDepth",
  "accessibilityIdentifier",
  "accessibilityIdentifierPrefix",
  "textLimit",
  "maxTargets"
] as const;

type RegistryLike = {
  refresh(): Promise<{ toolCount: number; conflicts: unknown[]; error?: unknown }>;
  tools(): unknown[];
  conflicts(): unknown[];
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
        return jsonResult(result as JSONObject);
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
        try {
          return jsonResult(await client.call(action, objectValue(input.data)));
        } catch (error) {
          const normalized = normalizeError(error);
          return resultForFailure(normalized);
        }
      }
    },
    observe: {
      name: "observe",
      description: "默认观察入口：调用 ui.viewTargets，返回 targets、navigationBar 与新的 viewSnapshotID；mode=topViewHierarchy 时返回完整层级树。",
      inputSchema: observeSchema(),
      handler: async input => {
        if (input.mode === "topViewHierarchy") {
          return jsonResult(await client.call("ui.topViewHierarchy", pickAllowedFields(input, topViewHierarchyOptionKeys)));
        }
        return jsonResult(await client.call("ui.viewTargets", pickAllowedFields(withoutKey(input, "mode"), viewTargetsOptionKeys)));
      }
    },
    wait_and_observe: {
      name: "wait_and_observe",
      description: "先调用 ui.waitAny，再调用 ui.viewTargets。wait_timeout 后仍尽量返回最新 observation。",
      inputSchema: waitAndObserveSchema(),
      handler: async input => {
        const viewTargetsOptions = pickAllowedFields(objectValue(input.viewTargetsOptions), viewTargetsOptionKeys);
        try {
          const wait = await client.call("ui.waitAny", withoutKey(input, "viewTargetsOptions"));
          const observation = await client.call("ui.viewTargets", viewTargetsOptions);
          return jsonResult({ wait, observation });
        } catch (error) {
          const normalized = normalizeError(error);
          if (normalized.source === "ios_envelope" && normalized.code === "wait_timeout") {
            const observation = await client.call("ui.viewTargets", viewTargetsOptions);
            return jsonResult({ wait: normalized, observation }, false);
          }
          return errorResult(normalized as StructuredError);
        }
      }
    }
  };
}

function observeSchema(): JSONObject {
  return {
    type: "object",
    properties: {
      mode: { type: "string", enum: ["viewTargets", "topViewHierarchy"], default: "viewTargets" },
      detailLevel: { type: "string", enum: ["basic", "appearance", "full"], description: "仅 mode=topViewHierarchy 时透传给 ui.topViewHierarchy。" },
      includeHidden: { type: "boolean", description: "mode=topViewHierarchy 时透传给 ui.topViewHierarchy；默认 viewTargets 模式下按 ui.viewTargets 原字段透传。" },
      maxDepth: { type: "integer", description: "mode=topViewHierarchy 时透传给 ui.topViewHierarchy；默认 viewTargets 模式下按 ui.viewTargets 原字段透传。" }
    }
  };
}

function waitAndObserveSchema(): JSONObject {
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
      viewTargetsOptions: {
        type: "object",
        description:
          "传给 ui.viewTargets 的可选参数。只能传 ui.viewTargets 真实字段（includeHidden / includeDisabled / includeStaticText / includeContainers / maxDepth / accessibilityIdentifier / accessibilityIdentifierPrefix / textLimit / maxTargets），不接受 ui.topViewHierarchy 专用的 detailLevel 或 ui.waitAny 专用的 conditions 等字段。",
        properties: {
          includeHidden: { type: "boolean" },
          includeDisabled: { type: "boolean" },
          includeStaticText: { type: "boolean" },
          includeContainers: { type: "boolean" },
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
