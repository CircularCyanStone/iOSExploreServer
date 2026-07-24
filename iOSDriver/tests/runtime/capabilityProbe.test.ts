import { describe, expect, test } from "vitest";
import { CONTRACT_BUNDLE_METADATA } from "../../src/generated/contractBundle.js";
import { DEVICE_ACTION_CONTRACTS } from "../../src/generated/deviceActionContracts.js";
import { CapabilityProbe, type CapabilityInvoker } from "../../src/runtime/capabilityProbe.js";
import type { DriverError } from "../../src/runtime/driverErrors.js";
import type { InvocationResult } from "../../src/runtime/types.js";

const ok = (data: Record<string, unknown>): InvocationResult => ({ ok: true, data, artifacts: [], elapsedMs: 0, attempts: 1 });
const failure = (source: DriverError["source"] = "transport"): InvocationResult => ({ ok: false, error: { source, code: source === "transport" ? "transport_unavailable" : "protocol_error", message: "failed" }, elapsedMs: 0, attempts: 1 });
const command = (action: string, inputSchema: Record<string, unknown> = { type: "object", properties: {}, required: [], additionalProperties: false }) => ({ action, inputSchema });

function fake(outcomes: Record<string, InvocationResult>): CapabilityInvoker & { calls: string[] } {
  const calls: string[] = [];
  return { calls, async invoke(action) { calls.push(action); return outcomes[action] ?? failure(); } };
}

describe("CapabilityProbe", () => {
  test("构造不发 HTTP，显式 health 才调用 ping/help", async () => {
    const runtime = fake({ ping: ok({ pong: true }), help: ok({ commands: [] }) });
    const probe = new CapabilityProbe(runtime);
    expect(runtime.calls).toEqual([]);
    await probe.health();
    expect(runtime.calls).toEqual(["ping", "help"]);
  });

  test("endpoint 不可达时 action/module 为 unknown，不伪造 missing", async () => {
    const report = await new CapabilityProbe(fake({ ping: failure(), help: failure() })).doctor();
    expect(report.connection).toBe("unreachable");
    expect(report.actions).toMatchObject({ status: "unknown", missingActions: [] });
    expect(report.modules.uikit.status).toBe("unknown");

    const httpFailure = await new CapabilityProbe(fake({ ping: failure("http"), help: failure("http") })).health();
    expect(httpFailure.connection).toBe("reachable");
    expect(httpFailure.actions.status).toBe("unknown");
  });

  test("ping 可达但 help 缺失或 malformed 时仍不伪造 action 缺失", async () => {
    for (const help of [failure("appEnvelope"), ok({}), ok({ commands: "bad" })]) {
      const report = await new CapabilityProbe(fake({ ping: ok({ pong: true }), help })).capabilities();
      expect(report.connection).toBe("reachable");
      expect(report.actions.status).toBe("unknown");
      expect(report.modules.diagnostics.status).toBe("unknown");
    }
  });

  test("完整注册和 partial action 正确区分模块", async () => {
    const fullCommands = DEVICE_ACTION_CONTRACTS.map(contract => command(contract.action, contract.inputSchema));
    const all = await new CapabilityProbe(fake({
      ping: ok({ pong: true }),
      help: ok({
        protocolVersion: CONTRACT_BUNDLE_METADATA.protocolVersion,
        contractVersion: CONTRACT_BUNDLE_METADATA.contractVersion,
        contractHash: CONTRACT_BUNDLE_METADATA.contractHash,
        commands: fullCommands
      })
    })).health();
    expect(all.modules.uikit.status).toBe("registered");
    expect(all.modules.diagnostics.status).toBe("registered");
    expect(all.schemaCompatibility).toBe("exact");
    expect(all.metadata?.hashMatches).toBe(true);

    const partial = await new CapabilityProbe(fake({
      ping: ok({ pong: true }),
      help: ok({ contractHash: "sha256:different", commands: fullCommands.filter(item => item.action !== "ui.inspect") })
    })).capabilities();
    expect(partial.modules.uikit.status).toBe("partial");
    expect(partial.metadata?.hashMatches).toBe(false);
    expect(partial.actions.status).toBe("known");

    const unregistered = await new CapabilityProbe(fake({
      ping: ok({ pong: true }),
      help: ok({ commands: ["ping", "echo", "info", "help"].map(action => command(action)) })
    })).health();
    expect(unregistered.modules.uikit.status).toBe("not_registered");
    expect(unregistered.modules.diagnostics.status).toBe("not_registered");
  });
});
