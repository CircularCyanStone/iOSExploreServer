/**
 * 固定 `POST /` action 协议的 HTTP 实现（整个 host 的唯一真实网络出口）。
 *
 * 职责边界（本层只保证三件事）：
 * 1. 请求确实发出去了（fetch 成功）；
 * 2. 响应体不超过 8 MiB 上限（防止恶意/异常 App 响应把进程内存打爆）；
 * 3. 响应 JSON 顶层是对象。
 *
 * `code/data/message` 的**含义**不在这里解释——那是 `DriverRuntime` 的事。
 * 所有可预期的网络/HTTP/协议失败都转为 `DriverFailure` 抛出，并携带
 * `responseReceived` 标志，供 runtime 判断是否可能安全重试。
 *
 * 典型调用：`transport.execute({action:"ping",data:{}}, {timeoutMs:10000})`
 * → `{ httpStatus:200, envelope:{code:"ok",data:{pong:true}} }`（envelope 未解释）。
 */
import type { JSONObject } from "../types.js";
import type { ActionTransport, ActionTransportResponse } from "./actionTransport.js";
import { DriverFailure, type DriverError, type TransportPhase } from "./driverErrors.js";

/**
 * 可注入的 fetch 函数类型（与全局 fetch 签名一致）。
 * 测试注入 fake 后无需绑定端口，也能覆盖超时、abort、非法响应等全部场景。
 */
export type FetchLike = (input: string | URL | Request, init?: RequestInit) => Promise<Response>;

/** HTTP transport 构造选项。 */
export interface HttpActionTransportOptions {
  /** 自定义 fetch 实现；不传则用 `globalThis.fetch`。 */
  readonly fetchImpl?: FetchLike;
  /** 预留的认证 token；当前 App 产品开关关闭、不校验，空白时完全不发送 header。 */
  readonly authToken?: string;
  /** App 原始 JSON 响应体上限（字节），默认 8 MiB。 */
  readonly maxResponseBodyBytes?: number;
}

/** 默认响应体上限：8 MiB（`8 * 1024 * 1024` 字节）。 */
const DEFAULT_MAX_RESPONSE_BODY_BYTES = 8 * 1024 * 1024;

/**
 * 使用 `POST /` JSON 协议访问 App 的唯一 HTTP transport 实现。
 * 实现 `ActionTransport` 接口；构造完成后所有行为由三个私有成员决定。
 */
export class HttpActionTransport implements ActionTransport {
  /** 已绑定 this 的 fetch（`bind(globalThis)` 防止某些实现丢失上下文）。 */
  private readonly fetchImpl: FetchLike;
  /** 构造时已 trim 的 token；空值表示不发送认证 header。 */
  private readonly authToken: string | undefined;
  /** 响应体字节上限；同时约束 Content-Length 快速路径与流式累计路径。 */
  private readonly maxResponseBodyBytes: number;

  /**
   * 创建 HTTP transport。
   *
   * @param baseURL App HTTP action 端点（已由 config 层规范化，含尾斜杠）。
   * @param fetchOrOptions 可选 fetch 实现（兼容旧构造方式），或响应体限制等选项。
   * @throws {RangeError} maxResponseBodyBytes 不是正整数时抛出（构造期尽早暴露配置错误）。
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
   * 发送请求 → 在字节上限内流式读取响应体 → 校验 JSON 形状，返回未解释的 envelope。
   *
   * 失败分类（全部以 `DriverFailure` 抛出）：
   * - 非 2xx 状态 → `source:"http"`，code "http_error"；
   * - JSON 解析失败 → `source:"protocol"`，protocolIssue "invalid_json"；
   * - 顶层不是对象 → `source:"protocol"`，protocolIssue "invalid_envelope"；
   * - 超时/取消/网络错误 → `source:"transport"`（phase 区分 timeout/abort/connect/reset）。
   *
   * @param request action 名与 JSON data。
   * @param options 单次请求超时（毫秒）与外部取消信号。
   * @returns HTTP 状态码与未解释的 envelope 对象。
   *   示例：App 正常响应 → `{ httpStatus:200, envelope:{code:"ok",...} }`。
   * @throws {DriverFailure} 上述全部预期失败；未知异常原样抛出。
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

/**
 * 规范化 token：trim 后为空串等价于未配置。
 *
 * @param value 原始 token 字符串。
 * @returns 非空 token；undefined/空白串返回 undefined（不发送认证 header）。
 */
function normalizedAuthToken(value: string | undefined): string | undefined {
  const token = value?.trim();
  return token === undefined || token.length === 0 ? undefined : token;
}

/**
 * 在固定字节预算内读取响应体并返回 UTF-8 文本。
 *
 * 两层防护：可信的 Content-Length 头可**提前拒绝**（还没开始读流）；长度缺失或伪造时
 * 逐 chunk 累计字节数，超限立即 cancel 流并抛错——绝不把超限内容全部读进内存。
 * 清理失败（cancel/releaseLock 抛错）会被静默吞掉，保证原始 `response_too_large`
 * 错误不被覆盖。
 *
 * @param response fetch 响应对象。
 * @param maxBytes 字节上限。
 * @param action action 名（仅用于错误信息）。
 * @returns 响应体 UTF-8 文本。
 * @throws {DriverFailure} 响应体超过上限时抛出（protocolIssue "response_too_large"）。
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

/**
 * 解析 Content-Length 响应头：只认纯数字，否则视为不可信。
 *
 * @param raw 响应头原始值（可能为 null）。
 * @returns 数字字节数；不可信（缺失/非纯数字）返回 undefined，
 *   极端大数返回 Infinity（必然触发超限检查）。
 */
function contentLength(raw: string | null): number | undefined {
  if (raw === null || !/^\d+$/.test(raw.trim())) return undefined;
  const value = Number(raw);
  return Number.isFinite(value) ? value : Number.POSITIVE_INFINITY;
}

/**
 * 构造「响应体超限」的协议错误。
 *
 * @param action action 名。
 * @param maxBytes 上限字节数。
 * @returns 已分类的 DriverFailure（source=protocol，responseReceived=true）。
 */
function responseTooLarge(action: string, maxBytes: number): DriverFailure {
  return new DriverFailure({
    source: "protocol",
    code: "protocol_error",
    message: `HTTP response body exceeded ${maxBytes} bytes`,
    action,
    protocolIssue: "response_too_large"
  }, true);
}

/** 静默 cancel 响应体流（清理失败不覆盖原始错误）。 */
async function cancelQuietly(body: ReadableStream<Uint8Array> | null): Promise<void> {
  if (body === null) return;
  try { await body.cancel(); } catch { /* 保留已分类的响应体超限错误。 */ }
}

/** 静默 cancel 流 reader（清理失败不覆盖原始错误）。 */
async function cancelReaderQuietly(reader: ReadableStreamDefaultReader<Uint8Array>): Promise<void> {
  try { await reader.cancel(); } catch { /* 保留已分类的响应体超限错误。 */ }
}

/** 静默释放 reader 锁（清理失败不覆盖正文读取失败）。 */
function releaseReaderQuietly(reader: ReadableStreamDefaultReader<Uint8Array>): void {
  try { reader.releaseLock(); } catch { /* 清理失败不能覆盖正文读取失败。 */ }
}

/** 判断未知值是否为 JSON 对象（非 null、非数组的对象）。 */
function isJSONObject(value: unknown): value is JSONObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/**
 * 将 Node/undici/浏览器风格的 fetch 错误压缩为 runtime 需要的有限阶段集合。
 *
 * 映射规则：
 * - ECONNRESET/EPIPE/UND_ERR_SOCKET → "reset"（连接建立后被重置）；
 * - ECONNREFUSED/ENOTFOUND/EHOSTUNREACH/ENETUNREACH/ETIMEDOUT → "connect"
 *   （连接未建立，请求肯定没到 App，可安全重试）；
 * - 其他 TypeError → 按是否收到过 response 猜 reset/connect；其余 → "unknown"。
 *
 * @param error 未知的 fetch 异常。
 * @param responseReceived 是否已收到过 HTTP response（影响 TypeError 分支的猜测）。
 * @returns 有限阶段之一。
 */
function networkPhase(error: unknown, responseReceived: boolean): TransportPhase {
  const code = errorCode(error);
  if (code === "ECONNRESET" || code === "EPIPE" || code === "UND_ERR_SOCKET") return "reset";
  if (code === "ECONNREFUSED" || code === "ENOTFOUND" || code === "EHOSTUNREACH" || code === "ENETUNREACH"
      || code === "ETIMEDOUT") {
    return "connect";
  }
  return error instanceof TypeError ? (responseReceived ? "reset" : "connect") : "unknown";
}

/**
 * 从错误对象或其 cause 链中提取稳定的错误码（如 "ECONNREFUSED"）。
 *
 * @param error 未知异常。
 * @returns 字符串错误码；直接或 cause 嵌套均处理，找不到返回 undefined。
 */
function errorCode(error: unknown): string | undefined {
  if (typeof error !== "object" || error === null) return undefined;
  const direct = (error as { code?: unknown }).code;
  if (typeof direct === "string") return direct;
  const cause = (error as { cause?: unknown }).cause;
  return typeof cause === "object" && cause !== null && typeof (cause as { code?: unknown }).code === "string"
    ? (cause as { code: string }).code
    : undefined;
}

/** 安全提取错误消息（非 Error 类型不会崩溃）。 */
function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

/**
 * 截断诊断用的响应正文：超过 500 字符只保留开头。
 *
 * 避免意外把大型 App 页面或 payload 完整写进错误输出。
 *
 * @param body 响应正文。
 * @returns 截断后的片段（最长 503 字符）。
 */
function bodySnippet(body: string): string {
  return body.length > 500 ? `${body.slice(0, 500)}...` : body;
}
