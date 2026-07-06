import { describe, expect, test } from "vitest";
import { createToolHandlers } from "../src/server.js";
import type { JSONObject } from "../src/types.js";

describe("server handlers", () => {
  test("lists fixed and dynamic tools", async () => {
    const handlers = createToolHandlers({
      staticTools: {
        health_check: {
          name: "health_check",
          description: "health",
          inputSchema: { type: "object", properties: {} },
          handler: async () => ({ content: [{ type: "text", text: "{}" }] })
        }
      },
      registry: {
        tools: () => [{ name: "ios_ping", description: "ping", inputSchema: {}, action: "ping" }],
        findByName: () => undefined
      },
      client: { call: async () => ({}) }
    });

    const listed = await handlers.listTools();
    expect(listed.tools.map(tool => tool.name)).toEqual(["health_check", "ios_ping"]);
  });

  test("calls dynamic tool by original action", async () => {
    const calls: Array<{ action: string; data: JSONObject }> = [];
    const handlers = createToolHandlers({
      staticTools: {},
      registry: {
        tools: () => [],
        findByName: () => ({ name: "ios_ping", description: "ping", inputSchema: {}, action: "ping" })
      },
      client: {
        call: async (action, data = {}) => {
          calls.push({ action, data });
          return { pong: true };
        }
      }
    });

    const result = await handlers.callTool("ios_ping", { verbose: true });
    expect(calls).toEqual([{ action: "ping", data: { verbose: true } }]);
    expect(JSON.parse(result.content[0]!.text)).toEqual({ pong: true });
  });
});
