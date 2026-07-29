/**
 * iOSDriver CLI 的应用编排模块。
 *
 * `main.ts` 只处理 Node 进程入口；本模块在 argv parser、配置、runtime 与命令行为层之间
 * 编排一次 CLI 调用。它不直接终止进程，而是返回稳定退出码，便于入口和测试共同调用。
 */
import { homedir } from "node:os";
import { resolve } from "node:path";
import { CapabilityProbe } from "../../runtime/capabilityProbe.js";
import { DriverRuntime } from "../../runtime/driverRuntime.js";
import { defaultHostLogger, type HostLogger } from "../../runtime/hostLogger.js";
import { HttpActionTransport } from "../../runtime/httpActionTransport.js";
import {
  setupMCPClient as defaultSetupMCPClient,
  type MCPClientSetupInput,
  type MCPClientSetupResult
} from "../../registration/mcpClientSetup.js";
import { WorkflowRunner } from "../../workflows/workflowRunner.js";
import { startMCPStdioServer } from "../mcp/server.js";
import {
  knownCLICommand,
  parseCLIArguments,
  type MCPSetupArguments,
  type OperationalArguments
} from "./arguments.js";
import { executeCLICommand, EXIT_CODES, type CLICommandContext } from "./commands.js";
import { CLIConfigError, configPathFor, resolveCLIConfig } from "./config.js";
import { processOutput, type CLIOutput } from "./output.js";

/** `runCLI` 可注入的进程与 IO 依赖；生产入口只需要提供 `cliEntryPath`。 */
export interface CLIApplicationDependencies {
  /** 当前可执行 CLI JS 文件，用于生成 MCP 客户端的启动参数。 */
  readonly cliEntryPath: string;
  /** stdout/stderr 写入点；测试注入后不会污染真实标准流。 */
  readonly output?: CLIOutput;
  /** 配置解析和 MCP 注册读取的环境变量集合。 */
  readonly env?: NodeJS.ProcessEnv;
  /** `doctor` 最低版本检查使用的版本字符串。 */
  readonly nodeVersion?: string;
  /** 贯穿 CLI、runtime、workflow 和 MCP 的结构化日志器。 */
  readonly logger?: HostLogger;
  /** 相对 `--config` 与 `--project-dir` 的解析基准。 */
  readonly cwd?: string;
  /** 默认配置路径及 user scope 客户端配置的用户目录。 */
  readonly homeDir?: string;
  /** MCP 客户端注册最终调用的 Node 可执行文件。 */
  readonly nodePath?: string;
  /** MCP 注册写入实现；测试可替换以避免修改真实客户端配置。 */
  readonly setupMCPClient?: (input: MCPClientSetupInput) => Promise<MCPClientSetupResult>;
}

/** 解析默认值后的进程环境，后续方法不再直接读取可变全局状态。 */
interface ResolvedApplicationDependencies {
  readonly cliEntryPath: string;
  readonly output: CLIOutput;
  readonly env: NodeJS.ProcessEnv;
  readonly nodeVersion?: string;
  readonly logger: HostLogger;
  readonly cwd: string;
  readonly homeDir: string;
  readonly nodePath: string;
  readonly setupMCPClient: (input: MCPClientSetupInput) => Promise<MCPClientSetupResult>;
}

/**
 * 执行一次完整 CLI 调用并返回退出码。
 *
 * 执行阶段固定为：解析 argv；无网络地处理 `mcp setup`，或解析 App 配置并组装 runtime；
 * 将已解析命令交给 `executeCLICommand`；最后清理本次调用安装的 SIGINT listener。
 */
export async function runCLI(
  argv: readonly string[],
  dependencies: CLIApplicationDependencies
): Promise<number> {
  const resolved = resolveApplicationDependencies(dependencies);
  const controller = new AbortController();
  const onSIGINT = () => controller.abort(new Error("SIGINT"));
  let handlesSIGINT = false;

  try {
    const parsed = parseCLIArguments(argv);

    // setup 只修改 host 侧客户端配置，不需要 App 可达，也不应读取 App 连接配置。
    if (parsed.kind === "mcpSetup") return await executeMCPSetup(parsed, resolved);

    // 仅一次性 HTTP call 接管 Ctrl-C；stdio MCP transport 自己管理长生命周期。
    handlesSIGINT = parsed.command === "call";
    if (handlesSIGINT) process.once("SIGINT", onSIGINT);

    return await executeOperationalCommand(parsed, resolved, controller.signal);
  } catch (error) {
    return reportStartupError(error, argv, resolved);
  } finally {
    if (handlesSIGINT) process.off("SIGINT", onSIGINT);
  }
}

/**
 * 一次性解析所有默认进程依赖。
 *
 * 集中读取 `process` 和用户目录可以让后续编排只依赖稳定值，也让测试无需替换全局对象。
 */
function resolveApplicationDependencies(
  dependencies: CLIApplicationDependencies
): ResolvedApplicationDependencies {
  return {
    cliEntryPath: dependencies.cliEntryPath,
    output: dependencies.output ?? processOutput,
    env: dependencies.env ?? process.env,
    ...(dependencies.nodeVersion === undefined ? {} : { nodeVersion: dependencies.nodeVersion }),
    logger: dependencies.logger ?? defaultHostLogger,
    cwd: dependencies.cwd ?? process.cwd(),
    homeDir: dependencies.homeDir ?? homedir(),
    nodePath: dependencies.nodePath ?? process.execPath,
    setupMCPClient: dependencies.setupMCPClient ?? defaultSetupMCPClient
  };
}

/**
 * 执行 `mcp setup` 的 host-only 路径。
 *
 * 相对路径在这里统一转为绝对路径，确保写入客户端配置的启动命令不依赖客户端将来的
 * 工作目录。该路径不会创建 transport、probe 或 workflow runner。
 */
async function executeMCPSetup(
  parsed: MCPSetupArguments,
  dependencies: ResolvedApplicationDependencies
): Promise<number> {
  dependencies.logger.emit("info", "cli.command.start", {
    command: "mcp.setup",
    client: parsed.client
  });

  const rawConfigPath = parsed.configPath ?? configPathFor(dependencies.env, dependencies.homeDir);
  const configPath = resolve(dependencies.cwd, rawConfigPath);
  const projectDir = resolve(dependencies.cwd, parsed.projectDir ?? ".");
  const result = await dependencies.setupMCPClient({
    client: parsed.client,
    ...(parsed.scope === undefined ? {} : { scope: parsed.scope }),
    dryRun: parsed.dryRun,
    force: parsed.force,
    cwd: projectDir,
    homeDir: dependencies.homeDir,
    env: dependencies.env,
    launch: {
      command: dependencies.nodePath,
      args: [dependencies.cliEntryPath, "mcp", "--config", configPath]
    }
  });

  dependencies.output.stdout(`${JSON.stringify(result, null, 2)}\n`);
  dependencies.logger.emit("info", "cli.command.complete", {
    command: "mcp.setup",
    client: parsed.client,
    status: result.status,
    exitCode: EXIT_CODES.success
  });
  return EXIT_CODES.success;
}

/**
 * 构造连接 App 所需的共享对象并执行普通命令。
 *
 * transport、runtime、probe 与 workflow runner 每次调用只创建一份；同一组实例也传给
 * MCP stdio server，避免 CLI 层和 MCP adapter 各自持有状态不一致的连接对象。
 */
async function executeOperationalCommand(
  parsed: OperationalArguments,
  dependencies: ResolvedApplicationDependencies,
  signal: AbortSignal
): Promise<number> {
  const config = await resolveCLIConfig(parsed.config, dependencies.env);
  const runtime = new DriverRuntime({
    transport: new HttpActionTransport(config.baseURL, {
      ...(config.authToken === undefined ? {} : { authToken: config.authToken })
    }),
    configuredRequestTimeoutMs: config.requestTimeoutMs,
    logger: dependencies.logger
  });
  const capabilityProbe = new CapabilityProbe(runtime, undefined, dependencies.logger);
  const workflowRunner = new WorkflowRunner({ runtime, logger: dependencies.logger });

  // context 是 commands 层的唯一依赖入口，命令实现无需读取进程全局或自行创建网络对象。
  const context: CLICommandContext = {
    config,
    output: dependencies.output,
    runtime,
    capabilityProbe,
    workflowRunner,
    ...(dependencies.nodeVersion === undefined ? {} : { nodeVersion: dependencies.nodeVersion }),
    env: dependencies.env,
    signal,
    logger: dependencies.logger,
    ...(parsed.human ? { human: true } : {})
  };

  if (parsed.command === "call") {
    return await executeCLICommand("call", context, parsed.call);
  }
  return await executeCLICommand(parsed.command, {
    ...context,
    startMCP: () => startMCPStdioServer({
      runtime,
      capabilityProbe,
      workflowRunner,
      logger: dependencies.logger
    })
  });
}

/**
 * 把 argv、配置读取和依赖组装阶段的异常投影为 exit code 2。
 *
 * 命令行为层有自己的错误分类；到达这里的异常都发生在命令启动阶段。日志只包含白名单
 * 命令名和错误类型，用户原始 argv 与 data 不会进入结构化日志。
 */
function reportStartupError(
  error: unknown,
  argv: readonly string[],
  dependencies: ResolvedApplicationDependencies
): number {
  dependencies.logger.emit("error", "cli.command.error", {
    command: knownCLICommand(argv),
    exitCode: EXIT_CODES.configError,
    errorType: error instanceof Error ? error.name : typeof error,
    phase: "startup"
  });
  const message = error instanceof CLIConfigError
    ? error.message
    : error instanceof Error
      ? error.message
      : String(error);
  dependencies.output.stderr(`${message}\n`);
  return EXIT_CODES.configError;
}
