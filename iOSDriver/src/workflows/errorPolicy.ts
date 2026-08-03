/**
 * workflow 对中间阶段错误的继续/终止策略。
 *
 * 为什么需要独立策略：合同中的一般 retryable/terminal 元数据不能直接等价为
 * 「继续执行下一个 UI 阶段」；只有 `wait_timeout` 能表达「等待条件未命中，但当前
 * 界面仍值得 inspect」的过程状态（其他失败如连接/协议错误应短路 workflow）。
 */
import { CONTRACT_ERROR_INDEX } from "../generated/contractBundle.js";
import type { DriverError } from "../runtime/driverErrors.js";

/** 当前决策实际需要的 generated error 元数据最小投影。 */
interface ContractErrorMetadata {
  readonly source: string;
  readonly terminal: boolean;
}

/** 允许作为「过程信号」继续 inspect 的错误码白名单。 */
const WAIT_CONTINUE_CODES = new Set(["wait_timeout"]);

/**
 * 判断 wait 失败是否仍能作为有效过程信号继续 inspect。
 *
 * 双重校验：错误码必须在本地白名单中，**且** generated 合同元数据确认它是
 * appEnvelope 来源、非 terminal——避免未来某个同名错误改变 source/terminal 语义后，
 * workflow 仍按旧假设继续执行。
 *
 * @param error wait 阶段产生的稳定错误。
 * @returns true=应继续执行 inspect（仅 wait_timeout 且合同语义允许时）。
 */
export function shouldContinueAfterWaitFailure(error: DriverError): boolean {
  if (!WAIT_CONTINUE_CODES.has(error.code)) return false;
  const metadata = (CONTRACT_ERROR_INDEX as Record<string, ContractErrorMetadata | undefined>)[error.code];
  return metadata?.source === "appEnvelope" && metadata.terminal === false;
}
