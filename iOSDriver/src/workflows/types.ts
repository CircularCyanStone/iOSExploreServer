import type { JSONObject } from "../types.js";
import type { InvocationResult } from "../runtime/types.js";
import type { HostLogger } from "../runtime/hostLogger.js";

/** 当前支持的复合操作名称。 */
export type WorkflowOperation = "tap_and_inspect" | "wait_and_inspect";

/** workflow 对 DriverRuntime 的最小调用边界。 */
export interface WorkflowRuntime {
  /**
   * 调用一个 App action。
   *
   * @param action action 名称。
   * @param data 已按 host contract 投影的 JSON 参数。
   * @param options 当前阶段基于剩余总预算创建的取消信号。
   * @returns runtime 归一化后的调用结果。
   */
  invoke(
    action: string,
    data?: JSONObject,
    options?: { readonly signal?: AbortSignal }
  ): Promise<InvocationResult>;
}

/** workflow 使用的时钟；注入能力用于确定性验证总 deadline。 */
export interface WorkflowClock {
  /** @returns 当前时间戳，单位为毫秒。 */
  now(): number;

  /**
   * 注册一次 deadline 取消回调。
   *
   * @param callback deadline 到达时执行的回调。
   * @param delayMs 距离 deadline 的剩余毫秒数。
   * @returns 可用于取消计时器的句柄。
   */
  setTimeout(callback: () => void, delayMs: number): unknown;

  /**
   * 清除阶段计时器。
   *
   * @param handle `setTimeout` 返回的句柄。
   */
  clearTimeout(handle: unknown): void;
}

/** WorkflowRunner 的构造参数。 */
export interface WorkflowRunnerOptions {
  readonly runtime: WorkflowRuntime;
  readonly clock?: WorkflowClock;
  /** Host 命令链 logger；CLI/MCP 入口注入共享 stderr logger。 */
  readonly logger?: HostLogger;
}

/** 单次 workflow 的总截止时间。 */
export interface WorkflowRunOptions {
  /** Unix epoch 毫秒时间戳；所有子 action 共用这一总 deadline。 */
  readonly deadlineAtMs: number;
}

/** workflow 内部执行阶段时可用的受限上下文。 */
export interface WorkflowExecutionContext {
  /** @returns 当前时间戳，单位为毫秒。 */
  now(): number;

  /**
   * 在总 deadline 的剩余预算内调用一个子 action。
   *
   * @param action action 名称。
   * @param data 已投影的 action 参数。
   * @returns runtime 结果；预算耗尽时返回稳定的 `workflow_timeout` 失败。
   */
  invoke(action: string, data: JSONObject): Promise<InvocationResult>;
}

/** workflow 与普通 action 共用的稳定 runtime 返回类型。 */
export type WorkflowResult = InvocationResult;
