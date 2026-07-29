import type { JSONObject } from "../types.js";
import type { DriverError } from "./driverErrors.js";

/** Runtime 产出的二进制或结构化附件，不依赖任何上层 adapter SDK。 */
export interface Artifact {
  /** 附件的逻辑类型，adapter 据此选择图片、文本或 JSON 输出。 */
  readonly kind: "image" | "text" | "json";
  /** 标准 MIME type，例如截图使用 `image/png`。 */
  readonly mimeType: string;
  /** 已完成校验和解码的原始字节。 */
  readonly data: Uint8Array;
  /** 从 App 响应中剥离二进制字段后保留的附件描述信息。 */
  readonly metadata: JSONObject;
}

/** action 成功时的稳定 runtime 返回值。 */
export interface InvocationSuccess {
  /** 判别联合标记；`true` 表示 action envelope 的 code 为 `ok`。 */
  readonly ok: true;
  /** 去除二进制 artifact 后的业务结果。 */
  readonly data: JSONObject;
  /** 从业务结果中安全解码出的附件；没有附件时为空数组。 */
  readonly artifacts: readonly Artifact[];
  /** 从首次尝试开始到获得终态结果的总耗时。 */
  readonly elapsedMs: number;
  /** 实际 transport 请求次数，包含一次可能的安全重试。 */
  readonly attempts: number;
}

/** action 预期失败时的稳定 runtime 返回值。 */
export interface InvocationFailure {
  /** 判别联合标记；`false` 表示调用以稳定错误结束。 */
  readonly ok: false;
  /** 已按 config/transport/http/protocol/app/workflow/artifact 分类的错误。 */
  readonly error: DriverError;
  /** 失败 envelope 或 workflow 已产生的结构化上下文。 */
  readonly data?: JSONObject;
  /** 失败前已经成功解码的附件。 */
  readonly artifacts?: readonly Artifact[];
  /** 从首次尝试开始到失败结束的总耗时。 */
  readonly elapsedMs: number;
  /** 实际 transport 请求次数；deadline 尚未发起请求时可为 0。 */
  readonly attempts: number;
}

/** DriverRuntime 的统一结果；业务失败通过值返回而不是抛异常。 */
export type InvocationResult = InvocationSuccess | InvocationFailure;
