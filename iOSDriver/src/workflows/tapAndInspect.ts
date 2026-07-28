import { HOST_OPERATION_SPECS } from "../generated/hostOperationSpecs.js";
import type { InvocationResult } from "../runtime/types.js";
import type { JSONObject, JSONValue } from "../types.js";
import { shouldContinueAfterWaitFailure } from "./errorPolicy.js";
import { stepValue, workflowFailure, workflowSuccess } from "./resultAggregation.js";
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
    return workflowFailure(tapResult.error, "tap", {
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
    if (!waitResult.ok && !shouldContinueAfterWaitFailure(waitResult.error)) {
      const totalMs = context.now() - workflowStartedAt;
      return workflowFailure(waitResult.error, "wait", {
        tap: stepValue(tapResult),
        wait: stepValue(waitResult),
        timing: tapTiming(tapMs, waitMs, 0, totalMs)
      }, results, totalMs);
    }
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
    return workflowFailure(inspectResult.error, "inspect", data, results, totalMs);
  }
  return workflowSuccess(data, results, totalMs);
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
