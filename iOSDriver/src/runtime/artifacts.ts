/**
 * App 响应附件的解码与安全清理。
 *
 * 当前 wire 协议把截图作为 base64 放在 `data.image` 字段中。本模块在返回 adapter
 * 之前做四件事：验证编码规范（strict/canonical base64）、解码后字节数上限、PNG 签名、
 * 尺寸字段，并**从普通 data 中移除原始 image**——避免 CLI JSON、MCP text content 或
 * 错误分支再次携带大块 base64（防止大 payload 旁路泄漏到输出）。
 */
import type { JSONObject } from "../types.js";
import type { DriverError } from "./driverErrors.js";
import type { Artifact } from "./types.js";

/** PNG 文件头魔数（8 字节），用于验证解码结果确实是 PNG。 */
const PNG_SIGNATURE = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
/** 严格 base64 正则：4 字符一组，结尾只能是 0/1/2 个填充符。 */
const STRICT_BASE64 = /^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/;

/** `ArtifactDecoder.decode` 的成功结果。 */
export interface ArtifactDecodeSuccess {
  readonly ok: true;
  /** 已移除 wire 二进制字段的业务数据（可安全进入 CLI/MCP JSON 输出）。 */
  readonly data: JSONObject;
  /** 通过大小、编码、签名检查的附件集合（当前最多一个 image）。 */
  readonly artifacts: readonly Artifact[];
}

/** `ArtifactDecoder.decode` 的失败结果；data 已移除潜在的大块 image 字段。 */
export interface ArtifactDecodeFailure {
  readonly ok: false;
  /** 固定为 artifact source（调用方无需解析 message 即可判断类别）。 */
  readonly error: DriverError;
  /** 即使失败也已移除潜在大块 image 原文（防旁路）。 */
  readonly data: JSONObject;
  /** 当前实现解码失败时为空数组（保留字段是为了稳定联合类型）。 */
  readonly artifacts: readonly Artifact[];
}

/** Artifact 解码结果（成功/失败的判别联合）。 */
export type ArtifactDecodeResult = ArtifactDecodeSuccess | ArtifactDecodeFailure;

/**
 * 当前只负责把 `ui.screenshot` 的 PNG data 转为内部 image artifact。
 * 其他 action 的 data 原样透传（不解码、不剥离）。
 */
export class ArtifactDecoder {
  /** 解码后字节数上限；先按 base64 长度预判再实际解码，避免无谓分配。 */
  private readonly maxDecodedBytes: number;

  /**
   * 创建 artifact decoder。
   *
   * @param options decoded 二进制上限（默认 8 MiB）。
   */
  constructor(options: { maxDecodedBytes?: number } = {}) {
    this.maxDecodedBytes = options.maxDecodedBytes ?? 8 * 1024 * 1024;
  }

  /**
   * 解码 action data 中的二进制 artifact，返回清理后的 data 与附件。
   *
   * 校验顺序：action 必须是 ui.screenshot → 解构移除 image 字段 → 检查 image 为字符串
   * → format==="png" → mimeType（如有）为 image/png → 宽高为正整数 → strict base64
   * → 预判解码字节数不超限 → Buffer 解码 + canonical round-trip → PNG 签名。
   *
   * @param action 当前 App action 名。
   * @param data App envelope data（可能含 image 字段）。
   * @returns 清理后的业务 data + 附件；任一校验失败返回 `artifact_decode_failed`
   *   错误（data 已剥离 image）。
   */
  decode(action: string, data: JSONObject): ArtifactDecodeResult {
    // 只有合同声明返回 image 的 screenshot 使用当前 wire 约定，其他 action 原样透传。
    if (action !== "ui.screenshot") return { ok: true, data, artifacts: [] };

    // 先解构移除 image；此后任何失败结果都只会携带安全的 metadata。
    const { image: rawImage, ...metadata } = data;
    if (typeof rawImage !== "string") return this.failure(action, metadata, "Screenshot image is missing");
    if (data.format !== "png") return this.failure(action, metadata, "Screenshot format is not PNG");
    if (data.mimeType !== undefined && data.mimeType !== "image/png") {
      return this.failure(action, metadata, "Screenshot MIME type is not image/png");
    }
    if (!validDimension(data.width) || !validDimension(data.height)) {
      return this.failure(action, metadata, "Screenshot dimensions are invalid");
    }
    if (rawImage.length === 0 || rawImage.length % 4 !== 0 || !STRICT_BASE64.test(rawImage)) {
      return this.failure(action, metadata, "Screenshot image is not strict base64");
    }
    const paddingBytes = rawImage.endsWith("==") ? 2 : rawImage.endsWith("=") ? 1 : 0;
    const decodedBytes = rawImage.length / 4 * 3 - paddingBytes;
    if (decodedBytes > this.maxDecodedBytes) {
      return this.failure(action, metadata, "Screenshot exceeds decoded byte limit");
    }

    const decoded = Buffer.from(rawImage, "base64");
    // Node 的 base64 decoder 会宽松接受部分非规范输入，round-trip 检查补上 canonical 约束。
    if (decoded.toString("base64") !== rawImage) {
      return this.failure(action, metadata, "Screenshot image is not canonical base64");
    }
    if (decoded.length < PNG_SIGNATURE.length || !decoded.subarray(0, PNG_SIGNATURE.length).equals(PNG_SIGNATURE)) {
      return this.failure(action, metadata, "Screenshot has an invalid PNG signature");
    }

    return {
      ok: true,
      data: metadata,
      artifacts: [{ kind: "image", mimeType: "image/png", data: decoded, metadata: { ...metadata } }]
    };
  }

  /**
   * 构造不携带原始 image 的稳定失败（防止错误路径绕过大小限制旁路输出）。
   *
   * @param action action 名（进错误信息）。
   * @param data 已剥离 image 的 metadata。
   * @param message 失败原因。
   * @returns `ArtifactDecodeFailure`（source=artifact，code=artifact_decode_failed）。
   */
  private failure(action: string, data: JSONObject, message: string): ArtifactDecodeFailure {
    return {
      ok: false,
      error: { source: "artifact", code: "artifact_decode_failed", message, action },
      data,
      artifacts: []
    };
  }
}

/**
 * 校验截图尺寸字段：undefined（App 未提供）或正整数都合法。
 *
 * @param value 未知值。
 * @returns true=undefined 或正整数。
 */
function validDimension(value: unknown): boolean {
  return value === undefined || (typeof value === "number" && Number.isFinite(value) && Number.isInteger(value) && value > 0);
}
