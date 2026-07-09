import { describe, expect, test } from "vitest";
import { loadConfig, requestTimeoutForAction } from "../src/config.js";
describe("config", () => {
    test("uses localhost defaults", () => {
        const config = loadConfig({});
        expect(config.baseURL).toBe("http://localhost:38321/");
        expect(config.requestTimeoutMs).toBe(10000);
    });
    test("normalizes base URL trailing slash", () => {
        const config = loadConfig({ IOS_EXPLORE_BASE_URL: "http://127.0.0.1:38321" });
        expect(config.baseURL).toBe("http://127.0.0.1:38321/");
    });
    test("rejects invalid base URL", () => {
        expect(() => loadConfig({ IOS_EXPLORE_BASE_URL: "not a url" })).toThrow("IOS_EXPLORE_BASE_URL");
    });
    test("wait actions use data timeout plus grace", () => {
        const config = loadConfig({ IOS_EXPLORE_REQUEST_TIMEOUT_MS: "10000" });
        expect(requestTimeoutForAction(config, "ui.waitAny", { timeoutMs: 8000 })).toBe(13000);
        expect(requestTimeoutForAction(config, "ui.wait", { timeoutMs: 1000 })).toBe(10000);
        expect(requestTimeoutForAction(config, "ui.tap", { timeoutMs: 8000 })).toBe(10000);
    });
});
