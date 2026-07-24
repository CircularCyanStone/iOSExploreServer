import type { JSONObject } from "../types.js";

/** 一次 action 请求的传输层返回值；业务 envelope 由 runtime 解释。 */
export interface ActionTransportResponse {
  readonly httpStatus: number;
  readonly envelope: JSONObject;
}

/**
 * App action 的可注入传输边界。
 *
 * 实现只负责把请求送达 App 并返回 JSON 对象，不解释任何 UIKit 字段。
 */
export interface ActionTransport {
  /**
   * 执行一次 action 请求。
   *
   * @param request action 名与 JSON data。
   * @param options 单次 transport timeout 与可选外部取消信号。
   * @returns HTTP 状态和未经业务解释的 envelope。
   */
  execute(
    request: { action: string; data: JSONObject },
    options: { timeoutMs: number; signal?: AbortSignal }
  ): Promise<ActionTransportResponse>;
}
