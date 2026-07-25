import { describe, expect, test } from "vitest";
import { createMCPToolHandlers, type MCPCapabilityProbe } from "../../../src/adapters/mcp/server.js";
import { STATIC_TOOL_NAMES } from "../../../src/adapters/mcp/toolMappings.js";
import type { CapabilityReport } from "../../../src/runtime/capabilityProbe.js";
import type { InvocationOptions, InvocationPolicy } from "../../../src/runtime/driverRuntime.js";
import type { InvocationResult } from "../../../src/runtime/types.js";
import type { JSONObject } from "../../../src/types.js";
import type { WorkflowOperation } from "../../../src/workflows/types.js";
import { hostLogRecorder } from "../../support/hostLogRecorder.js";

describe("MCP adapter handlers", () => {
  test("tools/list 离线返回固定 28 项且不调用 runtime/probe/workflow", async () => {
    const fixture = createFixture();
    const handlers = createMCPToolHandlers(fixture.options);

    const first = await handlers.listTools();
    const second = await handlers.listTools();

    expect(first).toEqual(second);
    expect(first.tools.map(tool => tool.name)).toEqual(STATIC_TOOL_NAMES);
    expect(fixture.runtimeCalls).toEqual([]);
    expect(fixture.probeCalls).toEqual([]);
    expect(fixture.workflowCalls).toEqual([]);
  });

  test("device action、capability 和 workflow 分别路由到明确边界", async () => {
    const fixture = createFixture();
    const handlers = createMCPToolHandlers(fixture.options);

    await handlers.callTool("ui_inspect", { maxDepth: 2 });
    await handlers.callTool("health_check", {});
    await handlers.callTool("check_capabilities", {});
    await handlers.callTool("wait_and_inspect", { conditions: [], timeoutMs: 7_000 });
    await handlers.callTool("ui_tap_and_inspect", { viewSnapshotID: "v", path: "/0", stableTimeMs: 400 });

    expect(fixture.runtimeCalls[0]).toMatchObject({ action: "ui.inspect", data: { maxDepth: 2 } });
    expect(fixture.probeCalls).toEqual(["health", "capabilities"]);
    expect(fixture.workflowCalls.map(call => call.operation)).toEqual(["wait_and_inspect", "tap_and_inspect"]);
    expect(fixture.workflowCalls[0]!.deadlineAtMs).toBe(22_000);
    expect(fixture.workflowCalls[1]!.deadlineAtMs).toBe(16_400);
  });

  test("call_action 接受任意 action 并只转交已知 help policy", async () => {
    const policy: InvocationPolicy = { idempotency: "readOnly", timeoutClass: "wait" };
    const fixture = createFixture({ policy });
    const handlers = createMCPToolHandlers(fixture.options);

    await handlers.callTool("call_action", { action: "extension.search", data: { timeoutMs: 4000 } });

    expect(fixture.runtimeCalls).toEqual([{
      action: "extension.search",
      data: { timeoutMs: 4000 },
      options: { policy }
    }]);
  });

  test("未知 extension 默认不带 policy，adapter 不执行 retry", async () => {
    const fixture = createFixture();
    const handlers = createMCPToolHandlers(fixture.options);

    await handlers.callTool("call_action", { action: "extension.mutate", data: { value: 1 } });

    expect(fixture.runtimeCalls).toEqual([{
      action: "extension.mutate",
      data: { value: 1 },
      options: {}
    }]);
  });

  test("未知工具返回 unknown_tool 且不触碰任何执行边界", async () => {
    const fixture = createFixture();
    const result = await createMCPToolHandlers(fixture.options).callTool("extension_tool", { secret: "value" });
    expect(result.isError).toBe(true);
    const payload = JSON.parse(result.content[0]!.type === "text" ? result.content[0]!.text : "{}");
    expect(payload).toMatchObject({ source: "mcp_server", code: "unknown_tool" });
    expect(JSON.stringify(payload)).not.toContain("extension_tool");
    expect(fixture.runtimeCalls).toEqual([]);
    expect(fixture.probeCalls).toEqual([]);
    expect(fixture.workflowCalls).toEqual([]);
    expect(fixture.logEntries().map(entry => entry.event)).toEqual(["mcp.tool.start", "mcp.tool.complete"]);
    expect(fixture.logEntries()[1]).toMatchObject({ tool: "extension_tool", outcome: "failure", code: "unknown_tool" });
    expect(fixture.logLines.join("")).not.toContain("secret");
  });

  test("未分类异常统一返回 unexpected 且不泄露原始 message", async () => {
    const fixture = createFixture();
    const handlers = createMCPToolHandlers({
      ...fixture.options,
      runtime: {
        async invoke() {
          throw new Error("secret runtime details");
        }
      }
    });

    const result = await handlers.callTool("ui_inspect", {});

    expect(result.isError).toBe(true);
    const payload = JSON.parse(result.content[0]!.type === "text" ? result.content[0]!.text : "{}");
    expect(payload).toEqual({
      source: "mcp_server",
      code: "unexpected",
      message: "Unexpected host error"
    });
    expect(JSON.stringify(payload)).not.toContain("secret runtime details");
    expect(fixture.logEntries().at(-1)).toMatchObject({ event: "mcp.tool.unexpected", tool: "ui_inspect", errorType: "Error" });
    expect(fixture.logLines.join("")).not.toContain("secret runtime details");
  });
});

function createFixture(options: { policy?: InvocationPolicy } = {}) {
  const runtimeCalls: Array<{ action: string; data: JSONObject; options: InvocationOptions }> = [];
  const probeCalls: string[] = [];
  const workflowCalls: Array<{ operation: WorkflowOperation; input: JSONObject; deadlineAtMs: number }> = [];
  const recorded = hostLogRecorder();
  const runtime = {
    async invoke(action: string, data: JSONObject = {}, invocationOptions: InvocationOptions = {}) {
      runtimeCalls.push({ action, data, options: invocationOptions });
      return success({ action });
    }
  };
  const report = { mode: "health", connection: "reachable" } as CapabilityReport;
  const capabilityProbe: MCPCapabilityProbe = {
    async health() { probeCalls.push("health"); return report; },
    async capabilities() { probeCalls.push("capabilities"); return { ...report, mode: "capabilities" }; },
    invocationPolicy() { return options.policy; }
  };
  const workflowRunner = {
    async run(operation: WorkflowOperation, input: JSONObject, runOptions: { deadlineAtMs: number }) {
      workflowCalls.push({ operation, input, deadlineAtMs: runOptions.deadlineAtMs });
      return success({ operation });
    }
  };
  return {
    runtimeCalls, probeCalls, workflowCalls,
    logLines: recorded.lines,
    logEntries: recorded.entries,
    options: { runtime, capabilityProbe, workflowRunner, now: () => 5_000, logger: recorded.logger }
  };
}

function success(data: JSONObject): InvocationResult {
  return { ok: true, data, artifacts: [], elapsedMs: 0, attempts: 1 };
}
