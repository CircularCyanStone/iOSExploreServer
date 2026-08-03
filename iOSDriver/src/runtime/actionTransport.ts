import type { JSONObject } from "../types.js";

/**
 * 一次 action 请求的传输层返回值；业务 envelope 由 runtime 解释。
 */
export interface ActionTransportResponse {
  /** 原始 HTTP 状态码；保留它允许自定义 transport 把非 2xx 交给 runtime 统一分类。 */
  readonly httpStatus: number;
  /** 已确认是 JSON 对象、但尚未解释 `code/data/message` 的响应 envelope。 */
  readonly envelope: JSONObject;
}

/**
 * App action 的可注入传输边界（整个 host 唯一的网络插头）。
 *
 * 职责边界：实现只负责「把请求送达 App 并返回 JSON 对象」；不解释任何 UIKit 字段、
 * 不做业务判断。生产实现是 `HttpActionTransport`，测试注入 fake 可无网络验证上层逻辑。
 */
export interface ActionTransport {
  /**
   * 执行一次 action 请求。
   *
   * @param request action 名与 JSON data。
   * @param options 单次 transport 超时与可选外部取消信号。
   * @returns HTTP 状态与未经业务解释的 envelope。
   * @throws {DriverFailure} 已分类的 transport/HTTP/协议失败，携带 responseReceived。
   */
  execute(
    request: {
      /** action 名；transport 必须原样发送，不能在此层重写 action 路由。 */
      action: string;
      /** data 对象；对 transport 是不透明内容，UIKit 字段由 App parser 所有。 */
      data: JSONObject;
    },
    options: {
      /** 单次尝试的预算；若 runtime 安全重试，第二次重新使用同一预算。 */
      timeoutMs: number;
      /** 外部取消信号；必须与内部 timeout 分类为不同的 transport phase。 */
      signal?: AbortSignal;
    }
  ): Promise<ActionTransportResponse>;
}
