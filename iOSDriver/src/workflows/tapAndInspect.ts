import { HOST_OPERATION_SPECS } from "../generated/hostOperationSpecs.js";
import type { DriverError } from "../runtime/driverErrors.js";
import type { Artifact, InvocationResult } from "../runtime/types.js";
import type { JSONObject, JSONValue } from "../types.js";
import type { WorkflowExecutionContext, WorkflowResult } from "./types.js";

interface ContractProperty {
  readonly default?: unknown;
}

interface ContractObjectSchema {
  readonly properties: Readonly<Record<string, ContractProperty>>;
}

const TAP_AND_INSPECT_SPEC = HOST_OPERATION_SPECS.find(
  spec => spec.operation === "tap_and_inspect"
);

if (TAP_AND_INSPECT_SPEC === undefined) {
  throw new Error("Missing generated host operation contract: tap_and_inspect");
}

const INPUT_SCHEMA = TAP_AND_INSPECT_SPEC.inputSchema as unknown as ContractObjectSchema;
const WORKFLOW_KEYS = new Set([
  "waitForStable",
  "stableTimeMs",
  "inspectDepth",
  "inspectMaxTargets"
]);
const TAP_KEYS = Object.keys(INPUT_SCHEMA.properties).filter(key => !WORKFLOW_KEYS.has(key));

/**
 * 固定执行 `ui.tap -> 可选 ui.wait(idle) -> ui.inspect`。
 *
 * @param context 由 WorkflowRunner 提供的 deadline 受限调用上下文。
 * @param input host operation 输入。
 * @param workflowStartedAt workflow 起始时间戳。
 * @returns inspect 成功时返回整体成功；任一终态失败保留已执行阶段和 timing。
 */
export async function runTapAndInspect(
  context: WorkflowExecutionContext,
  input: JSONObject,
  workflowStartedAt: number
): Promise<WorkflowResult> {
  const results: InvocationResult[] = [];
  const tapStartedAt = context.now();
  const tapResult = await context.invoke("ui.tap", project(input, TAP_KEYS));
  const tapMs = context.now() - tapStartedAt;
  results.push(tapResult);

  if (!tapResult.ok) {
    const totalMs = context.now() - workflowStartedAt;
    return failure(tapResult.error, {
      tap: stepValue(tapResult),
      timing: tapTiming(tapMs, undefined, 0, totalMs)
    }, results, totalMs);
  }

  const waitForStable = valueOrDefault<boolean>(input, "waitForStable");
  const stableTimeMs = valueOrDefault<number>(input, "stableTimeMs");
  let waitResult: InvocationResult | undefined;
  let waitMs: number | undefined;

  if (waitForStable) {
    const waitStartedAt = context.now();
    waitResult = await context.invoke("ui.wait", {
      mode: "idle",
      stableMs: stableTimeMs,
      timeoutMs: stableTimeMs + 1000
    });
    waitMs = context.now() - waitStartedAt;
    results.push(waitResult);
  }

  const inspectStartedAt = context.now();
  const inspectResult = await context.invoke("ui.inspect", {
    maxDepth: valueOrDefault<number>(input, "inspectDepth"),
    maxTargets: valueOrDefault<number>(input, "inspectMaxTargets")
  });
  const inspectMs = context.now() - inspectStartedAt;
  results.push(inspectResult);
  const totalMs = context.now() - workflowStartedAt;
  const data: JSONObject = {
    tap: stepValue(tapResult),
    ...(waitResult === undefined ? {} : { wait: stepValue(waitResult) }),
    stateAfter: stepValue(inspectResult),
    timing: tapTiming(tapMs, waitMs, inspectMs, totalMs)
  };

  if (!inspectResult.ok) {
    return failure(inspectResult.error, data, results, totalMs);
  }
  return success(data, results, totalMs);
}

function valueOrDefault<T extends boolean | number>(input: JSONObject, key: string): T {
  const value = input[key];
  if (typeof value === "boolean" || typeof value === "number") return value as T;
  const defaultValue = INPUT_SCHEMA.properties[key]?.default;
  if (typeof defaultValue !== "boolean" && typeof defaultValue !== "number") {
    throw new Error(`Generated tap_and_inspect contract is missing default for ${key}`);
  }
  return defaultValue as T;
}

function tapTiming(
  tapMs: number,
  waitMs: number | undefined,
  inspectMs: number,
  totalMs: number
): JSONObject {
  return {
    tapMs,
    ...(waitMs === undefined ? {} : { waitMs }),
    inspectMs,
    totalMs
  };
}

function project(input: JSONObject, allowedKeys: readonly string[]): JSONObject {
  return Object.fromEntries(
    allowedKeys.flatMap(key => input[key] === undefined ? [] : [[key, input[key] as JSONValue]])
  );
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
