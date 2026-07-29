/**
 * CLI 命令的行为层。
 *
 * `arguments.ts` 负责 argv 解析，`application.ts` 负责依赖组装；这里接收已经解析的
 * 值，调用 runtime/probe，并维持 stdout、stderr 与退出码的稳定合同。这样同一命令
 * 可以在不启动真实进程的情况下测试，且不会把业务 JSON 与诊断日志混在同一通道。
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

/** 固定 CLI 命令集合。 */
export type CLICommandName = "init" | "doctor" | "call" | "mcp";

/** 已解析的 call 参数；data 可以是 JSON 文本或 @file。 */
export interface CallCommandOptions {
  /** 在执行前会 trim 并拒绝空值；是否为已知 action 由合同或 App help 决定。 */
  readonly action: string;
  /** 内联 JSON，或以 `@` 开头的 UTF-8 JSON 文件路径。 */
  readonly data?: string;
  /** 仅 image artifact 会写入此路径，结构化结果仍照常输出到 stdout。 */
  readonly output?: string;
}

/** commands 模块的全部依赖，均可替换为测试实现。 */
export interface CLICommandContext {
  /** 已合并 CLI、环境变量、文件和默认值的不可变配置。 */
  readonly config: CLIConfig;
  /** 业务结果固定走 stdout，错误结果固定走 stderr。 */
  readonly output: CLIOutput;
  /** 只暴露 invoke，防止命令层绕过 runtime 的错误归一化。 */
  readonly runtime: Pick<DriverRuntime, "invoke">;
  /** doctor 与未知 action 策略的唯一来源。 */
  readonly capabilityProbe: Pick<CapabilityProbe, "doctor" | "invocationPolicy">;
  /** host workflow 的执行入口；当前普通 CLI call 不直接调用它。 */
  readonly workflowRunner: Pick<WorkflowRunner, "run">;
  /** `mcp` 命令才需要；测试注入后不会占用真实 stdio。 */
  readonly startMCP?: () => Promise<void>;
  /** `call --data @file` 的 UTF-8 读取边界。 */
  readonly readFile?: (path: string) => Promise<string>;
  /** 截图落盘边界；注入后可验证内容而不写磁盘。 */
  readonly writeArtifact?: ArtifactWriter;
  /** `init` 的文件系统边界，用于验证原子写入。 */
  readonly fileSystem?: ConfigFileSystem;
  /** `init` 解析环境覆盖值时使用，默认取当前进程环境。 */
  readonly env?: NodeJS.ProcessEnv;
  /** `doctor` 的紧凑文本模式；默认输出完整 JSON 报告。 */
  readonly human?: boolean;
  /** 仅用于 doctor 的最低版本检查，不影响当前 Node runtime。 */
  readonly nodeVersion?: string;
  /** 从 CLI SIGINT 传入 probe/runtime 的取消信号。 */
  readonly signal?: AbortSignal;
  /** CLI 命令 logger；默认固定写 stderr，与业务输出通道分离。 */
  readonly logger?: HostLogger;
}

/** 固定退出码：成功、业务/workflow、配置、transport/HTTP/protocol。 */
export const EXIT_CODES = Object.freeze({ success: 0, appFailure: 1, configError: 2, transportFailure: 3 });

const GENERATED_ACTIONS: ReadonlySet<string> = new Set(DEVICE_ACTION_CONTRACTS.map(contract => contract.action));

/**
 * 执行一个已解析的 CLI 命令并负责 stdout/stderr 分离。
 *
 * 预期的参数/配置错误返回 2，已归一化调用失败由各命令映射为 1 或 3；只有命令实现
 * 未分类抛出的异常统一视为 host/transport 失败并返回 3。logger 只记录命令名、退出码
 * 和错误类型，不记录 argv、data 或响应正文。
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
 * 初始化 iOSDriver App 连接配置。
 *
 * 该命令只创建/补全配置文件，不探测 App，也不注册 MCP 客户端。输出中的
 * `configChanged` 可让安装脚本区分首次写入与幂等执行。
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
 * 执行 endpoint、ping/help 和合同 bundle 一致性检查，不管理任何外部进程。
 *
 * 协议版本不匹配意味着 host 无法可靠解释响应，归为 transport/protocol 退出码 3；
 * 合同 hash/version 不精确则说明两端功能集合不一致，归为业务兼容失败退出码 1。
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
 * 解析 data、调用 DriverRuntime，并按 artifact output 约定渲染结果。
 *
 * 已生成合同中的 action 可直接使用本地重试/超时元数据；扩展 action 必须先执行一次
 * doctor，从 App help 获取并严格校验策略。help 不可信时仍允许调用，但 runtime 使用
 * 保守策略，不自动重试未知 action。
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
 * 读取并校验 `call --data`。
 *
 * `@path` 的文件内容和 JSON 原文都不会进入错误消息，既避免泄露业务数据，也防止大型
 * payload 污染终端。这里只确认顶层是对象，action 自身字段仍由 App 的 typed input
 * factory 负责校验，host 不复制 Swift 业务 parser。
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
 * 将 runtime 错误来源映射为稳定退出码。
 *
 * App envelope 与 workflow 失败说明请求已到达并被理解，返回 1；连接、HTTP、协议和
 * artifact 失败会让调用方无法信任业务结果，返回 3；本地输入配置问题返回 2。
 */
export function exitCodeForError(error: DriverError): number {
  if (error.source === "config") return EXIT_CODES.configError;
  if (error.source === "transport" || error.source === "http" || error.source === "protocol" || error.source === "artifact") return EXIT_CODES.transportFailure;
  return EXIT_CODES.appFailure;
}

function minimumNodeVersion(version: string, minimumMajor: number): boolean {
  const major = Number.parseInt(version.split(".")[0] ?? "0", 10);
  return Number.isFinite(major) && major >= minimumMajor;
}
