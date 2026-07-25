import { describe, expect, test } from "vitest";
import type { ActionTransport, ActionTransportResponse } from "../../src/runtime/actionTransport.js";
import { DriverFailure } from "../../src/runtime/driverErrors.js";
import { DriverRuntime } from "../../src/runtime/driverRuntime.js";
import type { JSONObject } from "../../src/types.js";
import { hostLogRecorder } from "../support/hostLogRecorder.js";

const PNG = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

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

  test("失败 envelope 的 screenshot artifact 无法解码时仍保留 App 业务失败", async () => {
    const transport = new FakeTransport([{
      httpStatus: 200,
      envelope: {
        code: "capture_failed",
        message: "screen unavailable",
        data: { image: "not base64", format: "png", reason: "window missing" }
      }
    }]);
    const runtime = new DriverRuntime({ transport, configuredRequestTimeoutMs: 1000 });

    const result = await runtime.invoke("ui.screenshot", {});

    expect(result).toMatchObject({
      ok: false,
      error: {
        source: "appEnvelope",
        code: "capture_failed",
        message: "screen unavailable",
        action: "ui.screenshot"
      },
      artifacts: [],
      attempts: 1
    });
    if (!result.ok) {
      const originalData = { image: "not base64", format: "png", reason: "window missing" };
      expect(result.error.data).toEqual(originalData);
      expect(result.data).toEqual(originalData);
    }
  });

  test("失败 envelope 的合法 screenshot artifact 与 App 业务失败同时保留", async () => {
    const transport = new FakeTransport([{
      httpStatus: 200,
      envelope: {
        code: "capture_partial",
        message: "captured before failure",
        data: { image: PNG.toString("base64"), format: "png", width: 1, height: 1 }
      }
    }]);
    const runtime = new DriverRuntime({ transport, configuredRequestTimeoutMs: 1000 });

    const result = await runtime.invoke("ui.screenshot", {});

    expect(result).toMatchObject({
      ok: false,
      error: {
        source: "appEnvelope",
        code: "capture_partial",
        message: "captured before failure",
        data: { format: "png", width: 1, height: 1 }
      },
      data: { format: "png", width: 1, height: 1 },
      artifacts: [{ kind: "image", mimeType: "image/png" }],
      attempts: 1
    });
    if (!result.ok) expect(Buffer.from(result.artifacts![0]!.data)).toEqual(PNG);
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

  test("已验证 per-call policy 可为 extension 决定 wait timeout 和 runtime retry", async () => {
    const transport = new FakeTransport([
      transportFailure("connect", false),
      { httpStatus: 200, envelope: { code: "ok", data: { recovered: true } } }
    ]);
    const runtime = new DriverRuntime({ transport, configuredRequestTimeoutMs: 1_000 });

    await expect(runtime.invoke("extension.wait", { timeoutMs: 4_000 }, {
      policy: { idempotency: "readOnly", timeoutClass: "wait" }
    })).resolves.toMatchObject({ ok: true, attempts: 2 });

    expect(transport.calls.map(call => call.timeoutMs)).toEqual([9_000, 9_000]);
  });

  test("生成合同优先于 per-call policy，ui.tap 的 connect/reset 失败均不重试", async () => {
    for (const phase of ["connect", "reset"] as const) {
      const transport = new FakeTransport([transportFailure(phase, false)]);
      const runtime = new DriverRuntime({ transport, configuredRequestTimeoutMs: 1_000 });

      const result = await runtime.invoke("ui.tap", { timeoutMs: 20_000 }, {
        policy: { idempotency: "readOnly", timeoutClass: "wait" }
      });

      expect(result).toMatchObject({ ok: false, error: { transportPhase: phase }, attempts: 1 });
      expect(transport.calls).toEqual([{ action: "ui.tap", data: { timeoutMs: 20_000 }, timeoutMs: 1_000 }]);
    }
  });

  test("非法 per-call policy 对未知 extension 保持保守策略", async () => {
    const transport = new FakeTransport([transportFailure("connect", false)]);
    const runtime = new DriverRuntime({ transport, configuredRequestTimeoutMs: 1_000 });

    const result = await runtime.invoke("extension.invalid", { timeoutMs: 99_000 }, {
      policy: { idempotency: "unsafe", timeoutClass: "wait" } as never
    });

    expect(result).toMatchObject({ ok: false, attempts: 1 });
    expect(transport.calls).toEqual([{ action: "extension.invalid", data: { timeoutMs: 99_000 }, timeoutMs: 1_000 }]);
  });

  test("记录 invoke、retry、failure 和 throw 摘要且不泄露 payload 或错误全文", async () => {
    const recorded = hostLogRecorder();
    const runtime = new DriverRuntime({
      transport: new FakeTransport([
        new DriverFailure({
          source: "transport",
          code: "transport_unavailable",
          message: "contains-secret-message",
          baseURL: "http://token@localhost/",
          transportPhase: "connect"
        }, false),
        { httpStatus: 200, envelope: { code: "invalid_data", message: "private-value", data: { password: "123456" } } }
      ]),
      configuredRequestTimeoutMs: 1000,
      logger: recorded.logger
    });

    await runtime.invoke("ping", { token: "secret-token", image: "base64-secret" });
    const events = recorded.entries();
    expect(events.map(entry => entry.event)).toEqual([
      "runtime.invoke.start",
      "runtime.invoke.retry",
      "runtime.invoke.failure"
    ]);
    expect(events[1]).toMatchObject({ action: "ping", attempts: 1, nextAttempt: 2, source: "transport", code: "transport_unavailable", transportPhase: "connect" });
    expect(events[2]).toMatchObject({ action: "ping", attempts: 2, source: "appEnvelope", code: "invalid_data" });
    expect(recorded.lines.join("")).not.toMatch(/secret|password|base64|token@|private-value/);

    const thrown = hostLogRecorder();
    const throwingRuntime = new DriverRuntime({
      transport: { async execute() { throw new Error("do-not-log-this"); } },
      configuredRequestTimeoutMs: 1000,
      logger: thrown.logger
    });
    await expect(throwingRuntime.invoke("ping", {})).rejects.toThrow("do-not-log-this");
    expect(thrown.entries().at(-1)).toMatchObject({ event: "runtime.invoke.throw", action: "ping", errorType: "Error" });
    expect(thrown.lines.join("")).not.toContain("do-not-log-this");
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
