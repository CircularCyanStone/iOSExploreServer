/**
 * MCP 历史工具名与 canonical 合同标识之间的**唯一手写映射**。
 *
 * 为什么必须显式维护：MCP 工具名（如 `ui_tap`）是客户端兼容表面——Claude Code 的
 * 配置、prompt、缓存都引用它，不能随 App action 名或 help 返回动态变化；所以不能从
 * App `help` 动态生成工具列表。但字段 schema、description 仍由合同生成读取，
 * 本文件只保存「名字 → 合同标识」这一层映射。
 *
 * 映射关系示例：
 *   toolName "ui_tap" → kind deviceAction → action "ui.tap"
 *   toolName "wait_and_inspect" → kind hostOperation → operation "wait_and_inspect"
 */
/** MCP 工具可映射到的宿主操作名称（在 Mac 侧执行，而非发给 App）。 */
export type MappedHostOperation =
  | "health"
  | "capabilities"
  | "call_action"
  | "wait_and_inspect"
  | "tap_and_inspect";

/**
 * 历史 MCP 工具名到 generated contract 标识的显式映射（判别联合）。
 *
 * - kind="deviceAction"：直接转发给 App 的 canonical action（如 "ui.tap"）；
 * - kind="hostOperation"：在 Mac 侧执行的能力检查、动态调用或复合 workflow。
 */
export type ToolMapping =
  | Readonly<{
      /** 对 MCP 客户端保持稳定的外部工具名。 */
      toolName: string;
      kind: "deviceAction";
      /** 直接交给 App `POST /` 的 canonical action 名。 */
      action: string;
    }>
  | Readonly<{
      /** 对 MCP 客户端保持稳定的外部工具名。 */
      toolName: string;
      kind: "hostOperation";
      /** 在 Mac 侧执行的能力检查、动态调用或复合 workflow 名。 */
      operation: MappedHostOperation;
    }>;

/**
 * 冻结的 28 个历史 MCP 工具映射（当前是完整清单）。
 * 只保存名称与合同标识；schema 与 description 始终从 generated 产物读取。
 * 新增工具：同时更新本数组、合同与 toolCatalog 的消费逻辑。
 */
const MAPPINGS: readonly ToolMapping[] = [
  { toolName: "health_check", kind: "hostOperation", operation: "health" },
  { toolName: "check_capabilities", kind: "hostOperation", operation: "capabilities" },
  { toolName: "call_action", kind: "hostOperation", operation: "call_action" },
  { toolName: "app_logs_mark", kind: "deviceAction", action: "app.logs.mark" },
  { toolName: "app_logs_read", kind: "deviceAction", action: "app.logs.read" },
  { toolName: "ui_topViewHierarchy", kind: "deviceAction", action: "ui.topViewHierarchy" },
  { toolName: "ui_inspect", kind: "deviceAction", action: "ui.inspect" },
  { toolName: "ui_control_sendAction", kind: "deviceAction", action: "ui.control.sendAction" },
  { toolName: "ui_input", kind: "deviceAction", action: "ui.input" },
  { toolName: "ui_tap", kind: "deviceAction", action: "ui.tap" },
  { toolName: "ui_screenshot", kind: "deviceAction", action: "ui.screenshot" },
  { toolName: "ui_keyboard_dismiss", kind: "deviceAction", action: "ui.keyboard.dismiss" },
  { toolName: "ui_scroll", kind: "deviceAction", action: "ui.scroll" },
  { toolName: "ui_navigation_back", kind: "deviceAction", action: "ui.navigation.back" },
  { toolName: "ui_navigation_tapBarButton", kind: "deviceAction", action: "ui.navigation.tapBarButton" },
  { toolName: "ui_waitAny", kind: "deviceAction", action: "ui.waitAny" },
  { toolName: "ui_scrollToElement", kind: "deviceAction", action: "ui.scrollToElement" },
  { toolName: "ui_alert_respond", kind: "deviceAction", action: "ui.alert.respond" },
  { toolName: "ui_controllers", kind: "deviceAction", action: "ui.controllers" },
  { toolName: "ui_swipe", kind: "deviceAction", action: "ui.swipe" },
  { toolName: "ui_longPress", kind: "deviceAction", action: "ui.longPress" },
  { toolName: "ui_tabBar_selectTab", kind: "deviceAction", action: "ui.tabBar.selectTab" },
  { toolName: "ui_datePicker_setDate", kind: "deviceAction", action: "ui.datePicker.setDate" },
  { toolName: "ui_picker_selectRow", kind: "deviceAction", action: "ui.picker.selectRow" },
  { toolName: "ui_webView_eval", kind: "deviceAction", action: "ui.webView.eval" },
  { toolName: "wait_and_inspect", kind: "hostOperation", operation: "wait_and_inspect" },
  { toolName: "ui_wait", kind: "deviceAction", action: "ui.wait" },
  { toolName: "ui_tap_and_inspect", kind: "hostOperation", operation: "tap_and_inspect" }
];

/**
 * 已冻结的映射数组（数组与元素都 freeze，防止长生命周期 MCP 进程中被意外改写）。
 * 供 toolCatalog 构建静态目录。
 */
export const TOOL_MAPPINGS: readonly ToolMapping[] = Object.freeze(
  MAPPINGS.map(mapping => Object.freeze(mapping))
);

/** 冻结的历史 MCP 工具名列表；顺序即稳定的 tools/list 顺序。 */
export const STATIC_TOOL_NAMES: readonly string[] = Object.freeze(
  TOOL_MAPPINGS.map(mapping => mapping.toolName)
);
