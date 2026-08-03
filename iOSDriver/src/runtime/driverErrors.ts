import type { JSONObject } from "../types.js";

/**
 * transport 失败发生的阶段；用于严格限制自动重试范围。
 *
 * - "connect"：连接未建立（拒绝/DNS 失败/不可达）——请求肯定没到 App，可安全重试；
 * - "reset"：连接建立后被重置——请求可能已到达，仅在只读/幂等时可重试；
 * - "timeout"：超时；"abort"：外部取消；"unknown"：无法分类。
 */
export type TransportPhase = "connect" | "reset" | "timeout" | "abort" | "unknown";

/**
 * protocol 失败的具体类别；稳定 code 统一为 "protocol_error"，类别由本字段细分。
 */
export type ProtocolIssue = "invalid_json" | "invalid_envelope" | "response_too_large";

/**
 * Host runtime 对外暴露的稳定错误结构（所有预期失败的统一形态）。
 *
 * adapter 只根据 `source` 决定处理方式：CLI 映射退出码（config→2，
 * transport/http/protocol/artifact→3，其余→1），MCP 映射 isError。
 */
export interface DriverError {
  /** 失败所属层：config/transport/http/protocol/appEnvelope/workflow/artifact。 */
  readonly source: "config" | "transport" | "http" | "protocol" | "appEnvelope" | "workflow" | "artifact";
  /** 可供脚本做稳定判断的错误码（如 "transport_unavailable"、"invalid_data"）。 */
  readonly code: string;
  /** 给人阅读的错误摘要；不含完整请求 payload（防泄漏）。 */
  readonly message: string;
  /** 失败的 device action 或 host workflow 名（如 "ping"、"wait_and_inspect"）。 */
  readonly action?: string;
  /** transport 失败时实际访问的 App endpoint。 */
  readonly baseURL?: string;
  /** HTTP 层失败时的状态码（如 500）。 */
  readonly status?: number;
  /** transport 或 workflow 使用的超时预算（毫秒）。 */
  readonly timeoutMs?: number;
  /** 非成功 HTTP/非法 JSON 的截断响应片段（最多 500 字符，由 transport 控制）。 */
  readonly bodySnippet?: string;
  /** App 或 workflow 返回的结构化失败上下文。 */
  readonly data?: JSONObject;
  /** transport 失败阶段；runtime 仅对 connect/reset 判断安全重试。 */
  readonly transportPhase?: TransportPhase;
  /** JSON/envelope/响应体大小中的具体协议问题。 */
  readonly protocolIssue?: ProtocolIssue;
}

/**
 * transport 实现向 runtime 传递的已分类异常。
 *
 * 与 `DriverError` 的关系：DriverError 是「稳定错误数据」，DriverFailure 是
 * 「抛出来的异常包装」。`responseReceived` 是重试的安全边界——一旦收到过 HTTP
 * response，runtime 不再自动重放请求（可能已触发 UI 操作）。
 */
export class DriverFailure extends Error {
  /** 已归一化的稳定错误数据。 */
  readonly driverError: DriverError;
  /** 是否已经收到过 HTTP response（true=请求肯定到达过 App，不可重放）。 */
  readonly responseReceived: boolean;

  /**
   * 创建一个已分类的 transport 异常。
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
