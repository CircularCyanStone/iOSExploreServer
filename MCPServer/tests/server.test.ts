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
        tools: () => [{ name: "ping", description: "ping", inputSchema: {}, action: "ping" }],
        findByName: () => undefined
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
        findByName: () => ({ name: "ping", description: "ping", inputSchema: {}, action: "ping" })
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
        findByName: () => ({ name: "ui_screenshot", description: "screenshot", inputSchema: {}, action: "ui.screenshot" })
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
});

function textContent(result: { content: Array<{ type: string; text?: string }> }): string {
  const first = result.content[0];
  if (first?.type !== "text" || typeof first.text !== "string") {
    throw new Error("expected first content block to be text");
  }
  return first.text;
}
