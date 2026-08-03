/**
 * 显式能力探测与扩展 action 策略缓存。
 *
 * 设计原则：**工具发现阶段绝不访问 App**——MCP 的 tools/list、CLI 启动都不发请求；
 * 只有显式执行 doctor/health/capabilities，或调用未知 action 需要策略时才发起
 * `ping → help` 两次调用。
 *
 * 报告刻意把「App 可达」「UIKit 已注册」「两端合同完全一致」拆成多个维度，
 * 避免把三个不同的事实混成一个布尔值；help 不可信时对缺失/模块只报 unknown，
 * 不做负面判断（App 离线 ≠ App 能力不完整）。
 *
 * 典型调用（doctor 模式）：probe("doctor") → invoke("ping") → invoke("help")
 *   → 计算 connection/actions/modules/contractCompatibility → CapabilityReport。
 */
import { DEVICE_ACTION_CONTRACTS, type DeviceActionContract } from "../generated/deviceActionContracts.js";
import { CONTRACT_BUNDLE_METADATA } from "../generated/contractBundle.js";
import type { JSONObject } from "../types.js";
import type { DriverError } from "./driverErrors.js";
import type { InvocationPolicy } from "./driverRuntime.js";
import type { InvocationResult } from "./types.js";
import { noopHostLogger, type HostLogger } from "./hostLogger.js";

/** CapabilityProbe 所需的最小 runtime 边界（只暴露 invoke），便于 adapter 和测试注入。 */
export interface CapabilityInvoker {
  invoke(action: string, data?: JSONObject, options?: CapabilityProbeInvocationOptions): Promise<InvocationResult>;
}

/** capability probe 透传给 runtime 的可选调用参数（目前只有取消信号）。 */
export interface CapabilityProbeInvocationOptions {
  readonly signal?: AbortSignal;
}

/** 显式能力检查入口（三种模式探测步骤相同，仅报告标记与消费方不同）。 */
export type CapabilityProbeMode = "doctor" | "health" | "capabilities";
/** 连接结论：reachable=可达；unreachable=transport 失败；malformed=响应畸形。 */
export type ConnectionStatus = "reachable" | "unreachable" | "malformed";
/** 模块注册结论：registered=全部注册；partial=部分；not_registered=零注册；unknown=无法判断。 */
export type ModuleStatus = "registered" | "partial" | "not_registered" | "unknown";
/** 合同一致性：exact=三项元数据全等；mismatch=有显式不等；unknown=缺字段无法比较。 */
export type ContractCompatibility = "exact" | "mismatch" | "unknown";

/**
 * action 注册状态。离线或 help 不可解析时保持 unknown（不做负面判断）。
 */
export interface ActionCapabilityStatus {
  /** help 是否成功提供了 action 集合：known=有结论；unknown=无法判断。 */
  readonly status: "known" | "unknown";
  /** App 当前注册的 action 名列表。 */
  readonly registeredActions: readonly string[];
  /** 本地合同里有但 App 未注册的 action；仅 status=known 时有结论。 */
  readonly missingActions: readonly string[];
}

/**
 * UIKit/Diagnostics 模块的注册状态（按合同 provider 分组统计）。
 */
export interface ModuleCapabilityStatus {
  /** 模块注册结论（registered/partial/not_registered/unknown）。 */
  readonly status: ModuleStatus;
  /** 已注册的合同 action 数量。 */
  readonly registeredCount?: number;
  /** 本地合同要求该模块提供的 action 总数。 */
  readonly requiredCount?: number;
  /** 缺失的模块 action 列表。 */
  readonly missingActions?: readonly string[];
}

/**
 * help 自省结果的稳定投影（doctor 报告的完整结构）。
 *
 * 所有维度独立报告，不合并成单一布尔；消费方（commands.ts runDoctor / MCP
 * health_check）按各自语义映射退出码或 isError。
 */
export interface CapabilityReport {
  /** 触发本次探针的显式入口（doctor/health/capabilities）。 */
  readonly mode: CapabilityProbeMode;
  /** HTTP endpoint 与 ping 的连接结论。 */
  readonly connection: ConnectionStatus;
  /** ping 结果：ok 还要求 data.pong === true（仅 envelope ok 不足以证明协议兼容）。 */
  readonly ping: { readonly status: "ok" | "failed" | "malformed" | "unknown"; readonly error?: DriverError };
  /** help 结果：available 要求 commands 数组可解析。 */
  readonly help: { readonly status: "available" | "failed" | "malformed" | "unknown"; readonly error?: DriverError };
  /** 全局 action 注册结论（registered/missing 列表）。 */
  readonly actions: ActionCapabilityStatus;
  /** UIKit 与 Diagnostics 模块注册结论。 */
  readonly modules: Readonly<{ uikit: ModuleCapabilityStatus; diagnostics: ModuleCapabilityStatus }>;
  /** App 与 host 是否由同一份 canonical contract bundle 生成。 */
  readonly contractCompatibility: ContractCompatibility;
  /** App help 宣布的协议/合同版本与 hash，以及与本地基线的逐项比较结果。 */
  readonly metadata?: Readonly<{
    protocolVersion?: string;
    contractVersion?: string;
    contractHash?: string;
    protocolVersionMatches?: boolean;
    contractVersionMatches?: boolean;
    hashMatches?: boolean;
  }>;
}

/**
 * 调用 ping/help 并把 App 能力投影为 adapter 可消费的稳定报告。
 */
export class CapabilityProbe {
  /** 本地 canonical 合同基线（用于计算缺失 action 与模块注册比例）。 */
  private readonly expectedContracts: readonly DeviceActionContract[];
  private readonly logger: HostLogger;
  /** 只保存最近一次完整可信 ping/help 中提取的扩展 action 策略快照。 */
  private actionPolicies: ReadonlyMap<string, InvocationPolicy> = new Map();
  /** 探测代际计数：防止并发 probe 中较早完成的旧请求覆盖较新一轮的缓存。 */
  private probeGeneration = 0;

  /**
   * 创建能力探针；构造过程是纯配置，**不发出任何 action**（工具发现零网络）。
   *
   * @param runtime 可注入的 DriverRuntime 兼容对象。
   * @param expectedContracts 本地生成合同基线，默认使用 canonical bundle。
   * @param logger 结构化日志器；CLI/MCP 入口注入共享 stderr logger。
   */
  constructor(
    private readonly runtime: CapabilityInvoker,
    expectedContracts: readonly DeviceActionContract[] = DEVICE_ACTION_CONTRACTS,
    logger: HostLogger = noopHostLogger
  ) {
    this.expectedContracts = expectedContracts;
    this.logger = logger;
  }

  /**
   * 显式执行能力探测：ping → help → 计算各维度报告。
   *
   * @param mode 探测模式（doctor/health/capabilities，仅影响报告标记）。
   * @param options 透传给 runtime 的可选参数（取消信号）。
   * @returns 完整 CapabilityReport。
   *   示例（App 离线）：connection=unreachable，ping/help=failed，
   *     actions/modules/contractCompatibility=unknown。
   */
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

  /** 以 doctor 模式标记报告（CLI `iosdriver doctor` 使用）。探测步骤与其他模式相同。 */
  async doctor(options: CapabilityProbeInvocationOptions = {}): Promise<CapabilityReport> { return this.probe("doctor", options); }
  /** 以 health 模式标记报告（MCP `health_check` 工具使用）。 */
  async health(options: CapabilityProbeInvocationOptions = {}): Promise<CapabilityReport> { return this.probe("health", options); }
  /** 以 capabilities 模式标记报告（MCP `check_capabilities` 工具使用）。 */
  async capabilities(options: CapabilityProbeInvocationOptions = {}): Promise<CapabilityReport> { return this.probe("capabilities", options); }

  /**
   * 返回最近一次完整成功 probe 中严格校验过的扩展 action 策略。
   *
   * 后续 probe 失败或 help 畸形时快照会被清空——避免基于旧 App 元数据重试扩展 action。
   *
   * @param action action 名。
   * @returns 同时具有合法 idempotency/timeoutClass 的策略；未知/非法返回 undefined
   *   （调用方按保守策略处理：不自动重试）。
   */
  invocationPolicy(action: string): InvocationPolicy | undefined {
    return this.actionPolicies.get(action);
  }

  /**
   * 记录探测摘要日志（不含完整 action 列表，避免日志随合同规模膨胀）后返回报告。
   *
   * @param report 完整报告。
   * @param startedAt 起始时间戳（计算 elapsedMs）。
   * @returns 原样返回报告（日志是旁路）。
   */
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

/**
 * help 返回的单条命令的最小形状（字段未经验证，用 unknown 表示待校验）。
 */
type HelpCommand = {
  readonly action?: unknown;
  readonly idempotency?: unknown;
  readonly timeoutClass?: unknown;
};
/** help 返回数据的稳定投影（commands 数组 + 版本元数据）。 */
type HelpData = { readonly commands: readonly HelpCommand[]; readonly metadata?: CapabilityReport["metadata"] };

/**
 * 判断 ping 结果：成功还必须包含 `data.pong === true`。
 * 仅 envelope ok 不足以证明协议兼容（App 可能返回假 ok）。
 *
 * @param result ping 的 invoke 结果。
 * @returns ping 状态；协议错误 → malformed，其他失败 → failed（带 error）。
 */
function pingStatus(result: InvocationResult): CapabilityReport["ping"] {
  if (!result.ok) return { status: result.error.source === "protocol" ? "malformed" : "failed", error: result.error };
  return result.data.pong === true ? { status: "ok" } : { status: "malformed" };
}

/**
 * 提取 help 结果中后续比较需要的字段（commands + 版本元数据）。
 * 只投影已知字段，不把未知 App 元数据扩散到 host 类型。
 *
 * @param result help 的 invoke 结果。
 * @returns help 状态；commands 数组合法才算 available。
 */
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

/**
 * 按 provider 的合同全集计算模块注册状态（registered/partial/not_registered）。
 * 基于合同基线统计而不是猜测模块开关：required=合同中 provider 归属该模块的 action。
 *
 * @param contracts 本地合同基线。
 * @param provider 模块名（uikit/diagnostics）。
 * @param registered App 实际注册的 action 集合。
 * @returns 模块注册状态与数量统计。
 */
function moduleStatus(contracts: readonly DeviceActionContract[], provider: "uikit" | "diagnostics", registered: Set<string>): ModuleCapabilityStatus {
  const required = contracts.filter(contract => contract.provider === provider).map(contract => contract.action);
  const missing = required.filter(action => !registered.has(action));
  const count = required.length - missing.length;
  return { status: count === required.length ? "registered" : count === 0 ? "not_registered" : "partial", registeredCount: count, requiredCount: required.length, missingActions: missing };
}

/**
 * 汇总合同一致性：三项元数据全部出现且全等 → exact；
 * 任一显式不等 → mismatch；缺字段 → unknown（无法比较，不臆断）。
 *
 * @param metadata App help 的版本元数据（可能 undefined）。
 * @returns exact/mismatch/unknown。
 */
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

/** 类型守卫：未知值是否为对象（非 null、非数组）。 */
function isObject(value: unknown): value is HelpCommand { return typeof value === "object" && value !== null && !Array.isArray(value); }

/**
 * 从 help 的 commands 创建扩展 action 策略快照。
 *
 * 严格规则：同名 action 重复声明或任一策略字段非法时**整项拒绝**（不是取其中一个
 * 声明）——这样未知副作用的 action 会回到「不自动重试」的保守行为。
 *
 * @param commands help 返回的命令列表。
 * @returns action 名 → 已校验策略的 Map；不可信项不进入。
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

/**
 * 校验未知来源的策略字段：两个字段都必须是合法枚举值。
 *
 * @param idempotency 未知值。
 * @param timeoutClass 未知值。
 * @returns 合法时返回策略对象；任一非法返回 undefined。
 */
function policyValue(idempotency: unknown, timeoutClass: unknown): InvocationPolicy | undefined {
  if (idempotency !== "readOnly" && idempotency !== "idempotent" && idempotency !== "sideEffecting") return undefined;
  if (timeoutClass !== "standard" && timeoutClass !== "wait" && timeoutClass !== "screenshot") return undefined;
  return { idempotency, timeoutClass };
}
