import { IOSExploreStructuredError } from "./errors.js";
import { errorResult, jsonResult } from "./result.js";
import type { IOSExploreCaller, JSONObject, MCPToolResult, StructuredError } from "./types.js";

// ui.inspect 合法可选字段，用于过滤组合工具的 inspectOptions。
// 这里只保留 Swift inputSchema 当前声明的字段，避免把 App 不认识的键透传过去。
const inspectOptionKeys = [
  "includeHidden",
  "maxDepth",
  "accessibilityIdentifier",
  "accessibilityIdentifierPrefix",
  "textLimit",
  "maxTargets",
  "maxVisitedNodes"
] as const;

// ui.waitAny 合法字段，用于过滤组合工具的等待参数。
// 等同于 waitAndInspectSchema().properties 中除 inspectOptions 外的顶层键名，
// 与 App 端 ui.waitAny inputSchema additionalProperties:false 保持一致。
const waitAnyKeys = [
  "conditions",
  "timeoutMs",
  "intervalMs",
  "stableMs",
  "includeHidden"
] as const;

type StaticTool = {
  name: string;
  description: string;
  inputSchema: JSONObject;
  handler(input: JSONObject): Promise<MCPToolResult>;
};

/** 稳定公共 action 与 iOSDriver 自身能力的唯一静态工具清单。 */
export const STATIC_TOOL_NAMES = [
  "health_check",
  "check_capabilities",
  "call_action",
  "app_logs_mark",
  "app_logs_read",
  "ui_topViewHierarchy",
  "ui_inspect",
  "ui_control_sendAction",
  "ui_input",
  "ui_tap",
  "ui_screenshot",
  "ui_keyboard_dismiss",
  "ui_scroll",
  "ui_navigation_back",
  "ui_navigation_tapBarButton",
  "ui_waitAny",
  "ui_scrollToElement",
  "ui_alert_respond",
  "ui_controllers",
  "ui_swipe",
  "ui_longPress",
  "ui_tabBar_selectTab",
  "ui_datePicker_setDate",
  "ui_picker_selectRow",
  "ui_webView_eval",
  "wait_and_inspect",
  "ui_wait",
  "ui_tap_and_inspect"
] as const;

/** 静态 MCP 工具到稳定公共 App action 的唯一映射。 */
export const STATIC_ACTIONS = {
  ui_topViewHierarchy: "ui.topViewHierarchy",
  ui_inspect: "ui.inspect",
  ui_control_sendAction: "ui.control.sendAction",
  ui_tap: "ui.tap",
  ui_screenshot: "ui.screenshot",
  ui_input: "ui.input",
  ui_keyboard_dismiss: "ui.keyboard.dismiss",
  ui_scroll: "ui.scroll",
  ui_navigation_back: "ui.navigation.back",
  ui_navigation_tapBarButton: "ui.navigation.tapBarButton",
  ui_wait: "ui.wait",
  ui_waitAny: "ui.waitAny",
  ui_scrollToElement: "ui.scrollToElement",
  ui_alert_respond: "ui.alert.respond",
  ui_controllers: "ui.controllers",
  ui_swipe: "ui.swipe",
  ui_longPress: "ui.longPress",
  ui_tabBar_selectTab: "ui.tabBar.selectTab",
  ui_datePicker_setDate: "ui.datePicker.setDate",
  ui_picker_selectRow: "ui.picker.selectRow",
  ui_webView_eval: "ui.webView.eval",
  app_logs_mark: "app.logs.mark",
  app_logs_read: "app.logs.read"
} as const;

export function createStaticTools(options: { client: IOSExploreCaller }): Record<string, StaticTool> {
  const { client } = options;
  const forwardActionTool = (toolName: string, action: string, description: string, inputSchema: JSONObject): StaticTool => ({
    name: toolName,
    description: `${description}\n\n对应 iOSExplore action：${action}`,
    inputSchema,
    handler: async input => {
      try {
        const data = await client.call(action, input);
        if (action === "ui.screenshot" && typeof data.image === "string" && data.format === "png") {
          const { image, ...metadata } = data;
          return { isError: false, content: [
            { type: "image", data: image, mimeType: "image/png" },
            { type: "text", text: JSON.stringify(metadata) }
          ] };
        }
        return jsonResult(data);
      } catch (error) {
        return resultForStaticActionFailure(normalizeError(error));
      }
    }
  });

  let staticTools: Record<string, StaticTool>;
  staticTools = {
    health_check: {
      name: "health_check",
      description: "检查 MCP server、iOSExplore App 的 ping/help，以及静态公共工具依赖是否满足；不会改变 tools/list。",
      inputSchema: emptyObjectSchema(),
      handler: async () => {
        try {
          return jsonResult(await capabilityReport(client, staticTools));
        } catch (error) {
          const normalized = normalizeError(error);
          if (normalized.source === "transport") {
            return jsonResult({
              ok: false,
              server: { ok: true },
              error: normalized,
              connection: transportFailureContext(normalized)
            }, false);
          }
          return jsonResult({ ok: false, server: { ok: true }, error: normalized }, false);
        }
      }
    },
    check_capabilities: {
      name: "check_capabilities",
      description: "读取 App help 并报告当前注册 action、静态工具缺失项和明显 schema 不兼容；不会改变 tools/list。",
      inputSchema: emptyObjectSchema(),
      handler: async () => {
        return jsonResult(await capabilityReport(client, staticTools));
      }
    },
    call_action: {
      name: "call_action",
      description: "调用宿主 App 的私有、debug、experimental 或尚未静态封装的 action。稳定公共 action 应优先使用对应静态工具。",
      inputSchema: {
        type: "object",
        properties: {
          action: { type: "string" },
          data: { type: "object" }
        },
        required: ["action"],
        additionalProperties: false
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
          // 与静态工具执行路径保持一致，
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
    ui_topViewHierarchy: forwardActionTool("ui_topViewHierarchy", "ui.topViewHierarchy", "读取当前最外层 UIViewController 容器层级。", topViewHierarchySchema()),
    ui_inspect: forwardActionTool(
      "ui_inspect",
      "ui.inspect",
      "读取当前 UI 结构并签发 viewSnapshotID。稳定静态入口，调用前无需依赖 App help。",
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
    ui_screenshot: forwardActionTool("ui_screenshot", "ui.screenshot", "获取当前 UI 的 PNG 截图；响应会以 MCP image content 返回。", screenshotSchema()),
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
    ui_scroll: forwardActionTool("ui_scroll", "ui.scroll", "按方向滚动目标 UIScrollView。", scrollSchema()),
    ui_navigation_back: forwardActionTool("ui_navigation_back", "ui.navigation.back", "按策略返回或关闭当前页面。", navigationBackSchema()),
    ui_navigation_tapBarButton: forwardActionTool("ui_navigation_tapBarButton", "ui.navigation.tapBarButton", "点击导航栏指定按钮。", navigationBarButtonSchema()),
    ui_waitAny: forwardActionTool("ui_waitAny", "ui.waitAny", "等待多个 UI 条件中的任意一个满足。", waitAnySchema()),
    ui_alert_respond: forwardActionTool("ui_alert_respond", "ui.alert.respond", "按标题、下标或角色响应当前 alert。", alertRespondSchema()),
    ui_controllers: forwardActionTool("ui_controllers", "ui.controllers", "读取当前 controller 层级。", controllersSchema()),
    ui_swipe: forwardActionTool("ui_swipe", "ui.swipe", "对目标 view 执行方向滑动。", swipeSchema()),
    ui_longPress: forwardActionTool("ui_longPress", "ui.longPress", "对目标 view 执行长按。", longPressSchema()),
    ui_tabBar_selectTab: forwardActionTool("ui_tabBar_selectTab", "ui.tabBar.selectTab", "按 index 或 title 选择 tab。", tabBarSelectSchema()),
    ui_datePicker_setDate: forwardActionTool("ui_datePicker_setDate", "ui.datePicker.setDate", "设置日期选择器日期。", datePickerSchema()),
    ui_picker_selectRow: forwardActionTool("ui_picker_selectRow", "ui.picker.selectRow", "按 row 或 title 选择 picker 行。", pickerSelectRowSchema()),
    ui_webView_eval: forwardActionTool("ui_webView_eval", "ui.webView.eval", "在目标 WKWebView 执行 script 或 function。", webViewEvalSchema()),
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
          return resultForStaticActionFailure(normalizeError(error));
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
        const waitForStable = input.waitForStable !== false; // 默认等待稳定
        const stableTimeMs = typeof input.stableTimeMs === "number" ? input.stableTimeMs : 300;
        const inspectDepth = typeof input.inspectDepth === "number" ? input.inspectDepth : 2;
        const inspectMaxTargets = typeof input.inspectMaxTargets === "number" ? input.inspectMaxTargets : 20;

        const timing: { tapMs: number; waitMs?: number; inspectMs: number; totalMs: number } = {
          tapMs: 0,
          inspectMs: 0,
          totalMs: 0
        };

        try {
          // 第一步：执行点击。
          const tapStart = Date.now();
          const tapResult = await client.call("ui.tap", tapParams);
          timing.tapMs = Date.now() - tapStart;

          // 第二步：按需等待 UI 稳定。
          if (waitForStable) {
            const waitStart = Date.now();
            try {
              await client.call("ui.wait", { mode: "idle", stableMs: stableTimeMs, timeoutMs: stableTimeMs + 1000 });
              timing.waitMs = Date.now() - waitStart;
            } catch (waitError) {
              // 等待超时仍继续检查，确保返回操作后的最新 UI。
              timing.waitMs = Date.now() - waitStart;
            }
          }

          // 第三步：检查当前 UI 状态。
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
          // 点击失败时立即返回，不再执行等待和检查。
          const normalized = normalizeError(error);
          timing.totalMs = Date.now() - startTime;
          return errorResult({ ...normalized, timing } as StructuredError);
        }
      }
    }
  };
  return staticTools;
}

function emptyObjectSchema(): JSONObject {
  return {
    type: "object",
    properties: {},
    additionalProperties: false
  };
}

async function capabilityReport(client: IOSExploreCaller, staticTools: Record<string, StaticTool>): Promise<JSONObject> {
  let ping: JSONObject | undefined;
  let help: JSONObject | undefined;
  let pingError: StructuredError | undefined;
  let helpError: StructuredError | undefined;
  try { ping = await client.call("ping"); } catch (error) { pingError = normalizeError(error); }
  try { help = await client.call("help"); } catch (error) { helpError = normalizeError(error); }
  if (!helpError && !Array.isArray(help?.commands)) {
    helpError = { source: "mcp_server", code: "invalid_help_response", message: "help response did not contain commands array", action: "help" };
  }

  const helpAvailable = !helpError && Array.isArray(help?.commands);
  const commands = helpAvailable ? help!.commands as unknown[] : [];
  const actions = commands.filter(isObject).map(command => command.action).filter((action): action is string => typeof action === "string");
  const actionSet = new Set(actions);
  const missingActions = helpAvailable ? Object.values(STATIC_ACTIONS).filter(action => !actionSet.has(action)) : [];
  const uikitActions = Object.values(STATIC_ACTIONS).filter(action => action.startsWith("ui."));
  const diagnosticsActions = Object.values(STATIC_ACTIONS).filter(action => action.startsWith("app.logs."));
  const appCommands = new Map(commands.filter(isObject).map(command => [command.action, command]));
  const schemaIncompatibilities = helpAvailable
    ? Object.entries(STATIC_ACTIONS).flatMap(([toolName, action]) => {
        const command = appCommands.get(action);
        if (!command) return [];
        if (!isObject(command.inputSchema)) return [`${action}: inputSchema missing or invalid`];
        return schemaDifferences(staticTools[toolName]?.inputSchema, command.inputSchema).map(detail => `${action}: ${detail}`);
      })
    : [];
  const result: JSONObject = {
    ok: !pingError && !helpError && missingActions.length === 0 && schemaIncompatibilities.length === 0,
    server: { ok: true, staticToolCount: STATIC_TOOL_NAMES.length },
    app: {
      ping: pingError ? { ok: false, error: pingError } : { ok: true, response: ping },
      help: helpError ? { ok: false, error: helpError, status: "unknown" } : { ok: true, actionCount: actions.length },
      registeredActions: actions,
      missingStaticActions: missingActions,
      schemaIncompatibilities,
      modules: helpAvailable ? {
        uikit: moduleStatus(uikitActions, actionSet),
        diagnostics: moduleStatus(diagnosticsActions, actionSet)
      } : { uikit: { status: "unknown" }, diagnostics: { status: "unknown" } }
    }
  };
  const transportError = firstTransportError([pingError, helpError]);
  if (transportError) {
    result.connection = transportFailureContext(transportError);
  }
  return result;
}

function moduleStatus(requiredActions: readonly string[], registeredActions: Set<string>): JSONObject {
  const missingActions = requiredActions.filter(action => !registeredActions.has(action));
  const registeredCount = requiredActions.length - missingActions.length;
  const status = registeredCount === requiredActions.length ? "registered" : registeredCount === 0 ? "not_registered" : "partial";
  return { status, registeredCount, requiredCount: requiredActions.length, missingActions };
}

function schemaDifferences(expected: JSONObject | undefined, actual: JSONObject): string[] {
  if (!expected) return ["static tool schema missing"];
  const differences: string[] = [];
  const expectedProperties = isObject(expected.properties) ? Object.keys(expected.properties).sort() : [];
  const actualProperties = isObject(actual.properties) ? Object.keys(actual.properties).sort() : [];
  if (JSON.stringify(expectedProperties) !== JSON.stringify(actualProperties)) {
    differences.push(`properties expected=${expectedProperties.join(",")} actual=${actualProperties.join(",")}`);
  }
  if (expected.additionalProperties === false && actual.additionalProperties !== false) {
    differences.push("additionalProperties expected=false");
  }
  if (isObject(expected.properties) && isObject(actual.properties)) {
    for (const [name, expectedProperty] of Object.entries(expected.properties)) {
      const actualProperty = actual.properties[name];
      if (!isObject(expectedProperty) || !isObject(actualProperty)) continue;
      for (const key of ["enum", "minimum", "maximum", "minItems", "maxItems", "default"] as const) {
        if (expectedProperty[key] !== undefined && actualProperty[key] !== undefined && JSON.stringify(expectedProperty[key]) !== JSON.stringify(actualProperty[key])) {
          differences.push(`properties.${name}.${key} expected=${JSON.stringify(expectedProperty[key])} actual=${JSON.stringify(actualProperty[key])}`);
        }
      }
    }
  }
  return differences;
}

function isObject(value: unknown): value is JSONObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function locatorProperties(): JSONObject {
  return {
    accessibilityIdentifier: { type: "string", description: "按 accessibilityIdentifier 定位；通常与 path 二选一。" },
    path: { type: "string", description: "按 ui.inspect 返回的 path 定位；通常与 accessibilityIdentifier 二选一。" },
    viewSnapshotID: { type: "string", description: "ui.inspect 签发的快照 ID，用于陈旧目标校验。" }
  };
}

const JSON_SAFE_INTEGER_MAX = Number.MAX_SAFE_INTEGER;

function topViewHierarchySchema(): JSONObject { return {
  type: "object", properties: {
    detailLevel: { type: "string", enum: ["basic", "appearance", "full"], default: "appearance" },
    includeHidden: { type: "boolean", default: false },
    maxDepth: { type: "integer", minimum: 0, maximum: JSON_SAFE_INTEGER_MAX },
    accessibilityIdentifier: { type: "string" },
    accessibilityIdentifierPrefix: { type: "string" },
    controller: { type: "string", description: "ui.controllers 返回的 controller path。" }
  }, additionalProperties: false
}; }

function screenshotSchema(): JSONObject { return {
  type: "object", properties: { maxDimension: { type: "integer", minimum: 1, maximum: 4096, default: 1280 } }, additionalProperties: false
}; }

function scrollSchema(): JSONObject { return {
  type: "object", properties: {
    direction: { type: "string", enum: ["up", "down", "left", "right"] },
    amount: { type: "number", exclusiveMinimum: 0 }, ...locatorProperties(),
    animated: { type: "boolean", default: false }
  }, required: ["direction"], additionalProperties: false
}; }

function navigationBackSchema(): JSONObject { return {
  type: "object", properties: {
    strategy: { type: "string", enum: ["auto", "navigationController", "dismiss"], default: "auto" },
    animated: { type: "boolean", default: false },
    waitAfterMs: { type: "integer", minimum: 0, maximum: 3000, default: 300 }
  }, additionalProperties: false
}; }

function navigationBarButtonSchema(): JSONObject { return {
  type: "object", properties: {
    placement: { type: "string", enum: ["left", "right"] },
    index: { type: "integer", minimum: 0, maximum: 20 },
    title: { type: "string" }, accessibilityIdentifier: { type: "string" },
    waitAfterMs: { type: "integer", minimum: 0, maximum: 3000, default: 300 }
  }, additionalProperties: false
}; }

function waitAnySchema(): JSONObject {
  const condition = {
    type: "object", properties: {
      id: { type: "string" }, mode: { type: "string", enum: ["idle", "targetExists", "targetGone", "textExists", "snapshotChanged"] },
      accessibilityIdentifier: { type: "string" }, path: { type: "string" }, text: { type: "string" }, viewSnapshotID: { type: "string" }
    }, required: ["id", "mode"], additionalProperties: false
  };
  return { type: "object", properties: {
    conditions: { type: "array", minItems: 1, maxItems: 16, items: condition },
    timeoutMs: { type: "integer", minimum: 0, maximum: 30000, default: 3000 },
    intervalMs: { type: "integer", minimum: 50, maximum: 5000, default: 100 },
    stableMs: { type: "integer", minimum: 0, maximum: 10000, default: 300 },
    includeHidden: { type: "boolean", default: false }
  }, required: ["conditions"], additionalProperties: false };
}

function alertRespondSchema(): JSONObject { return {
  type: "object", properties: {
    buttonTitle: { type: "string" }, buttonIndex: { type: "integer", minimum: 0, maximum: JSON_SAFE_INTEGER_MAX }, role: { type: "string", enum: ["default", "cancel", "destructive"] }
  }, additionalProperties: false, description: "buttonTitle、buttonIndex、role 最多提供一个。"
}; }

function controllersSchema(): JSONObject { return { type: "object", properties: {
  maxDepth: { type: "integer", minimum: 0, maximum: JSON_SAFE_INTEGER_MAX }
}, additionalProperties: false }; }
function swipeSchema(): JSONObject { return { type: "object", properties: {
  direction: { type: "string", enum: ["up", "down", "left", "right"] },
  distance: { type: "number", exclusiveMinimum: 0, maximum: 1, default: 0.8, description: "滑动距离比例，范围 (0, 1]，默认 0.8。" },
  ...locatorProperties(),
  cellAccessibilityIdentifier: { type: "string", description: "swipe action 的目标 cell；与 cellPath 二选一。" },
  cellPath: { type: "string", description: "swipe action 的目标 cell path；与 cellAccessibilityIdentifier 二选一。" },
  actionTitle: { type: "string", description: "要触发的 swipe action 标题；省略时触发第一个。" }
}, required: ["direction"], additionalProperties: false, description: "主 locator 和 cell locator 都可省略；cellAccessibilityIdentifier/cellPath 互斥。" }; }
function longPressSchema(): JSONObject { return { type: "object", properties: {
  duration: { type: "number", exclusiveMinimum: 0, maximum: 10, default: 0.5 }, ...locatorProperties()
}, additionalProperties: false, description: "locator 与 viewSnapshotID 都可省略；缺省 locator 时使用 keyWindow 第一个可长按 view。" }; }
function tabBarSelectSchema(): JSONObject { return { type: "object", properties: {
  tabBarControllerPath: { type: "string" }, index: { type: "integer", minimum: 0, maximum: JSON_SAFE_INTEGER_MAX }, title: { type: "string" }, triggerDelegate: { type: "boolean", default: true }
}, additionalProperties: false, description: "index 与 title 必须且只能提供一个。" }; }
function datePickerSchema(): JSONObject { return { type: "object", properties: {
  ...locatorProperties(), date: { type: "string", description: "ISO 8601 日期时间字符串。与日期分量互斥。" },
  year: { type: "integer", minimum: 0, maximum: JSON_SAFE_INTEGER_MAX }, month: { type: "integer", minimum: 0, maximum: JSON_SAFE_INTEGER_MAX }, day: { type: "integer", minimum: 0, maximum: JSON_SAFE_INTEGER_MAX },
  hour: { type: "integer", minimum: 0, maximum: JSON_SAFE_INTEGER_MAX }, minute: { type: "integer", minimum: 0, maximum: JSON_SAFE_INTEGER_MAX }, animated: { type: "boolean", default: false }
}, additionalProperties: false, description: "accessibilityIdentifier 与 path 必须且只能提供一个；必须提供 date 或至少一个日期分量，两类日期输入互斥；viewSnapshotID 可选。" }; }
function pickerSelectRowSchema(): JSONObject { return { type: "object", properties: {
  ...locatorProperties(), component: { type: "integer", minimum: 0, maximum: JSON_SAFE_INTEGER_MAX }, row: { type: "integer", minimum: 0, maximum: JSON_SAFE_INTEGER_MAX }, title: { type: "string" }, animated: { type: "boolean", default: false }
}, required: ["component"], additionalProperties: false, description: "accessibilityIdentifier 与 path 必须且只能提供一个；row 与 title 必须且只能提供一个；viewSnapshotID 可选。" }; }
function webViewEvalSchema(): JSONObject { return { type: "object", properties: {
  ...locatorProperties(), script: { type: "string" }, function: { type: "string" }, arguments: { type: "object", additionalProperties: true }, timeout: { type: "number", minimum: 1, maximum: 30, default: 5 }
}, additionalProperties: false, description: "accessibilityIdentifier 与 path 必须且只能提供一个；script 与 function 必须且只能提供一个；arguments 只能与 function 一起使用；viewSnapshotID 可选。" }; }

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
      includeHidden: { type: "boolean", default: false },
      maxDepth: { type: "integer", minimum: 0 },
      accessibilityIdentifier: { type: "string" },
      accessibilityIdentifierPrefix: { type: "string" },
      textLimit: { type: "integer", minimum: 1, maximum: 200, default: 80 },
      maxTargets: { type: "integer", minimum: 1, maximum: 512, default: 200 },
      maxVisitedNodes: { type: "integer", minimum: 100, maximum: 20000, default: 2000 }
    },
    additionalProperties: false
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
      mode: { type: "string", enum: ["replace", "append"], default: "replace" },
      submit: {
        type: "boolean",
        default: false,
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
        default: true,
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
    required: ["fields"],
    additionalProperties: false,
    description: "每个 fields item 必须提供 accessibilityIdentifier 或 path 之一；viewSnapshotID 可选。"
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
    required: ["viewSnapshotID"],
    additionalProperties: false,
    description: "accessibilityIdentifier 与 path 必须且只能提供一个。"
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
        enum: ["touchDown", "touchUpInside", "valueChanged", "editingChanged", "editingDidBegin", "editingDidEnd"]
      },
      value: {
        type: "number",
        description: "控件值。UISlider 用 0.0...1.0，UISegmentedControl 用索引，UISwitch/UIStepper 通常不传。"
      }
    },
    required: ["event", "viewSnapshotID"],
    additionalProperties: false,
    description: "accessibilityIdentifier 与 path 必须且只能提供一个。"
  };
}

function uiKeyboardDismissSchema(): JSONObject {
  return {
    type: "object",
    properties: {
      strategy: { type: "string", enum: ["auto", "resignFirstResponder", "endEditing"], default: "auto" },
      waitAfterMs: { type: "integer", minimum: 0, maximum: 3000, default: 200 }
    }, additionalProperties: false
  };
}

function uiScrollToElementSchema(): JSONObject {
  return {
    type: "object",
    properties: {
      match: { type: "string", enum: ["text", "accessibilityIdentifier"], default: "text" },
      value: { type: "string", description: "要滚动到的文本片段或 accessibilityIdentifier。" },
      accessibilityIdentifier: { type: "string", description: "滚动容器 accessibilityIdentifier；与 path 二选一。" },
      path: { type: "string", description: "滚动容器 path；与 accessibilityIdentifier 二选一。" },
      animated: { type: "boolean", default: false }
    },
    required: ["value"],
    additionalProperties: false,
    description: "定位字段指向滚动容器自身，可同时省略；不签发或要求 viewSnapshotID。"
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
      timeoutMs: { type: "integer", minimum: 0, maximum: 30000, default: 3000 },
      intervalMs: { type: "integer", minimum: 50, maximum: 5000, default: 100 },
      stableMs: { type: "integer", minimum: 0, maximum: 10000, default: 300 },
      includeHidden: { type: "boolean", default: false },
      inspectOptions: {
        type: "object",
        description:
          "传给 ui.inspect 的可选参数。只能传 ui.inspect 真实字段（includeHidden / maxDepth / accessibilityIdentifier / accessibilityIdentifierPrefix / textLimit / maxTargets / maxVisitedNodes），不接受 ui.topViewHierarchy 专用的 detailLevel 或 ui.waitAny 专用的 conditions 等字段。",
        properties: {
          includeHidden: { type: "boolean" },
          maxDepth: { type: "integer", minimum: 0, maximum: JSON_SAFE_INTEGER_MAX },
          accessibilityIdentifier: { type: "string" },
          accessibilityIdentifierPrefix: { type: "string" },
          textLimit: { type: "integer", minimum: 1, maximum: 200, default: 80 },
          maxTargets: { type: "integer", minimum: 1, maximum: 512, default: 200 },
          maxVisitedNodes: { type: "integer", minimum: 100, maximum: 20000, default: 2000 }
        },
        additionalProperties: false
      }
    },
    required: ["conditions"],
    additionalProperties: false
  };
}

function uiWaitSchema(): JSONObject {
  return {
    type: "object",
    properties: {
      mode: {
        type: "string",
        enum: ["idle", "targetExists", "targetGone", "textExists", "snapshotChanged"],
        default: "idle",
        description: "等待模式: idle / targetExists / targetGone / textExists / snapshotChanged"
      },
      timeoutMs: {
        type: "integer",
        minimum: 0,
        maximum: 30000,
        default: 3000,
        description: "业务超时毫秒数, 范围 0...30000, 默认 3000"
      },
      intervalMs: {
        type: "integer",
        minimum: 50,
        maximum: 5000,
        default: 100,
        description: "轮询间隔毫秒数, 范围 50...5000, 默认 100"
      },
      stableMs: {
        type: "integer",
        minimum: 0,
        maximum: 10000,
        default: 300,
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
    },
    additionalProperties: false,
    description: "targetExists/targetGone 必须提供 accessibilityIdentifier 或 path；textExists 必须提供非空 text；snapshotChanged 必须提供 viewSnapshotID。"
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
    required: ["viewSnapshotID"],
    additionalProperties: false,
    description: "accessibilityIdentifier 与 path 必须且只能提供一个。"
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

function resultForStaticActionFailure(error: StructuredError): MCPToolResult {
  if (error.source === "ios_envelope") {
    const errorCodes = ["invalid_data", "stale_locator", "unknown_action"];
    if (error.code && errorCodes.includes(error.code)) {
      return errorResult(error);
    }
    return jsonResult(error as unknown as JSONObject, false);
  }
  return errorResult(error);
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

// transport 错误判定集中在兜底工具路径，避免不同工具产生不同错误语义。
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
    connection: transportFailureContext(normalized),
    nextSteps: transportNextSteps()
  };
}

async function pingHealthCheck(caller: IOSExploreCaller): Promise<JSONObject> {
  try {
    return { ok: true, ping: await caller.call("ping") };
  } catch (error) {
    return { ok: false, error: normalizeError(error) };
  }
}

function firstTransportError(errors: Array<StructuredError | undefined>): StructuredError | undefined {
  return errors.find((error): error is StructuredError => error?.source === "transport");
}

function transportFailureContext(error: StructuredError): JSONObject {
  return {
    status: "app_endpoint_unreachable",
    error,
    probableCause: "MCP server 已可调用，但目标 App 的 HTTP 自动化端点当前没有接受连接。",
    nextSteps: transportNextSteps()
  };
}

function transportNextSteps(): string[] {
  return [
    "确认目标 App 仍在运行，并且已经启动 iOSExplore HTTP server。",
    "确认 localhost:38321 指向的是可访问端点；真机场景还需要确认本地端口转发或代理仍在监听。",
    "如果当前构建/设备管理 MCP 已暴露 launch_app_device 或 launch_app_sim，使用对应启动工具重启 App 后再重试 health_check。",
    "如果当前任务是真机，但客户端只看得到 *_sim 工具，先修复或重连构建/设备管理 MCP，让真机启动工具暴露出来。"
  ];
}
