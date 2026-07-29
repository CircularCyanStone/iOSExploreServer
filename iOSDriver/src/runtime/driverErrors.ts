import type { JSONObject } from "../types.js";

/** transport 失败发生的阶段，用于严格限制自动重试范围。 */
export type TransportPhase = "connect" | "reset" | "timeout" | "abort" | "unknown";

/** protocol 失败的具体类别；稳定 code 统一为 `protocol_error`。 */
export type ProtocolIssue = "invalid_json" | "invalid_envelope" | "response_too_large";

/** Host runtime 对外暴露的稳定错误结构。 */
export interface DriverError {
  /** 失败所属层；adapter 使用它决定退出码和 MCP tool error。 */
  readonly source: "config" | "transport" | "http" | "protocol" | "appEnvelope" | "workflow" | "artifact";
  /** 可供脚本判断的稳定错误码。 */
  readonly code: string;
  /** 给人阅读的错误摘要，不应包含完整请求 payload。 */
  readonly message: string;
  /** 失败的 device action 或 host workflow 名。 */
  readonly action?: string;
  /** transport 失败时实际访问的 App endpoint。 */
  readonly baseURL?: string;
  /** HTTP 层失败时的状态码。 */
  readonly status?: number;
  /** transport 或 workflow 使用的超时预算。 */
  readonly timeoutMs?: number;
  /** 非成功 HTTP/非法 JSON 的截断响应片段，最长由 transport 控制。 */
  readonly bodySnippet?: string;
  /** App 或 workflow 返回的结构化失败上下文。 */
  readonly data?: JSONObject;
  /** transport 失败阶段，runtime 仅对 connect/reset 判断安全重试。 */
  readonly transportPhase?: TransportPhase;
  /** JSON/envelope/响应体大小中的具体协议问题。 */
  readonly protocolIssue?: ProtocolIssue;
}

/**
 * transport 实现向 runtime 传递的已分类异常。
 *
 * `responseReceived` 是 retry 的安全边界：一旦收到 HTTP response，runtime 不再自动重放请求。
 */
export class DriverFailure extends Error {
  /** 已归一化的稳定错误。 */
  readonly driverError: DriverError;
  /** 是否已经收到 HTTP response。 */
  readonly responseReceived: boolean;

  /**
   * 创建一个已分类 transport 异常。
   *
   * @param driverError 稳定错误信息。
   * @param responseReceived 是否已收到 HTTP response。
   */
  constructor(driverError: DriverError, responseReceived: boolean) {
    super(driverError.message);
    this.name = "DriverFailure";
    this.driverError = driverError;
    this.responseReceived = responseReceived;
  }
}
