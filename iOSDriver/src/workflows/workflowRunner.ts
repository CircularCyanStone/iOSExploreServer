/**
 * workflow 的总 deadline 执行器。
 *
 * 核心机制：runner 为每个子 action 根据**同一个绝对截止时间**创建 AbortSignal
 * （timer 只覆盖当前阶段，到期点始终是同一个 deadline），并在阶段返回后**再次检查
 * 时钟**——后置检查用于处理不遵守 abort 的注入 runtime，保证即使底层晚返回，
 * workflow 也不会把 deadline 之后的结果误报为成功。
 *
 * 典型调用（wait_and_inspect，总预算 20 秒）：
 *   run("wait_and_inspect", input, {deadlineAtMs}) → 阶段 1 ui.waitAny（共享 deadline）
 *   → 阶段 2 ui.inspect（共享 deadline）→ 聚合结果
 */
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

/** 生产时钟：直接代理 globalThis 的 now/setTimeout/clearTimeout。 */
const SYSTEM_CLOCK: WorkflowClock = {
  now: () => Date.now(),
  setTimeout: (callback, delayMs) => globalThis.setTimeout(callback, delayMs),
  clearTimeout: handle => globalThis.clearTimeout(handle as ReturnType<typeof setTimeout>)
};

/**
 * 在一个总 deadline 内串行执行 host workflow（wait_and_inspect / tap_and_inspect）。
 */
export class WorkflowRunner {
  /** 只暴露 invoke 的 runtime——复合操作无法直接访问 transport。 */
  private readonly runtime: WorkflowRunnerOptions["runtime"];
  /** 时钟：生产用系统时间，测试注入可控时钟。 */
  private readonly clock: WorkflowClock;
  private readonly logger: HostLogger;

  /**
   * 创建 workflow runner。
   *
   * @param options 最小 runtime 边界、可选测试时钟与 logger。
   */
  constructor(options: WorkflowRunnerOptions) {
    this.runtime = options.runtime;
    this.clock = options.clock ?? SYSTEM_CLOCK;
    this.logger = options.logger ?? noopHostLogger;
  }

  /**
   * 执行一个生成合同中声明的复合操作。
   *
   * @param operation host operation 名（wait_and_inspect / tap_and_inspect）。
   * @param input 由上层按 host contract 校验过的 JSON 输入；workflow 内部仍会做
   *   字段白名单投影（防止 workflow 控制字段泄漏到 App parser）。
   * @param options 所有子 action 共用的绝对截止时间（毫秒时间戳）。
   * @returns 与普通 action 一致的稳定 runtime 结果（含阶段聚合的 data）。
   */
  async run(
    operation: WorkflowOperation,
    input: JSONObject,
    options: WorkflowRunOptions
  ): Promise<WorkflowResult> {
    const startedAt = this.clock.now();
    // 过去的 deadline 被压为 0，后续 context 会在发请求前返回 workflow_timeout。
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

  /**
   * 创建只暴露「剩余预算内调用」能力的阶段上下文。
   *
   * 返回的 `invoke` 包装了三条纪律：
   * 1. 剩余预算 <=0 时直接返回 `workflow_timeout` 失败（不发请求）；
   * 2. 每个阶段用剩余预算创建 AbortSignal（timer 到期点 = 绝对 deadline）；
   * 3. 阶段返回后再次核对时间——不遵守 abort 的 runtime 晚返回也不能越界。
   *
   * @param operation 当前 workflow 名（仅用于日志/错误信息）。
   * @param deadlineAtMs 绝对截止时间戳。
   * @param totalBudgetMs 总预算（用于错误信息）。
   * @returns 受限执行上下文。
   */
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
        // timer 只覆盖当前阶段，但到期点始终是 workflow 的同一个绝对 deadline。
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

        // 某些 runtime/mock 可能忽略 AbortSignal；返回后再次核对时间可维持总预算合同。
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

/**
 * 提取 workflow 错误的可日志字段（不含 message/payload，防泄漏）。
 *
 * @param error 稳定错误。
 * @returns 稳定字段集合（source/code/status/timeoutMs/transportPhase/protocolIssue）。
 */
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

/**
 * 构造稳定的 workflow deadline 失败（不依赖底层 action 的错误格式）。
 *
 * @param operation workflow 名。
 * @param stageAction 超时发生时正在执行的子 action（记入 data）。
 * @param timeoutMs 总预算（毫秒）。
 * @returns source=workflow、code=workflow_timeout 的失败结果，attempts=0。
 */
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
