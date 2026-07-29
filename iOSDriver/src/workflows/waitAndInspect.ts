/**
 * `wait_and_inspect` 的固定阶段实现。
 *
 * 输入字段白名单来自 generated host contract，避免 schema 增减后这里继续维护一份手写
 * 参数表。等待未命中仍执行 inspect，让调用方看到 timeout 当下的真实 UI；其他错误则
 * 立即结束，避免在连接或协议已经失败时追加无意义请求。
 */
import { HOST_OPERATION_SPECS } from "../generated/hostOperationSpecs.js";
import type { InvocationResult } from "../runtime/types.js";
import type { JSONObject, JSONValue } from "../types.js";
import { shouldContinueAfterWaitFailure } from "./errorPolicy.js";
import { stepValue, workflowFailure, workflowSuccess } from "./resultAggregation.js";
import type { WorkflowExecutionContext, WorkflowResult } from "./types.js";

interface ContractProperty {
  /** 这里只需要递归读取嵌套 `inspectOptions` 的属性名。 */
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

  // wait_timeout 是观察窗口结束，不是连接终止；除此之外的失败都短路 workflow。
  if (!waitResult.ok && !shouldContinueAfterWaitFailure(waitResult.error)) {
    return workflowFailure(waitResult.error, "wait", {
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
    return workflowFailure(inspectResult.error, "inspect", data, results, totalMs);
  }
  return workflowSuccess(data, results, totalMs);
}

function waitTiming(waitMs: number, inspectMs: number, totalMs: number): JSONObject {
  return { waitMs, inspectMs, totalMs };
}

/** 只把合同属于当前子 action 的字段向下传递，workflow 控制字段不会泄漏到 App parser。 */
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
