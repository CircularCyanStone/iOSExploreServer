import { describe, expect, test } from "vitest";
import { DEVICE_ACTION_CONTRACTS } from "../../../src/generated/deviceActionContracts.js";
import { HOST_OPERATION_SPECS } from "../../../src/generated/hostOperationSpecs.js";
import { TOOL_CATALOG } from "../../../src/adapters/mcp/toolCatalog.js";
import { STATIC_TOOL_NAMES, TOOL_MAPPINGS } from "../../../src/adapters/mcp/toolMappings.js";

const EXPECTED_NAMES = [
  "health_check", "check_capabilities", "call_action", "app_logs_mark",
  "app_logs_read", "ui_topViewHierarchy", "ui_inspect", "ui_control_sendAction",
  "ui_input", "ui_tap", "ui_screenshot", "ui_keyboard_dismiss", "ui_scroll",
  "ui_navigation_back", "ui_navigation_tapBarButton", "ui_waitAny",
  "ui_scrollToElement", "ui_alert_respond", "ui_controllers", "ui_swipe",
  "ui_longPress", "ui_tabBar_selectTab", "ui_datePicker_setDate",
  "ui_picker_selectRow", "ui_webView_eval", "wait_and_inspect", "ui_wait",
  "ui_tap_and_inspect"
];

describe("MCP tool catalog", () => {
  test("精确冻结 28 个历史名称和显式映射", () => {
    expect(STATIC_TOOL_NAMES).toEqual(EXPECTED_NAMES);
    expect(TOOL_CATALOG.map(tool => tool.name)).toEqual(EXPECTED_NAMES);
    expect(TOOL_MAPPINGS).toHaveLength(28);
    expect(Object.isFrozen(TOOL_MAPPINGS)).toBe(true);
    expect(TOOL_MAPPINGS.every(Object.isFrozen)).toBe(true);
  });

  test("description/inputSchema 直接来自 generated contract", () => {
    for (const entry of TOOL_CATALOG) {
      const contract = entry.mapping.kind === "deviceAction"
        ? DEVICE_ACTION_CONTRACTS.find(candidate => candidate.action === entry.mapping.action)
        : HOST_OPERATION_SPECS.find(candidate => candidate.operation === entry.mapping.operation);
      expect(contract, entry.name).toBeDefined();
      expect(entry.description).toBe(contract!.description);
      expect(entry.inputSchema).toBe(contract!.inputSchema);
    }
  });

  test("未映射的公共 action 和 extension 不自动生成 MCP tool", () => {
    expect(TOOL_CATALOG.some(tool => tool.name === "ping")).toBe(false);
    expect(TOOL_CATALOG.some(tool => tool.name === "extension.demo")).toBe(false);
  });
});
