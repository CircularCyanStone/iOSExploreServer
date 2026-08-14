/**
 * iOSDriver 的协议解释层（runtime 核心）。
 *
 * 分层位置：`HttpActionTransport` 只保证「请求发出、响应是 JSON 对象」；本模块负责
 * 解释统一 envelope（`code/data/message`）、按合同元数据选择超时与重试策略、解码
 * 二进制 artifact，并把所有预期失败转换为统一的 `InvocationResult`。
 *
 * 结果，adapter（CLI/MCP/workflow）只消费 `InvocationResult` 一种结构，永远不需要
 * 理解网络异常或 App envelope 细节。
 *
 * 典型调用（call ping 离线）：
 *   invoke("ping", {}, {}) → transport 抛 DriverFailure(connect) → 安全重试一次
 *   → 再次失败 → { ok:false, error:{source:"transport",...}, attempts:2 }
 */
import { DEVICE_ACTION_CONTRACTS, type DeviceActionContract } from "../generated/deviceActionContracts.js";
import type { JSONObject } from "../types.js";
import type { ActionTransport } from "./actionTransport.js";
import { ArtifactDecoder } from "./artifacts.js";
import { DriverFailure, type DriverError } from "./driverErrors.js";
import { noopHostLogger, type HostLogger } from "./hostLogger.js";
import type { Artifact, InvocationResult } from "./types.js";
import type {
  DriverRuntimeOptions,
  InvocationOptions,
  InvocationPolicy
} from "./driverRuntimeTypes.js";

export type {
  DriverRuntimeOptions,
  InvocationOptions,
  InvocationPolicy
} from "./driverRuntimeTypes.js";

/**
 * 构建时从生成合同（src/generated/deviceActionContracts.ts）建立的「action 名 → 合同」
 * 索引。runtime 据此读取每个 canonical action 的幂等性/超时级别元数据（合同是
 * 构建时固化的可信来源，无需每次调用访问 App）。
 */
const ACTION_METADATA: ReadonlyMap<string, DeviceActionContract> = new Map(
  DEVICE_ACTION_CONTRACTS.map(contract => [contract.action, contract] as const)
);

/**
 * 把 transport 返回值归一化为稳定 `InvocationResult` 的 host runtime（协议解释层）。
 */
export class DriverRuntime {
  /** 可注入的传输实现（不解释业务字段）。 */
  private readonly transport: ActionTransport;
  /** 配置解析完成后固定；保证同一调用的多次尝试使用同一超时。 */
  private readonly configuredRequestTimeoutMs: number;
  /** 所有成功/失败 envelope 都经过同一附件大小与格式检查。 */
  private readonly artifactDecoder: ArtifactDecoder;
  /** 默认无输出；生产入口显式注入 stderr logger。 */
  private readonly logger: HostLogger;

  /**
   * 创建 runtime。
   *
   * @param options transport、默认请求超时、可选的 artifact decoder 与 logger。
   */
  constructor(options: DriverRuntimeOptions) {
    this.transport = options.transport;
    this.configuredRequestTimeoutMs = options.configuredRequestTimeoutMs;
    this.artifactDecoder = options.artifactDecoder ?? new ArtifactDecoder();
    this.logger = options.logger ?? noopHostLogger;
  }

  /**
   * 调用一个 App action，返回成功或预期失败的统一结果。
   *
   * 执行流程：查策略 → 算超时 → 进入重试循环（最多 2 次）→ 解释 envelope 或
   * 归一化失败。循环的三种出口：
   * - transport 成功 → `fromEnvelope`（成功或 appEnvelope 业务失败）；
   * - `DriverFailure` 且 `shouldRetry` 通过 → 重试第二轮；
   * - `DriverFailure` 且不重试 → 失败结果；
   * - **非 DriverFailure 的未知异常 → 原样抛出**（预期失败转结果，意外 bug 不伪装成业务失败）。
   *
   * @param action action 名（如 "ping"、"ui.tap"）。
   * @param data action 的 JSON data，默认 {}。
   * @param options 可选取消信号与策略覆盖。
   * @returns `InvocationResult`：{ ok:true, data, artifacts, elapsedMs, attempts }
   *   或 { ok:false, error, ... }。
   *   示例：App 离线时 invoke("ping") → ok:false，source:"transport"，attempts:2。
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
   * 将 App wire envelope（{"code":…,"message"?,"data"?}）投影为 runtime 结果。
   *
   * 三个分支：
   * 1. `code` 不是字符串 → protocol 错误（App 连最基本字段都给错，不可信）；
   * 2. `code === "ok"` → 成功：data 经 ArtifactDecoder 剥离二进制附件后返回；
   * 3. 其他 code → 业务失败：`source:"appEnvelope"`，code/message 原样保留，
   *    data/artifact 经 decoder 清理后附带（让 workflow/adapter 报告终态时保留上下文）。
   *
   * @param action action 名（用于错误信息）。
   * @param envelope 未经解释的响应 envelope。
   * @param startedAt 起始时间戳（计算 elapsedMs）。
   * @param attempts 当前尝试次数。
   * @returns 成功或失败结果。
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
   * 判断一次失败是否能自动重放（重试安全边界，四个条件**全部**满足才重试）：
   *
   * 1. `attempts < 2`：最多试两次，避免瞬时故障放大成请求风暴；
   * 2. `!responseReceived`：还没收到过任何 HTTP 响应——一旦收到过，请求必然到达
   *    App，重放可能**重复执行 UI 操作**（比如点了两次）；
   * 3. 合同声明 `readOnly`/`idempotent`：action 无副作用或重复执行无害；
   * 4. 失败阶段是 connect/reset：连接未建立或被重置——timeout/abort 是「请求可能
   *    已发出」的不确定状态，不能重放。
   *
   * 任何不确定性都选择不重试：宁可失败，不可重复操作。
   *
   * @param policy 当前 action 的调用策略（可能 undefined=未知 action 保守处理）。
   * @param failure 已分类的 transport 异常。
   * @param attempts 当前尝试次数。
   * @returns true=允许再发一次请求。
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

  /**
   * 统一构造失败结果：补齐 elapsedMs/attempts，并按实际存在情况保留 data/artifact。
   *
   * @param error 归一化错误。
   * @param startedAt 起始时间戳。
   * @param attempts 尝试次数。
   * @param data 可选的结构化失败上下文。
   * @param artifacts 可选的成功解码附件。
   * @returns `InvocationFailure`。
   */
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

  /**
   * 在返回 adapter 前记录不含 payload 的终态摘要日志。
   *
   * 只记录 action/attempts/elapsedMs/artifactCount 与错误字段（source/code 等），
   * **绝不记录 data 或响应正文**——防止业务 payload 泄漏进日志。
   *
   * @param action action 名。
   * @param result 终态结果（成功或失败）。
   * @returns 原样返回结果（日志是旁路，不改变返回值）。
   */
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

/**
 * 计算单次 transport 请求的超时预算。
 *
 * 普通 action：直接用配置值；wait 类 action（如 ui.wait）：业务等待之外预留 5 秒——
 * App 要先等满业务 timeoutMs，再花时间编码并传回终态 envelope，transport 超时若等于
 * 业务超时会在 App 刚完成时把请求掐断，所以必须错开。
 *
 * @param policy 调用策略（可能 undefined）。
 * @param data action data（wait 类取其中的 timeoutMs 字段）。
 * @param configuredRequestTimeoutMs 配置的基准超时。
 * @returns 毫秒超时预算。
 *   示例：policy=wait + data.timeoutMs=10000 + 配置 10000 → 15000。
 */
function requestTimeout(policy: InvocationPolicy | undefined, data: JSONObject, configuredRequestTimeoutMs: number): number {
  if (policy?.timeoutClass !== "wait") return configuredRequestTimeoutMs;
  const businessTimeoutMs = typeof data.timeoutMs === "number" ? data.timeoutMs : 0;
  return Math.max(configuredRequestTimeoutMs, businessTimeoutMs + 5000);
}

/**
 * 决定本次调用使用哪个策略：canonical 合同永远优先；per-call 策略只服务于
 * 通过 help 严格校验的扩展 action（校验见 isInvocationPolicy）。
 *
 * @param action action 名。
 * @param perCallPolicy 调用方传入的策略（可能未经验证）。
 * @returns 有效策略；未知 action 且 per-call 非法时 undefined（保守：不自动重试）。
 */
function invocationPolicy(action: string, perCallPolicy: InvocationPolicy | undefined): InvocationPolicy | undefined {
  const generated = ACTION_METADATA.get(action);
  if (generated !== undefined) {
    return { idempotency: generated.idempotency, timeoutClass: generated.timeoutClass };
  }
  return isInvocationPolicy(perCallPolicy) ? perCallPolicy : undefined;
}

/**
 * 类型守卫：校验未知来源的策略对象两个字段都是合法枚举值。
 *
 * @param value 待校验值。
 * @returns true=可安全当作 InvocationPolicy 使用。
 */
function isInvocationPolicy(value: InvocationPolicy | undefined): value is InvocationPolicy {
  return value !== undefined
    && (value.idempotency === "readOnly" || value.idempotency === "idempotent" || value.idempotency === "sideEffecting")
    && (value.timeoutClass === "standard" || value.timeoutClass === "wait" || value.timeoutClass === "screenshot");
}

/**
 * 判断未知值是否为 JSON 对象（非 null、非数组）。
 *
 * @param value 未知值。
 * @returns 是对象时收窄类型返回，否则 undefined。
 */
function objectValue(value: unknown): JSONObject | undefined {
  return typeof value === "object" && value !== null && !Array.isArray(value) ? value as JSONObject : undefined;
}

/**
 * 构造统一的「envelope 协议错误」（App 响应结构不合法时使用）。
 *
 * @param action action 名。
 * @returns source=protocol、protocolIssue=invalid_envelope 的 DriverError。
 */
function protocolError(action: string): DriverError {
  return {
    source: "protocol",
    code: "protocol_error",
    message: "App response did not match the action envelope protocol",
    action,
    protocolIssue: "invalid_envelope"
  };
}

/**
 * 提取错误的可日志字段（不含 message/payload，防止敏感信息进日志）。
 *
 * @param error 归一化错误。
 * @returns 稳定字段集合（source/code/status/timeoutMs/transportPhase/protocolIssue）。
 */
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

/**
 * 提取异常的类型名（用于日志中的 errorType 字段）。
 *
 * @param error 任意异常。
 * @returns Error 实例的 name，否则 typeof 结果。
 */
function errorType(error: unknown): string {
  return error instanceof Error ? error.name : typeof error;
}
