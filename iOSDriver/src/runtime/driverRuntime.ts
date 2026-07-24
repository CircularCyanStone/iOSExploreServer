import { DEVICE_ACTION_CONTRACTS, type DeviceActionContract } from "../generated/deviceActionContracts.js";
import type { JSONObject } from "../types.js";
import type { ActionTransport } from "./actionTransport.js";
import { ArtifactDecoder } from "./artifacts.js";
import { DriverFailure, type DriverError } from "./driverErrors.js";
import type { Artifact, InvocationResult } from "./types.js";

const ACTION_METADATA: ReadonlyMap<string, DeviceActionContract> = new Map(
  DEVICE_ACTION_CONTRACTS.map(contract => [contract.action, contract] as const)
);

/** DriverRuntime 的构造参数。 */
export interface DriverRuntimeOptions {
  readonly transport: ActionTransport;
  readonly configuredRequestTimeoutMs: number;
  readonly artifactDecoder?: ArtifactDecoder;
}

/** 单次 invoke 的调用参数。 */
export interface InvocationOptions {
  readonly signal?: AbortSignal;
}

/** 把 transport 返回值归一化为稳定 InvocationResult 的 Host runtime。 */
export class DriverRuntime {
  private readonly transport: ActionTransport;
  private readonly configuredRequestTimeoutMs: number;
  private readonly artifactDecoder: ArtifactDecoder;

  /**
   * 创建 runtime。
   *
   * @param options 可注入 transport、默认请求 timeout 和 artifact decoder。
   */
  constructor(options: DriverRuntimeOptions) {
    this.transport = options.transport;
    this.configuredRequestTimeoutMs = options.configuredRequestTimeoutMs;
    this.artifactDecoder = options.artifactDecoder ?? new ArtifactDecoder();
  }

  /**
   * 调用一个 App action。
   *
   * @param action action 名。
   * @param data action JSON data。
   * @param options 可选外部取消信号。
   * @returns 成功或预期失败的统一结果；仅未分类的编程错误会继续抛出。
   */
  async invoke(action: string, data: JSONObject = {}, options: InvocationOptions = {}): Promise<InvocationResult> {
    const startedAt = Date.now();
    const timeoutMs = requestTimeout(action, data, this.configuredRequestTimeoutMs);
    let attempts = 0;

    while (true) {
      attempts += 1;
      try {
        const response = await this.transport.execute({ action, data }, {
          timeoutMs,
          ...(options.signal === undefined ? {} : { signal: options.signal })
        });
        if (response.httpStatus < 200 || response.httpStatus >= 300) {
          return this.failure({
            source: "http",
            code: "http_error",
            message: `HTTP ${response.httpStatus}`,
            action,
            status: response.httpStatus
          }, startedAt, attempts);
        }
        return this.fromEnvelope(action, response.envelope, startedAt, attempts);
      } catch (error) {
        if (!(error instanceof DriverFailure)) throw error;
        if (this.shouldRetry(action, error, attempts)) continue;
        return this.failure(error.driverError, startedAt, attempts);
      }
    }
  }

  private fromEnvelope(
    action: string,
    envelope: JSONObject,
    startedAt: number,
    attempts: number
  ): InvocationResult {
    if (typeof envelope.code !== "string") {
      return this.failure(protocolError(action), startedAt, attempts);
    }

    if (envelope.code === "ok") {
      const data = envelope.data === undefined ? {} : objectValue(envelope.data);
      if (data === undefined) return this.failure(protocolError(action), startedAt, attempts);
      const decoded = this.artifactDecoder.decode(action, data);
      if (!decoded.ok) {
        return this.failure(decoded.error, startedAt, attempts, decoded.data, decoded.artifacts);
      }
      return {
        ok: true,
        data: decoded.data,
        artifacts: decoded.artifacts,
        elapsedMs: Date.now() - startedAt,
        attempts
      };
    }

    if (typeof envelope.message !== "string") {
      return this.failure(protocolError(action), startedAt, attempts);
    }
    const responseData = envelope.data === undefined ? undefined : objectValue(envelope.data);
    if (envelope.data !== undefined && responseData === undefined) {
      return this.failure(protocolError(action), startedAt, attempts);
    }
    const decoded = responseData === undefined
      ? { ok: true as const, data: undefined, artifacts: [] as readonly Artifact[] }
      : this.artifactDecoder.decode(action, responseData);
    if (!decoded.ok) {
      return this.failure(decoded.error, startedAt, attempts, decoded.data, decoded.artifacts);
    }
    return this.failure({
      source: "appEnvelope",
      code: envelope.code,
      message: envelope.message,
      action,
      ...(decoded.data === undefined ? {} : { data: decoded.data })
    }, startedAt, attempts, decoded.data, decoded.artifacts);
  }

  private shouldRetry(action: string, failure: DriverFailure, attempts: number): boolean {
    if (attempts >= 2 || failure.responseReceived) return false;
    const metadata = ACTION_METADATA.get(action);
    const idempotency: string | undefined = metadata?.idempotency;
    if (idempotency !== "readOnly" && idempotency !== "idempotent") {
      return false;
    }
    return failure.driverError.source === "transport"
      && (failure.driverError.transportPhase === "connect" || failure.driverError.transportPhase === "reset");
  }

  private failure(
    error: DriverError,
    startedAt: number,
    attempts: number,
    data?: JSONObject,
    artifacts?: readonly Artifact[]
  ): InvocationResult {
    return {
      ok: false,
      error,
      ...(data === undefined ? {} : { data }),
      ...(artifacts === undefined ? {} : { artifacts }),
      elapsedMs: Date.now() - startedAt,
      attempts
    };
  }
}

function requestTimeout(action: string, data: JSONObject, configuredRequestTimeoutMs: number): number {
  if (ACTION_METADATA.get(action)?.timeoutClass !== "wait") return configuredRequestTimeoutMs;
  const businessTimeoutMs = typeof data.timeoutMs === "number" ? data.timeoutMs : 0;
  return Math.max(configuredRequestTimeoutMs, businessTimeoutMs + 5000);
}

function objectValue(value: unknown): JSONObject | undefined {
  return typeof value === "object" && value !== null && !Array.isArray(value) ? value as JSONObject : undefined;
}

function protocolError(action: string): DriverError {
  return {
    source: "protocol",
    code: "protocol_error",
    message: "App response did not match the action envelope protocol",
    action,
    protocolIssue: "invalid_envelope"
  };
}
