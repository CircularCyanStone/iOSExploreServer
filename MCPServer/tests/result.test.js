import { describe, expect, test } from "vitest";
import { jsonResult, errorResult } from "../src/result.js";
describe("MCP result helpers", () => {
    test("jsonResult returns structured JSON text content", () => {
        const result = jsonResult({ ok: true });
        expect(result.isError).toBe(false);
        const first = result.content[0];
        expect(first).toBeDefined();
        expect(first.type).toBe("text");
        expect(first.type === "text" ? first.text : undefined).toBe(JSON.stringify({ ok: true }, null, 2));
    });
    test("errorResult keeps structured payload", () => {
        const result = errorResult({ source: "transport", code: "connection_failed", message: "down" });
        expect(result.isError).toBe(true);
        const first = result.content[0];
        expect(first).toBeDefined();
        expect(JSON.parse(first.type === "text" ? first.text : "{}")).toEqual({
            source: "transport",
            code: "connection_failed",
            message: "down"
        });
    });
});
