import { describe, expect, test } from "vitest";
import { renderInvocationResult } from "../../../src/adapters/mcp/resultRenderer.js";
import type { InvocationResult } from "../../../src/runtime/types.js";

describe("MCP result renderer", () => {
  test("普通 data 渲染为 JSON text", () => {
    const result = renderInvocationResult(success({ pong: true }));
    expect(result).toEqual({
      content: [{ type: "text", text: JSON.stringify({ pong: true }) }],
      isError: false
    });
  });

  test("image artifact 渲染为 image，text metadata 不含原始 base64", () => {
    const raw = Uint8Array.from([137, 80, 78, 71]);
    const invocation: InvocationResult = {
      ok: true,
      data: { format: "png", width: 1, height: 1 },
      artifacts: [{ kind: "image", mimeType: "image/png", data: raw, metadata: { format: "png" } }],
      elapsedMs: 1,
      attempts: 1
    };
    const result = renderInvocationResult(invocation);
    expect(result.content[0]).toEqual({ type: "image", data: Buffer.from(raw).toString("base64"), mimeType: "image/png" });
    expect(result.content[1]).toEqual({ type: "text", text: JSON.stringify(invocation.data) });
    expect(result.content[1]!.type === "text" ? result.content[1]!.text : "").not.toContain(Buffer.from(raw).toString("base64"));
  });

  test("稳定 source/code 决定 isError，call_action unknown_action 保留探索语义", () => {
    const invalid = failure("appEnvelope", "invalid_data", "bad input");
    expect(renderInvocationResult(invalid, "deviceAction").isError).toBe(true);

    const unavailable = failure("appEnvelope", "alert_unavailable", "no alert");
    expect(renderInvocationResult(unavailable, "deviceAction").isError).toBe(false);

    const unknown = failure("appEnvelope", "unknown_action", "not registered");
    expect(renderInvocationResult(unknown, "deviceAction").isError).toBe(true);
    expect(renderInvocationResult(unknown, "callAction").isError).toBe(false);

    expect(renderInvocationResult(failure("transport", "transport_unavailable", "offline")).isError).toBe(true);
  });

  test("wait_and_inspect 吸收 wait_timeout 后的成功结果不是 tool error", () => {
    const result = renderInvocationResult(success({
      wait: { source: "appEnvelope", code: "wait_timeout", message: "not ready" },
      observation: { viewSnapshotID: "snapshot" }
    }), "workflow");
    expect(result.isError).toBe(false);
  });

  test("nextSteps 只由稳定规则生成，不拼接 message", () => {
    const result = renderInvocationResult(failure("appEnvelope", "stale_locator", "secret-user-locator"));
    const payload = JSON.parse(result.content[0]!.type === "text" ? result.content[0]!.text : "{}");
    expect(payload.nextSteps).toEqual([
      "重新调用 ui_inspect 获取 viewSnapshotID，并从最新快照重新选择目标。"
    ]);
    expect(JSON.stringify(payload.nextSteps)).not.toContain("secret-user-locator");
  });
});

function success(data: Record<string, unknown>): InvocationResult {
  return { ok: true, data, artifacts: [], elapsedMs: 0, attempts: 1 };
}

function failure(
  source: "appEnvelope" | "transport",
  code: string,
  message: string
): InvocationResult {
  return { ok: false, error: { source, code, message }, elapsedMs: 0, attempts: 1 };
}
