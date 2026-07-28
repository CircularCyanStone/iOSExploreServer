import { afterEach, describe, expect, test, vi } from "vitest";
import { IOSExploreClient } from "../src/iosExploreClient.js";

describe("IOSExploreClient compatibility facade", () => {
  afterEach(() => vi.unstubAllGlobals());

  test("保留 constructor(config) 与 call(action, data) 成功行为", async () => {
    const fetchImpl = vi.fn(async () => response({ code: "ok", data: { pong: true } }));
    vi.stubGlobal("fetch", fetchImpl);
    const client = new IOSExploreClient({ baseURL: "http://localhost:38321/", requestTimeoutMs: 1000 });

    await expect(client.call("ping", {})).resolves.toEqual({ pong: true });
    expect(fetchImpl).toHaveBeenCalledTimes(1);
  });

  test("兼容 facade 会把 authToken 传给 HTTP transport", async () => {
    const fetchImpl = vi.fn(async () => response({ code: "ok", data: { pong: true } }));
    vi.stubGlobal("fetch", fetchImpl);
    const client = new IOSExploreClient({
      baseURL: "http://localhost:38321/",
      requestTimeoutMs: 1000,
      authToken: "secret-token"
    });

    await client.call("ping", {});

    expect(fetchImpl).toHaveBeenCalledWith("http://localhost:38321/", expect.objectContaining({
      headers: expect.objectContaining({ "X-Auth-Token": "secret-token" })
    }));
  });

  test("App failure 转回既有 IOSExploreStructuredError 语义并保留 data", async () => {
    vi.stubGlobal("fetch", async () => response({
      code: "wait_timeout",
      message: "not ready",
      data: { elapsedMs: 1200, attempts: 12 }
    }));
    const client = new IOSExploreClient({ baseURL: "http://localhost:38321/", requestTimeoutMs: 1000 });

    await expect(client.call("ui.waitAny", {})).rejects.toMatchObject({
      source: "ios_envelope",
      code: "wait_timeout",
      message: "not ready",
      action: "ui.waitAny",
      data: { elapsedMs: 1200, attempts: 12 }
    });
  });

  test("HTTP 与非法 JSON 转回既有结构化错误", async () => {
    vi.stubGlobal("fetch", async () => new Response("server exploded", { status: 500 }));
    const httpClient = new IOSExploreClient({ baseURL: "http://localhost:38321/", requestTimeoutMs: 1000 });
    await expect(httpClient.call("ping", {})).rejects.toMatchObject({
      source: "http", status: 500, action: "ping", bodySnippet: "server exploded"
    });

    vi.stubGlobal("fetch", async () => new Response("not-json"));
    const jsonClient = new IOSExploreClient({ baseURL: "http://localhost:38321/", requestTimeoutMs: 1000 });
    await expect(jsonClient.call("ping", {})).rejects.toMatchObject({
      source: "http", code: "invalid_json", action: "ping", bodySnippet: "not-json"
    });
  });

  test("transport failure 不在 facade 额外重试", async () => {
    const fetchImpl = vi.fn(async () => { throw new TypeError("offline"); });
    vi.stubGlobal("fetch", fetchImpl);
    const client = new IOSExploreClient({ baseURL: "http://localhost:38321/", requestTimeoutMs: 1000 });

    await expect(client.call("ui.tap", {})).rejects.toMatchObject({
      source: "transport", code: "connection_failed", action: "ui.tap"
    });
    expect(fetchImpl).toHaveBeenCalledTimes(1);
  });

  test("截图仍返回旧的 base64 data 形态", async () => {
    const png = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
    vi.stubGlobal("fetch", async () => response({
      code: "ok",
      data: { image: png.toString("base64"), format: "png", width: 1, height: 1 }
    }));
    const client = new IOSExploreClient({ baseURL: "http://localhost:38321/", requestTimeoutMs: 1000 });

    await expect(client.call("ui.screenshot", {})).resolves.toEqual({
      image: png.toString("base64"), format: "png", width: 1, height: 1
    });
  });
});

function response(body: unknown): Response {
  return new Response(JSON.stringify(body), { headers: { "Content-Type": "application/json" } });
}
