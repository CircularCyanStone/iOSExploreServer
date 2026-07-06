import { describe, expect, test } from "vitest";
import { createStaticTools } from "../src/staticTools.js";
import type { JSONObject } from "../src/types.js";

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

  test("observe calls ui.viewTargets with provided options", async () => {
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

    const result = await (tools.observe!).handler({ maxTargets: 100 });
    expect(calls).toEqual([{ action: "ui.viewTargets", data: { maxTargets: 100 } }]);
    expect(JSON.parse(textContent(result)).viewSnapshotID).toBe("snap-1");
  });

  test("observe strips hierarchy-only fields in default viewTargets mode", async () => {
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

    // detailLevel is topViewHierarchy-only; maxDepth is shared with ui.viewTargets and stays.
    await (tools.observe!).handler({ detailLevel: "full", maxDepth: 2, maxTargets: 100 });
    expect(calls).toEqual([{ action: "ui.viewTargets", data: { maxDepth: 2, maxTargets: 100 } }]);
  });

  test("observe can call ui.topViewHierarchy in hierarchy mode", async () => {
    const calls: Array<{ action: string; data: JSONObject }> = [];
    const tools = createStaticTools({
      client: {
        call: async (action, data = {}) => {
          calls.push({ action, data });
          return { root: { type: "UIView" } };
        }
      },
      registry: fakeRegistry(0)
    });

    const result = await (tools.observe!).handler({
      mode: "topViewHierarchy",
      includeHidden: true,
      detailLevel: "full",
      maxDepth: 3,
      maxTargets: 100
    });
    expect(calls).toEqual([
      {
        action: "ui.topViewHierarchy",
        data: { includeHidden: true, detailLevel: "full", maxDepth: 3 }
      }
    ]);
    expect(JSON.parse(textContent(result)).root.type).toBe("UIView");
  });

  test("wait_and_observe observes after wait timeout", async () => {
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

    const result = await (tools.wait_and_observe!).handler({ conditions: [{ id: "gone", mode: "textExists", text: "Done" }] });
    expect(calls).toEqual(["ui.waitAny", "ui.viewTargets"]);
    expect(JSON.parse(textContent(result))).toMatchObject({
      wait: { code: "wait_timeout" },
      observation: { viewSnapshotID: "snap-after" }
    });
    expect(result.isError).toBeFalsy();
  });

  test("wait_and_observe strips unknown viewTargetsOptions before observing", async () => {
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

    await (tools.wait_and_observe!).handler({
      conditions: [{ id: "idle", mode: "idle" }],
      viewTargetsOptions: {
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
        action: "ui.viewTargets",
        data: { includeHidden: true, accessibilityIdentifier: "login.submit", maxDepth: 2 }
      }
    ]);
  });

  test("wait_and_observe schema rejects detailLevel inside viewTargetsOptions", () => {
    const schema = createStaticTools({
      client: { call: async () => ({}) },
      registry: fakeRegistry(0)
    }).wait_and_observe!.inputSchema;

    const viewTargetsOptionsSchema = (schema as { properties: { viewTargetsOptions: { properties: Record<string, unknown>; additionalProperties: boolean } } }).properties.viewTargetsOptions;

    // schema-level additionalProperties:false lists which fields are allowed
    const allowedFields = Object.keys(viewTargetsOptionsSchema.properties);
    expect(allowedFields.sort()).toEqual(
      [
        "includeHidden",
        "includeDisabled",
        "includeStaticText",
        "includeContainers",
        "maxDepth",
        "accessibilityIdentifier",
        "accessibilityIdentifierPrefix",
        "textLimit",
        "maxTargets"
      ].sort()
    );
    expect(viewTargetsOptionsSchema.additionalProperties).toBe(false);
    // detailLevel is a topViewHierarchy-only field and must NOT be in viewTargetsOptions' allowed set
    expect(allowedFields).not.toContain("detailLevel");
  });

  test("wait_and_observe handler passes viewTargetsOptions.maxDepth through to ui.viewTargets", async () => {
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

    await (tools.wait_and_observe!).handler({
      conditions: [{ id: "idle", mode: "idle" }],
      viewTargetsOptions: {
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
        action: "ui.viewTargets",
        data: { maxDepth: 3, maxTargets: 100 }
      }
    ]);
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
    }
  };
}
