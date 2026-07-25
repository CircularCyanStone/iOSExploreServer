import { describe, expect, it } from "vitest";

import type { InvocationResult } from "../../src/runtime/types.js";
import type { JSONObject } from "../../src/types.js";
import { WorkflowRunner } from "../../src/workflows/workflowRunner.js";
import type { WorkflowClock, WorkflowRuntime } from "../../src/workflows/types.js";
import { hostLogRecorder } from "../support/hostLogRecorder.js";

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

describe("wait_and_inspect", () => {
  it("按固定顺序执行、投影字段，并为每阶段传递剩余预算", async () => {
    const clock = new FakeClock();
    const runtime = new FakeRuntime(clock, [
      { result: success({ matchedConditionID: "ready" }), advanceMs: 12 },
      { result: success({ viewSnapshotID: "snapshot-1" }), advanceMs: 18 }
    ]);
    const runner = new WorkflowRunner({ runtime, clock });

    const result = await runner.run("wait_and_inspect", {
      conditions: [{ id: "ready", mode: "idle" }],
      timeoutMs: 500,
      unknownField: true,
      inspectOptions: {
        maxDepth: 3,
        maxTargets: 8,
        unknownInspectField: true
      }
    }, { deadlineAtMs: 100 });

    expect(runtime.calls.map(call => call.action)).toEqual(["ui.waitAny", "ui.inspect"]);
    expect(runtime.calls[0]?.data).toEqual({
      conditions: [{ id: "ready", mode: "idle" }],
      timeoutMs: 500
    });
    expect(runtime.calls[1]?.data).toEqual({ maxDepth: 3, maxTargets: 8 });
    expect(runtime.calls.every(call => call.signal instanceof AbortSignal)).toBe(true);
    expect(clock.scheduledDelays).toEqual([100, 88]);
    expect(result).toMatchObject({
      ok: true,
      data: {
        wait: { matchedConditionID: "ready" },
        observation: { viewSnapshotID: "snapshot-1" },
        timing: { waitMs: 12, inspectMs: 18, totalMs: 30 }
      },
      elapsedMs: 30,
      attempts: 2
    });
  });

  it("把 wait_timeout 作为过程信号保留原 code/data 后继续 inspect", async () => {
    const clock = new FakeClock();
    const runtime = new FakeRuntime(clock, [
      {
        result: failure("wait_timeout", "No condition matched", { elapsedMs: 3000 }),
        advanceMs: 25
      },
      { result: success({ viewSnapshotID: "latest" }), advanceMs: 5 }
    ]);
    const runner = new WorkflowRunner({ runtime, clock });

    const result = await runner.run("wait_and_inspect", {
      conditions: [{ id: "gone", mode: "targetGone", path: "0.1" }]
    }, { deadlineAtMs: 100 });

    expect(runtime.calls.map(call => call.action)).toEqual(["ui.waitAny", "ui.inspect"]);
    expect(result).toMatchObject({
      ok: true,
      data: {
        wait: {
          code: "wait_timeout",
          data: { elapsedMs: 3000 }
        },
        observation: { viewSnapshotID: "latest" },
        timing: { waitMs: 25, inspectMs: 5, totalMs: 30 }
      }
    });
  });

  it("把 inspect 失败作为 workflow 终态并保留 observation 与 timing", async () => {
    const clock = new FakeClock();
    const runtime = new FakeRuntime(clock, [
      { result: success({ matchedConditionID: "ready" }), advanceMs: 4 },
      { result: failure("protocol_error", "Invalid envelope"), advanceMs: 6 }
    ]);
    const runner = new WorkflowRunner({ runtime, clock });

    const result = await runner.run("wait_and_inspect", {
      conditions: [{ id: "ready", mode: "idle" }]
    }, { deadlineAtMs: 100 });

    expect(result).toMatchObject({
      ok: false,
      error: { code: "protocol_error" },
      data: {
        stage: "inspect",
        wait: { matchedConditionID: "ready" },
        observation: { code: "protocol_error" },
        timing: { waitMs: 4, inspectMs: 6, totalMs: 10 }
      }
    });
  });

  it("总 deadline 耗尽后返回稳定 workflow_timeout 且不再发 inspect", async () => {
    const clock = new FakeClock();
    const runtime = new FakeRuntime(clock, [
      { result: failure("wait_timeout", "No condition matched"), advanceMs: 50 }
    ]);
    const runner = new WorkflowRunner({ runtime, clock });

    const result = await runner.run("wait_and_inspect", {
      conditions: [{ id: "ready", mode: "idle" }]
    }, { deadlineAtMs: 50 });

    expect(runtime.calls.map(call => call.action)).toEqual(["ui.waitAny"]);
    expect(clock.scheduledDelays).toEqual([50]);
    expect(result).toMatchObject({
      ok: false,
      error: {
        source: "workflow",
        code: "workflow_timeout",
        action: "wait_and_inspect",
        timeoutMs: 50,
        data: { stageAction: "ui.waitAny" }
      },
      data: {
        stage: "wait",
        wait: { source: "workflow", code: "workflow_timeout" },
        timing: { waitMs: 50, inspectMs: 0, totalMs: 50 }
      }
    });
  });

  it("记录 operation、阶段调用和 timeout，不记录 workflow 输入", async () => {
    const clock = new FakeClock();
    const runtime = new FakeRuntime(clock, [
      { result: failure("wait_timeout", "private wait error"), advanceMs: 50 }
    ]);
    const recorded = hostLogRecorder();
    const runner = new WorkflowRunner({ runtime, clock, logger: recorded.logger });

    await runner.run("wait_and_inspect", {
      conditions: [{ id: "secret-condition", mode: "idle" }]
    }, { deadlineAtMs: 50 });

    expect(recorded.entries().map(entry => entry.event)).toEqual([
      "workflow.operation.start",
      "workflow.stage.start",
      "workflow.stage.timeout",
      "workflow.operation.failure"
    ]);
    expect(recorded.entries()[2]).toMatchObject({ operation: "wait_and_inspect", action: "ui.waitAny", timeoutMs: 50 });
    expect(recorded.lines.join("")).not.toMatch(/secret-condition|private wait error|conditions/);
  });
});

function success(data: JSONObject): InvocationResult {
  return { ok: true, data, artifacts: [], elapsedMs: 0, attempts: 1 };
}

function failure(code: string, message: string, data?: JSONObject): InvocationResult {
  return {
    ok: false,
    error: {
      source: code === "protocol_error" ? "protocol" : "appEnvelope",
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
