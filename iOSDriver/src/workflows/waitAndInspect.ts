/**
 * `wait_and_inspect` 的固定阶段实现：`ui.waitAny → ui.inspect`。
 *
 * 输入字段白名单来自 generated host contract（`HOST_OPERATION_SPECS`），避免 schema
 * 增减后这里维护一份手写参数表。语义要点：**等待未命中（wait_timeout）仍继续执行
 * inspect**——让调用方看到超时当下的真实 UI；其他错误（连接/协议失败）则立即结束，
 * 避免在连接已失败时追加无意义请求。
 *
 * 典型流程：
 *   waitAny(conditions, timeoutMs) → [wait_timeout 可继续] → inspect(inspectOptions)
 *   → 结果聚合 { wait, observation, timing }
 */
import { HOST_OPERATION_SPECS } from "../generated/hostOperationSpecs.js";
import type { InvocationResult } from "../runtime/types.js";
import type { JSONObject, JSONValue } from "../types.js";
import { shouldContinueAfterWaitFailure } from "./errorPolicy.js";
import { stepValue, workflowFailure, workflowSuccess } from "./resultAggregation.js";
import type { WorkflowExecutionContext, WorkflowResult } from "./types.js";

/** 合同 schema 的运行时最小形状（只需读属性名与嵌套 inspectOptions 的属性名）。 */
interface ContractProperty {
  /** 这里只需要递归读取嵌套 `inspectOptions` 的属性名。 */
  readonly properties?: Readonly<Record<string, ContractProperty>>;
}

interface ContractObjectSchema {
  readonly properties: Readonly<Record<string, ContractProperty>>;
}

/** 从 generated 产物中查找 wait_and_inspect 的输入 schema（启动期校验存在）。 */
const WAIT_AND_INSPECT_SPEC = HOST_OPERATION_SPECS.find(
  spec => spec.operation === "wait_and_inspect"
);

if (WAIT_AND_INSPECT_SPEC === undefined) {
  throw new Error("Missing generated host operation contract: wait_and_inspect");
}

/** 输入 schema 的 properties；顶层除 inspectOptions 外的键都属于 waitAny。 */
const INPUT_SCHEMA = WAIT_AND_INSPECT_SPEC.inputSchema as unknown as ContractObjectSchema;
const WAIT_KEYS = Object.keys(INPUT_SCHEMA.properties).filter(key => key !== "inspectOptions");
const INSPECT_SCHEMA = INPUT_SCHEMA.properties.inspectOptions as ContractObjectSchema;
const INSPECT_KEYS = Object.keys(INSPECT_SCHEMA.properties);

/**
 * 固定执行 `ui.waitAny → ui.inspect`，把 `wait_timeout` 仅视为过程信号。
 *
 * @param context 由 WorkflowRunner 提供的 deadline 受限调用上下文。
 * @param input host operation 输入（顶层字段给 waitAny，inspectOptions 给 inspect）。
 * @param workflowStartedAt workflow 起始时间戳（计算 totalMs）。
 * @returns observation 成功时返回整体成功；终态失败保留已执行阶段与 timing。
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

/**
 * 构造各阶段耗时统计（waitMs/inspectMs/totalMs）。
 *
 * @param waitMs waitAny 阶段耗时。
 * @param inspectMs inspect 阶段耗时。
 * @param totalMs workflow 总耗时。
 * @returns 计时 JSON 对象。
 */
function waitTiming(waitMs: number, inspectMs: number, totalMs: number): JSONObject {
  return { waitMs, inspectMs, totalMs };
}

/**
 * 字段白名单投影：只把合同属于当前子 action 的字段向下传递。
 * 保证 workflow 控制字段（如 inspectOptions）不会泄漏到 App parser。
 *
 * @param input 完整 host 输入。
 * @param allowedKeys 允许传给子 action 的键。
 * @returns 只含 allowedKeys 中实际存在字段的新对象。
 */
function project(input: JSONObject, allowedKeys: readonly string[]): JSONObject {
  return Object.fromEntries(
    allowedKeys.flatMap(key => input[key] === undefined ? [] : [[key, input[key] as JSONValue]])
  );
}

/** 类型守卫：未知值是否为 JSON 对象（非 null、非数组）。 */
function objectValue(value: unknown): JSONObject | undefined {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? value as JSONObject
    : undefined;
}
