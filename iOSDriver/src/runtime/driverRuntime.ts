/**
 * iOSDriver 的协议解释层。
 *
 * transport 只负责 HTTP 和 JSON 对象，本模块再解释统一 envelope、选择超时与重试策略、
 * 解码 artifact，并把所有预期失败转换为 `InvocationResult`。adapter 因此不需要理解网络
 * 异常或 App envelope 的细节。
 */
import { DEVICE_ACTION_CONTRACTS, type DeviceActionContract } from "../generated/deviceActionContracts.js";
import type { JSONObject } from "../types.js";
import type { ActionTransport } from "./actionTransport.js";
import { ArtifactDecoder } from "./artifacts.js";
import { DriverFailure, type DriverError } from "./driverErrors.js";
import { noopHostLogger, type HostLogger } from "./hostLogger.js";
import type { Artifact, InvocationResult } from "./types.js";

const ACTION_METADATA: ReadonlyMap<string, DeviceActionContract> = new Map(
  DEVICE_ACTION_CONTRACTS.map(contract => [contract.action, contract] as const)
);

/** DriverRuntime 的构造参数。 */
export interface DriverRuntimeOptions {
  /** 唯一网络边界，可替换为测试 transport。 */
  readonly transport: ActionTransport;
  /** standard/screenshot action 的 transport 超时基线。 */
  readonly configuredRequestTimeoutMs: number;
  /** 负责从 envelope data 剥离并验证二进制字段。 */
  readonly artifactDecoder?: ArtifactDecoder;
  /** Host 命令链 logger；CLI/MCP 入口注入共享 stderr logger。 */
  readonly logger?: HostLogger;
}

/** 单次 invoke 的调用参数。 */
export interface InvocationOptions {
  /** 外部取消只终止当前调用，不改变 runtime 实例状态。 */
  readonly signal?: AbortSignal;
  /** 仅供已严格验证的 help metadata 覆盖未知 action 的保守默认策略。 */
  readonly policy?: InvocationPolicy;
}

/** 单次 action 的 timeout 与重试安全属性。 */
export interface InvocationPolicy {
  /** readOnly/idempotent 才允许 runtime 对安全 transport 阶段自动重试。 */
  readonly idempotency: "readOnly" | "idempotent" | "sideEffecting";
  /** timeoutClass 决定是否为业务等待 timeout 预留 transport 余量。 */
  readonly timeoutClass: "standard" | "wait" | "screenshot";
}

/** 把 transport 返回值归一化为稳定 InvocationResult 的 Host runtime。 */
export class DriverRuntime {
  /** 不解释业务字段的可注入传输实现。 */
  private readonly transport: ActionTransport;
  /** 配置解析完成后固定，避免同一调用的多次尝试使用不同超时。 */
  private readonly configuredRequestTimeoutMs: number;
  /** 所有成功/失败 envelope 都经过同一附件大小和格式检查。 */
  private readonly artifactDecoder: ArtifactDecoder;
  /** 默认无输出；生产入口显式注入 stderr logger。 */
  private readonly logger: HostLogger;

  /**
   * 创建 runtime。
   *
   * @param options 可注入 transport、默认请求 timeout 和 artifact decoder。
   */
  constructor(options: DriverRuntimeOptions) {
    this.transport = options.transport;
    this.configuredRequestTimeoutMs = options.configuredRequestTimeoutMs;
    this.artifactDecoder = options.artifactDecoder ?? new ArtifactDecoder();
    this.logger = options.logger ?? noopHostLogger;
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
    const policy = invocationPolicy(action, options.policy);
    const timeoutMs = requestTimeout(policy, data, this.configuredRequestTimeoutMs);
    let attempts = 0;
    this.logger.emit("info", "runtime.invoke.start", {
      action,
      timeoutMs,
      idempotency: policy?.idempotency ?? "unknown",
      timeoutClass: policy?.timeoutClass ?? "unknown"
    });

    // 循环最多执行两次；是否进入第二次由 shouldRetry 的幂等性和传输阶段共同决定。
    while (true) {
      attempts += 1;
      try {
        const response = await this.transport.execute({ action, data }, {
          timeoutMs,
          ...(options.signal === undefined ? {} : { signal: options.signal })
        });
        // 自定义 transport 可能直接返回非 2xx；HTTP 实现通常会先抛 DriverFailure。
        if (response.httpStatus < 200 || response.httpStatus >= 300) {
          return this.finish(action, this.failure({
            source: "http",
            code: "http_error",
            message: `HTTP ${response.httpStatus}`,
            action,
            status: response.httpStatus
          }, startedAt, attempts));
        }
        return this.finish(action, this.fromEnvelope(action, response.envelope, startedAt, attempts));
      } catch (error) {
        if (!(error instanceof DriverFailure)) {
          this.logger.emit("error", "runtime.invoke.throw", {
            action,
            attempts,
            elapsedMs: Date.now() - startedAt,
            errorType: errorType(error)
          });
          throw error;
        }
        if (this.shouldRetry(policy, error, attempts)) {
          this.logger.emit("warn", "runtime.invoke.retry", {
            action,
            attempts,
            nextAttempt: attempts + 1,
            elapsedMs: Date.now() - startedAt,
            ...errorFields(error.driverError)
          });
          continue;
        }
        return this.finish(action, this.failure(error.driverError, startedAt, attempts));
      }
    }
  }

  /**
   * 将 App wire envelope 投影为 runtime 结果。
   *
   * `code`、`message`、`data` 的结构错误统一归为 protocol；业务失败仍可携带清理后的
   * data/artifact，使 workflow 和 adapter 在报告终态错误时保留已经获得的上下文。
   */
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
    // 即使保留 App 的业务错误，artifact decoder 的清理结果也必须生效，
    // 避免非法或超限 image 经 error.data/result.data 旁路输出。
    const failureData = decoded.data;
    const artifacts = decoded.artifacts;
    return this.failure({
      source: "appEnvelope",
      code: envelope.code,
      message: envelope.message,
      action,
      ...(failureData === undefined ? {} : { data: failureData })
    }, startedAt, attempts, failureData, artifacts);
  }

  /**
   * 判断一次失败是否能自动重放。
   *
   * 只有尚未收到任何 HTTP response 的 connect/reset，且合同声明 action 为只读或幂等时
   * 才允许第二次请求。sideEffecting、未知策略、timeout、abort 和所有 response 后失败
   * 都不会重试，避免重复触发 UI 操作。
   */
  private shouldRetry(policy: InvocationPolicy | undefined, failure: DriverFailure, attempts: number): boolean {
    if (attempts >= 2 || failure.responseReceived) return false;
    const idempotency = policy?.idempotency;
    if (idempotency !== "readOnly" && idempotency !== "idempotent") {
      return false;
    }
    return failure.driverError.source === "transport"
      && (failure.driverError.transportPhase === "connect" || failure.driverError.transportPhase === "reset");
  }

  /** 统一补齐失败耗时与尝试次数，并按实际存在情况保留 data/artifact。 */
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

  /** 在返回 adapter 前记录不含 payload 的终态摘要。 */
  private finish(action: string, result: InvocationResult): InvocationResult {
    if (result.ok) {
      this.logger.emit("info", "runtime.invoke.success", {
        action,
        attempts: result.attempts,
        elapsedMs: result.elapsedMs,
        artifactCount: result.artifacts.length
      });
    } else {
      this.logger.emit("warn", "runtime.invoke.failure", {
        action,
        attempts: result.attempts,
        elapsedMs: result.elapsedMs,
        artifactCount: result.artifacts?.length ?? 0,
        ...errorFields(result.error)
      });
    }
    return result;
  }
}

/** wait action 的业务 timeout 之外预留 5 秒，让 App 有时间编码并传回终态 envelope。 */
function requestTimeout(policy: InvocationPolicy | undefined, data: JSONObject, configuredRequestTimeoutMs: number): number {
  if (policy?.timeoutClass !== "wait") return configuredRequestTimeoutMs;
  const businessTimeoutMs = typeof data.timeoutMs === "number" ? data.timeoutMs : 0;
  return Math.max(configuredRequestTimeoutMs, businessTimeoutMs + 5000);
}

/** canonical 合同永远优先；per-call 策略只服务于通过 help 校验的扩展 action。 */
function invocationPolicy(action: string, perCallPolicy: InvocationPolicy | undefined): InvocationPolicy | undefined {
  const generated = ACTION_METADATA.get(action);
  if (generated !== undefined) {
    return { idempotency: generated.idempotency, timeoutClass: generated.timeoutClass };
  }
  return isInvocationPolicy(perCallPolicy) ? perCallPolicy : undefined;
}

function isInvocationPolicy(value: InvocationPolicy | undefined): value is InvocationPolicy {
  return value !== undefined
    && (value.idempotency === "readOnly" || value.idempotency === "idempotent" || value.idempotency === "sideEffecting")
    && (value.timeoutClass === "standard" || value.timeoutClass === "wait" || value.timeoutClass === "screenshot");
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

function errorFields(error: DriverError): Record<string, string | number | undefined> {
  return {
    source: error.source,
    code: error.code,
    status: error.status,
    timeoutMs: error.timeoutMs,
    transportPhase: error.transportPhase,
    protocolIssue: error.protocolIssue
  };
}

function errorType(error: unknown): string {
  return error instanceof Error ? error.name : typeof error;
}
