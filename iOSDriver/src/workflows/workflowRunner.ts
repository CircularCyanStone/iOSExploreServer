import type { JSONObject } from "../types.js";
import type { InvocationResult } from "../runtime/types.js";
import type { DriverError } from "../runtime/driverErrors.js";
import { noopHostLogger, type HostLogger } from "../runtime/hostLogger.js";
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
  private readonly logger: HostLogger;

  /**
   * 创建 workflow runner。
   *
   * @param options 最小 runtime 边界和可选测试时钟。
   */
  constructor(options: WorkflowRunnerOptions) {
    this.runtime = options.runtime;
    this.clock = options.clock ?? SYSTEM_CLOCK;
    this.logger = options.logger ?? noopHostLogger;
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
    this.logger.emit("info", "workflow.operation.start", { operation, totalBudgetMs });

    try {
      let result: WorkflowResult;
      switch (operation) {
        case "tap_and_inspect":
          result = await runTapAndInspect(context, input, startedAt);
          break;
        case "wait_and_inspect":
          result = await runWaitAndInspect(context, input, startedAt);
          break;
      }
      this.logger.emit(result.ok ? "info" : "warn", result.ok ? "workflow.operation.complete" : "workflow.operation.failure", {
        operation,
        outcome: result.ok ? "success" : "failure",
        attempts: result.attempts,
        elapsedMs: result.elapsedMs,
        ...(result.ok ? {} : workflowErrorFields(result.error))
      });
      return result;
    } catch (error) {
      this.logger.emit("error", "workflow.operation.failure", {
        operation,
        outcome: "throw",
        elapsedMs: this.clock.now() - startedAt,
        errorType: error instanceof Error ? error.name : typeof error
      });
      throw error;
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
        this.logger.emit("debug", "workflow.stage.start", { operation, action, remainingMs });
        if (remainingMs <= 0) {
          this.logger.emit("warn", "workflow.stage.timeout", { operation, action, timeoutMs: totalBudgetMs });
          return workflowTimeout(operation, action, totalBudgetMs);
        }

        const controller = new AbortController();
        const timer = this.clock.setTimeout(() => controller.abort(), remainingMs);
        let result: InvocationResult;
        try {
          result = await this.runtime.invoke(action, data, { signal: controller.signal });
        } catch (error) {
          this.logger.emit("error", "workflow.stage.failure", {
            operation,
            action,
            outcome: "throw",
            errorType: error instanceof Error ? error.name : typeof error
          });
          throw error;
        } finally {
          this.clock.clearTimeout(timer);
        }

        if (this.clock.now() >= deadlineAtMs) {
          this.logger.emit("warn", "workflow.stage.timeout", { operation, action, timeoutMs: totalBudgetMs });
          return workflowTimeout(operation, action, totalBudgetMs);
        }
        this.logger.emit(result.ok ? "debug" : "warn", result.ok ? "workflow.stage.complete" : "workflow.stage.failure", {
          operation,
          action,
          outcome: result.ok ? "success" : "failure",
          attempts: result.attempts,
          elapsedMs: result.elapsedMs,
          ...(result.ok ? {} : workflowErrorFields(result.error))
        });
        return result;
      }
    };
  }
}

function workflowErrorFields(error: DriverError): Record<string, string | number | undefined> {
  return {
    source: error.source,
    code: error.code,
    status: error.status,
    timeoutMs: error.timeoutMs,
    transportPhase: error.transportPhase,
    protocolIssue: error.protocolIssue
  };
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
