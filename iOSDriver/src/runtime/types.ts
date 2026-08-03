import type { JSONObject } from "../types.js";
import type { DriverError } from "./driverErrors.js";

/**
 * Runtime 产出的二进制或结构化附件（如截图），不依赖任何上层 adapter SDK。
 */
export interface Artifact {
  /** 附件的逻辑类型；adapter 据此选择图片、文本或 JSON 输出方式。 */
  readonly kind: "image" | "text" | "json";
  /** 标准 MIME type；例如截图使用 "image/png"。 */
  readonly mimeType: string;
  /** 已完成校验和解码的原始字节（供落盘或 base64 编码）。 */
  readonly data: Uint8Array;
  /** 从 App 响应剥离二进制字段后保留的附件描述信息（如尺寸）。 */
  readonly metadata: JSONObject;
}

/**
 * action 成功时的稳定 runtime 返回值（`InvocationResult` 的判别分支之一）。
 *
 * 示例（call ping 成功）：
 *   { ok:true, data:{pong:true}, artifacts:[], elapsedMs:12, attempts:1 }
 */
export interface InvocationSuccess {
  /** 判别联合标记：固定 `true`，表示 action envelope 的 code 为 "ok"。 */
  readonly ok: true;
  /** 去除二进制 artifact 后的业务结果（App 响应的 data 字段）。 */
  readonly data: JSONObject;
  /** 从业务结果中安全解码出的附件；没有附件时为空数组。 */
  readonly artifacts: readonly Artifact[];
  /** 从首次尝试开始到获得终态结果的总耗时（毫秒）。 */
  readonly elapsedMs: number;
  /** 实际 transport 请求次数；包含一次可能的安全重试（通常为 1，重试后为 2）。 */
  readonly attempts: number;
}

/**
 * action 预期失败时的稳定 runtime 返回值（`InvocationResult` 的判别分支之一）。
 *
 * 业务失败通过「值返回」而不是「抛异常」传递——调用方用统一的 `result.ok`
 * 分支处理成功与失败，不需要 try/catch。
 */
export interface InvocationFailure {
  /** 判别联合标记：固定 `false`，表示调用以稳定错误结束。 */
  readonly ok: false;
  /** 已按 config/transport/http/protocol/appEnvelope/workflow/artifact 分类的错误。 */
  readonly error: DriverError;
  /** 失败 envelope 或 workflow 已产生的结构化上下文（尽力保留）。 */
  readonly data?: JSONObject;
  /** 失败前已经成功解码的附件。 */
  readonly artifacts?: readonly Artifact[];
  /** 从首次尝试开始到失败结束的总耗时（毫秒）。 */
  readonly elapsedMs: number;
  /** 实际 transport 请求次数；workflow 在 deadline 前未发请求时可为 0。 */
  readonly attempts: number;
}

/**
 * DriverRuntime 的统一调用结果：成功与失败合并为一个判别联合。
 * adapter（CLI/MCP/workflow）只消费这一种结构，永远不需要看 HTTP/网络细节。
 */
export type InvocationResult = InvocationSuccess | InvocationFailure;
