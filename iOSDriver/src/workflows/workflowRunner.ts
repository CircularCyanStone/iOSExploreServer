import type { JSONObject } from "../types.js";
import type { InvocationResult } from "../runtime/types.js";
import { runTapAndInspect } from "./tapAndInspect.js";
import type {
  WorkflowClock,
  WorkflowExecutionContext,
  WorkflowOperation,
  WorkflowResult,
  WorkflowRunnerOptions,
  WorkflowRunOptions
} from "./types.js";
import { runWaitAndInspect } from "./waitAndInspect.js";

const SYSTEM_CLOCK: WorkflowClock = {
  now: () => Date.now(),
  setTimeout: (callback, delayMs) => globalThis.setTimeout(callback, delayMs),
  clearTimeout: handle => globalThis.clearTimeout(handle as ReturnType<typeof setTimeout>)
};

/** 在一个总 deadline 内串行执行 host workflow。 */
export class WorkflowRunner {
  private readonly runtime: WorkflowRunnerOptions["runtime"];
  private readonly clock: WorkflowClock;

  /**
   * 创建 workflow runner。
   *
   * @param options 最小 runtime 边界和可选测试时钟。
   */
  constructor(options: WorkflowRunnerOptions) {
    this.runtime = options.runtime;
    this.clock = options.clock ?? SYSTEM_CLOCK;
  }

  /**
   * 执行一个生成合同中声明的复合操作。
   *
   * @param operation host operation 名称。
   * @param input 由上层按 host contract 校验过的 JSON 输入；workflow 仍会再次做字段白名单投影。
   * @param options 所有子 action 共用的绝对截止时间。
   * @returns 与普通 action 一致的稳定 runtime 结果。
   */
  async run(
    operation: WorkflowOperation,
    input: JSONObject,
    options: WorkflowRunOptions
  ): Promise<WorkflowResult> {
    const startedAt = this.clock.now();
    const totalBudgetMs = Math.max(0, options.deadlineAtMs - startedAt);
    const context = this.context(operation, options.deadlineAtMs, totalBudgetMs);

    switch (operation) {
      case "tap_and_inspect":
        return runTapAndInspect(context, input, startedAt);
      case "wait_and_inspect":
        return runWaitAndInspect(context, input, startedAt);
    }
  }

  private context(
    operation: WorkflowOperation,
    deadlineAtMs: number,
    totalBudgetMs: number
  ): WorkflowExecutionContext {
    return {
      now: () => this.clock.now(),
      invoke: async (action, data) => {
        const remainingMs = deadlineAtMs - this.clock.now();
        if (remainingMs <= 0) {
          return workflowTimeout(operation, action, totalBudgetMs);
        }

        const controller = new AbortController();
        const timer = this.clock.setTimeout(() => controller.abort(), remainingMs);
        let result: InvocationResult;
        try {
          result = await this.runtime.invoke(action, data, { signal: controller.signal });
        } finally {
          this.clock.clearTimeout(timer);
        }

        if (this.clock.now() >= deadlineAtMs) {
          return workflowTimeout(operation, action, totalBudgetMs);
        }
        return result;
      }
    };
  }
}

function workflowTimeout(
  operation: WorkflowOperation,
  stageAction: string,
  timeoutMs: number
): InvocationResult {
  const data: JSONObject = { stageAction };
  return {
    ok: false,
    error: {
      source: "workflow",
      code: "workflow_timeout",
      message: `Workflow ${operation} exceeded its total deadline`,
      action: operation,
      timeoutMs,
      data
    },
    data,
    elapsedMs: timeoutMs,
    attempts: 0
  };
}
