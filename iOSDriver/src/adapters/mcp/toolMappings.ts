/** MCP 工具映射到的宿主操作名称。 */
export type MappedHostOperation =
  | "health"
  | "capabilities"
  | "call_action"
  | "wait_and_inspect"
  | "tap_and_inspect";

/** 历史 MCP 工具名到 generated contract 标识的显式映射。 */
export type ToolMapping =
  | Readonly<{ toolName: string; kind: "deviceAction"; action: string }>
  | Readonly<{ toolName: string; kind: "hostOperation"; operation: MappedHostOperation }>;

/**
 * 冻结的 28 个历史 MCP 工具映射。
 *
 * 这里只保存名称与合同标识，schema 和 description 始终从 generated 产物读取。
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

export const TOOL_MAPPINGS: readonly ToolMapping[] = Object.freeze(
  MAPPINGS.map(mapping => Object.freeze(mapping))
);

/** 冻结的历史 MCP 工具名，顺序也是稳定 tools/list 顺序。 */
export const STATIC_TOOL_NAMES: readonly string[] = Object.freeze(
  TOOL_MAPPINGS.map(mapping => mapping.toolName)
);
