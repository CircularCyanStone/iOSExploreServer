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

// ToolRegistry 用这份清单排除与静态桥接同名的动态工具。名称与实现放在同一模块，
// 避免新增静态工具后漏改启动入口，导致 listTools 暴露重名工具。
export const STATIC_TOOL_NAMES = [
  "health_check",
  "refresh_tools",
  "call_action",
  "app_logs_mark",
  "app_logs_read",
  "ui_inspect",
  "ui_input",
  "ui_tap",
  "ui_control_sendAction",
  "ui_keyboard_dismiss",
  "ui_scrollToElement",
  "wait_and_inspect",
  "ui_wait",
  "ui_tap_and_inspect"
] as const;

export function createStaticTools(options: { client: IOSExploreCaller; registry: RegistryLike }): Record<string, StaticTool> {
  const { client, registry } = options;
  const forwardActionTool = (toolName: string, action: string, description: string, inputSchema: JSONObject): StaticTool => ({
    name: toolName,
    description: `${description}\n\nStatic bridge for iOSExplore action: ${action}`,
    inputSchema,
    handler: async input => {
      try {
        return jsonResult(await client.call(action, input));
      } catch (error) {
        return resultForFailure(normalizeError(error));
      }
    }
  });

  return {
    health_check: {
      name: "health_check",
      description: "检查 Mac MCP server 是否能连到 iOSExplore App 的 ping/help。自动加载动态工具。",
      inputSchema: { type: "object", properties: {} },
      handler: async () => {
        try {
          const ping = await client.call("ping");
          const refresh = await registry.refresh();
          if (refresh.error) {
            return jsonResult({
              ok: false,
              ping,
              error: refresh.error,
              dynamicToolCount: registry.tools().length,
              conflicts: registry.conflicts()
            }, false);
          }
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
    app_logs_mark: forwardActionTool(
      "app_logs_mark",
      "app.logs.mark",
      "建立当前 App 进程日志检查点。返回 cursor 与各日志来源的 capture 状态；后续 app_logs_read 应把 cursor 作为 after 传入。",
      emptyObjectSchema()
    ),
    app_logs_read: forwardActionTool(
      "app_logs_read",
      "app.logs.read",
      "读取当前 App 进程内日志。增量验证应传入 app_logs_mark 或上一次读取返回的 cursor，并先检查 capture 状态再判断日志是否发生。",
      appLogsReadSchema()
    ),
    ui_inspect: forwardActionTool(
      "ui_inspect",
      "ui.inspect",
      "读取当前 UI 结构并签发 viewSnapshotID。用于工具面板未暴露动态 ui_inspect 时的稳定入口。",
      uiInspectSchema()
    ),
    ui_input: forwardActionTool(
      "ui_input",
      "ui.input",
      "按顺序向多个 UITextField / UITextView / UISearchTextField 注入文本。顶层传 fields 数组，单字段输入也必须放进数组；stopOnFailure 默认 true，只有需要 Return / Done / Search / 结束编辑语义时才显式把单项 submit 设为 true。",
      uiInputSchema()
    ),
    ui_tap: forwardActionTool(
      "ui_tap",
      "ui.tap",
      "点击 ui.inspect 签发的可操作目标。通常需要 accessibilityIdentifier 或 path，并传入 viewSnapshotID。",
      uiTapSchema()
    ),
    ui_control_sendAction: forwardActionTool(
      "ui_control_sendAction",
      "ui.control.sendAction",
      "向 UIControl 发送真实 target-action 事件，如 valueChanged。",
      uiControlSendActionSchema()
    ),
    ui_keyboard_dismiss: forwardActionTool(
      "ui_keyboard_dismiss",
      "ui.keyboard.dismiss",
      "收起当前键盘或结束编辑状态。仅在目标被键盘遮挡、业务依赖结束编辑、或任务本身验证键盘状态时使用。",
      uiKeyboardDismissSchema()
    ),
    ui_scrollToElement: forwardActionTool(
      "ui_scrollToElement",
      "ui.scrollToElement",
      "把匹配文本或 accessibilityIdentifier 的元素滚动到可见区域。滚动后必须重新 ui_inspect。",
      uiScrollToElementSchema()
    ),
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
    },
    ui_wait: {
      name: "ui_wait",
      description: "等待 UI 稳定或等待目标/文本/快照变化",
      inputSchema: uiWaitSchema(),
      handler: async input => {
        try {
          return jsonResult(await client.call("ui.wait", input));
        } catch (error) {
          return resultForFailure(normalizeError(error));
        }
      }
    },
    ui_tap_and_inspect: {
      name: "ui_tap_and_inspect",
      description: "点击元素后自动检查 UI 状态。组合 ui.tap + ui.wait + ui.inspect，减少 Agent 推理次数。95% 的点击场景需要检查结果，建议优先使用此工具。",
      inputSchema: uiTapAndInspectSchema(),
      handler: async input => {
        const startTime = Date.now();
        const tapParams = pickAllowedFields(input, ["accessibilityIdentifier", "path", "viewSnapshotID"]);
        const waitForStable = input.waitForStable !== false; // default true
        const stableTimeMs = typeof input.stableTimeMs === "number" ? input.stableTimeMs : 300;
        const inspectDepth = typeof input.inspectDepth === "number" ? input.inspectDepth : 2;
        const inspectMaxTargets = typeof input.inspectMaxTargets === "number" ? input.inspectMaxTargets : 20;

        const timing: { tapMs: number; waitMs?: number; inspectMs: number; totalMs: number } = {
          tapMs: 0,
          inspectMs: 0,
          totalMs: 0
        };

        try {
          // Step 1: Execute tap
          const tapStart = Date.now();
          const tapResult = await client.call("ui.tap", tapParams);
          timing.tapMs = Date.now() - tapStart;

          // Step 2: Wait for UI to stabilize (if requested)
          if (waitForStable) {
            const waitStart = Date.now();
            try {
              await client.call("ui.wait", { mode: "idle", stableMs: stableTimeMs, timeoutMs: stableTimeMs + 1000 });
              timing.waitMs = Date.now() - waitStart;
            } catch (waitError) {
              // If wait times out, continue to inspect anyway
              timing.waitMs = Date.now() - waitStart;
            }
          }

          // Step 3: Inspect current UI state
          const inspectStart = Date.now();
          const inspectResult = await client.call("ui.inspect", {
            maxDepth: inspectDepth,
            maxTargets: inspectMaxTargets
          });
          timing.inspectMs = Date.now() - inspectStart;
          timing.totalMs = Date.now() - startTime;

          return jsonResult({
            tap: tapResult,
            stateAfter: inspectResult,
            timing
          });
        } catch (error) {
          // If tap fails, return error immediately without continuing
          const normalized = normalizeError(error);
          timing.totalMs = Date.now() - startTime;
          return errorResult({ ...normalized, timing } as StructuredError);
        }
      }
    }
  };
}

function emptyObjectSchema(): JSONObject {
  return {
    type: "object",
    properties: {},
    additionalProperties: false
  };
}

function appLogsReadSchema(): JSONObject {
  return {
    type: "object",
    properties: {
      after: {
        type: ["object", "null"],
        description: "增量读取起点 cursor；使用 app_logs_mark 或上一次 app_logs_read 返回的 cursor。",
        properties: {
          captureSessionID: { type: "string" },
          id: { type: "integer", minimum: 0 }
        },
        required: ["captureSessionID", "id"],
        additionalProperties: false
      },
      limit: {
        type: "integer",
        minimum: 1,
        maximum: 500,
        default: 100,
        description: "本次最多返回的日志条数。"
      },
      sources: {
        type: ["array", "null"],
        items: { type: "string", enum: ["explore", "bridge", "stdout", "stderr", "nslog", "oslog"] },
        uniqueItems: true,
        description: "日志来源过滤；省略表示读取全部来源。"
      },
      minimumLevel: {
        type: ["string", "null"],
        enum: ["debug", "info", "error", "fault", "unknown"],
        description: "最低日志等级过滤。"
      }
    },
    additionalProperties: false
  };
}

function uiInspectSchema(): JSONObject {
  return {
    type: "object",
    properties: {
      includeHidden: { type: "boolean" },
      maxDepth: { type: "integer", minimum: 0, maximum: 20 },
      accessibilityIdentifier: { type: "string" },
      accessibilityIdentifierPrefix: { type: "string" },
      textLimit: { type: "integer", minimum: 0, maximum: 1000 },
      maxTargets: { type: "integer", minimum: 1, maximum: 2048 },
      maxVisitedNodes: { type: "integer", minimum: 1, maximum: 20000 }
    }
  };
}

function uiInputSchema(): JSONObject {
  const fieldSchema = {
    type: "object",
    properties: {
      accessibilityIdentifier: {
        type: "string",
        description: "按 accessibilityIdentifier 精确定位目标 view；与 path 二选一。"
      },
      path: {
        type: "string",
        description: "按 ui.inspect 返回的只读路径定位目标 view；与 accessibilityIdentifier 二选一。"
      },
      text: {
        type: "string",
        description: "要注入的文本内容，不是 value 或 input。"
      },
      mode: { type: "string", enum: ["replace", "append"] },
      submit: {
        type: "boolean",
        description: "是否触发 Return / Done / Search / 结束编辑语义；批量输入默认显式传 false。"
      }
    },
    required: ["text"],
    additionalProperties: false
  };

  return {
    type: "object",
    properties: {
      viewSnapshotID: { type: "string" },
      stopOnFailure: {
        type: "boolean",
        description: "某个字段失败后是否停止执行后续字段；默认 true。"
      },
      fields: {
        type: "array",
        minItems: 1,
        maxItems: 16,
        items: fieldSchema,
        description: "按顺序执行的字段数组；单字段输入也必须放进数组。"
      }
    },
    required: ["fields"]
  };
}

function uiTapSchema(): JSONObject {
  return {
    type: "object",
    properties: {
      accessibilityIdentifier: { type: "string" },
      path: { type: "string" },
      viewSnapshotID: { type: "string" }
    },
    required: ["viewSnapshotID"]
  };
}

function uiControlSendActionSchema(): JSONObject {
  return {
    type: "object",
    properties: {
      accessibilityIdentifier: { type: "string" },
      path: { type: "string" },
      viewSnapshotID: { type: "string" },
      event: {
        type: "string",
        enum: ["touchUpInside", "valueChanged", "editingChanged", "editingDidBegin", "editingDidEnd"]
      },
      value: {
        description: "控件值。UISlider 用 0.0...1.0，UISegmentedControl 用索引，UISwitch/UIStepper 通常不传。"
      }
    },
    required: ["event", "viewSnapshotID"]
  };
}

function uiKeyboardDismissSchema(): JSONObject {
  return {
    type: "object",
    properties: {
      strategy: { type: "string", enum: ["auto", "endEditing", "resignFirstResponder"] },
      waitAfterMs: { type: "integer", minimum: 0, maximum: 1500 }
    }
  };
}

function uiScrollToElementSchema(): JSONObject {
  return {
    type: "object",
    properties: {
      match: { type: "string", enum: ["text", "accessibilityIdentifier"] },
      value: { type: "string", description: "要滚动到的文本片段或 accessibilityIdentifier。" },
      containerAccessibilityIdentifier: { type: "string" },
      containerPath: { type: "string" },
      direction: { type: "string", enum: ["up", "down"] },
      maxScrolls: { type: "integer", minimum: 1, maximum: 50 },
      includeHidden: { type: "boolean" }
    },
    required: ["match", "value"]
  };
}

function waitAndInspectSchema(): JSONObject {
  const waitConditionSchema = {
    type: "object",
    properties: {
      id: {
        type: "string",
        description: "条件标识,用于从 matchedID 判断命中的是哪条成功或失败判据。"
      },
      mode: {
        type: "string",
        enum: ["idle", "targetExists", "targetGone", "textExists", "snapshotChanged"],
        description: "等待模式。targetExists/targetGone 需要 accessibilityIdentifier 或 path；textExists 需要 text；snapshotChanged 需要 viewSnapshotID；idle 无额外字段。"
      },
      accessibilityIdentifier: {
        type: "string",
        description: "targetExists/targetGone 模式按 accessibilityIdentifier 精确定位目标 view。"
      },
      path: {
        type: "string",
        description: "targetExists/targetGone 模式按 ui.inspect 返回的 root/0/1 路径定位目标 view。"
      },
      text: {
        type: "string",
        description: "textExists 模式要等待的文本片段。"
      },
      viewSnapshotID: {
        type: "string",
        description: "snapshotChanged 模式参照的 viewSnapshotID。"
      }
    },
    required: ["id", "mode"],
    additionalProperties: false
  };

  return {
    type: "object",
    properties: {
      conditions: {
        type: "array",
        minItems: 1,
        maxItems: 16,
        items: waitConditionSchema,
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

function uiWaitSchema(): JSONObject {
  return {
    type: "object",
    properties: {
      mode: {
        type: "string",
        enum: ["idle", "targetExists", "targetGone", "textExists", "snapshotChanged"],
        description: "等待模式: idle / targetExists / targetGone / textExists / snapshotChanged"
      },
      timeoutMs: {
        type: "integer",
        minimum: 0,
        maximum: 30000,
        description: "业务超时毫秒数, 范围 0...30000, 默认 3000"
      },
      intervalMs: {
        type: "integer",
        minimum: 50,
        maximum: 5000,
        description: "轮询间隔毫秒数, 范围 50...5000, 默认 100"
      },
      stableMs: {
        type: "integer",
        minimum: 0,
        maximum: 10000,
        description: "idle 模式下连续稳定的毫秒数, 范围 0...10000, 默认 300"
      },
      text: {
        type: "string",
        description: "textExists 模式要等待的文本片段"
      },
      viewSnapshotID: {
        type: "string",
        description: "snapshotChanged 模式参照的 viewSnapshotID (由 ui.inspect 签发)"
      },
      accessibilityIdentifier: {
        type: "string",
        description: "targetExists/targetGone 模式: 按 accessibilityIdentifier 精确定位目标 view"
      },
      path: {
        type: "string",
        description: "targetExists/targetGone 模式: 按 ui.inspect 或 ui.topViewHierarchy 返回的 root/0/1 路径定位目标 view"
      },
      includeHidden: {
        type: "boolean",
        description: "idle/textExists/targetExists/targetGone 是否考虑隐藏 view, 默认 false"
      }
    }
  };
}

function uiTapAndInspectSchema(): JSONObject {
  return {
    type: "object",
    properties: {
      accessibilityIdentifier: {
        type: "string",
        description: "按 accessibilityIdentifier 精确定位目标 view。与 path 二选一（互斥）：两字段中有且仅提供一个"
      },
      path: {
        type: "string",
        description: "按 ui.inspect 或 ui.topViewHierarchy 返回的 root/0/1 路径定位目标 view。与 accessibilityIdentifier 二选一（互斥）：两字段中有且仅提供一个"
      },
      viewSnapshotID: {
        type: "string",
        description: "ui.inspect 签发的结构化 target 指纹快照标识"
      },
      waitForStable: {
        type: "boolean",
        description: "是否等待 UI 稳定后再 inspect，默认 true"
      },
      stableTimeMs: {
        type: "integer",
        minimum: 0,
        maximum: 3000,
        description: "等待 UI 稳定的时长（毫秒），默认 300"
      },
      inspectDepth: {
        type: "integer",
        minimum: 0,
        maximum: 10,
        description: "inspect 的最大递归深度，默认 2"
      },
      inspectMaxTargets: {
        type: "integer",
        minimum: 1,
        maximum: 512,
        description: "inspect 返回的最大目标数量，默认 20"
      }
    },
    required: ["viewSnapshotID"]
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
  if (error.source === "ios_envelope") {
    // call_action 的 unknown_action 保持 isError=false（兜底工具本就让 agent 猜 action 名）；
    // invalid_data / stale_locator 升格为 isError=true（参数错误、snapshot 过期）；
    // 其它 ios_envelope code（wait_timeout / alert_unavailable 等）保持 isError=false。
    const errorCodes = ["invalid_data", "stale_locator"];
    if (error.code && errorCodes.includes(error.code)) {
      return errorResult(error);
    }
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
