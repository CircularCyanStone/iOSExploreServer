import type { MCPServerConfig } from "./config.js";
import { IOSExploreStructuredError, type StructuredError } from "./errors.js";
import { DriverRuntime } from "./runtime/driverRuntime.js";
import type { DriverError } from "./runtime/driverErrors.js";
import { HttpActionTransport } from "./runtime/httpActionTransport.js";
import type { Artifact } from "./runtime/types.js";
import type { JSONObject } from "./types.js";

/**
 * @deprecated 请直接使用 `DriverRuntime.invoke`；本类只为现有调用方保留旧 `call` 行为。
 */
export class IOSExploreClient {
  private readonly runtime: DriverRuntime;

  /**
   * 创建兼容客户端。
   *
   * @param config 现有 MCP server 的 baseURL 与请求 timeout 配置。
   */
  constructor(private readonly config: MCPServerConfig) {
    this.runtime = new DriverRuntime({
      transport: new HttpActionTransport(config.baseURL),
      configuredRequestTimeoutMs: config.requestTimeoutMs
    });
  }

  /**
   * 使用旧接口调用 action。
   *
   * @param action action 名。
   * @param data action JSON data。
   * @returns 旧接口所需的 JSONObject；截图 artifact 会还原为原 base64 字段。
   * @throws `IOSExploreStructuredError`，保持现有调用方的错误处理语义。
   */
  async call(action: string, data: JSONObject = {}): Promise<JSONObject> {
    const result = await this.runtime.invoke(action, data);
    if (!result.ok) throw new IOSExploreStructuredError(legacyError(result.error, this.config.baseURL));
    return restoreLegacyArtifacts(result.data, result.artifacts);
  }
}

function restoreLegacyArtifacts(data: JSONObject, artifacts: readonly Artifact[]): JSONObject {
  const image = artifacts.find(artifact => artifact.kind === "image" && artifact.mimeType === "image/png");
  return image === undefined ? data : { ...data, image: Buffer.from(image.data).toString("base64") };
}

function legacyError(error: DriverError, baseURL: string): StructuredError {
  if (error.source === "appEnvelope") {
    return {
      source: "ios_envelope",
      code: error.code,
      message: error.message,
      ...(error.action === undefined ? {} : { action: error.action }),
      ...(error.data === undefined ? {} : { data: error.data })
    };
  }
  if (error.source === "http") {
    return {
      source: "http",
      message: error.message,
      ...(error.action === undefined ? {} : { action: error.action }),
      ...(error.status === undefined ? {} : { status: error.status }),
      ...(error.bodySnippet === undefined ? {} : { bodySnippet: error.bodySnippet })
    };
  }
  if (error.source === "protocol") {
    return {
      source: "http",
      code: error.protocolIssue === "invalid_json" ? "invalid_json" : "protocol_error",
      message: error.message,
      ...(error.action === undefined ? {} : { action: error.action }),
      ...(error.bodySnippet === undefined ? {} : { bodySnippet: error.bodySnippet })
    };
  }
  if (error.source === "transport") {
    return {
      source: "transport",
      code: error.code === "transport_timeout" ? "request_timeout" : "connection_failed",
      message: error.message,
      ...(error.action === undefined ? {} : { action: error.action }),
      baseURL: error.baseURL ?? baseURL,
      ...(error.timeoutMs === undefined ? {} : { timeoutMs: error.timeoutMs })
    };
  }
  return {
    source: "ios_envelope",
    code: error.code,
    message: error.message,
    ...(error.action === undefined ? {} : { action: error.action }),
    ...(error.data === undefined ? {} : { data: error.data })
  };
}
