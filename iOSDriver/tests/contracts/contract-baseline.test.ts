import { describe, expect, test } from "vitest";
import { loadAndValidateContractBundle } from "../../src/contracts/generator/loadBundle.js";
import { TOOL_MAPPINGS } from "../../src/adapters/mcp/toolMappings.js";

const expectedDeviceActions = [
  "ping",
  "echo",
  "info",
  "help",
  "ui.topViewHierarchy",
  "ui.inspect",
  "ui.control.sendAction",
  "ui.tap",
  "ui.screenshot",
  "ui.input",
  "ui.keyboard.dismiss",
  "ui.scroll",
  "ui.navigation.back",
  "ui.navigation.tapBarButton",
  "ui.wait",
  "ui.waitAny",
  "ui.scrollToElement",
  "ui.alert.respond",
  "ui.controllers",
  "ui.swipe",
  "ui.longPress",
  "ui.tabBar.selectTab",
  "ui.datePicker.setDate",
  "ui.picker.selectRow",
  "ui.webView.eval",
  "app.logs.mark",
  "app.logs.read"
];

const expectedHostOperations = [
  "health",
  "capabilities",
  "call_action",
  "wait_and_inspect",
  "tap_and_inspect"
];

const expectedFiles = [
  "device-actions/core.ping.json",
  "device-actions/core.echo.json",
  "device-actions/core.info.json",
  "device-actions/core.help.json",
  "device-actions/uikit.top-view-hierarchy.json",
  "device-actions/uikit.inspect.json",
  "device-actions/uikit.control-send-action.json",
  "device-actions/uikit.tap.json",
  "device-actions/uikit.screenshot.json",
  "device-actions/uikit.input.json",
  "device-actions/uikit.keyboard-dismiss.json",
  "device-actions/uikit.scroll.json",
  "device-actions/uikit.navigation-back.json",
  "device-actions/uikit.navigation-tap-bar-button.json",
  "device-actions/uikit.wait.json",
  "device-actions/uikit.wait-any.json",
  "device-actions/uikit.scroll-to-element.json",
  "device-actions/uikit.alert-respond.json",
  "device-actions/uikit.controllers.json",
  "device-actions/uikit.swipe.json",
  "device-actions/uikit.long-press.json",
  "device-actions/uikit.tab-bar-select-tab.json",
  "device-actions/uikit.date-picker-set-date.json",
  "device-actions/uikit.picker-select-row.json",
  "device-actions/uikit.web-view-eval.json",
  "device-actions/diagnostics.app-logs-mark.json",
  "device-actions/diagnostics.app-logs-read.json",
  "host-operations/health.json",
  "host-operations/capabilities.json",
  "host-operations/call-action.json",
  "host-operations/wait-and-inspect.json",
  "host-operations/tap-and-inspect.json"
];

describe("contract baseline", () => {
  test("freezes the current device and host operation surface", () => {
    const bundle = loadAndValidateContractBundle();

    expect(bundle.protocolVersion).toBe("1");
    expect(bundle.contractVersion).toBe("1.0.0");
    expect(bundle.generatorVersion).toBe("1");
    expect(bundle.files).toEqual(expectedFiles);
    expect(bundle.deviceActions).toHaveLength(expectedDeviceActions.length);
    expect(bundle.hostOperations).toHaveLength(expectedHostOperations.length);

    expect(bundle.deviceActions.map(contract => contract.action).sort()).toEqual([...expectedDeviceActions].sort());
    expect(bundle.hostOperations.map(spec => spec.operation).sort()).toEqual([...expectedHostOperations].sort());

    for (const contract of bundle.deviceActions) {
      expect(contract.kind).toBe("deviceAction");
      expect(contract.provider).toMatch(/^(core|uikit|diagnostics|extension)$/);
      expect(contract.stability).toMatch(/^(public|experimental|internal)$/);
      expect(contract.result.kind).toMatch(/^(json|image|text)$/);
      expect(Array.isArray(contract.errors)).toBe(true);
      expect(contract.errors.length).toBeGreaterThan(0);
      expect(contract.idempotency).toMatch(/^(readOnly|idempotent|sideEffecting)$/);
      expect(contract.timeoutClass).toMatch(/^(standard|wait|screenshot)$/);
      expect(contract.inputSchema).toBeTruthy();
    }

    for (const spec of bundle.hostOperations) {
      expect(spec.kind).toBe("hostOperation");
      expect(spec.result.kind).toMatch(/^(json|image|text)$/);
      expect(Array.isArray(spec.errors)).toBe(true);
      expect(spec.errors.length).toBeGreaterThan(0);
      expect(spec.inputSchema).toBeTruthy();
    }

    expect(toolMapping("ui_inspect")).toBe("ui.inspect");
    expect(toolMapping("app_logs_read")).toBe("app.logs.read");
    expect(toolMapping("wait_and_inspect")).toBe("wait_and_inspect");
    expect(toolMapping("ui_tap_and_inspect")).toBe("tap_and_inspect");

    expect(toolMappingFromCatalog("ui_inspect")).toBe("ui.inspect");
    expect(toolMappingFromCatalog("app_logs_read")).toBe("app.logs.read");
  });
});

function toolMapping(name: string): string {
  const mappings: Record<string, string> = {
    ui_inspect: "ui.inspect",
    app_logs_read: "app.logs.read",
    wait_and_inspect: "wait_and_inspect",
    ui_tap_and_inspect: "tap_and_inspect"
  };
  const mapping = mappings[name];
  if (!mapping) {
    throw new Error(`unknown mapping: ${name}`);
  }
  return mapping;
}

function toolMappingFromCatalog(name: string): string {
  const mapping = TOOL_MAPPINGS.find(candidate => candidate.toolName === name);
  if (mapping === undefined) throw new Error(`unknown mapping: ${name}`);
  return mapping.kind === "deviceAction" ? mapping.action : mapping.operation;
}
