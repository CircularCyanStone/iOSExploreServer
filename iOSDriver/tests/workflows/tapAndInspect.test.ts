import { describe, expect, it } from "vitest";

import type { InvocationResult } from "../../src/runtime/types.js";
import type { JSONObject } from "../../src/types.js";
import { WorkflowRunner } from "../../src/workflows/workflowRunner.js";
import type { WorkflowClock, WorkflowRuntime } from "../../src/workflows/types.js";

interface QueuedResult {
  readonly result: InvocationResult;
  readonly advanceMs: number;
}

class FakeClock implements WorkflowClock {
  currentMs = 0;
  readonly scheduledDelays: number[] = [];

  now(): number {
    return this.currentMs;
  }

  setTimeout(_callback: () => void, delayMs: number): unknown {
    this.scheduledDelays.push(delayMs);
    return this.scheduledDelays.length;
  }

  clearTimeout(_handle: unknown): void {}

  advance(milliseconds: number): void {
    this.currentMs += milliseconds;
  }
}

class FakeRuntime implements WorkflowRuntime {
  readonly calls: Array<{
    readonly action: string;
    readonly data: JSONObject;
    readonly signal: AbortSignal | undefined;
  }> = [];

  constructor(
    private readonly clock: FakeClock,
    private readonly queuedResults: QueuedResult[]
  ) {}

  async invoke(
    action: string,
    data: JSONObject = {},
    options: { readonly signal?: AbortSignal } = {}
  ): Promise<InvocationResult> {
    this.calls.push({ action, data, signal: options.signal });
    const next = this.queuedResults.shift();
    if (next === undefined) throw new Error(`Unexpected action: ${action}`);
    this.clock.advance(next.advanceMs);
    return next.result;
  }
}

describe("tap_and_inspect", () => {
  it("按固定顺序执行并从生成合同读取默认值", async () => {
    const clock = new FakeClock();
    const runtime = new FakeRuntime(clock, [
      { result: success({ performed: true }), advanceMs: 10 },
      { result: success({ satisfied: true }), advanceMs: 20 },
      { result: success({ viewSnapshotID: "after-tap" }), advanceMs: 15 }
    ]);
    const runner = new WorkflowRunner({ runtime, clock });

    const result = await runner.run("tap_and_inspect", {
      path: "0.2",
      viewSnapshotID: "before-tap",
      unknownField: true
    }, { deadlineAtMs: 100 });

    expect(runtime.calls.map(call => call.action)).toEqual(["ui.tap", "ui.wait", "ui.inspect"]);
    expect(runtime.calls[0]?.data).toEqual({ path: "0.2", viewSnapshotID: "before-tap" });
    expect(runtime.calls[1]?.data).toEqual({ mode: "idle", stableMs: 300, timeoutMs: 1300 });
    expect(runtime.calls[2]?.data).toEqual({ maxDepth: 2, maxTargets: 20 });
    expect(runtime.calls.every(call => call.signal instanceof AbortSignal)).toBe(true);
    expect(clock.scheduledDelays).toEqual([100, 90, 70]);
    expect(result).toMatchObject({
      ok: true,
      data: {
        tap: { performed: true },
        wait: { satisfied: true },
        stateAfter: { viewSnapshotID: "after-tap" },
        timing: { tapMs: 10, waitMs: 20, inspectMs: 15, totalMs: 45 }
      },
      elapsedMs: 45,
      attempts: 3
    });
  });

  it("wait_timeout 后继续 inspect 并保留 wait 结果", async () => {
    const clock = new FakeClock();
    const runtime = new FakeRuntime(clock, [
      { result: success({ performed: true }), advanceMs: 3 },
      { result: failure("wait_timeout", "UI did not stabilize", { elapsedMs: 1300 }), advanceMs: 8 },
      { result: success({ viewSnapshotID: "latest" }), advanceMs: 4 }
    ]);
    const runner = new WorkflowRunner({ runtime, clock });

    const result = await runner.run("tap_and_inspect", {
      accessibilityIdentifier: "submit",
      viewSnapshotID: "before"
    }, { deadlineAtMs: 100 });

    expect(runtime.calls.map(call => call.action)).toEqual(["ui.tap", "ui.wait", "ui.inspect"]);
    expect(result).toMatchObject({
      ok: true,
      data: {
        tap: { performed: true },
        wait: { code: "wait_timeout", data: { elapsedMs: 1300 } },
        stateAfter: { viewSnapshotID: "latest" },
        timing: { tapMs: 3, waitMs: 8, inspectMs: 4, totalMs: 15 }
      }
    });
  });

  it("tap 失败立即短路", async () => {
    const clock = new FakeClock();
    const runtime = new FakeRuntime(clock, [
      { result: failure("target_not_found", "Target not found"), advanceMs: 6 }
    ]);
    const runner = new WorkflowRunner({ runtime, clock });

    const result = await runner.run("tap_and_inspect", {
      path: "0.9",
      viewSnapshotID: "before"
    }, { deadlineAtMs: 100 });

    expect(runtime.calls.map(call => call.action)).toEqual(["ui.tap"]);
    expect(result).toMatchObject({
      ok: false,
      error: { code: "target_not_found" },
      data: {
        stage: "tap",
        tap: { code: "target_not_found" },
        timing: { tapMs: 6, inspectMs: 0, totalMs: 6 }
      }
    });
  });

  it("非 wait_timeout 的 wait 失败也继续 inspect 并保留过程结果", async () => {
    const clock = new FakeClock();
    const runtime = new FakeRuntime(clock, [
      { result: success({ performed: true }), advanceMs: 2 },
      { result: failure("transport_unavailable", "Connection lost"), advanceMs: 7 },
      { result: success({ viewSnapshotID: "after-recovery" }), advanceMs: 4 }
    ]);
    const runner = new WorkflowRunner({ runtime, clock });

    const result = await runner.run("tap_and_inspect", {
      path: "0.1",
      viewSnapshotID: "before"
    }, { deadlineAtMs: 100 });

    expect(runtime.calls.map(call => call.action)).toEqual(["ui.tap", "ui.wait", "ui.inspect"]);
    expect(result).toMatchObject({
      ok: true,
      data: {
        tap: { performed: true },
        wait: { code: "transport_unavailable" },
        stateAfter: { viewSnapshotID: "after-recovery" },
        timing: { tapMs: 2, waitMs: 7, inspectMs: 4, totalMs: 13 }
      }
    });
  });

  it("inspect 失败是终态并保留 stateAfter 与完整 timing", async () => {
    const clock = new FakeClock();
    const runtime = new FakeRuntime(clock, [
      { result: success({ performed: true }), advanceMs: 2 },
      { result: success({ satisfied: true }), advanceMs: 3 },
      { result: failure("protocol_error", "Invalid envelope"), advanceMs: 5 }
    ]);
    const runner = new WorkflowRunner({ runtime, clock });

    const result = await runner.run("tap_and_inspect", {
      path: "0.1",
      viewSnapshotID: "before"
    }, { deadlineAtMs: 100 });

    expect(result).toMatchObject({
      ok: false,
      error: { code: "protocol_error" },
      data: {
        stage: "inspect",
        tap: { performed: true },
        wait: { satisfied: true },
        stateAfter: { code: "protocol_error" },
        timing: { tapMs: 2, waitMs: 3, inspectMs: 5, totalMs: 10 }
      }
    });
  });

  it("关闭稳定等待时直接 inspect 且仍按剩余预算创建 signal", async () => {
    const clock = new FakeClock();
    const runtime = new FakeRuntime(clock, [
      { result: success({ performed: true }), advanceMs: 40 },
      { result: success({ viewSnapshotID: "latest" }), advanceMs: 5 }
    ]);
    const runner = new WorkflowRunner({ runtime, clock });

    const result = await runner.run("tap_and_inspect", {
      path: "0.1",
      viewSnapshotID: "before",
      waitForStable: false,
      inspectDepth: 4,
      inspectMaxTargets: 30
    }, { deadlineAtMs: 50 });

    expect(runtime.calls.map(call => call.action)).toEqual(["ui.tap", "ui.inspect"]);
    expect(clock.scheduledDelays).toEqual([50, 10]);
    expect(result).toMatchObject({
      ok: true,
      data: {
        stateAfter: { viewSnapshotID: "latest" },
        timing: { tapMs: 40, inspectMs: 5, totalMs: 45 }
      }
    });
    expect((result.data as JSONObject).wait).toBeUndefined();
  });

  it("终态失败聚合各阶段 attempts 和 image artifacts", async () => {
    const clock = new FakeClock();
    const image = { kind: "image" as const, mimeType: "image/png", data: Uint8Array.from([1]), metadata: {} };
    const runtime = new FakeRuntime(clock, [
      { result: { ...success({ performed: true }), artifacts: [image], attempts: 2 }, advanceMs: 2 },
      { result: success({ satisfied: true }), advanceMs: 3 },
      { result: { ...failure("protocol_error", "Invalid envelope"), artifacts: [image], attempts: 3 }, advanceMs: 5 }
    ]);

    const result = await new WorkflowRunner({ runtime, clock }).run("tap_and_inspect", {
      path: "0.1",
      viewSnapshotID: "before"
    }, { deadlineAtMs: 100 });

    expect(result).toMatchObject({ ok: false, attempts: 6, data: { stage: "inspect" } });
    if (result.ok) throw new Error("expected workflow failure");
    expect(result.artifacts).toEqual([image, image]);
  });
});

function success(data: JSONObject): InvocationResult {
  return { ok: true, data, artifacts: [], elapsedMs: 0, attempts: 1 };
}

function failure(code: string, message: string, data?: JSONObject): InvocationResult {
  return {
    ok: false,
    error: {
      source: code === "protocol_error" ? "protocol" : code === "transport_unavailable" ? "transport" : "appEnvelope",
      code,
      message,
      action: "test.action",
      ...(data === undefined ? {} : { data })
    },
    ...(data === undefined ? {} : { data }),
    elapsedMs: 0,
    attempts: 1
  };
}
