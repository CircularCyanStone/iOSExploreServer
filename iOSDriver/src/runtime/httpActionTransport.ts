import { bodySnippet } from "../errors.js";
import type { JSONObject } from "../types.js";
import type { ActionTransport, ActionTransportResponse } from "./actionTransport.js";
import { DriverFailure, type DriverError, type TransportPhase } from "./driverErrors.js";

/** 可注入的 fetch 边界，测试无需建立真实网络连接。 */
export type FetchLike = (input: string | URL | Request, init?: RequestInit) => Promise<Response>;

/** 使用 `POST /` JSON 协议访问 App 的唯一 HTTP transport 实现。 */
export class HttpActionTransport implements ActionTransport {
  private readonly fetchImpl: FetchLike;

  /**
   * 创建 HTTP transport。
   *
   * @param baseURL App HTTP action 端点。
   * @param fetchImpl 可选 fetch 实现，默认使用运行环境的全局 fetch。
   */
  constructor(
    private readonly baseURL: string,
    fetchImpl: FetchLike = globalThis.fetch.bind(globalThis)
  ) {
    this.fetchImpl = fetchImpl;
  }

  /**
   * 发送请求、读取完整 body 并解析 JSON 对象。
   *
   * @param request action 请求。
   * @param options transport timeout 与外部取消信号。
   * @returns HTTP 状态及 JSON envelope。
   * @throws `DriverFailure`，区分 transport、HTTP 和 protocol 失败。
   */
  async execute(
    request: { action: string; data: JSONObject },
    options: { timeoutMs: number; signal?: AbortSignal }
  ): Promise<ActionTransportResponse> {
    const controller = new AbortController();
    let timedOut = false;
    let externallyAborted = false;
    let responseReceived = false;
    const onExternalAbort = () => {
      if (!timedOut) externallyAborted = true;
      controller.abort(options.signal?.reason);
    };
    if (options.signal?.aborted) onExternalAbort();
    else options.signal?.addEventListener("abort", onExternalAbort, { once: true });
    const timer = setTimeout(() => {
      if (externallyAborted) return;
      timedOut = true;
      controller.abort();
    }, options.timeoutMs);

    try {
      const response = await this.fetchImpl(this.baseURL, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(request),
        signal: controller.signal
      });
      responseReceived = true;
      const text = await response.text();

      if (!response.ok) {
        throw new DriverFailure({
          source: "http",
          code: "http_error",
          message: `HTTP ${response.status}`,
          action: request.action,
          status: response.status,
          bodySnippet: bodySnippet(text)
        }, true);
      }

      let parsed: unknown;
      try {
        parsed = JSON.parse(text);
      } catch {
        throw new DriverFailure({
          source: "protocol",
          code: "protocol_error",
          message: "HTTP response was not valid JSON",
          action: request.action,
          bodySnippet: bodySnippet(text),
          protocolIssue: "invalid_json"
        }, true);
      }
      if (!isJSONObject(parsed)) {
        throw new DriverFailure({
          source: "protocol",
          code: "protocol_error",
          message: "HTTP response JSON was not an object envelope",
          action: request.action,
          protocolIssue: "invalid_envelope"
        }, true);
      }
      return { httpStatus: response.status, envelope: parsed };
    } catch (error) {
      if (error instanceof DriverFailure) throw error;
      const phase: TransportPhase = timedOut
        ? "timeout"
        : externallyAborted
          ? "abort"
          : networkPhase(error, responseReceived);
      const driverError: DriverError = phase === "timeout"
        ? {
            source: "transport",
            code: "transport_timeout",
            message: `Request timed out after ${options.timeoutMs}ms`,
            action: request.action,
            baseURL: this.baseURL,
            timeoutMs: options.timeoutMs,
            transportPhase: phase
          }
        : {
            source: "transport",
            code: "transport_unavailable",
            message: phase === "abort" ? "Request was aborted" : errorMessage(error),
            action: request.action,
            baseURL: this.baseURL,
            timeoutMs: options.timeoutMs,
            transportPhase: phase
          };
      throw new DriverFailure(driverError, responseReceived);
    } finally {
      clearTimeout(timer);
      options.signal?.removeEventListener("abort", onExternalAbort);
    }
  }
}

function isJSONObject(value: unknown): value is JSONObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function networkPhase(error: unknown, responseReceived: boolean): TransportPhase {
  const code = errorCode(error);
  if (code === "ECONNRESET" || code === "EPIPE" || code === "UND_ERR_SOCKET") return "reset";
  if (code === "ECONNREFUSED" || code === "ENOTFOUND" || code === "EHOSTUNREACH" || code === "ENETUNREACH"
      || code === "ETIMEDOUT") {
    return "connect";
  }
  return error instanceof TypeError ? (responseReceived ? "reset" : "connect") : "unknown";
}

function errorCode(error: unknown): string | undefined {
  if (typeof error !== "object" || error === null) return undefined;
  const direct = (error as { code?: unknown }).code;
  if (typeof direct === "string") return direct;
  const cause = (error as { cause?: unknown }).cause;
  return typeof cause === "object" && cause !== null && typeof (cause as { code?: unknown }).code === "string"
    ? (cause as { code: string }).code
    : undefined;
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}
