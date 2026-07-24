import { describe, expect, test, vi } from "vitest";
import { HttpActionTransport } from "../../src/runtime/httpActionTransport.js";

describe("HttpActionTransport", () => {
  test("向 baseURL 发送 JSON POST 请求并返回 HTTP 状态和 envelope", async () => {
    const fetchImpl = vi.fn(async () => new Response(JSON.stringify({ code: "ok", data: { pong: true } }), {
      status: 200,
      headers: { "Content-Type": "application/json" }
    }));
    const transport = new HttpActionTransport("http://localhost:38321/", fetchImpl);

    await expect(transport.execute(
      { action: "ping", data: { value: 1 } },
      { timeoutMs: 1000 }
    )).resolves.toEqual({ httpStatus: 200, envelope: { code: "ok", data: { pong: true } } });

    expect(fetchImpl).toHaveBeenCalledWith("http://localhost:38321/", expect.objectContaining({
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ action: "ping", data: { value: 1 } })
    }));
  });

  test.each([
    ["connect", Object.assign(new TypeError("connect failed"), { cause: { code: "ECONNREFUSED" } })],
    ["reset", Object.assign(new TypeError("socket reset"), { cause: { code: "ECONNRESET" } })]
  ] as const)("区分 %s transport failure", async (phase, failure) => {
    const transport = new HttpActionTransport("http://localhost:38321/", async () => { throw failure; });

    await expect(transport.execute({ action: "ping", data: {} }, { timeoutMs: 1000 }))
      .rejects.toMatchObject({
        driverError: { source: "transport", code: "transport_unavailable", transportPhase: phase },
        responseReceived: false
      });
  });

  test("连接阶段和读取 body 阶段均受内部 timeout 控制", async () => {
    vi.useFakeTimers();
    try {
      const connectTransport = new HttpActionTransport("http://localhost:38321/", (_url, init) =>
        new Promise((_resolve, reject) => init?.signal?.addEventListener("abort", () => reject(abortError()), { once: true }))
      );
      const connect = connectTransport.execute({ action: "ping", data: {} }, { timeoutMs: 25 });
      const connectAssertion = expect(connect).rejects.toMatchObject({
        driverError: { code: "transport_timeout", transportPhase: "timeout" },
        responseReceived: false
      });
      await vi.advanceTimersByTimeAsync(25);
      await connectAssertion;

      const readTransport = new HttpActionTransport("http://localhost:38321/", async (_url, init) => ({
        ok: true,
        status: 200,
        text: () => new Promise((_resolve, reject) =>
          init?.signal?.addEventListener("abort", () => reject(abortError()), { once: true }))
      } as Response));
      const read = readTransport.execute({ action: "ping", data: {} }, { timeoutMs: 25 });
      const readAssertion = expect(read).rejects.toMatchObject({
        driverError: { code: "transport_timeout", transportPhase: "timeout" },
        responseReceived: true
      });
      await vi.advanceTimersByTimeAsync(25);
      await readAssertion;
    } finally {
      vi.useRealTimers();
    }
  });

  test("外部 signal abort 不会误报为内部 timeout", async () => {
    const controller = new AbortController();
    const transport = new HttpActionTransport("http://localhost:38321/", (_url, init) =>
      new Promise((_resolve, reject) => init?.signal?.addEventListener("abort", () => reject(abortError()), { once: true }))
    );
    const request = transport.execute({ action: "ping", data: {} }, { timeoutMs: 1000, signal: controller.signal });

    controller.abort();

    await expect(request).rejects.toMatchObject({
      driverError: { code: "transport_unavailable", transportPhase: "abort" },
      responseReceived: false
    });
  });

  test("HTTP 非 2xx、非法 JSON 和非对象 JSON 使用不同稳定错误", async () => {
    const http = new HttpActionTransport("http://localhost:38321/", async () => new Response("server exploded", { status: 503 }));
    await expect(http.execute({ action: "ping", data: {} }, { timeoutMs: 1000 })).rejects.toMatchObject({
      driverError: { source: "http", code: "http_error", status: 503, bodySnippet: "server exploded" },
      responseReceived: true
    });

    const invalidJSON = new HttpActionTransport("http://localhost:38321/", async () => new Response("not-json"));
    await expect(invalidJSON.execute({ action: "ping", data: {} }, { timeoutMs: 1000 })).rejects.toMatchObject({
      driverError: { source: "protocol", code: "protocol_error", protocolIssue: "invalid_json" },
      responseReceived: true
    });

    const invalidObject = new HttpActionTransport("http://localhost:38321/", async () => new Response("[]"));
    await expect(invalidObject.execute({ action: "ping", data: {} }, { timeoutMs: 1000 })).rejects.toMatchObject({
      driverError: { source: "protocol", code: "protocol_error", protocolIssue: "invalid_envelope" },
      responseReceived: true
    });
  });
});

function abortError(): Error {
  return new DOMException("aborted", "AbortError");
}
