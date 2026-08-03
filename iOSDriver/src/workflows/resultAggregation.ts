/**
 * workflow 子调用结果的聚合规则。
 *
 * 聚合只组合 data、artifact、耗时与尝试次数，**不重写底层 `DriverError`**——调用方
 * 既能看到失败发生在哪个 workflow 阶段（data.stage），也能继续按原始 error
 * source/code 做机器判断。
 */
import type { DriverError } from "../runtime/driverErrors.js";
import type { Artifact, InvocationResult } from "../runtime/types.js";
import type { JSONObject } from "../types.js";
import type { WorkflowResult } from "./types.js";

/** workflow 终态失败所在的业务阶段（写入结果 data.stage）。 */
export type WorkflowStage = "tap" | "wait" | "inspect";

/**
 * 将子调用转换为可嵌入 workflow data 的阶段快照：成功取 data，失败保留稳定诊断字段。
 *
 * @param result 子调用结果。
 * @returns 可安全嵌入聚合 data 的 JSON 对象（失败时不带大块 payload）。
 */
export function stepValue(result: InvocationResult): JSONObject {
  if (result.ok) return result.data;
  return errorValue(result.error, result.data);
}

/**
 * 聚合成功结果：合并全部子调用的 artifact 与尝试次数。
 *
 * @param data 已组装的业务 data（含各阶段快照与 timing）。
 * @param results 已执行阶段的调用结果列表。
 * @param totalMs 总耗时（runner 的共享时钟提供）。
 * @returns ok=true 的 WorkflowResult。
 */
export function workflowSuccess(
  data: JSONObject,
  results: readonly InvocationResult[],
  totalMs: number
): WorkflowResult {
  return {
    ok: true,
    data,
    artifacts: artifacts(results),
    elapsedMs: totalMs,
    attempts: attempts(results)
  };
}

/**
 * 聚合失败结果，显式记录终态失败阶段且**保持底层错误不变**。
 *
 * 已执行阶段产生的 artifact 仍会返回；尚未执行的阶段不会制造占位结果。
 *
 * @param error 底层稳定错误（原样保留）。
 * @param stage 终态失败所在的业务阶段（写入 data.stage）。
 * @param data 已组装的业务 data。
 * @param results 已执行阶段的调用结果列表。
 * @param totalMs 总耗时。
 * @returns ok=false 的 WorkflowResult。
 */
export function workflowFailure(
  error: DriverError,
  stage: WorkflowStage,
  data: JSONObject,
  results: readonly InvocationResult[],
  totalMs: number
): WorkflowResult {
  const collectedArtifacts = artifacts(results);
  return {
    ok: false,
    error,
    data: { ...data, stage },
    ...(collectedArtifacts.length === 0 ? {} : { artifacts: collectedArtifacts }),
    elapsedMs: totalMs,
    attempts: attempts(results)
  };
}

/**
 * 把错误转成可嵌入聚合 data 的快照（失败时保留稳定诊断字段）。
 *
 * 使用调用结果 data 优先于 error.data——确保 artifact decoder 的清理结果生效
 * （非法/超限 image 不会经此旁路输出）。
 *
 * @param error 稳定错误。
 * @param data 调用结果中已清理的 data（可能 undefined）。
 * @returns 稳定字段 + data 的 JSON 对象。
 */
function errorValue(error: DriverError, data?: JSONObject): JSONObject {
  return {
    source: error.source,
    code: error.code,
    message: error.message,
    ...(error.action === undefined ? {} : { action: error.action }),
    ...(error.baseURL === undefined ? {} : { baseURL: error.baseURL }),
    ...(error.status === undefined ? {} : { status: error.status }),
    ...(error.timeoutMs === undefined ? {} : { timeoutMs: error.timeoutMs }),
    ...(error.bodySnippet === undefined ? {} : { bodySnippet: error.bodySnippet }),
    ...(error.transportPhase === undefined ? {} : { transportPhase: error.transportPhase }),
    ...(error.protocolIssue === undefined ? {} : { protocolIssue: error.protocolIssue }),
    ...((data ?? error.data) === undefined ? {} : { data: (data ?? error.data) as JSONObject })
  };
}

/** 收集全部已执行子调用的 artifact（成功/失败结果都取）。 */
function artifacts(results: readonly InvocationResult[]): readonly Artifact[] {
  return results.flatMap(result => result.ok ? result.artifacts : result.artifacts ?? []);
}

/** 累计全部子调用的 transport 尝试次数。 */
function attempts(results: readonly InvocationResult[]): number {
  return results.reduce((total, result) => total + result.attempts, 0);
}
