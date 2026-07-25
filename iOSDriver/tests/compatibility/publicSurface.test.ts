import { describe, expect, test, vi } from "vitest";
import { DEVICE_ACTION_CONTRACTS } from "../../src/generated/deviceActionContracts.js";
import { HOST_OPERATION_SPECS } from "../../src/generated/hostOperationSpecs.js";
import { createMCPToolHandlers } from "../../src/adapters/mcp/server.js";
import { TOOL_CATALOG, type ToolCatalogEntry } from "../../src/adapters/mcp/toolCatalog.js";
import { STATIC_TOOL_NAMES, TOOL_MAPPINGS } from "../../src/adapters/mcp/toolMappings.js";
import { HttpActionTransport } from "../../src/runtime/httpActionTransport.js";
import { DriverRuntime, type InvocationOptions } from "../../src/runtime/driverRuntime.js";
import type { Artifact, InvocationResult } from "../../src/runtime/types.js";
import type { CapabilityReport } from "../../src/runtime/capabilityProbe.js";
import type { JSONObject } from "../../src/types.js";
import type { WorkflowOperation } from "../../src/workflows/types.js";

const EXPECTED_TOOL_NAMES = [
  "health_check", "check_capabilities", "call_action", "app_logs_mark", "app_logs_read",
  "ui_topViewHierarchy", "ui_inspect", "ui_control_sendAction", "ui_input", "ui_tap",
  "ui_screenshot", "ui_keyboard_dismiss", "ui_scroll", "ui_navigation_back",
  "ui_navigation_tapBarButton", "ui_waitAny", "ui_scrollToElement", "ui_alert_respond",
  "ui_controllers", "ui_swipe", "ui_longPress", "ui_tabBar_selectTab", "ui_datePicker_setDate",
  "ui_picker_selectRow", "ui_webView_eval", "wait_and_inspect", "ui_wait", "ui_tap_and_inspect"
] as const;

const EXPECTED_TOOL_MAPPINGS = [
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
] as const;

describe("public compatibility surface", () => {
  test("固定 28 个工具、映射和 generated schema 保持稳定", async () => {
    const handlers = createMCPToolHandlers(fixture().options);
    const listed = await handlers.listTools();

    expect(STATIC_TOOL_NAMES).toEqual(EXPECTED_TOOL_NAMES);
    expect(listed.tools.map(tool => tool.name)).toEqual(EXPECTED_TOOL_NAMES);
    expect(TOOL_MAPPINGS).toEqual(EXPECTED_TOOL_MAPPINGS);
    for (const entry of TOOL_CATALOG) {
      const contract = contractFor(entry);
      expect(entry.description, entry.name).toBe(contract.description);
      expect(entry.inputSchema, entry.name).toBe(contract.inputSchema);
    }
  });

  test("App 离线时 tools/list 仍返回完整静态表面且不触发 runtime", async () => {
    const fixtureState = fixture();
    const listed = await createMCPToolHandlers(fixtureState.options).listTools();
    expect(listed.tools).toHaveLength(28);
    expect(fixtureState.runtimeCalls).toEqual([]);
    expect(fixtureState.probeCalls).toEqual([]);
    expect(fixtureState.workflowCalls).toEqual([]);
  });

  test("workflow output 保留 wait/observation 与 tap/stateAfter/timing 字段", async () => {
    const handlers = createMCPToolHandlers({
      ...fixture().options,
      workflowRunner: {
        async run(operation: WorkflowOperation): Promise<InvocationResult> {
          return operation === "wait_and_inspect"
            ? success({ wait: { satisfied: true }, observation: { targets: [] } })
            : success({ tap: { tapped: true }, stateAfter: { targets: [] }, timing: { totalMs: 1 } });
        }
      }
    });

    const wait = await handlers.callTool("wait_and_inspect", { conditions: [] });
    const tap = await handlers.callTool("ui_tap_and_inspect", { viewSnapshotID: "snapshot", path: "/0" });
    expect(json(wait)).toEqual(expect.objectContaining({ wait: expect.any(Object), observation: expect.any(Object) }));
    expect(json(tap)).toEqual(expect.objectContaining({
      tap: expect.any(Object), stateAfter: expect.any(Object), timing: expect.any(Object)
    }));
  });

  test("screenshot artifact 渲染为 MCP image content", async () => {
    const result = await createMCPToolHandlers({
      ...fixture().options,
      runtime: { async invoke(): Promise<InvocationResult> {
        return success({}, [{ kind: "image", mimeType: "image/png", data: PNG, metadata: { width: 1, height: 1 } }]);
      } }
    }).callTool("ui_screenshot", {});

    expect(result.content[0]).toEqual({ type: "image", data: Buffer.from(PNG).toString("base64"), mimeType: "image/png" });
    expect(result.isError).toBe(false);
  });

  test("HTTP transport 使用 POST / 且 body 固定为 { action, data }", async () => {
    const fetchImpl = vi.fn(async () => new Response(JSON.stringify({ code: "ok", data: { pong: true } }), { status: 200 }));
    await new HttpActionTransport("http://localhost:38321/", fetchImpl).execute(
      { action: "ping", data: { value: 1 } }, { timeoutMs: 1000 }
    );
    expect(fetchImpl).toHaveBeenCalledWith("http://localhost:38321/", expect.objectContaining({
      method: "POST",
      body: JSON.stringify({ action: "ping", data: { value: 1 } })
    }));
  });

  test("HTTP 400/500 是 transport/http 失败，HTTP 200 业务 envelope 保留业务错误", async () => {
    for (const status of [400, 500]) {
      const transport = new HttpActionTransport("http://localhost:38321/", async () => new Response("failed", { status }));
      const result = await new DriverRuntime({ transport, configuredRequestTimeoutMs: 1000 }).invoke("ping", {});
      expect(result).toMatchObject({ ok: false, error: { source: "http", code: "http_error", status } });
    }

    const business = new HttpActionTransport("http://localhost:38321/", async () => new Response(
      JSON.stringify({ code: "invalid_data", message: "bad input", data: { field: "value" } }), { status: 200 }
    ));
    const result = await new DriverRuntime({ transport: business, configuredRequestTimeoutMs: 1000 }).invoke("ui.inspect", {});
    expect(result).toMatchObject({ ok: false, error: { source: "appEnvelope", code: "invalid_data" }, data: { field: "value" } });
  });

  test("call_action 允许 extension/private action，未知 action 不由 adapter 拦截或重试", async () => {
    const fixtureState = fixture();
    const result = await createMCPToolHandlers(fixtureState.options).callTool("call_action", {
      action: "extension.privateAction", data: { value: 1 }
    });
    expect(result.isError).toBe(false);
    expect(fixtureState.runtimeCalls).toEqual([{
      action: "extension.privateAction", data: { value: 1 }, options: {}
    }]);
  });
});

function contractFor(entry: ToolCatalogEntry) {
  return entry.mapping.kind === "deviceAction"
    ? DEVICE_ACTION_CONTRACTS.find(contract => contract.action === entry.mapping.action)!
    : HOST_OPERATION_SPECS.find(spec => spec.operation === entry.mapping.operation)!;
}

function json(result: { content: readonly { type: string; text?: string }[] }): JSONObject {
  const text = result.content.find(item => item.type === "text")?.text;
  if (text === undefined) throw new Error("expected JSON text content");
  return JSON.parse(text) as JSONObject;
}

function success(data: JSONObject, artifacts: readonly Artifact[] = []): InvocationResult {
  return { ok: true, data, artifacts: artifacts ?? [], elapsedMs: 0, attempts: 1 };
}

const PNG = Uint8Array.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

function fixture() {
  const runtimeCalls: Array<{ action: string; data: JSONObject; options: InvocationOptions }> = [];
  const probeCalls: string[] = [];
  const workflowCalls: string[] = [];
  return {
    runtimeCalls, probeCalls, workflowCalls,
    options: {
      runtime: { async invoke(action: string, data: JSONObject = {}, options: InvocationOptions = {}) {
        runtimeCalls.push({ action, data, options });
        return success({ action });
      } },
      capabilityProbe: {
        async health() { probeCalls.push("health"); return { mode: "health", connection: "reachable" } as CapabilityReport; },
        async capabilities() { probeCalls.push("capabilities"); return { mode: "capabilities", connection: "reachable" } as CapabilityReport; },
        invocationPolicy() { return undefined; }
      },
      workflowRunner: { async run(operation: WorkflowOperation) { workflowCalls.push(operation); return success({ operation }); } },
      now: () => 5_000
    }
  };
}
