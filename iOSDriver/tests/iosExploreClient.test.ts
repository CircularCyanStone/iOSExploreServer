import { describe, expect, test } from "vitest";
import { IOSExploreClient } from "../src/iosExploreClient.js";
import { withMockIOSExploreServer } from "./support/mockIOSExploreServer.js";

describe("IOSExploreClient", () => {
  test("posts action and data to POST /", async () => {
    await withMockIOSExploreServer(
      request => ({ body: { code: "ok", data: { echoed: request.data } } }),
      async ({ baseURL, requests }) => {
        const client = new IOSExploreClient({ baseURL, requestTimeoutMs: 10000 });
        const result = await client.call("echo", { name: "Ada" });
        expect(result).toEqual({ echoed: { name: "Ada" } });
        expect(requests).toEqual([{ action: "echo", data: { name: "Ada" } }]);
      }
    );
  });

  test("throws structured iOS envelope error", async () => {
    await withMockIOSExploreServer(
      () => ({ body: { code: "invalid_data", message: "bad field", data: { field: "path" } } }),
      async ({ baseURL }) => {
        const client = new IOSExploreClient({ baseURL, requestTimeoutMs: 10000 });
        await expect(client.call("ui.tap", {})).rejects.toMatchObject({
          source: "ios_envelope",
          code: "invalid_data",
          action: "ui.tap",
          message: "bad field",
          data: { field: "path" }
        });
      }
    );
  });

  test("throws structured HTTP error with body snippet", async () => {
    await withMockIOSExploreServer(
      () => ({ status: 500, body: "server exploded" }),
      async ({ baseURL }) => {
        const client = new IOSExploreClient({ baseURL, requestTimeoutMs: 10000 });
        await expect(client.call("ping", {})).rejects.toMatchObject({
          source: "http",
          status: 500,
          action: "ping",
          bodySnippet: "server exploded"
        });
      }
    );
  });

  test("wait action timeout uses command timeout plus grace", async () => {
    await withMockIOSExploreServer(
      () => ({ delayMs: 50, body: { code: "wait_timeout", message: "timeout" } }),
      async ({ baseURL }) => {
        const client = new IOSExploreClient({ baseURL, requestTimeoutMs: 10 });
        await expect(client.call("ui.waitAny", { timeoutMs: 40 })).rejects.toMatchObject({
          source: "ios_envelope",
          code: "wait_timeout",
          action: "ui.waitAny"
        });
      }
    );
  });

  test("preserves structured failure data from iOS envelope", async () => {
    await withMockIOSExploreServer(
      () => ({
        body: {
          code: "wait_timeout",
          message: "wait timed out mode=any",
          data: { elapsedMs: 1200, attempts: 12, snapshotUnavailableReason: "view snapshot unknown or expired" }
        }
      }),
      async ({ baseURL }) => {
        const client = new IOSExploreClient({ baseURL, requestTimeoutMs: 10000 });
        await expect(client.call("ui.waitAny", { conditions: [] })).rejects.toMatchObject({
          source: "ios_envelope",
          code: "wait_timeout",
          action: "ui.waitAny",
          data: {
            elapsedMs: 1200,
            attempts: 12,
            snapshotUnavailableReason: "view snapshot unknown or expired"
          }
        });
      }
    );
  });
});
