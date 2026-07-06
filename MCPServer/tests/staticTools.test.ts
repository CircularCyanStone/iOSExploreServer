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
    expect(JSON.parse(result.content[0]!.text)).toMatchObject({
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
    expect(JSON.parse(result.content[0]!.text).viewSnapshotID).toBe("snap-1");
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
    expect(JSON.parse(result.content[0]!.text)).toMatchObject({
      wait: { code: "wait_timeout" },
      observation: { viewSnapshotID: "snap-after" }
    });
    expect(result.isError).toBeFalsy();
  });
});

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
