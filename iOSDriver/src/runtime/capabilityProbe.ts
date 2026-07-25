import { DEVICE_ACTION_CONTRACTS, type DeviceActionContract } from "../generated/deviceActionContracts.js";
import { CONTRACT_BUNDLE_METADATA } from "../generated/contractBundle.js";
import type { JSONObject } from "../types.js";
import type { DriverError } from "./driverErrors.js";
import type { InvocationPolicy } from "./driverRuntime.js";
import type { InvocationResult } from "./types.js";
import { noopHostLogger, type HostLogger } from "./hostLogger.js";
import { compareContractSchemas, type ActionSchemaCompatibility, type SchemaCompatibility } from "./schemaCompatibility.js";

/** CapabilityProbe 所需的最小 runtime 边界，便于 adapter 和测试注入。 */
export interface CapabilityInvoker {
  invoke(action: string, data?: JSONObject): Promise<InvocationResult>;
}

/** 显式能力检查入口；不会在构造或工具发现阶段访问网络。 */
export type CapabilityProbeMode = "doctor" | "health" | "capabilities";
export type ConnectionStatus = "reachable" | "unreachable" | "malformed";
export type ModuleStatus = "registered" | "partial" | "not_registered" | "unknown";

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
  /** 所有已知 action schema 的汇总结论。 */
  readonly schemaCompatibility: SchemaCompatibility;
  /** 每个合同 action 的 schema 细节。 */
  readonly schemaDifferences: readonly ActionSchemaCompatibility[];
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
  private readonly expectedContracts: readonly DeviceActionContract[];
  private readonly logger: HostLogger;
  private actionPolicies: ReadonlyMap<string, InvocationPolicy> = new Map();
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
  async probe(mode: CapabilityProbeMode = "capabilities"): Promise<CapabilityReport> {
    const generation = ++this.probeGeneration;
    // 一旦开始重新探测，旧 App 的扩展策略便不再可信；探测期间保持保守默认值。
    this.actionPolicies = new Map();
    const startedAt = Date.now();
    this.logger.emit("info", "capability.probe.start", { mode });
    try {
      const pingResult = await this.runtime.invoke("ping", {});
      const ping = pingStatus(pingResult);
      const helpResult = await this.runtime.invoke("help", {});
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
      if (help.status !== "available" || connection === "unreachable" || connection === "malformed") {
        return this.complete({
          mode, connection, ping, help,
          actions: { status: "unknown", registeredActions: [], missingActions: [] },
          modules: { uikit: { status: "unknown" }, diagnostics: { status: "unknown" } },
          schemaCompatibility: "unknown",
          schemaDifferences: []
        }, startedAt);
      }
      const commands = help.commands;
      const registeredActions = commands.map(command => command.action).filter((action): action is string => typeof action === "string");
      const registered = new Set(registeredActions);
      const missingActions = this.expectedContracts.map(contract => contract.action).filter(action => !registered.has(action));
      const schemaDifferences = compareContractSchemas(this.expectedContracts, commands);
      const schemaCompatibility = summarizeSchema(schemaDifferences);
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
        schemaCompatibility,
        schemaDifferences,
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

  /** doctor 的显式别名。 */
  async doctor(): Promise<CapabilityReport> { return this.probe("doctor"); }
  /** health 的显式别名。 */
  async health(): Promise<CapabilityReport> { return this.probe("health"); }
  /** capabilities 的显式别名。 */
  async capabilities(): Promise<CapabilityReport> { return this.probe("capabilities"); }

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
      schemaCompatibility: report.schemaCompatibility,
      schemaDifferenceCount: report.schemaDifferences.length
    });
    return report;
  }
}

type HelpCommand = {
  readonly action?: unknown;
  readonly inputSchema?: unknown;
  readonly idempotency?: unknown;
  readonly timeoutClass?: unknown;
};
type HelpData = { readonly commands: readonly HelpCommand[]; readonly metadata?: CapabilityReport["metadata"] };

function pingStatus(result: InvocationResult): CapabilityReport["ping"] {
  if (!result.ok) return { status: result.error.source === "protocol" ? "malformed" : "failed", error: result.error };
  return result.data.pong === true ? { status: "ok" } : { status: "malformed" };
}
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
function moduleStatus(contracts: readonly DeviceActionContract[], provider: "uikit" | "diagnostics", registered: Set<string>): ModuleCapabilityStatus {
  const required = contracts.filter(contract => contract.provider === provider).map(contract => contract.action);
  const missing = required.filter(action => !registered.has(action));
  const count = required.length - missing.length;
  return { status: count === required.length ? "registered" : count === 0 ? "not_registered" : "partial", registeredCount: count, requiredCount: required.length, missingActions: missing };
}
function summarizeSchema(results: readonly ActionSchemaCompatibility[]): SchemaCompatibility {
  if (results.some(result => result.status === "unknown")) return "unknown";
  if (results.some(result => result.status === "breaking")) return "breaking";
  if (results.some(result => result.status === "additive")) return "additive";
  return "exact";
}
function isObject(value: unknown): value is HelpCommand { return typeof value === "object" && value !== null && !Array.isArray(value); }

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
