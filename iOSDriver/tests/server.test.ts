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
        tools: () => [{ name: "ping", description: "ping", inputSchema: {}, action: "ping" }],
        findByName: () => undefined,
        refresh: async () => ({ toolCount: 1, conflicts: [] })
      },
      client: { call: async () => ({}) }
    });

    const listed = await handlers.listTools();
    expect(listed.tools.map(tool => tool.name)).toEqual(["health_check", "ping"]);
  });

  test("calls dynamic tool by original action", async () => {
    const calls: Array<{ action: string; data: JSONObject }> = [];
    const handlers = createToolHandlers({
      staticTools: {},
      registry: {
        tools: () => [],
        findByName: () => ({ name: "ping", description: "ping", inputSchema: {}, action: "ping" }),
        refresh: async () => ({ toolCount: 1, conflicts: [] })
      },
      client: {
        call: async (action, data = {}) => {
          calls.push({ action, data });
          return { pong: true };
        }
      }
    });

    const result = await handlers.callTool("ping", { verbose: true });
    expect(calls).toEqual([{ action: "ping", data: { verbose: true } }]);
    expect(JSON.parse(textContent(result))).toEqual({ pong: true });
  });

  test("returns png screenshots as image content with metadata text", async () => {
    const handlers = createToolHandlers({
      staticTools: {},
      registry: {
        tools: () => [],
        findByName: () => ({ name: "ui_screenshot", description: "screenshot", inputSchema: {}, action: "ui.screenshot" }),
        refresh: async () => ({ toolCount: 1, conflicts: [] })
      },
      client: {
        call: async () => ({
          image: "base64png",
          format: "png",
          width: 100,
          height: 200,
          scale: 2
        })
      }
    });

    const result = await handlers.callTool("ui_screenshot", {});
    expect(result.content).toEqual([
      { type: "image", data: "base64png", mimeType: "image/png" },
      {
        type: "text",
        text: JSON.stringify({ format: "png", width: 100, height: 200, scale: 2 })
      }
    ]);
  });

  test("refreshes registry once when an iOS dynamic tool is missing, then calls the refreshed action", async () => {
    const calls: Array<{ action: string; data: JSONObject }> = [];
    let refreshed = false;
    const handlers = createToolHandlers({
      staticTools: {},
      registry: {
        tools: () => [],
        findByName: (name: string): ToolDefinition | undefined =>
          refreshed && name === "ui_newAction"
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

    const result = await handlers.callTool("ui_newAction", { value: 1 });

    expect(calls).toEqual([{ action: "ui.newAction", data: { value: 1 } }]);
    const firstText = result.content.find(c => c.type === "text")!;
    expect(JSON.parse(firstText.text)).toEqual({ called: "ui.newAction" });
  });

  test("retries a dynamic call once after transport failure before returning success", async () => {
    const calls: Array<{ action: string; data: JSONObject }> = [];
    const handlers = createToolHandlers({
      staticTools: {},
      registry: {
        tools: () => [],
        findByName: () => ({ name: "ping", description: "ping", inputSchema: {}, action: "ping" }),
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

    const result = await handlers.callTool("ping", { verbose: true });

    expect(calls).toEqual([
      { action: "ping", data: { verbose: true } },
      { action: "ping", data: { verbose: true } }
    ]);
    const secondText = result.content.find(c => c.type === "text")!;
    expect(JSON.parse(secondText.text)).toEqual({ pong: true, attempt: 2 });
  });

  test("adds ping health details when the retry after a transport failure also fails", async () => {
    const calls: string[] = [];
    const handlers = createToolHandlers({
      staticTools: {},
      registry: {
        tools: () => [],
        findByName: () => ({ name: "ping", description: "ping", inputSchema: {}, action: "ping" }),
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

    const result = await handlers.callTool("ping", {});
    const textContent = result.content.find(c => c.type === "text")!;
    const body = JSON.parse(textContent.text);

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

  test("dynamic tool returns invalid_data ios_envelope as isError:true", async () => {
    const handlers = createToolHandlers({
      staticTools: {},
      registry: {
        tools: () => [],
        findByName: () => ({ name: "ui_invalidInput", description: "bad input", inputSchema: {}, action: "ui.invalidInput" }),
        refresh: async () => ({ toolCount: 1, conflicts: [] })
      },
      client: {
        call: async () => {
          throw new IOSExploreStructuredError({
            source: "ios_envelope",
            code: "invalid_data",
            message: "invalid action parameters"
          });
        }
      }
    });

    const result = await handlers.callTool("ui_invalidInput", {});
    const body = JSON.parse(textContent(result));
    expect(body).toMatchObject({ source: "ios_envelope", code: "invalid_data" });
    expect(result.isError).toBe(true);
  });

  test("dynamic tool returns stale_locator ios_envelope as isError:true", async () => {
    const handlers = createToolHandlers({
      staticTools: {},
      registry: {
        tools: () => [],
        findByName: () => ({ name: "ui_staleTap", description: "stale tap", inputSchema: {}, action: "ui.tap" }),
        refresh: async () => ({ toolCount: 1, conflicts: [] })
      },
      client: {
        call: async () => {
          throw new IOSExploreStructuredError({
            source: "ios_envelope",
            code: "stale_locator",
            message: "snapshot expired"
          });
        }
      }
    });

    const result = await handlers.callTool("ui_staleTap", {});
    const body = JSON.parse(textContent(result));
    expect(body).toMatchObject({ source: "ios_envelope", code: "stale_locator" });
    expect(result.isError).toBe(true);
  });

  test("dynamic tool returns unknown_action ios_envelope as isError:true", async () => {
    const handlers = createToolHandlers({
      staticTools: {},
      registry: {
        tools: () => [],
        findByName: () => ({ name: "ui_badAction", description: "bad action", inputSchema: {}, action: "ui.badAction" }),
        refresh: async () => ({ toolCount: 1, conflicts: [] })
      },
      client: {
        call: async () => {
          throw new IOSExploreStructuredError({
            source: "ios_envelope",
            code: "unknown_action",
            message: "no handler for ui.badAction"
          });
        }
      }
    });

    const result = await handlers.callTool("ui_badAction", {});
    const body = JSON.parse(textContent(result));
    expect(body).toMatchObject({ source: "ios_envelope", code: "unknown_action" });
    expect(result.isError).toBe(true);
  });

  test("dynamic tool returns wait_timeout ios_envelope as isError:false", async () => {
    const handlers = createToolHandlers({
      staticTools: {},
      registry: {
        tools: () => [],
        findByName: () => ({ name: "ui_wait", description: "wait", inputSchema: {}, action: "ui.waitAny" }),
        refresh: async () => ({ toolCount: 1, conflicts: [] })
      },
      client: {
        call: async () => {
          throw new IOSExploreStructuredError({
            source: "ios_envelope",
            code: "wait_timeout",
            message: "condition not satisfied within timeout"
          });
        }
      }
    });

    const result = await handlers.callTool("ui_wait", {});
    const body = JSON.parse(textContent(result));
    expect(body).toMatchObject({ source: "ios_envelope", code: "wait_timeout" });
    expect(result.isError).toBe(false);
  });

  test("dynamic tool returns alert_unavailable ios_envelope as isError:false", async () => {
    const handlers = createToolHandlers({
      staticTools: {},
      registry: {
        tools: () => [],
        findByName: () => ({ name: "ui_alertRespond", description: "alert respond", inputSchema: {}, action: "ui.alert.respond" }),
        refresh: async () => ({ toolCount: 1, conflicts: [] })
      },
      client: {
        call: async () => {
          throw new IOSExploreStructuredError({
            source: "ios_envelope",
            code: "alert_unavailable",
            message: "no alert is currently presented"
          });
        }
      }
    });

    const result = await handlers.callTool("ui_alertRespond", {});
    const body = JSON.parse(textContent(result));
    expect(body).toMatchObject({ source: "ios_envelope", code: "alert_unavailable" });
    expect(result.isError).toBe(false);
  });
});

function textContent(result: { content: Array<{ type: string; text?: string }> }): string {
  const first = result.content[0];
  if (first?.type !== "text" || typeof first.text !== "string") {
    throw new Error("expected first content block to be text");
  }
  return first.text;
}
