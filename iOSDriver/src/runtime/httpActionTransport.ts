/**
 * 固定 `POST /` action 协议的 HTTP 实现。
 *
 * 本层只保证请求可达、响应体不超过上限且 JSON 顶层为对象；`code/data/message` 由
 * `DriverRuntime` 解释。所有可预期网络/HTTP/协议失败都转为 `DriverFailure`，并携带
 * `responseReceived` 供 runtime 判断是否可能安全重试。
 */
import type { JSONObject } from "../types.js";
import type { ActionTransport, ActionTransportResponse } from "./actionTransport.js";
import { DriverFailure, type DriverError, type TransportPhase } from "./driverErrors.js";

/** 可注入的 fetch 边界，测试无需建立真实网络连接。 */
export type FetchLike = (input: string | URL | Request, init?: RequestInit) => Promise<Response>;

/** HTTP transport 构造选项。 */
export interface HttpActionTransportOptions {
  /** 注入 fetch 后测试无需绑定端口，也能覆盖 abort 和非法响应。 */
  readonly fetchImpl?: FetchLike;
  /** 预留的请求 token；当前 App 产品开关关闭，会忽略对应 header。 */
  readonly authToken?: string;
  /** App 原始 JSON response body 上限，默认 8 MiB。 */
  readonly maxResponseBodyBytes?: number;
}

const DEFAULT_MAX_RESPONSE_BODY_BYTES = 8 * 1024 * 1024;

/** 使用 `POST /` JSON 协议访问 App 的唯一 HTTP transport 实现。 */
export class HttpActionTransport implements ActionTransport {
  /** 保存已绑定的 fetch，避免调用时丢失 globalThis 上下文。 */
  private readonly fetchImpl: FetchLike;
  /** 构造时去除空白；为空则不发送 header。 */
  private readonly authToken: string | undefined;
  /** 同时约束 Content-Length 快速路径和流式累计字节数。 */
  private readonly maxResponseBodyBytes: number;

  /**
   * 创建 HTTP transport。
   *
   * @param baseURL App HTTP action 端点。
   * @param fetchOrOptions 可选 fetch 实现（兼容旧构造方式），或 response body 限制选项。
   */
  constructor(
    private readonly baseURL: string,
    fetchOrOptions: FetchLike | HttpActionTransportOptions = {}
  ) {
    const options = typeof fetchOrOptions === "function" ? { fetchImpl: fetchOrOptions } : fetchOrOptions;
    this.fetchImpl = options.fetchImpl ?? globalThis.fetch.bind(globalThis);
    this.authToken = normalizedAuthToken(options.authToken);
    this.maxResponseBodyBytes = options.maxResponseBodyBytes ?? DEFAULT_MAX_RESPONSE_BODY_BYTES;
    if (!Number.isSafeInteger(this.maxResponseBodyBytes) || this.maxResponseBodyBytes <= 0) {
      throw new RangeError("maxResponseBodyBytes must be a positive safe integer");
    }
  }

  /**
   * 发送请求、在固定字节上限内流式读取 body，并解析 JSON 对象。
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
    // 内部 controller 合并外部取消与本次请求 timer，同时用两个标志保留真实取消原因。
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
      const headers: Record<string, string> = { "Content-Type": "application/json" };
      if (this.authToken !== undefined) headers["X-Auth-Token"] = this.authToken;
      const response = await this.fetchImpl(this.baseURL, {
        method: "POST",
        headers,
        body: JSON.stringify(request),
        signal: controller.signal
      });
      responseReceived = true;
      // 在 JSON.parse 前限制原始 UTF-8 body，避免恶意或异常 App 响应造成无界内存占用。
      const text = await readResponseText(response, this.maxResponseBodyBytes, request.action);

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
      // fetch 在不同 Node/undici 版本下错误类型不同，因此同时结合 abort 标志、错误码
      // 和是否已收到 response 来归一化阶段。
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
      // 无论成功、分类失败还是未知异常，都解除 timer/listener，避免长生命周期 MCP 泄漏。
      clearTimeout(timer);
      options.signal?.removeEventListener("abort", onExternalAbort);
    }
  }
}

function normalizedAuthToken(value: string | undefined): string | undefined {
  const token = value?.trim();
  return token === undefined || token.length === 0 ? undefined : token;
}

/**
 * 在固定字节预算内读取响应。
 *
 * 可信 Content-Length 可提前拒绝；缺失或伪造长度时仍逐 chunk 累计。流被拒绝后主动
 * cancel，并让原始的 `response_too_large` 保持为最终错误。
 */
async function readResponseText(response: Response, maxBytes: number, action: string): Promise<string> {
  const declaredBytes = contentLength(response.headers.get("content-length"));
  if (declaredBytes !== undefined && declaredBytes > maxBytes) {
    await cancelQuietly(response.body);
    throw responseTooLarge(action, maxBytes);
  }

  if (response.body == null) {
    const text = await response.text();
    if (Buffer.byteLength(text, "utf8") > maxBytes) throw responseTooLarge(action, maxBytes);
    return text;
  }

  const reader = response.body.getReader();
  const chunks: Uint8Array[] = [];
  let bytes = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      bytes += value.byteLength;
      if (bytes > maxBytes) {
        await cancelReaderQuietly(reader);
        throw responseTooLarge(action, maxBytes);
      }
      chunks.push(value);
    }
  } finally {
    releaseReaderQuietly(reader);
  }
  return Buffer.concat(chunks.map(chunk => Buffer.from(chunk)), bytes).toString("utf8");
}

function contentLength(raw: string | null): number | undefined {
  if (raw === null || !/^\d+$/.test(raw.trim())) return undefined;
  const value = Number(raw);
  return Number.isFinite(value) ? value : Number.POSITIVE_INFINITY;
}

function responseTooLarge(action: string, maxBytes: number): DriverFailure {
  return new DriverFailure({
    source: "protocol",
    code: "protocol_error",
    message: `HTTP response body exceeded ${maxBytes} bytes`,
    action,
    protocolIssue: "response_too_large"
  }, true);
}

async function cancelQuietly(body: ReadableStream<Uint8Array> | null): Promise<void> {
  if (body === null) return;
  try { await body.cancel(); } catch { /* 保留已分类的响应体超限错误。 */ }
}

async function cancelReaderQuietly(reader: ReadableStreamDefaultReader<Uint8Array>): Promise<void> {
  try { await reader.cancel(); } catch { /* 保留已分类的响应体超限错误。 */ }
}

function releaseReaderQuietly(reader: ReadableStreamDefaultReader<Uint8Array>): void {
  try { reader.releaseLock(); } catch { /* 清理失败不能覆盖正文读取失败。 */ }
}

function isJSONObject(value: unknown): value is JSONObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/** 将 Node、undici 和浏览器风格 fetch 错误压缩为 runtime 需要的有限阶段集合。 */
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

/** 限制 HTTP/JSON 诊断正文，避免意外把大型 App 页面或 payload 写入错误输出。 */
function bodySnippet(body: string): string {
  return body.length > 500 ? `${body.slice(0, 500)}...` : body;
}
