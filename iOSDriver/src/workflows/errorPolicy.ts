/**
 * workflow 对中间阶段错误的继续/终止策略。
 *
 * 合同中的一般 retryable/terminal 元数据不能直接等价为“继续执行下一个 UI 阶段”；只有
 * `wait_timeout` 能表达“等待条件未命中，但当前界面仍值得 inspect”的过程状态。
 */
import { CONTRACT_ERROR_INDEX } from "../generated/contractBundle.js";
import type { DriverError } from "../runtime/driverErrors.js";

/** 当前决策实际需要的 generated error 元数据最小投影。 */
interface ContractErrorMetadata {
  readonly source: string;
  readonly terminal: boolean;
}

const WAIT_CONTINUE_CODES = new Set(["wait_timeout"]);

/**
 * 判断 wait 失败是否仍能作为有效过程信号继续 inspect。
 *
 * 同时校验本地白名单和 generated 元数据，避免未来某个同名错误改变 source/terminal
 * 语义后，workflow 仍按旧假设继续执行。
 */
export function shouldContinueAfterWaitFailure(error: DriverError): boolean {
  if (!WAIT_CONTINUE_CODES.has(error.code)) return false;
  const metadata = (CONTRACT_ERROR_INDEX as Record<string, ContractErrorMetadata | undefined>)[error.code];
  return metadata?.source === "appEnvelope" && metadata.terminal === false;
}
