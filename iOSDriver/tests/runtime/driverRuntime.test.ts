import { describe, expect, test } from "vitest";
import type { ActionTransport, ActionTransportResponse } from "../../src/runtime/actionTransport.js";
import { DriverFailure } from "../../src/runtime/driverErrors.js";
import { DriverRuntime } from "../../src/runtime/driverRuntime.js";
import type { JSONObject } from "../../src/types.js";

class FakeTransport implements ActionTransport {
  readonly calls: Array<{ action: string; data: JSONObject; timeoutMs: number }> = [];

  constructor(private readonly outcomes: Array<ActionTransportResponse | DriverFailure>) {}

  async execute(
    request: { action: string; data: JSONObject },
    options: { timeoutMs: number; signal?: AbortSignal }
  ): Promise<ActionTransportResponse> {
    this.calls.push({ ...request, timeoutMs: options.timeoutMs });
    const outcome = this.outcomes.shift();
    if (outcome instanceof DriverFailure) throw outcome;
    if (outcome === undefined) throw new Error("fake transport has no outcome");
    return outcome;
  }
}

describe("DriverRuntime", () => {
  test("App success 保留 data、elapsedMs 和 attempts", async () => {
    const transport = new FakeTransport([{ httpStatus: 200, envelope: { code: "ok", data: { pong: true } } }]);
    const runtime = new DriverRuntime({ transport, configuredRequestTimeoutMs: 1000 });

    await expect(runtime.invoke("ping", {})).resolves.toMatchObject({
      ok: true,
      data: { pong: true },
      artifacts: [],
      attempts: 1,
      elapsedMs: expect.any(Number)
    });
  });

  test("App failure 是结果而非 throw，并保留 data", async () => {
    const transport = new FakeTransport([{
      httpStatus: 200,
      envelope: { code: "wait_timeout", message: "not ready", data: { attempts: 12 } }
    }]);
    const runtime = new DriverRuntime({ transport, configuredRequestTimeoutMs: 1000 });

    await expect(runtime.invoke("ui.wait", {})).resolves.toMatchObject({
      ok: false,
      error: { source: "appEnvelope", code: "wait_timeout", message: "not ready", action: "ui.wait" },
      data: { attempts: 12 },
      artifacts: [],
      attempts: 1
    });
  });

  test("非法 protocol envelope 返回 protocol_error", async () => {
    const transport = new FakeTransport([{ httpStatus: 200, envelope: { data: {} } }]);
    const runtime = new DriverRuntime({ transport, configuredRequestTimeoutMs: 1000 });

    await expect(runtime.invoke("ping", {})).resolves.toMatchObject({
      ok: false,
      error: { source: "protocol", code: "protocol_error", protocolIssue: "invalid_envelope" },
      attempts: 1
    });
  });

  test("readOnly action 仅对未收到响应的 connect/reset 自动重试一次", async () => {
    for (const phase of ["connect", "reset"] as const) {
      const transport = new FakeTransport([
        transportFailure(phase, false),
        { httpStatus: 200, envelope: { code: "ok", data: { recovered: true } } }
      ]);
      const runtime = new DriverRuntime({ transport, configuredRequestTimeoutMs: 1000 });

      await expect(runtime.invoke("ping", {})).resolves.toMatchObject({ ok: true, attempts: 2 });
      expect(transport.calls).toHaveLength(2);
    }
  });

  test("sideEffecting、未知 action、timeout、已收到响应均不重试", async () => {
    const cases = [
      ["ui.tap", transportFailure("connect", false)],
      ["extension.unknown", transportFailure("connect", false)],
      ["ping", new DriverFailure({ source: "transport", code: "transport_timeout", message: "late", transportPhase: "timeout" }, false)],
      ["ping", transportFailure("reset", true)]
    ] as const;

    for (const [action, failure] of cases) {
      const transport = new FakeTransport([failure]);
      const runtime = new DriverRuntime({ transport, configuredRequestTimeoutMs: 1000 });
      const result = await runtime.invoke(action, {});

      expect(result).toMatchObject({ ok: false, attempts: 1 });
      expect(transport.calls).toHaveLength(1);
    }
  });

  test("两次 transport failure 返回第二次错误并报告 attempts=2", async () => {
    const transport = new FakeTransport([
      transportFailure("connect", false),
      transportFailure("reset", false)
    ]);
    const runtime = new DriverRuntime({ transport, configuredRequestTimeoutMs: 1000 });

    await expect(runtime.invoke("ping", {})).resolves.toMatchObject({
      ok: false,
      error: { transportPhase: "reset" },
      attempts: 2
    });
  });

  test("等待合同使用 max(configured timeout, business timeout + 5000)", async () => {
    const transport = new FakeTransport([
      { httpStatus: 200, envelope: { code: "ok", data: {} } },
      { httpStatus: 200, envelope: { code: "ok", data: {} } },
      { httpStatus: 200, envelope: { code: "ok", data: {} } }
    ]);
    const runtime = new DriverRuntime({ transport, configuredRequestTimeoutMs: 10_000 });

    await runtime.invoke("ui.wait", { timeoutMs: 8_000 });
    await runtime.invoke("ui.waitAny", { timeoutMs: 1_000 });
    await runtime.invoke("ping", { timeoutMs: 99_000 });

    expect(transport.calls.map(call => call.timeoutMs)).toEqual([13_000, 10_000, 10_000]);
  });

  test("调用 signal 会透传给 transport", async () => {
    const controller = new AbortController();
    let receivedSignal: AbortSignal | undefined;
    const transport: ActionTransport = {
      async execute(_request, options) {
        receivedSignal = options.signal;
        return { httpStatus: 200, envelope: { code: "ok" } };
      }
    };
    const runtime = new DriverRuntime({ transport, configuredRequestTimeoutMs: 1000 });

    await runtime.invoke("ping", {}, { signal: controller.signal });

    expect(receivedSignal).toBe(controller.signal);
  });
});

function transportFailure(phase: "connect" | "reset", responseReceived: boolean): DriverFailure {
  return new DriverFailure({
    source: "transport",
    code: "transport_unavailable",
    message: phase,
    transportPhase: phase
  }, responseReceived);
}
