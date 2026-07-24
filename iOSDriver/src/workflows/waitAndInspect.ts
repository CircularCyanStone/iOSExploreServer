import { HOST_OPERATION_SPECS } from "../generated/hostOperationSpecs.js";
import type { DriverError } from "../runtime/driverErrors.js";
import type { Artifact, InvocationResult } from "../runtime/types.js";
import type { JSONObject, JSONValue } from "../types.js";
import type { WorkflowExecutionContext, WorkflowResult } from "./types.js";

interface ContractProperty {
  readonly properties?: Readonly<Record<string, ContractProperty>>;
}

interface ContractObjectSchema {
  readonly properties: Readonly<Record<string, ContractProperty>>;
}

const WAIT_AND_INSPECT_SPEC = HOST_OPERATION_SPECS.find(
  spec => spec.operation === "wait_and_inspect"
);

if (WAIT_AND_INSPECT_SPEC === undefined) {
  throw new Error("Missing generated host operation contract: wait_and_inspect");
}

const INPUT_SCHEMA = WAIT_AND_INSPECT_SPEC.inputSchema as unknown as ContractObjectSchema;
const WAIT_KEYS = Object.keys(INPUT_SCHEMA.properties).filter(key => key !== "inspectOptions");
const INSPECT_SCHEMA = INPUT_SCHEMA.properties.inspectOptions as ContractObjectSchema;
const INSPECT_KEYS = Object.keys(INSPECT_SCHEMA.properties);

/**
 * 固定执行 `ui.waitAny -> ui.inspect`，并把 `wait_timeout` 仅视为过程信号。
 *
 * @param context 由 WorkflowRunner 提供的 deadline 受限调用上下文。
 * @param input host operation 输入。
 * @param workflowStartedAt workflow 起始时间戳。
 * @returns observation 成功时返回整体成功；其他终态失败保留已执行阶段和 timing。
 */
export async function runWaitAndInspect(
  context: WorkflowExecutionContext,
  input: JSONObject,
  workflowStartedAt: number
): Promise<WorkflowResult> {
  const waitStartedAt = context.now();
  const waitResult = await context.invoke("ui.waitAny", project(input, WAIT_KEYS));
  const waitMs = context.now() - waitStartedAt;
  const results: InvocationResult[] = [waitResult];

  if (!waitResult.ok && waitResult.error.code !== "wait_timeout") {
    return failure(waitResult.error, {
      wait: stepValue(waitResult),
      timing: waitTiming(waitMs, 0, context.now() - workflowStartedAt)
    }, results, context.now() - workflowStartedAt);
  }

  const inspectInput = objectValue(input.inspectOptions) ?? {};
  const inspectStartedAt = context.now();
  const inspectResult = await context.invoke("ui.inspect", project(inspectInput, INSPECT_KEYS));
  const inspectMs = context.now() - inspectStartedAt;
  results.push(inspectResult);
  const totalMs = context.now() - workflowStartedAt;
  const data: JSONObject = {
    wait: stepValue(waitResult),
    observation: stepValue(inspectResult),
    timing: waitTiming(waitMs, inspectMs, totalMs)
  };

  if (!inspectResult.ok) {
    return failure(inspectResult.error, data, results, totalMs);
  }
  return success(data, results, totalMs);
}

function waitTiming(waitMs: number, inspectMs: number, totalMs: number): JSONObject {
  return { waitMs, inspectMs, totalMs };
}

function project(input: JSONObject, allowedKeys: readonly string[]): JSONObject {
  return Object.fromEntries(
    allowedKeys.flatMap(key => input[key] === undefined ? [] : [[key, input[key] as JSONValue]])
  );
}

function objectValue(value: unknown): JSONObject | undefined {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? value as JSONObject
    : undefined;
}

function stepValue(result: InvocationResult): JSONObject {
  if (result.ok) return result.data;
  return errorValue(result.error, result.data);
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

function success(data: JSONObject, results: readonly InvocationResult[], totalMs: number): WorkflowResult {
  return {
    ok: true,
    data,
    artifacts: artifacts(results),
    elapsedMs: totalMs,
    attempts: attempts(results)
  };
}

function failure(
  error: DriverError,
  data: JSONObject,
  results: readonly InvocationResult[],
  totalMs: number
): WorkflowResult {
  const collectedArtifacts = artifacts(results);
  return {
    ok: false,
    error,
    data,
    ...(collectedArtifacts.length === 0 ? {} : { artifacts: collectedArtifacts }),
    elapsedMs: totalMs,
    attempts: attempts(results)
  };
}

function artifacts(results: readonly InvocationResult[]): readonly Artifact[] {
  return results.flatMap(result => result.ok ? result.artifacts : result.artifacts ?? []);
}

function attempts(results: readonly InvocationResult[]): number {
  return results.reduce((total, result) => total + result.attempts, 0);
}
