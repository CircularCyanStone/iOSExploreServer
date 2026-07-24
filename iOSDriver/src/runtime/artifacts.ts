import type { JSONObject } from "../types.js";
import type { DriverError } from "./driverErrors.js";
import type { Artifact } from "./types.js";

const PNG_SIGNATURE = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
const STRICT_BASE64 = /^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/;

/** ArtifactDecoder 的成功结果。 */
export interface ArtifactDecodeSuccess {
  readonly ok: true;
  readonly data: JSONObject;
  readonly artifacts: readonly Artifact[];
}

/** ArtifactDecoder 的失败结果；data 已移除潜在的大块 image 字段。 */
export interface ArtifactDecodeFailure {
  readonly ok: false;
  readonly error: DriverError;
  readonly data: JSONObject;
  readonly artifacts: readonly Artifact[];
}

/** Artifact 解码结果。 */
export type ArtifactDecodeResult = ArtifactDecodeSuccess | ArtifactDecodeFailure;

/** 当前只负责把 `ui.screenshot` 的 PNG data 转为内部 image artifact。 */
export class ArtifactDecoder {
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
    if (action !== "ui.screenshot") return { ok: true, data, artifacts: [] };

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
