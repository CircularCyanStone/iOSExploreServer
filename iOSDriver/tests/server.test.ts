import { describe, expect, test } from "vitest";
import { STATIC_TOOL_NAMES } from "../src/adapters/mcp/toolMappings.js";
import { createToolHandlers } from "../src/server.js";
import type { CapabilityReport } from "../src/runtime/capabilityProbe.js";
import type { InvocationResult } from "../src/runtime/types.js";

const success: InvocationResult = { ok: true, data: {}, artifacts: [], elapsedMs: 0, attempts: 1 };

describe("server 兼容委托", () => {
  test("createToolHandlers 委托到新静态合同 adapter", async () => {
    const handlers = createToolHandlers({
      runtime: { async invoke() { return success; } },
      capabilityProbe: {
        async health() { return report("health"); },
        async capabilities() { return report("capabilities"); },
        invocationPolicy() { return undefined; }
      },
      workflowRunner: { async run() { return success; } }
    });

    const listed = await handlers.listTools();
    expect(listed.tools.map(tool => tool.name)).toEqual(STATIC_TOOL_NAMES);
    await expect(handlers.callTool("unknown", {})).resolves.toMatchObject({ isError: true });
  });
});

function report(mode: "health" | "capabilities"): CapabilityReport {
  return { mode, connection: "reachable" } as CapabilityReport;
}
