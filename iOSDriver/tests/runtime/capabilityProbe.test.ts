import { describe, expect, test } from "vitest";
import { CONTRACT_BUNDLE_METADATA } from "../../src/generated/contractBundle.js";
import { DEVICE_ACTION_CONTRACTS } from "../../src/generated/deviceActionContracts.js";
import { CapabilityProbe, type CapabilityInvoker } from "../../src/runtime/capabilityProbe.js";
import type { DriverError } from "../../src/runtime/driverErrors.js";
import type { InvocationResult } from "../../src/runtime/types.js";
import { hostLogRecorder } from "../support/hostLogRecorder.js";

const ok = (data: Record<string, unknown>): InvocationResult => ({ ok: true, data, artifacts: [], elapsedMs: 0, attempts: 1 });
const failure = (source: DriverError["source"] = "transport"): InvocationResult => ({ ok: false, error: { source, code: source === "transport" ? "transport_unavailable" : "protocol_error", message: "failed" }, elapsedMs: 0, attempts: 1 });
const command = (
  action: string,
  inputSchema: Record<string, unknown> = { type: "object", properties: {}, required: [], additionalProperties: false },
  metadata: Record<string, unknown> = {}
) => ({ action, inputSchema, ...metadata });

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

  test("只缓存同时合法且不重复的 help action policy", async () => {
    const runtime = fake({
      ping: ok({ pong: true }),
      help: ok({ commands: [
        command("extension.wait", undefined, { idempotency: "readOnly", timeoutClass: "wait" }),
        command("extension.bad-idempotency", undefined, { idempotency: "maybe", timeoutClass: "standard" }),
        command("extension.bad-timeout", undefined, { idempotency: "readOnly", timeoutClass: "slow" }),
        command("extension.duplicate", undefined, { idempotency: "readOnly", timeoutClass: "standard" }),
        command("extension.duplicate", undefined, { idempotency: "sideEffecting", timeoutClass: "standard" })
      ] })
    });
    const probe = new CapabilityProbe(runtime);

    await probe.capabilities();

    expect(probe.invocationPolicy("extension.wait")).toEqual({ idempotency: "readOnly", timeoutClass: "wait" });
    expect(probe.invocationPolicy("extension.bad-idempotency")).toBeUndefined();
    expect(probe.invocationPolicy("extension.bad-timeout")).toBeUndefined();
    expect(probe.invocationPolicy("extension.duplicate")).toBeUndefined();
  });

  test("后续显式 probe 失败仍保留最近一次成功 help policy", async () => {
    const outcomes: Record<string, InvocationResult> = {
      ping: ok({ pong: true }),
      help: ok({ commands: [command("extension.wait", undefined, { idempotency: "readOnly", timeoutClass: "wait" })] })
    };
    const probe = new CapabilityProbe(fake(outcomes));
    await probe.health();
    expect(probe.invocationPolicy("extension.wait")).toBeDefined();

    outcomes.ping = failure();
    outcomes.help = failure();
    await probe.capabilities();
    expect(probe.invocationPolicy("extension.wait")).toEqual({ idempotency: "readOnly", timeoutClass: "wait" });
  });

  test("同轮 ping 失败但 help 成功时仍发布最新 help policy", async () => {
    const outcomes: Record<string, InvocationResult> = {
      ping: ok({ pong: true }),
      help: ok({ commands: [command("extension.old", undefined, { idempotency: "readOnly", timeoutClass: "standard" })] })
    };
    const probe = new CapabilityProbe(fake(outcomes));
    await probe.capabilities();

    outcomes.ping = failure();
    outcomes.help = ok({ commands: [command("extension.new", undefined, { idempotency: "idempotent", timeoutClass: "wait" })] });
    await probe.capabilities();

    expect(probe.invocationPolicy("extension.new")).toEqual({ idempotency: "idempotent", timeoutClass: "wait" });
    expect(probe.invocationPolicy("extension.old")).toBeUndefined();
  });

  test("并发 probe 仅发布最近完成的成功 help 原子快照", async () => {
    const helpResolvers: Array<(result: InvocationResult) => void> = [];
    let bothHelpCallsResolve: (() => void) | undefined;
    const bothHelpCalls = new Promise<void>(resolve => { bothHelpCallsResolve = resolve; });
    const runtime: CapabilityInvoker = {
      async invoke(action) {
        if (action === "ping") return ok({ pong: true });
        return new Promise<InvocationResult>(resolve => {
          helpResolvers.push(resolve);
          if (helpResolvers.length === 2) bothHelpCallsResolve?.();
        });
      }
    };
    const probe = new CapabilityProbe(runtime);

    const firstProbe = probe.capabilities();
    const secondProbe = probe.capabilities();
    await bothHelpCalls;

    helpResolvers[1]!(ok({ commands: [
      command("extension.second", undefined, { idempotency: "idempotent", timeoutClass: "standard" })
    ] }));
    await secondProbe;
    expect(probe.invocationPolicy("extension.second")).toEqual({ idempotency: "idempotent", timeoutClass: "standard" });
    expect(probe.invocationPolicy("extension.first")).toBeUndefined();

    helpResolvers[0]!(ok({ commands: [
      command("extension.first", undefined, { idempotency: "readOnly", timeoutClass: "wait" })
    ] }));
    await firstProbe;
    expect(probe.invocationPolicy("extension.first")).toEqual({ idempotency: "readOnly", timeoutClass: "wait" });
    expect(probe.invocationPolicy("extension.second")).toBeUndefined();
  });

  test("记录 probe 起止与连接、ping、help、schema 摘要，不记录 commands 内容", async () => {
    const recorded = hostLogRecorder();
    const probe = new CapabilityProbe(fake({
      ping: ok({ pong: true }),
      help: ok({ commands: [command("secret.command", undefined, { description: "private payload" })] })
    }), DEVICE_ACTION_CONTRACTS, recorded.logger);

    await probe.health();

    expect(recorded.entries().map(entry => entry.event)).toEqual([
      "capability.probe.start",
      "capability.probe.complete"
    ]);
    expect(recorded.entries()[1]).toMatchObject({
      mode: "health",
      connection: "reachable",
      pingStatus: "ok",
      helpStatus: "available",
      actionsStatus: "known",
      schemaCompatibility: expect.any(String)
    });
    expect(recorded.lines.join("")).not.toMatch(/secret\.command|private payload|commands/);
  });
});
