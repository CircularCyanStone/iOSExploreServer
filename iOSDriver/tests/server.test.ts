import { describe, expect, test } from "vitest";
import { createToolHandlers } from "../src/server.js";

const tool = (name: string, handler = async () => ({ content: [{ type: "text" as const, text: "{}" }] })) => ({
  name, description: name, inputSchema: { type: "object" }, handler
});

describe("静态 MCP handlers", () => {
  test("tools/list 只返回静态工具，且 App 不可达不影响列表", async () => {
    const handlers = createToolHandlers({ staticTools: { health_check: tool("health_check"), call_action: tool("call_action") } });
    await expect(handlers.listTools()).resolves.toEqual({ tools: [
      { name: "health_check", description: "health_check", inputSchema: { type: "object" } },
      { name: "call_action", description: "call_action", inputSchema: { type: "object" } }
    ] });
  });

  test("未知 MCP tool 直接返回 unknown_tool，不调用 App help", async () => {
    const handlers = createToolHandlers({ staticTools: { health_check: tool("health_check") } });
    const result = await handlers.callTool("greet", {});
    expect(result.isError).toBe(true);
    expect(JSON.parse(result.content[0]!.type === "text" ? result.content[0]!.text : "{}")).toMatchObject({ code: "unknown_tool" });
    // createToolHandlers 没有 App client 或 registry 依赖，未知工具路径不会发起任何 HTTP 请求。
  });
});
