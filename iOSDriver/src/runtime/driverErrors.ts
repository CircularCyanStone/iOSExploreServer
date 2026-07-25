import type { JSONObject } from "../types.js";

/** transport 失败发生的阶段，用于严格限制自动重试范围。 */
export type TransportPhase = "connect" | "reset" | "timeout" | "abort" | "unknown";

/** protocol 失败的具体类别；稳定 code 统一为 `protocol_error`。 */
export type ProtocolIssue = "invalid_json" | "invalid_envelope" | "response_too_large";

/** Host runtime 对外暴露的稳定错误结构。 */
export interface DriverError {
  readonly source: "config" | "transport" | "http" | "protocol" | "appEnvelope" | "workflow" | "artifact";
  readonly code: string;
  readonly message: string;
  readonly action?: string;
  readonly baseURL?: string;
  readonly status?: number;
  readonly timeoutMs?: number;
  readonly bodySnippet?: string;
  readonly data?: JSONObject;
  readonly transportPhase?: TransportPhase;
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
