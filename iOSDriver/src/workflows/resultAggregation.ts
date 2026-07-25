import type { DriverError } from "../runtime/driverErrors.js";
import type { Artifact, InvocationResult } from "../runtime/types.js";
import type { JSONObject } from "../types.js";
import type { WorkflowResult } from "./types.js";

/** workflow 终态失败所在的业务阶段。 */
export type WorkflowStage = "tap" | "wait" | "inspect";

/** 将子调用转换为 workflow data 中可序列化的阶段结果。 */
export function stepValue(result: InvocationResult): JSONObject {
  if (result.ok) return result.data;
  return errorValue(result.error, result.data);
}

/** 聚合所有子调用的 artifact、耗时和尝试次数，生成成功结果。 */
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

/** 聚合失败结果，并显式记录终态失败阶段且保持底层错误不变。 */
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

function artifacts(results: readonly InvocationResult[]): readonly Artifact[] {
  return results.flatMap(result => result.ok ? result.artifacts : result.artifacts ?? []);
}

function attempts(results: readonly InvocationResult[]): number {
  return results.reduce((total, result) => total + result.attempts, 0);
}
