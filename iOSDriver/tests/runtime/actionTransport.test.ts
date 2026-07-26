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
        headers: new Headers(),
        body: null,
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

  test("Content-Length 超过上限时不读取 body 并返回 typed size error", async () => {
    let cancelled = false;
    const body = new ReadableStream<Uint8Array>({
      pull(controller) { controller.enqueue(new Uint8Array([1])); },
      cancel() { cancelled = true; }
    });
    const transport = new HttpActionTransport("http://localhost:38321/", {
      fetchImpl: async () => new Response(body, { headers: { "Content-Length": "100" } }),
      maxResponseBodyBytes: 32
    });

    await expect(transport.execute({ action: "ping", data: {} }, { timeoutMs: 1000 })).rejects.toMatchObject({
      driverError: {
        source: "protocol",
        code: "protocol_error",
        protocolIssue: "response_too_large",
        action: "ping"
      },
      responseReceived: true
    });
    expect(cancelled).toBe(true);
  });

  test.each([undefined, "1"])("%s Content-Length 不能绕过流式 body 上限", async (declaredLength) => {
    const headers = declaredLength === undefined ? undefined : { "Content-Length": declaredLength };
    const transport = new HttpActionTransport("http://localhost:38321/", {
      fetchImpl: async () => new Response("x".repeat(33), { headers }),
      maxResponseBodyBytes: 32
    });

    await expect(transport.execute({ action: "ping", data: {} }, { timeoutMs: 1000 })).rejects.toMatchObject({
      driverError: { source: "protocol", code: "protocol_error", protocolIssue: "response_too_large" },
      responseReceived: true
    });
  });

  test("reader cancel 失败不会覆盖已分类的 body 超限错误", async () => {
    const body = new ReadableStream<Uint8Array>({
      start(controller) { controller.enqueue(new Uint8Array(33)); },
      cancel() { throw new Error("cancel failed"); }
    });
    const transport = new HttpActionTransport("http://localhost:38321/", {
      fetchImpl: async () => new Response(body, { headers: { "Content-Length": "1" } }),
      maxResponseBodyBytes: 32
    });

    await expect(transport.execute({ action: "ping", data: {} }, { timeoutMs: 1000 })).rejects.toMatchObject({
      driverError: { source: "protocol", code: "protocol_error", protocolIssue: "response_too_large" },
      responseReceived: true
    });
  });

  test("response body 上限配置必须是正安全整数", () => {
    expect(() => new HttpActionTransport("http://localhost:38321/", { maxResponseBodyBytes: 0 })).toThrow(RangeError);
    expect(() => new HttpActionTransport("http://localhost:38321/", { maxResponseBodyBytes: Number.MAX_VALUE })).toThrow(RangeError);
  });
});

function abortError(): Error {
  return new DOMException("aborted", "AbortError");
}
