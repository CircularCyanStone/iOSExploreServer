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
import { DEVICE_ACTION_CONTRACTS } from "../../../generated/deviceActionContracts.js";
import { startMCPStdioServer } from "../../mcp/server.js";
import type { CapabilityProbe } from "../../../runtime/capabilityProbe.js";
import type { InvocationPolicy } from "../../../runtime/driverRuntime.js";
import {
  HostOperationInputValidationError,
  validateHostOperationInput
} from "../../../runtime/hostOperationInput.js";
import { defaultHostLogger } from "../../../runtime/hostLogger.js";
import type { JSONObject } from "../../../types.js";
import type { WorkflowRunner } from "../../../workflows/workflowRunner.js";
import { CLIConfigError, initCLIConfig } from "../config.js";
import { parseData, exitCodeForError, minimumNodeVersion } from "./commandSupport.js";
import {
  EXIT_CODES,
  type CallCommandOptions,
  type CLICommandContext,
  type CLICommandName
} from "./commandTypes.js";
import { printError, printHuman, printInvocationFailure, printInvocationSuccess, printJSON } from "../output.js";

export type { CallCommandOptions, CLICommandContext, CLICommandName } from "./commandTypes.js";
export { EXIT_CODES } from "./commandTypes.js";
export { parseData, exitCodeForError } from "./commandSupport.js";

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
