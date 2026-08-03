/**
 * CLI 命令行为层：接收已解析的参数，调用 runtime/probe，维持 stdout/stderr/退出码的
 * 稳定合同。
 *
 * 上游：`application.ts` 组装好依赖后调用 `executeCLICommand`；下游：`driverRuntime`
 * 负责实际请求。本层不做网络、不解析 argv，只做三件事：
 * 1. 按命令名分发到 runInit/runDoctor/runCall/mcp 分支；
 * 2. 把业务结果输出到 stdout、错误输出到 stderr（两条通道永不混用）；
 * 3. 把错误分类映射为退出码 0/1/2/3（`exitCodeForError`）。
 *
 * 设计约束：所有命令实现只通过 `CLICommandContext` 拿依赖，不读进程全局、
 * 不自建网络对象——因此可以在不启动真实进程的情况下测试。
 */
import { readFile } from "node:fs/promises";
import { DEVICE_ACTION_CONTRACTS } from "../../generated/deviceActionContracts.js";
import { startMCPStdioServer } from "../mcp/server.js";
import type { CapabilityProbe } from "../../runtime/capabilityProbe.js";
import type { DriverError } from "../../runtime/driverErrors.js";
import type { DriverRuntime, InvocationPolicy } from "../../runtime/driverRuntime.js";
import {
  HostOperationInputValidationError,
  validateHostOperationInput
} from "../../runtime/hostOperationInput.js";
import { defaultHostLogger, type HostLogger } from "../../runtime/hostLogger.js";
import type { JSONObject } from "../../types.js";
import type { WorkflowRunner } from "../../workflows/workflowRunner.js";
import { CLIConfigError, type CLIConfig, type ConfigFileSystem, asJSONObject, initCLIConfig } from "./config.js";
import { printError, printHuman, printInvocationFailure, printInvocationSuccess, printJSON, type ArtifactWriter, type CLIOutput } from "./output.js";

/**
 * 固定 CLI 命令白名单。
 * 新增命令必须同时更新本类型、`arguments.ts` 的命令校验和 `executeCLICommand` 的 switch。
 */
export type CLICommandName = "init" | "doctor" | "call" | "mcp";

/**
 * 已解析的 `call` 专属参数（来自 arguments.ts 的解析结果）。
 */
export interface CallCommandOptions {
  /** 要调用的 action 名（如 "ping"、"ui.tap"）；执行前会 trim 并拒绝空值，
   * 是否为已知 action 由生成合同或 App help 决定。 */
  readonly action: string;
  /** action 的 JSON data：内联 JSON 文本，或以 `@` 开头的 UTF-8 JSON 文件路径。 */
  readonly data?: string;
  /** 截图等 image artifact 的落盘路径；结构化结果仍照常输出到 stdout。 */
  readonly output?: string;
}

/**
 * commands 模块的全部依赖（依赖注入插头），每个字段均可由测试替换。
 */
export interface CLICommandContext {
  /** 已合并 CLI/环境变量/文件/默认值的不可变配置。 */
  readonly config: CLIConfig;
  /** 输出通道：业务结果固定走 stdout，错误结果固定走 stderr。 */
  readonly output: CLIOutput;
  /** 只暴露 `invoke` 一个方法，防止命令层绕过 runtime 的错误归一化直接发请求。 */
  readonly runtime: Pick<DriverRuntime, "invoke">;
  /** doctor 检查与未知 action 策略查询的唯一来源。 */
  readonly capabilityProbe: Pick<CapabilityProbe, "doctor" | "invocationPolicy">;
  /** host workflow（wait_and_inspect 等）的执行入口；普通 CLI call 不直接调用。 */
  readonly workflowRunner: Pick<WorkflowRunner, "run">;
  /** `mcp` 命令才使用的 stdio server 启动函数；测试注入 fake 不占用真实 stdio。 */
  readonly startMCP?: () => Promise<void>;
  /** `call --data @file` 的读文件边界；默认真实 fs。 */
  readonly readFile?: (path: string) => Promise<string>;
  /** 截图落盘边界；注入后可验证内容而不写磁盘。 */
  readonly writeArtifact?: ArtifactWriter;
  /** `init` 的文件系统边界，用于验证原子写入。 */
  readonly fileSystem?: ConfigFileSystem;
  /** `init` 解析环境覆盖值时使用；默认当前进程环境。 */
  readonly env?: NodeJS.ProcessEnv;
  /** `doctor` 的紧凑文本输出模式（--human）；默认输出完整 JSON 报告。 */
  readonly human?: boolean;
  /** 仅用于 doctor 的最低版本检查，不影响当前 Node runtime。 */
  readonly nodeVersion?: string;
  /** 从 CLI SIGINT 传入 probe/runtime 的取消信号（call 命令由 Ctrl-C 触发）。 */
  readonly signal?: AbortSignal;
  /** 结构化日志器；默认固定写 stderr，与业务输出通道分离。 */
  readonly logger?: HostLogger;
}

/**
 * 固定退出码合同（CLI 的「公共 API」，脚本据此判断结果，不能随意变更）：
 * - 0 success：成功；
 * - 1 appFailure：App 业务失败 / workflow 失败 / 合同不兼容（请求已到达并被理解）；
 * - 2 configError：配置、参数或 Node 版本错误；
 * - 3 transportFailure：transport/HTTP/protocol/artifact 失败（结果不可信）。
 */
export const EXIT_CODES = Object.freeze({ success: 0, appFailure: 1, configError: 2, transportFailure: 3 });

/** 生成合同里声明的全部 action 名（构建时固化）；用于「已知 action 免探测」判断。 */
const GENERATED_ACTIONS: ReadonlySet<string> = new Set(DEVICE_ACTION_CONTRACTS.map(contract => contract.action));

/**
 * 执行一个已解析的 CLI 命令，负责分发与 stdout/stderr/退出码的稳定投影。
 *
 * 错误处理分两层：`CLIConfigError`（配置/参数问题）→ 退出码 2；**其他所有异常**
 * （包括未预料到的 bug）→ 退出码 3——保证 CLI 永远返回一个退出码，脚本不会拿到
 * undefined。logger 只记录命令名、退出码、错误类型，绝不记录 argv/data/响应正文。
 *
 * @param command 命令名（白名单四选一）。
 * @param context 依赖集合（config/output/runtime/probe 等）。
 * @param options 仅 `call` 使用（action/data/output）；其他命令保留默认空 action。
 * @returns 退出码：0/1/2/3。
 *   示例：App 离线时 `executeCLICommand("call", ctx, {action:"ping"})` → 3。
 */
export async function executeCLICommand(
  command: CLICommandName,
  context: CLICommandContext,
  options: CallCommandOptions = { action: "" }
): Promise<number> {
  const logger = context.logger ?? defaultHostLogger;
  logger.emit("info", "cli.command.start", { command });
  try {
    let exitCode: number;
    // switch 是固定命令白名单；新增命令必须同时更新 CLICommandName 和 argv parser。
    switch (command) {
      case "init":
        exitCode = await runInit(context);
        break;
      case "doctor":
        exitCode = await runDoctor(context);
        break;
      case "call":
        exitCode = await runCall(options, context);
        break;
      case "mcp":
        // stdio server 的 Promise 在连接建立后返回；进程生命周期随后由 MCP transport 持有。
        await (context.startMCP ?? (() => startMCPStdioServer({
          runtime: context.runtime,
          capabilityProbe: context.capabilityProbe as CapabilityProbe,
          workflowRunner: context.workflowRunner as WorkflowRunner,
          logger
        })) )();
        exitCode = EXIT_CODES.success;
        break;
    }
    logger.emit(exitCode === EXIT_CODES.success ? "info" : "warn", exitCode === EXIT_CODES.success ? "cli.command.complete" : "cli.command.error", {
      command,
      exitCode
    });
    return exitCode;
  } catch (error) {
    if (error instanceof CLIConfigError) {
      printError(context.output, error);
      logger.emit("warn", "cli.command.error", {
        command,
        exitCode: EXIT_CODES.configError,
        errorType: error.name
      });
      return EXIT_CODES.configError;
    }
    printError(context.output, error instanceof Error ? error : String(error));
    logger.emit("error", "cli.command.error", {
      command,
      exitCode: EXIT_CODES.transportFailure,
      errorType: error instanceof Error ? error.name : typeof error
    });
    return EXIT_CODES.transportFailure;
  }
}

/**
 * `iosdriver init` 的实现：创建/补全配置文件，输出 configPath 与 configChanged。
 *
 * 边界：不探测 App、不注册 MCP 客户端——只碰配置文件。
 *
 * @param context 依赖集合。
 * @returns 固定 0（成功）；文件系统错误由上层 catch 映射（非 CLIConfigError → 3）。
 *   示例：首次执行 → stdout 输出 {"configChanged":true}，返回 0。
 */
async function runInit(context: CLICommandContext): Promise<number> {
  const result = await initCLIConfig({
    configPath: context.config.configPath,
    baseURL: context.config.baseURL,
    requestTimeoutMs: context.config.requestTimeoutMs
  }, context.env ?? process.env, context.fileSystem);
  printJSON(context.output, {
    configPath: result.config.configPath,
    configChanged: result.configChanged
  });
  return EXIT_CODES.success;
}

/**
 * `iosdriver doctor` 的实现：逐项体检（Node 版本、连接、ping/help、合同一致性）
 * 并输出多维报告，返回整体健康度对应的退出码。
 *
 * 退出码判定顺序（自上而下短路）：
 * - Node < 20 → 2（配置类）；
 * - ping/help 的底层错误存在 → `exitCodeForError`（1 或 3）；
 * - 连接/ping/help 任一不达标 → 3（transport/协议失败）；
 * - 协议版本不匹配 → 3（host 无法可靠解释响应）；
 * - 合同不 exact → 1（两端功能集合不一致）；
 * - 全部通过 → 0。
 *
 * @param context 依赖集合（含 capabilityProbe）。
 * @returns 退出码 0/1/2/3。
 *   示例：App 离线 → node ok、endpoint=unreachable，返回 3。
 */
async function runDoctor(context: CLICommandContext): Promise<number> {
  const nodeVersion = context.nodeVersion ?? process.versions.node;
  const nodeOK = minimumNodeVersion(nodeVersion, 20);
  const report = await context.capabilityProbe.doctor(
    context.signal === undefined ? {} : { signal: context.signal }
  );
  const result = {
    node: { version: nodeVersion, status: nodeOK ? "ok" : "unsupported" },
    config: { baseURL: context.config.baseURL, requestTimeoutMs: context.config.requestTimeoutMs },
    endpoint: report.connection,
    ping: report.ping,
    help: report.help,
    actions: report.actions,
    modules: report.modules,
    contractCompatibility: report.contractCompatibility,
    ...(report.metadata === undefined ? {} : { metadata: report.metadata })
  };
  if (context.human) {
    printHuman(context.output, `Node ${nodeVersion}: ${nodeOK ? "ok" : "unsupported"}`);
    printHuman(context.output, `Endpoint: ${report.connection}; ping=${report.ping.status}; help=${report.help.status}; contract=${report.contractCompatibility}`);
  } else {
    printJSON(context.output, result);
  }
  if (!nodeOK) return EXIT_CODES.configError;
  // 优先保留 probe 已归一化的底层错误来源，避免把 App envelope 失败误报为断网。
  const probeError = report.ping.error ?? report.help.error;
  if (probeError !== undefined) {
    return exitCodeForError(probeError);
  }
  if (report.connection !== "reachable" || report.ping.status !== "ok" || report.help.status !== "available") {
    return EXIT_CODES.transportFailure;
  }
  if (report.metadata?.protocolVersionMatches === false) {
    return EXIT_CODES.transportFailure;
  }
  if (report.contractCompatibility !== "exact") {
    return EXIT_CODES.appFailure;
  }
  return EXIT_CODES.success;
}

/**
 * `iosdriver call <action>` 的实现：校验入参 → 查策略 → 调用 runtime → 渲染结果。
 *
 * 执行链：
 * 1. action trim 后非空（否则 CLIConfigError → 2）；
 * 2. `parseData` 解析 --data（内联 JSON 或 @file）；
 * 3. `validateHostOperationInput` 校验包装层字段（action 字符串、data 对象）；
 *    —— action 自身的业务字段由 App 的 typed input factory 校验，host 不复制 parser；
 * 4. `policyForAction` 取超时/重试策略（已知 action 零探测）；
 * 5. `runtime.invoke` 发请求并归一化结果；
 * 6. 成功 → stdout 输出（截图按 --output 落盘），返回 0；失败 → stderr 输出，
 *    按错误来源返回 1 或 3。
 *
 * @param options 已解析的 call 参数（action/data/output）。
 * @param context 依赖集合。
 * @returns 退出码 0/1/2/3。
 */
async function runCall(options: CallCommandOptions, context: CLICommandContext): Promise<number> {
  const action = options.action.trim();
  if (action.length === 0) throw new CLIConfigError("call 需要非空 action");
  const data = await parseData(options.data, context.readFile ?? (path => readFile(path, "utf8")));
  let operationInput: JSONObject;
  try {
    operationInput = validateHostOperationInput("call_action", { action, data });
  } catch (error) {
    if (error instanceof HostOperationInputValidationError) throw new CLIConfigError(error.message);
    throw error;
  }
  const policy = await policyForAction(operationInput.action as string, context.capabilityProbe, context.signal);
  const result = await context.runtime.invoke(
    operationInput.action as string,
    operationInput.data as JSONObject,
    {
      ...(context.signal === undefined ? {} : { signal: context.signal }),
      ...(policy === undefined ? {} : { policy })
    }
  );
  if (result.ok) {
    await printInvocationSuccess(context.output, result, options.output, context.writeArtifact);
    return EXIT_CODES.success;
  }
  printInvocationFailure(context.output, result);
  return exitCodeForError(result.error);
}

/**
 * 查询 action 的调用策略（幂等性/超时级别），供 runtime 决定重试与超时。
 *
 * 已知 action（生成合同里有）：直接返回 undefined——runtime 内部会从合同元数据
 * 自行查策略，**不需要**每次 call 都发 ping/help 请求；
 * 未知 action（App 扩展的）：必须先执行一次 doctor（ping+help），从 App 的 help
 * 声明中取策略；help 不可信时返回 undefined，runtime 按保守策略（不自动重试）。
 *
 * @param action action 名。
 * @param capabilityProbe 能力探测对象。
 * @param signal 取消信号（透传给 doctor）。
 * @returns 严格校验过的策略；未知/非法/不可信时 undefined。
 */
async function policyForAction(
  action: string,
  capabilityProbe: Pick<CapabilityProbe, "doctor" | "invocationPolicy">,
  signal: AbortSignal | undefined
): Promise<InvocationPolicy | undefined> {
  // canonical action 的策略已经随构建产物固定，无需每次 call 都额外发送 ping/help。
  if (GENERATED_ACTIONS.has(action)) return undefined;
  await capabilityProbe.doctor(signal === undefined ? {} : { signal });
  return capabilityProbe.invocationPolicy(action);
}

/**
 * 解析 `call --data` 的三种输入：无 → {}；`@path` → 读文件；否则按 JSON 文本解析。
 *
 * 安全约束：@path 的文件内容与 JSON 原文**都不会**进入错误消息——用户可能传
 * `--data '{"token":"secret"}'`，报错时不能把 secret 打到终端，也不能让大型
 * payload 污染终端。这里只确认顶层是对象；action 自身字段由 App 端校验。
 *
 * @param raw --data 的原始值；undefined 表示未传。
 * @param read 读文件函数（默认 node:fs/promises 的 readFile）。
 * @returns JSON 对象（空对象或用户传入的内容）。
 * @throws {CLIConfigError} 文件读不到、JSON 非法、顶层非对象时抛出。
 *   示例：raw='@screen.json' → 读文件内容并解析；raw='{"a":1}' → 解析为 {a:1}。
 */
export async function parseData(raw: string | undefined, read: (path: string) => Promise<string>): Promise<JSONObject> {
  if (raw === undefined) return {};
  let source: string;
  if (raw.startsWith("@")) {
    try { source = await read(raw.slice(1)); }
    catch { throw new CLIConfigError(`无法读取 data 文件: ${raw.slice(1)}`); }
  } else {
    source = raw;
  }
  let parsed: unknown;
  try { parsed = JSON.parse(source); } catch { throw new CLIConfigError("call --data 必须是合法 JSON"); }
  return asJSONObject(parsed);
}

/**
 * 把归一化错误（DriverError）的 source 映射为退出码——整个 CLI 的错误分层核心。
 *
 * 分层语义：
 * - `config` → 2：本地输入问题；
 * - `transport/http/protocol/artifact` → 3：请求未到达或响应不可信；
 * - `appEnvelope/workflow` → 1：请求已到达并被 App 理解，但业务拒绝。
 *
 * 第 1 与第 3 的区别是本质性的：业务失败是 App 的正常工作（如非法坐标），
 * 网络失败是基础设施问题——两者绝不混为一种退出码。
 *
 * @param error 归一化错误（来自 runtime.invoke 的结果）。
 * @returns 退出码 1/2/3。
 *   示例：source="transport" → 3；source="appEnvelope" → 1。
 */
export function exitCodeForError(error: DriverError): number {
  if (error.source === "config") return EXIT_CODES.configError;
  if (error.source === "transport" || error.source === "http" || error.source === "protocol" || error.source === "artifact") return EXIT_CODES.transportFailure;
  return EXIT_CODES.appFailure;
}

/**
 * 检查 Node 主版本是否不低于最低要求（doctor 用）。
 *
 * @param version Node 版本字符串，如 "24.16.0"。
 * @param minimumMajor 最低主版本号，如 20。
 * @returns true=主版本 >= 最低要求。
 *   示例："24.16.0" 与 20 → true；"18.3.0" 与 20 → false。
 */
function minimumNodeVersion(version: string, minimumMajor: number): boolean {
  const major = Number.parseInt(version.split(".")[0] ?? "0", 10);
  return Number.isFinite(major) && major >= minimumMajor;
}
