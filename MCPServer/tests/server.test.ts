import { describe, expect, test } from "vitest";
import { IOSExploreStructuredError } from "../src/errors.js";
import { createToolHandlers } from "../src/server.js";
import type { JSONObject, ToolDefinition } from "../src/types.js";

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
        findByName: () => undefined,
        refresh: async () => ({ toolCount: 1, conflicts: [] })
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
        findByName: () => ({ name: "ios_ping", description: "ping", inputSchema: {}, action: "ping" }),
        refresh: async () => ({ toolCount: 1, conflicts: [] })
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

  test("refreshes registry once when an ios dynamic tool is missing, then calls the refreshed action", async () => {
    const calls: Array<{ action: string; data: JSONObject }> = [];
    let refreshed = false;
    const handlers = createToolHandlers({
      staticTools: {},
      registry: {
        tools: () => [],
        findByName: (name: string): ToolDefinition | undefined =>
          refreshed && name === "ios_ui_newAction"
            ? { name, description: "new action", inputSchema: {}, action: "ui.newAction" }
            : undefined,
        refresh: async () => {
          refreshed = true;
          return { toolCount: 1, conflicts: [] };
        }
      },
      client: {
        call: async (action, data = {}) => {
          calls.push({ action, data });
          return { called: action };
        }
      }
    });

    const result = await handlers.callTool("ios_ui_newAction", { value: 1 });

    expect(calls).toEqual([{ action: "ui.newAction", data: { value: 1 } }]);
    expect(JSON.parse(result.content[0]!.text)).toEqual({ called: "ui.newAction" });
  });

  test("retries a dynamic call once after transport failure before returning success", async () => {
    const calls: Array<{ action: string; data: JSONObject }> = [];
    const handlers = createToolHandlers({
      staticTools: {},
      registry: {
        tools: () => [],
        findByName: () => ({ name: "ios_ping", description: "ping", inputSchema: {}, action: "ping" }),
        refresh: async () => ({ toolCount: 1, conflicts: [] })
      },
      client: {
        call: async (action, data = {}) => {
          calls.push({ action, data });
          if (calls.length === 1) {
            throw new IOSExploreStructuredError({
              source: "transport",
              code: "connection_failed",
              message: "fetch failed",
              action
            });
          }
          return { pong: true, attempt: calls.length };
        }
      }
    });

    const result = await handlers.callTool("ios_ping", { verbose: true });

    expect(calls).toEqual([
      { action: "ping", data: { verbose: true } },
      { action: "ping", data: { verbose: true } }
    ]);
    expect(JSON.parse(result.content[0]!.text)).toEqual({ pong: true, attempt: 2 });
  });

  test("adds ping health details when the retry after a transport failure also fails", async () => {
    const calls: string[] = [];
    const handlers = createToolHandlers({
      staticTools: {},
      registry: {
        tools: () => [],
        findByName: () => ({ name: "ios_ping", description: "ping", inputSchema: {}, action: "ping" }),
        refresh: async () => ({ toolCount: 1, conflicts: [] })
      },
      client: {
        call: async action => {
          calls.push(action);
          throw new IOSExploreStructuredError({
            source: "transport",
            code: "connection_failed",
            message: "fetch failed",
            action
          });
        }
      }
    });

    const result = await handlers.callTool("ios_ping", {});
    const body = JSON.parse(result.content[0]!.text);

    expect(result.isError).toBe(true);
    expect(calls).toEqual(["ping", "ping", "ping"]);
    expect(body).toMatchObject({
      source: "transport",
      code: "connection_failed",
      retry: { attempted: true, delayMs: 200, succeeded: false },
      healthCheck: { ok: false },
      nextSteps: expect.arrayContaining([expect.stringContaining("IOS_EXPLORE_AUTOSTART=1")])
    });
  });
});
