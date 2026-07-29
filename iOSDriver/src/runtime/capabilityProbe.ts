/**
 * 显式能力探测与扩展 action 策略缓存。
 *
 * 工具发现阶段绝不访问 App；只有 doctor/health/capabilities 或调用未知 action 时才执行
 * `ping -> help`。报告会同时给出连接状态、模块注册完整度和本地/设备合同一致性，避免
 * 把“App 可达”“UIKit 已注册”“两端合同完全一致”混成一个布尔值。
 */
import { DEVICE_ACTION_CONTRACTS, type DeviceActionContract } from "../generated/deviceActionContracts.js";
import { CONTRACT_BUNDLE_METADATA } from "../generated/contractBundle.js";
import type { JSONObject } from "../types.js";
import type { DriverError } from "./driverErrors.js";
import type { InvocationPolicy } from "./driverRuntime.js";
import type { InvocationResult } from "./types.js";
import { noopHostLogger, type HostLogger } from "./hostLogger.js";

/** CapabilityProbe 所需的最小 runtime 边界，便于 adapter 和测试注入。 */
export interface CapabilityInvoker {
  invoke(action: string, data?: JSONObject, options?: CapabilityProbeInvocationOptions): Promise<InvocationResult>;
}

/** capability probe 透传给 runtime 的可选调用参数。 */
export interface CapabilityProbeInvocationOptions {
  readonly signal?: AbortSignal;
}

/** 显式能力检查入口；不会在构造或工具发现阶段访问网络。 */
export type CapabilityProbeMode = "doctor" | "health" | "capabilities";
export type ConnectionStatus = "reachable" | "unreachable" | "malformed";
export type ModuleStatus = "registered" | "partial" | "not_registered" | "unknown";
export type ContractCompatibility = "exact" | "mismatch" | "unknown";

/** action 注册状态。离线或 help 不可解析时保持 unknown。 */
export interface ActionCapabilityStatus {
  /** help 是否成功提供 action 集合。 */
  readonly status: "known" | "unknown";
  /** App 当前注册的 action。 */
  readonly registeredActions: readonly string[];
  /** 本地合同中但 App 未注册的 action。仅在 status=known 时有结论。 */
  readonly missingActions: readonly string[];
}

/** UIKit/Diagnostics 模块的注册状态。 */
export interface ModuleCapabilityStatus {
  /** 模块注册结论。 */
  readonly status: ModuleStatus;
  /** 已注册的合同 action 数量。 */
  readonly registeredCount?: number;
  /** 本地合同要求的 action 数量。 */
  readonly requiredCount?: number;
  /** 缺失的模块 action。 */
  readonly missingActions?: readonly string[];
}

/** help 自省结果的稳定投影。 */
export interface CapabilityReport {
  /** 触发本次探针的显式入口。 */
  readonly mode: CapabilityProbeMode;
  /** HTTP endpoint 与 ping 的连接结论。 */
  readonly connection: ConnectionStatus;
  /** ping 结果。 */
  readonly ping: { readonly status: "ok" | "failed" | "malformed" | "unknown"; readonly error?: DriverError };
  /** help 结果。 */
  readonly help: { readonly status: "available" | "failed" | "malformed" | "unknown"; readonly error?: DriverError };
  /** 全局 action 注册结论。 */
  readonly actions: ActionCapabilityStatus;
  /** UIKit 与 Diagnostics 模块结论。 */
  readonly modules: Readonly<{ uikit: ModuleCapabilityStatus; diagnostics: ModuleCapabilityStatus }>;
  /** App 与 host 是否由同一份 canonical contract bundle 生成。 */
  readonly contractCompatibility: ContractCompatibility;
  /** App help 宣布的协议/合同版本和 hash，以及与本地基线的比较。 */
  readonly metadata?: Readonly<{
    protocolVersion?: string;
    contractVersion?: string;
    contractHash?: string;
    protocolVersionMatches?: boolean;
    contractVersionMatches?: boolean;
    hashMatches?: boolean;
  }>;
}

/** 调用 ping/help 并将 App 能力投影为 adapter 可消费的稳定报告。 */
export class CapabilityProbe {
  /** 用于计算缺失 action 和 provider 注册比例的本地 canonical 基线。 */
  private readonly expectedContracts: readonly DeviceActionContract[];
  private readonly logger: HostLogger;
  /** 只保存最近一次完整可信 ping/help 中的扩展 action 策略。 */
  private actionPolicies: ReadonlyMap<string, InvocationPolicy> = new Map();
  /** 防止并发 probe 中较早完成的旧请求覆盖较新一轮缓存。 */
  private probeGeneration = 0;

  /**
   * 创建能力探针；构造过程是纯配置，不发出任何 action。
   *
   * @param runtime 可注入的 DriverRuntime 兼容对象。
   * @param expectedContracts 本地生成合同，默认使用 canonical bundle。
   * @param logger Host 命令链 logger；CLI/MCP 入口注入共享 stderr logger。
   */
  constructor(
    private readonly runtime: CapabilityInvoker,
    expectedContracts: readonly DeviceActionContract[] = DEVICE_ACTION_CONTRACTS,
    logger: HostLogger = noopHostLogger
  ) {
    this.expectedContracts = expectedContracts;
    this.logger = logger;
  }

  /** 显式执行 doctor/health/capabilities 检查。 */
  async probe(
    mode: CapabilityProbeMode = "capabilities",
    options: CapabilityProbeInvocationOptions = {}
  ): Promise<CapabilityReport> {
    const generation = ++this.probeGeneration;
    // 一旦开始重新探测，旧 App 的扩展策略便不再可信；探测期间保持保守默认值。
    this.actionPolicies = new Map();
    const startedAt = Date.now();
    this.logger.emit("info", "capability.probe.start", { mode });
    try {
      const pingResult = await this.runtime.invoke("ping", {}, options);
      const ping = pingStatus(pingResult);
      const helpResult = await this.runtime.invoke("help", {}, options);
      const help = helpStatus(helpResult);
      const connection: ConnectionStatus = ping.status === "malformed"
        ? "malformed"
        : ping.status === "ok"
          ? "reachable"
          : ping.error?.source === "transport"
            ? "unreachable"
            : "reachable";

      // Policy 会影响未知扩展 action 的自动重试，只有同轮 ping/help 均可信时才发布。
      // App 重启、连接失败或畸形 help 后必须立即回到未知 action 的保守策略。
      if (generation === this.probeGeneration) {
        this.actionPolicies = ping.status === "ok" && help.status === "available"
          ? validatedActionPolicies(help.commands)
          : new Map();
      }
      // help 不可信时不能对 action 缺失或模块注册做负面判断，只能返回 unknown。
      if (help.status !== "available" || connection === "unreachable" || connection === "malformed") {
        return this.complete({
          mode, connection, ping, help,
          actions: { status: "unknown", registeredActions: [], missingActions: [] },
          modules: { uikit: { status: "unknown" }, diagnostics: { status: "unknown" } },
          contractCompatibility: "unknown"
        }, startedAt);
      }
      const commands = help.commands;
      const registeredActions = commands.map(command => command.action).filter((action): action is string => typeof action === "string");
      const registered = new Set(registeredActions);
      const missingActions = this.expectedContracts.map(contract => contract.action).filter(action => !registered.has(action));
      const metadata = help.metadata === undefined ? undefined : {
        ...help.metadata,
        ...(help.metadata.protocolVersion === undefined ? {} : { protocolVersionMatches: help.metadata.protocolVersion === CONTRACT_BUNDLE_METADATA.protocolVersion }),
        ...(help.metadata.contractVersion === undefined ? {} : { contractVersionMatches: help.metadata.contractVersion === CONTRACT_BUNDLE_METADATA.contractVersion }),
        ...(help.metadata.contractHash === undefined ? {} : { hashMatches: help.metadata.contractHash === CONTRACT_BUNDLE_METADATA.contractHash })
      };
      return this.complete({
        mode, connection, ping, help,
        actions: { status: "known", registeredActions, missingActions },
        modules: {
          uikit: moduleStatus(this.expectedContracts, "uikit", registered),
          diagnostics: moduleStatus(this.expectedContracts, "diagnostics", registered)
        },
        contractCompatibility: contractCompatibility(metadata),
        ...(metadata === undefined ? {} : { metadata })
      }, startedAt);
    } catch (error) {
      this.logger.emit("error", "capability.probe.complete", {
        mode,
        outcome: "throw",
        elapsedMs: Date.now() - startedAt,
        errorType: error instanceof Error ? error.name : typeof error
      });
      throw error;
    }
  }

  /** 以 doctor 模式标记报告；探测步骤与其他模式一致，区别留给 adapter 展示。 */
  async doctor(options: CapabilityProbeInvocationOptions = {}): Promise<CapabilityReport> { return this.probe("doctor", options); }
  /** 以 health 模式标记报告，供 MCP `health_check` 使用。 */
  async health(options: CapabilityProbeInvocationOptions = {}): Promise<CapabilityReport> { return this.probe("health", options); }
  /** 以 capabilities 模式标记报告，供 MCP `check_capabilities` 使用。 */
  async capabilities(options: CapabilityProbeInvocationOptions = {}): Promise<CapabilityReport> { return this.probe("capabilities", options); }

  /**
   * 返回最近一次完整成功 probe 中严格校验过的 action 策略。
   * 后续 probe 失败或 help 畸形时会清空快照，避免基于旧 App 元数据重试扩展 action。
   *
   * @param action action 名称。
   * @returns 同时具有合法 idempotency/timeoutClass 的策略；其他情况返回 undefined。
   */
  invocationPolicy(action: string): InvocationPolicy | undefined {
    return this.actionPolicies.get(action);
  }

  /** 记录不含完整 action 列表的探测摘要，避免日志随合同规模膨胀。 */
  private complete(report: CapabilityReport, startedAt: number): CapabilityReport {
    this.logger.emit(report.connection === "reachable" ? "info" : "warn", "capability.probe.complete", {
      mode: report.mode,
      outcome: "result",
      elapsedMs: Date.now() - startedAt,
      connection: report.connection,
      pingStatus: report.ping.status,
      helpStatus: report.help.status,
      actionsStatus: report.actions.status,
      registeredActionCount: report.actions.registeredActions.length,
      missingActionCount: report.actions.missingActions.length,
      uikitStatus: report.modules.uikit.status,
      diagnosticsStatus: report.modules.diagnostics.status,
      contractCompatibility: report.contractCompatibility
    });
    return report;
  }
}

type HelpCommand = {
  readonly action?: unknown;
  readonly idempotency?: unknown;
  readonly timeoutClass?: unknown;
};
type HelpData = { readonly commands: readonly HelpCommand[]; readonly metadata?: CapabilityReport["metadata"] };

/** ping 成功还必须包含 `pong: true`；仅 envelope ok 不足以证明协议兼容。 */
function pingStatus(result: InvocationResult): CapabilityReport["ping"] {
  if (!result.ok) return { status: result.error.source === "protocol" ? "malformed" : "failed", error: result.error };
  return result.data.pong === true ? { status: "ok" } : { status: "malformed" };
}
/** 只提取后续比较需要的 help 字段，不把未知 App 元数据扩散到 host 类型。 */
function helpStatus(result: InvocationResult): CapabilityReport["help"] & { readonly commands: readonly HelpCommand[]; readonly metadata?: CapabilityReport["metadata"] } {
  if (!result.ok) return { status: result.error.source === "protocol" ? "malformed" : "failed", error: result.error, commands: [] };
  const commands = Array.isArray(result.data.commands) ? result.data.commands.filter(isObject) : undefined;
  if (!commands) return { status: "malformed", commands: [] };
  const metadata = {
    ...(typeof result.data.protocolVersion === "string" ? { protocolVersion: result.data.protocolVersion } : {}),
    ...(typeof result.data.contractVersion === "string" ? { contractVersion: result.data.contractVersion } : {}),
    ...(typeof result.data.contractHash === "string" ? { contractHash: result.data.contractHash } : {})
  };
  return { status: "available", commands, ...(Object.keys(metadata).length === 0 ? {} : { metadata }) };
}
/** 按 provider 的合同全集计算 registered/partial/not_registered，而不是猜测模块开关。 */
function moduleStatus(contracts: readonly DeviceActionContract[], provider: "uikit" | "diagnostics", registered: Set<string>): ModuleCapabilityStatus {
  const required = contracts.filter(contract => contract.provider === provider).map(contract => contract.action);
  const missing = required.filter(action => !registered.has(action));
  const count = required.length - missing.length;
  return { status: count === required.length ? "registered" : count === 0 ? "not_registered" : "partial", registeredCount: count, requiredCount: required.length, missingActions: missing };
}
/** 三项元数据全部出现且相等才是 exact；缺字段保持 unknown，显式不等才是 mismatch。 */
function contractCompatibility(metadata: CapabilityReport["metadata"]): ContractCompatibility {
  if (metadata === undefined) return "unknown";
  const matches = [
    metadata.protocolVersionMatches,
    metadata.contractVersionMatches,
    metadata.hashMatches
  ];
  if (matches.some(value => value === false)) return "mismatch";
  return matches.every(value => value === true) ? "exact" : "unknown";
}
function isObject(value: unknown): value is HelpCommand { return typeof value === "object" && value !== null && !Array.isArray(value); }

/**
 * 从 help 创建扩展 action 策略快照。
 *
 * 同名 action 重复或任一策略字段非法时整项拒绝，而不是选择其中一个声明；这样未知
 * side effect 的 action 会回到“不自动重试”的保守行为。
 */
function validatedActionPolicies(commands: readonly HelpCommand[]): ReadonlyMap<string, InvocationPolicy> {
  const policies = new Map<string, InvocationPolicy>();
  const rejected = new Set<string>();
  for (const command of commands) {
    if (typeof command.action !== "string" || rejected.has(command.action)) continue;
    const policy = policyValue(command.idempotency, command.timeoutClass);
    if (policy === undefined || policies.has(command.action)) {
      policies.delete(command.action);
      rejected.add(command.action);
      continue;
    }
    policies.set(command.action, policy);
  }
  return policies;
}

function policyValue(idempotency: unknown, timeoutClass: unknown): InvocationPolicy | undefined {
  if (idempotency !== "readOnly" && idempotency !== "idempotent" && idempotency !== "sideEffecting") return undefined;
  if (timeoutClass !== "standard" && timeoutClass !== "wait" && timeoutClass !== "screenshot") return undefined;
  return { idempotency, timeoutClass };
}
