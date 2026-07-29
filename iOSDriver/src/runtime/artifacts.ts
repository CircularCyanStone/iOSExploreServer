/**
 * App 响应附件的解码与安全清理。
 *
 * 当前 wire 协议把截图作为 base64 放在 `data.image` 中。本模块在返回 adapter 前验证
 * 编码规范、解码后大小和 PNG 签名，并从普通 data 中移除原始 image，避免 CLI JSON、
 * MCP text content 或错误分支再次携带大块 base64。
 */
import type { JSONObject } from "../types.js";
import type { DriverError } from "./driverErrors.js";
import type { Artifact } from "./types.js";

const PNG_SIGNATURE = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
const STRICT_BASE64 = /^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/;

/** ArtifactDecoder 的成功结果。 */
export interface ArtifactDecodeSuccess {
  readonly ok: true;
  /** 已移除 wire 二进制字段，可安全进入 CLI/MCP JSON 输出。 */
  readonly data: JSONObject;
  /** 通过大小、编码和签名检查的附件集合。 */
  readonly artifacts: readonly Artifact[];
}

/** ArtifactDecoder 的失败结果；data 已移除潜在的大块 image 字段。 */
export interface ArtifactDecodeFailure {
  readonly ok: false;
  /** 固定为 artifact source，调用方无需解析 message 判断类别。 */
  readonly error: DriverError;
  /** 即使失败也已移除潜在大块 image 原文。 */
  readonly data: JSONObject;
  /** 当前实现解码失败时为空，保留字段是为了稳定联合类型。 */
  readonly artifacts: readonly Artifact[];
}

/** Artifact 解码结果。 */
export type ArtifactDecodeResult = ArtifactDecodeSuccess | ArtifactDecodeFailure;

/** 当前只负责把 `ui.screenshot` 的 PNG data 转为内部 image artifact。 */
export class ArtifactDecoder {
  /** 对解码后字节数设限；先根据 base64 长度预判，再执行 Buffer 解码。 */
  private readonly maxDecodedBytes: number;

  /**
   * 创建 artifact decoder。
   *
   * @param options decoded 二进制上限，默认 8 MiB。
   */
  constructor(options: { maxDecodedBytes?: number } = {}) {
    this.maxDecodedBytes = options.maxDecodedBytes ?? 8 * 1024 * 1024;
  }

  /**
   * 解码 action data 中的 artifact。
   *
   * @param action 当前 App action。
   * @param data App envelope data。
   * @returns 清理后的业务 data、artifact，或稳定的 `artifact_decode_failed`。
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

  /** 构造不携带原始 image 的稳定失败，防止错误路径绕过大小限制。 */
  private failure(action: string, data: JSONObject, message: string): ArtifactDecodeFailure {
    return {
      ok: false,
      error: { source: "artifact", code: "artifact_decode_failed", message, action },
      data,
      artifacts: []
    };
  }
}

function validDimension(value: unknown): boolean {
  return value === undefined || (typeof value === "number" && Number.isFinite(value) && Number.isInteger(value) && value > 0);
}
