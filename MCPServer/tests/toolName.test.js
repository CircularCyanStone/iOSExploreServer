import { describe, expect, test } from "vitest";
import { toolNameForAction, buildActionToolMap } from "../src/toolName.js";
describe("toolName", () => {
    test("maps action names to stable MCP names", () => {
        expect(toolNameForAction("ui.viewTargets")).toBe("ui_viewTargets");
        expect(toolNameForAction("ui.navigation.back")).toBe("ui_navigation_back");
        expect(toolNameForAction("app.logs.read")).toBe("app_logs_read");
    });
    test("reports conflicts and omits conflicted dynamic tool", () => {
        const map = buildActionToolMap([
            { action: "a.b", description: "first", inputSchema: {} },
            { action: "a_b", description: "second", inputSchema: {} }
        ], new Set());
        expect(map.tools).toHaveLength(0);
        expect(map.conflicts).toEqual([
            { toolName: "a_b", actions: ["a.b", "a_b"] }
        ]);
    });
    test("fixed tool conflict is reported", () => {
        const map = buildActionToolMap([{ action: "health.check", description: "bad", inputSchema: {} }], new Set(["health_check"]));
        expect(map.tools).toHaveLength(0);
        expect(map.conflicts).toEqual([
            { toolName: "health_check", actions: ["health.check"] }
        ]);
    });
});
