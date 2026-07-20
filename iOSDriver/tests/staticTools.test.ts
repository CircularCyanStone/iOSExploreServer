import { describe, expect, test } from "vitest";
import { createStaticTools } from "../src/staticTools.js";
import type { JSONObject } from "../src/types.js";
import { IOSExploreStructuredError } from "../src/errors.js";

describe("static tools", () => {
  test("health_check reports online status", async () => {
    const calls: string[] = [];
    const tools = createStaticTools({
      client: {
        call: async action => {
          calls.push(action);
          return action === "ping" ? { pong: true } : { commands: [] };
        }
      },
      registry: fakeRegistry(3)
    });

    const result = await (tools.health_check!).handler({});
    expect(JSON.parse(textContent(result))).toMatchObject({
      ok: true,
      dynamicToolCount: 3
    });
    expect(calls).toEqual(["ping", "help"]);
  });

  test("observe 已废弃，不应出现在静态工具列表", () => {
    const tools = createStaticTools({
      client: { call: async () => ({}) },
      registry: fakeRegistry(0)
    });
    expect(tools.observe).toBeUndefined();
  });

  test("常用 UI action 有静态桥接工具，避免动态工具未展示时只能 call_action", () => {
    const tools = createStaticTools({
      client: { call: async () => ({}) },
      registry: fakeRegistry(0)
    });

    expect(Object.keys(tools)).toEqual(
      expect.arrayContaining([
        "ui_inspect",
        "ui_input",
        "ui_tap",
        "ui_control_sendAction",
        "ui_keyboard_dismiss",
        "ui_scrollToElement"
      ])
    );
  });

  test("ui_inspect static bridge forwards input to ui.inspect", async () => {
    const calls: Array<{ action: string; data: JSONObject }> = [];
    const tools = createStaticTools({
      client: {
        call: async (action, data = {}) => {
          calls.push({ action, data });
          return { viewSnapshotID: "snap-1", targets: [] };
        }
      },
      registry: fakeRegistry(0)
    });

    const result = await (tools.ui_inspect!).handler({
      accessibilityIdentifierPrefix: "login_",
      maxDepth: 8,
      maxTargets: 120
    });

    expect(calls).toEqual([
      {
        action: "ui.inspect",
        data: { accessibilityIdentifierPrefix: "login_", maxDepth: 8, maxTargets: 120 }
      }
    ]);
    expect(JSON.parse(textContent(result))).toMatchObject({ viewSnapshotID: "snap-1" });
    expect(result.isError).toBeFalsy();
  });

  test("ui_input static bridge preserves invalid_data as error result", async () => {
    const tools = createStaticTools({
      client: {
        call: async () => {
          const error = new Error("bad input") as Error & { source: string; code: string };
          error.source = "ios_envelope";
          error.code = "invalid_data";
          throw error;
        }
      },
      registry: fakeRegistry(0)
    });

    const result = await (tools.ui_input!).handler({ accessibilityIdentifier: "field", text: "abc" });
    const body = JSON.parse(textContent(result));
    expect(body).toMatchObject({ source: "ios_envelope", code: "invalid_data" });
    expect(result.isError).toBe(true);
  });

  test("wait_and_inspect 调用 ui.inspect 而非 ui.viewTargets", async () => {
    const calls: string[] = [];
    const tools = createStaticTools({
      client: {
        call: async (action) => {
          calls.push(action);
          if (action === "ui.waitAny") {
            const error = new Error("timeout") as Error & { source: string; code: string; action: string };
            error.source = "ios_envelope";
            error.code = "wait_timeout";
            error.action = "ui.waitAny";
            throw error;
          }
          return { viewSnapshotID: "snap-after", targets: [] };
        }
      },
      registry: fakeRegistry(0)
    });

    const result = await (tools.wait_and_inspect!).handler({ conditions: [{ id: "gone", mode: "textExists", text: "Done" }] });
    expect(calls).toEqual(["ui.waitAny", "ui.inspect"]);
    expect(calls).not.toContain("ui.viewTargets");
    expect(JSON.parse(textContent(result))).toMatchObject({
      wait: { code: "wait_timeout" },
      observation: { viewSnapshotID: "snap-after" }
    });
    expect(result.isError).toBeFalsy();
  });

  test("wait_and_inspect strips unknown inspectOptions before inspecting", async () => {
    const calls: Array<{ action: string; data: JSONObject }> = [];
    const tools = createStaticTools({
      client: {
        call: async (action, data = {}) => {
          calls.push({ action, data });
          return action === "ui.waitAny" ? { satisfied: true } : { viewSnapshotID: "snap-after", targets: [] };
        }
      },
      registry: fakeRegistry(0)
    });

    await (tools.wait_and_inspect!).handler({
      conditions: [{ id: "idle", mode: "idle" }],
      inspectOptions: {
        includeHidden: true,
        accessibilityIdentifier: "login.submit",
        detailLevel: "full",
        maxDepth: 2,
        unknown: true
      }
    });

    expect(calls).toEqual([
      {
        action: "ui.waitAny",
        data: { conditions: [{ id: "idle", mode: "idle" }] }
      },
      {
        action: "ui.inspect",
        data: { includeHidden: true, accessibilityIdentifier: "login.submit", maxDepth: 2 }
      }
    ]);
  });

  test("wait_and_inspect strips unknown top-level keys from ui.waitAny input", async () => {
    const calls: Array<{ action: string; data: JSONObject }> = [];
    const tools = createStaticTools({
      client: {
        call: async (action, data = {}) => {
          calls.push({ action, data });
          return action === "ui.waitAny" ? { satisfied: true } : { viewSnapshotID: "snap-after", targets: [] };
        }
      },
      registry: fakeRegistry(0)
    });

    await (tools.wait_and_inspect!).handler({
      conditions: [{ id: "gone", mode: "textExists", text: "Done" }],
      foo: "bar",
      extra: 42
    });

    const waitCall = calls.find(c => c.action === "ui.waitAny")!;
    // foo and extra must not leak through to ui.waitAny
    expect(waitCall.data).toEqual({
      conditions: [{ id: "gone", mode: "textExists", text: "Done" }]
    });
    expect(waitCall.data).not.toHaveProperty("foo");
    expect(waitCall.data).not.toHaveProperty("extra");
  });

  test("wait_and_inspect schema uses inspectOptions 且不含已删字段", () => {
    const schema = createStaticTools({
      client: { call: async () => ({}) },
      registry: fakeRegistry(0)
    }).wait_and_inspect!.inputSchema;

    const properties = (schema as { properties: Record<string, unknown> }).properties;
    // 字段名从 viewTargetsOptions 改为 inspectOptions
    expect(properties.inspectOptions).toBeDefined();
    expect(properties.viewTargetsOptions).toBeUndefined();

    const inspectOptionsSchema = (properties as { inspectOptions: { properties: Record<string, unknown>; additionalProperties: boolean } }).inspectOptions;

    // schema-level additionalProperties:false lists which fields are allowed
    const allowedFields = Object.keys(inspectOptionsSchema.properties);
    expect(allowedFields.sort()).toEqual(
      [
        "includeHidden",
        "maxDepth",
        "accessibilityIdentifier",
        "accessibilityIdentifierPrefix",
        "textLimit",
        "maxTargets"
      ].sort()
    );
    // Task 3 已从 Swift inputSchema 删除的三个字段不应再透传
    expect(allowedFields).not.toContain("includeDisabled");
    expect(allowedFields).not.toContain("includeStaticText");
    expect(allowedFields).not.toContain("includeContainers");
    expect(inspectOptionsSchema.additionalProperties).toBe(false);
    // detailLevel is a topViewHierarchy-only field and must NOT be in inspectOptions' allowed set
    expect(allowedFields).not.toContain("detailLevel");
  });

  test("wait_and_inspect handler passes inspectOptions.maxDepth through to ui.inspect", async () => {
    const calls: Array<{ action: string; data: JSONObject }> = [];
    const tools = createStaticTools({
      client: {
        call: async (action, data = {}) => {
          calls.push({ action, data });
          return action === "ui.waitAny" ? { satisfied: true } : { viewSnapshotID: "snap-after", targets: [] };
        }
      },
      registry: fakeRegistry(0)
    });

    await (tools.wait_and_inspect!).handler({
      conditions: [{ id: "idle", mode: "idle" }],
      inspectOptions: {
        maxDepth: 3,
        maxTargets: 100
      }
    });

    expect(calls).toEqual([
      {
        action: "ui.waitAny",
        data: { conditions: [{ id: "idle", mode: "idle" }] }
      },
      {
        action: "ui.inspect",
        data: { maxDepth: 3, maxTargets: 100 }
      }
    ]);
  });

  // ----- call_action 修复测试 -----

  test("call_action forwards action and data to client.call", async () => {
    const calls: Array<{ action: string; data: JSONObject }> = [];
    const tools = createStaticTools({
      client: {
        call: async (action, data = {}) => {
          calls.push({ action, data });
          return { pong: true };
        }
      },
      registry: fakeRegistry(0)
    });

    const result = await (tools.call_action!).handler({ action: "echo", data: { msg: "hello" } });
    expect(calls).toEqual([{ action: "echo", data: { msg: "hello" } }]);
    expect(JSON.parse(textContent(result))).toEqual({ pong: true });
    expect(result.isError).toBeFalsy();
  });

  test("call_action returns error when action is empty string", async () => {
    const tools = createStaticTools({
      client: { call: async () => ({}) },
      registry: fakeRegistry(0)
    });

    const result = await (tools.call_action!).handler({ action: "", data: {} });
    const body = JSON.parse(textContent(result));
    expect(body).toMatchObject({ source: "mcp_server", code: "missing_action" });
    expect(result.isError).toBe(true);
  });

  test("call_action returns error when action field is missing", async () => {
    const tools = createStaticTools({
      client: { call: async () => ({}) },
      registry: fakeRegistry(0)
    });

    // input.action 会是 undefined → 被转为 ""
    const result = await (tools.call_action!).handler({ data: {} });
    const body = JSON.parse(textContent(result));
    expect(body).toMatchObject({ source: "mcp_server", code: "missing_action" });
    expect(result.isError).toBe(true);
  });

  test("call_action returns stale_locator ios_envelope failure as error result", async () => {
    const tools = createStaticTools({
      client: {
        call: async () => {
          const error = new Error("stale snapshot") as Error & { source: string; code: string };
          error.source = "ios_envelope";
          error.code = "stale_locator";
          throw error;
        }
      },
      registry: fakeRegistry(0)
    });

    const result = await (tools.call_action!).handler({ action: "ui.tap", data: {} });
    const body = JSON.parse(textContent(result));
    expect(body).toMatchObject({ source: "ios_envelope", code: "stale_locator" });
    // stale_locator 升格为 isError=true，Agent 应重新 inspect 后再操作
    expect(result.isError).toBe(true);
  });

  test("call_action returns invalid_data ios_envelope failure as error result", async () => {
    const tools = createStaticTools({
      client: {
        call: async () => {
          const error = new Error("bad input") as Error & { source: string; code: string };
          error.source = "ios_envelope";
          error.code = "invalid_data";
          throw error;
        }
      },
      registry: fakeRegistry(0)
    });

    const result = await (tools.call_action!).handler({ action: "ui.tap", data: {} });
    const body = JSON.parse(textContent(result));
    expect(body).toMatchObject({ source: "ios_envelope", code: "invalid_data" });
    // invalid_data 升格为 isError=true，Agent 应修正参数
    expect(result.isError).toBe(true);
  });

  test("call_action returns unknown_action ios_envelope failure as non-error result", async () => {
    const tools = createStaticTools({
      client: {
        call: async () => {
          const error = new Error("no handler") as Error & { source: string; code: string };
          error.source = "ios_envelope";
          error.code = "unknown_action";
          throw error;
        }
      },
      registry: fakeRegistry(0)
    });

    const result = await (tools.call_action!).handler({ action: "nonexistent", data: {} });
    const body = JSON.parse(textContent(result));
    expect(body).toMatchObject({ source: "ios_envelope", code: "unknown_action" });
    // call_action 的 unknown_action 保持 isError=false（兜底工具本就让 agent 猜 action 名）
    expect(result.isError).toBe(false);
  });

  test("call_action returns transport error as enriched error result", async () => {
    // transport 失败现在与动态工具路径一致：1 次重试 + healthCheck + nextSteps（issue 8）
    let calls = 0;
    const tools = createStaticTools({
      client: {
        call: async (action) => {
          calls++;
          // ping 在 enrichTransportError 里被调用，回个 ok 别让它自己也 throw
          if (action === "ping") return { pong: true };
          throw new IOSExploreStructuredError({
            source: "transport",
            code: "connection_failed",
            message: "fetch failed",
            action
          });
        }
      },
      registry: fakeRegistry(0)
    });

    const result = await (tools.call_action!).handler({ action: "echo", data: {} });
    const body = JSON.parse(textContent(result));
    expect(body).toMatchObject({ source: "transport", code: "connection_failed" });
    // 与动态工具路径一致的丰富字段
    expect(body.retry).toEqual({ attempted: true, delayMs: 200, succeeded: false });
    expect(body.healthCheck).toEqual({ ok: true, ping: { pong: true } });
    expect(Array.isArray(body.nextSteps)).toBe(true);
    // 重试过 2 次（首次 + 1 次重试），加 1 次 ping
    expect(calls).toBe(3);
    // transport 错误仍是真实错误
    expect(result.isError).toBe(true);
  });

  test("refresh_tools returns dynamicToolCount field consistent with health_check", async () => {
    const tools = createStaticTools({
      client: { call: async () => ({}) },
      registry: fakeRegistry(5)
    });

    const result = await (tools.refresh_tools!).handler({});
    const body = JSON.parse(textContent(result));
    // refresh_tools 不再返回 toolCount，统一使用 dynamicToolCount
    expect(body.toolCount).toBeUndefined();
    expect(body).toMatchObject({ dynamicToolCount: 5 });
    expect(Array.isArray(body.conflicts)).toBe(true);
    expect(result.isError).toBeFalsy();
  });
});

function textContent(result: { content: Array<{ type: string; text?: string }> }): string {
  const first = result.content[0];
  if (first?.type !== "text" || typeof first.text !== "string") {
    throw new Error("expected first content block to be text");
  }
  return first.text;
}

function fakeRegistry(toolCount: number) {
  return {
    async refresh() {
      return { toolCount, conflicts: [] as unknown[], error: undefined };
    },
    tools() {
      return new Array(toolCount).fill(null);
    },
    conflicts() {
      return [] as unknown[];
    },
    refreshError() {
      return undefined;
    }
  };
}
