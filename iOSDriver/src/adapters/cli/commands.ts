import { readFile } from "node:fs/promises";
import { startMCPStdioServer } from "../mcp/server.js";
import type { CapabilityProbe } from "../../runtime/capabilityProbe.js";
import type { DriverError } from "../../runtime/driverErrors.js";
import type { DriverRuntime } from "../../runtime/driverRuntime.js";
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
  readonly action: string;
  readonly data?: string;
  readonly output?: string;
}

/** commands 模块的全部依赖，均可替换为测试实现。 */
export interface CLICommandContext {
  readonly config: CLIConfig;
  readonly output: CLIOutput;
  readonly runtime: Pick<DriverRuntime, "invoke">;
  readonly capabilityProbe: Pick<CapabilityProbe, "doctor">;
  readonly workflowRunner: Pick<WorkflowRunner, "run">;
  readonly startMCP?: () => Promise<void>;
  readonly readFile?: (path: string) => Promise<string>;
  readonly writeArtifact?: ArtifactWriter;
  readonly fileSystem?: ConfigFileSystem;
  readonly env?: NodeJS.ProcessEnv;
  readonly human?: boolean;
  readonly nodeVersion?: string;
  readonly signal?: AbortSignal;
  /** CLI 命令 logger；默认固定写 stderr，与业务输出通道分离。 */
  readonly logger?: HostLogger;
}

/** 固定退出码：成功、业务/workflow、配置、transport/HTTP/protocol。 */
export const EXIT_CODES = Object.freeze({ success: 0, appFailure: 1, configError: 2, transportFailure: 3 });

/** 执行一个已解析的 CLI 命令并负责 stdout/stderr 分离。 */
export async function executeCLICommand(
  command: CLICommandName,
  context: CLICommandContext,
  options: CallCommandOptions = { action: "" }
): Promise<number> {
  const logger = context.logger ?? defaultHostLogger;
  logger.emit("info", "cli.command.start", { command });
  try {
    let exitCode: number;
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

/** 初始化配置并打印可复制的 MCP 配置片段。 */
async function runInit(context: CLICommandContext): Promise<number> {
  const result = await initCLIConfig({
    configPath: context.config.configPath,
    baseURL: context.config.baseURL,
    requestTimeoutMs: context.config.requestTimeoutMs
  }, context.env ?? process.env, context.fileSystem);
  printJSON(context.output, {
    configPath: result.config.configPath,
    configChanged: result.configChanged,
    mcp: { command: "iosdriver", args: ["mcp"] }
  });
  return EXIT_CODES.success;
}

/** 执行 endpoint、ping/help 和合同 bundle 一致性检查，不管理任何外部进程。 */
async function runDoctor(context: CLICommandContext): Promise<number> {
  const nodeVersion = context.nodeVersion ?? process.versions.node;
  const nodeOK = minimumNodeVersion(nodeVersion, 20);
  const report = await context.capabilityProbe.doctor();
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

/** 解析 data、调用 DriverRuntime，并按 artifact output 约定渲染结果。 */
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
  const result = await context.runtime.invoke(
    operationInput.action as string,
    operationInput.data as JSONObject,
    context.signal === undefined ? {} : { signal: context.signal }
  );
  if (result.ok) {
    await printInvocationSuccess(context.output, result, options.output, context.writeArtifact);
    return EXIT_CODES.success;
  }
  printInvocationFailure(context.output, result);
  return exitCodeForError(result.error);
}

/** 读取 JSON data；`@path` 形式只读取文件，不把原文写入 stderr。 */
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

/** 将 runtime 错误映射为 Task 10 固定退出码。 */
export function exitCodeForError(error: DriverError): number {
  if (error.source === "config") return EXIT_CODES.configError;
  if (error.source === "transport" || error.source === "http" || error.source === "protocol" || error.source === "artifact") return EXIT_CODES.transportFailure;
  return EXIT_CODES.appFailure;
}

function minimumNodeVersion(version: string, minimumMajor: number): boolean {
  const major = Number.parseInt(version.split(".")[0] ?? "0", 10);
  return Number.isFinite(major) && major >= minimumMajor;
}
