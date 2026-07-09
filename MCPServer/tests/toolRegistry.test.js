import { describe, expect, test } from "vitest";
import { ToolRegistry } from "../src/toolRegistry.js";
import { IOSExploreStructuredError } from "../src/errors.js";
describe("ToolRegistry", () => {
    test("refreshes tools from help", async () => {
        const registry = new ToolRegistry({
            fixedToolNames: new Set(["health_check"]),
            client: {
                call: async (action) => {
                    expect(action).toBe("help");
                    return {
                        commands: [
                            {
                                action: "ui.viewTargets",
                                description: "targets",
                                inputSchema: { type: "object", properties: {} }
                            }
                        ]
                    };
                }
            }
        });
        const result = await registry.refresh();
        expect(result.toolCount).toBe(1);
        expect(result.conflicts).toEqual([]);
        expect(registry.tools()[0]).toMatchObject({
            name: "ui_viewTargets",
            action: "ui.viewTargets"
        });
    });
    test("keeps server usable when help fails", async () => {
        const registry = new ToolRegistry({
            fixedToolNames: new Set(),
            client: {
                call: async () => {
                    throw new IOSExploreStructuredError({
                        source: "transport",
                        code: "connection_failed",
                        message: "offline",
                        action: "help"
                    });
                }
            }
        });
        const result = await registry.refresh();
        expect(result.toolCount).toBe(0);
        expect(result.error).toMatchObject({ source: "transport", code: "connection_failed" });
        expect(registry.tools()).toEqual([]);
    });
});
