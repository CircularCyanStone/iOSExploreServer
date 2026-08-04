/**
 * iOSDriver CLI 的应用编排层：一次命令行调用从 argv 到退出码的「指挥中心」。
 *
 * `main.ts` 只负责进程入口；本模块负责编排：解析 argv → 分流（`mcp setup` 走
 * host-only 路径，其余命令组装连接 App 的 runtime）→ 交给 `commands.ts` 执行 →
 * 返回稳定退出码。它不直接终止进程，因此入口和测试可以共同调用同一套逻辑。
 *
 * 典型调用链（`call ping`）：
 *   main(argv) → runCLI → parseCLIArguments → resolveCLIConfig
 *     → new HttpActionTransport → new DriverRuntime → new CapabilityProbe
 *     → executeCLICommand("call", context, {action}) → 退出码
 *
 * ## 路径的两个世界（读下面的字段注释前先建立这个概念）
 *
 * 本模块汇聚两类语义完全不同的路径，混在一起看必然头晕：
 *
 * - **Host 侧路径**（工具自身）：`cliEntryPath`/`nodePath`/`homeDir`/`configPath`，
 *   描述「iOSDriver 装在哪、它自己的配置在哪」，永远与目标 iOS 项目无关；
 * - **项目侧路径**（目标 iOS 项目）：`projectDir`（来自 `--project-dir`），
 *   指向要被接入 MCP 的 iOS 工程根目录，决定 `.mcp.json`/`.trae/mcp.json`
 *   写入哪里（真正的落点见 `registration/mcpClientSetup.ts` 的 `jsonConfigPath`）。
 *
 * 所有相对路径统一以 `dependencies.cwd`（默认 `process.cwd()`）为基准解析成绝对
 * 路径：因为写入客户端配置的启动命令将来可能在任意目录被执行，相对路径会失效。
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

/**
 * `runCLI` 可注入的进程与 IO 依赖。
 *
 * 所有字段都有默认实现（见 `resolveApplicationDependencies`），生产入口只需提供
 * 必填的 `cliEntryPath`；测试注入 fake 以替换真实 IO（不写 stdout、不读真实环境变量、
 * 不修改客户端配置）。
 *
 * 路径字段分两类（见文件头「路径的两个世界」）：【Host 侧】= 工具自身
 * （`cliEntryPath`/`nodePath`/`homeDir`）；【项目侧】= 目标 iOS 项目根目录
 * （由 `--project-dir` 解析出的 `projectDir`，见 `executeMCPSetup`）。
 */
export interface CLIApplicationDependencies {
  /** 【Host 侧】当前可执行 CLI JS 文件的绝对路径；用于生成 MCP 客户端启动命令（`mcp setup`）。 */
  readonly cliEntryPath: string;
  /** stdout/stderr 写入点；默认 `processOutput`（真实标准流），测试注入收集数组。 */
  readonly output?: CLIOutput;
  /** 配置解析与 MCP 注册读取的环境变量集合；默认 `process.env`。 */
  readonly env?: NodeJS.ProcessEnv;
  /** `doctor` 最低版本检查使用的 Node 版本字符串（如 "24.16.0"）；默认 `process.versions.node`。 */
  readonly nodeVersion?: string;
  /** 贯穿 CLI、runtime、workflow、MCP 的结构化日志器；默认写 stderr，测试可用 noop。 */
  readonly logger?: HostLogger;
  /** 【Host 侧】相对路径的解析基准（它只是锚点，不是项目目录本身）：
   * `--config` 与 `--project-dir` 都基于它解析；默认 `process.cwd()`。 */
  readonly cwd?: string;
  /** 【Host 侧】用户主目录；用于定位 iOSDriver 自身配置（`configPathFor`）
   * 与 claude user scope 的 `~/.claude.json`。默认 `os.homedir()`。 */
  readonly homeDir?: string;
  /** 【Host 侧】MCP 客户端注册命令使用的 Node 可执行文件；默认 `process.execPath`。 */
  readonly nodePath?: string;
  /** MCP 客户端注册的实现；默认真实写入客户端配置，测试注入 fake 以避免改本机配置。 */
  readonly setupMCPClient?: (input: MCPClientSetupInput) => Promise<MCPClientSetupResult>;
}

/**
 * 补齐默认值后的「全必填」依赖集合。
 *
 * 与 `CLIApplicationDependencies` 的差异：可选字段全部被 `resolveApplicationDependencies`
 * 填上默认实现变成必填，后续编排代码只面对「一定有值」的对象，不需要到处 `??`。
 * 各字段语义（含路径归属）与 `CLIApplicationDependencies` 一致，不再重复注释。
 */
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
 * 执行一次完整的 CLI 调用并返回退出码（不终止进程）。
 *
 * 执行顺序固定为：
 * 1. 解析 argv（`parseCLIArguments`）；
 * 2. `mcp setup` 走 host-only 路径（不组装 runtime、不碰 App）；
 * 3. 其他命令：解析配置 → 组装 transport/runtime/probe/workflow → 执行命令；
 * 4. 启动阶段的任何异常统一投影为退出码 2；
 * 5. finally 摘掉本次挂上的 SIGINT listener（防多次调用时监听器残留）。
 *
 * @param argv 命令行参数（不含 node 与脚本路径），如 `["call", "ping"]`。
 * @param dependencies 进程/IO 依赖；生产只需 `{ cliEntryPath }`。
 * @returns 退出码：0=成功，1=App 业务失败，2=配置/参数错误，3=网络/协议失败。
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
 * 把可选的注入依赖全部补齐默认值，返回「全必填」版本。
 *
 * 集中在这里读取 `process`/用户目录，让后续编排只依赖稳定值（不会被测试过程中的
 * 全局状态污染），也避免每个使用点各自写一遍 `?? 默认值`。
 *
 * @param dependencies 调用方传入的可选依赖（可能为空对象）。
 * @returns 每个字段都有值的依赖集合；`cliEntryPath` 必填、`nodeVersion` 保持可选。
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
 * 与普通命令路径的关键差异：这里**不创建** transport/runtime/probe/workflow——
 * setup 只修改 host 侧客户端配置文件，不连接 App，也不应被 App 配置问题连累。
 * 所有相对路径（`--config`/`--project-dir`）在此统一转为绝对路径，因为写入客户端
 * 配置的启动命令将来可能在任意工作目录被执行。
 *
 * @param parsed 已解析的 `mcp setup` 参数（client/scope/dryRun/force 等）。
 * @param dependencies 已补齐默认值的依赖集合。
 * @returns 固定 `EXIT_CODES.success`（0）；注册本身抛错则由 `runCLI` 的 catch 兜底。
 *   示例：`mcp setup codex --dry-run` → stdout 输出 status="planned" 的 JSON，返回 0。
 */
async function executeMCPSetup(
  parsed: MCPSetupArguments,
  dependencies: ResolvedApplicationDependencies
): Promise<number> {
  dependencies.logger.emit("info", "cli.command.start", {
    command: "mcp.setup",
    client: parsed.client
  });

  // 【Host 侧】iOSDriver 自身配置路径（baseURL/超时等，默认 ~/.config/iosdriver/config.json）。
  // 相对路径在此转绝对：它要写进客户端配置的启动命令 args，将来在任意目录被执行。
  const rawConfigPath = parsed.configPath ?? configPathFor(dependencies.env, dependencies.homeDir);
  const configPath = resolve(dependencies.cwd, rawConfigPath);
  // 【项目侧】目标 iOS 项目根目录：来自 `--project-dir`，缺省时就是当前工作目录。
  // 它决定 .mcp.json / .trae/mcp.json 写在哪里（见 mcpClientSetup.ts 的 jsonConfigPath）。
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
 * 构造连接 App 所需的共享对象，并执行普通命令（init/doctor/call/mcp）。
 *
 * 组装顺序即依赖顺序：`HttpActionTransport`（唯一网络边界）→ `DriverRuntime`（协议
 * 解释）→ `CapabilityProbe` / `WorkflowRunner`（都只依赖 runtime）。四个对象每次调用
 * 只创建一份；同一组实例也传给 MCP stdio server，保证 CLI 与 MCP 不持有状态不一致的
 * 连接对象。
 *
 * @param parsed 已解析的普通命令参数（kind="operational"）。
 * @param dependencies 已补齐默认值的依赖集合。
 * @param signal 取消信号（`call` 命令由 Ctrl-C 触发，其他命令始终不触发）。
 * @returns 命令执行后的退出码。
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
 * 把启动阶段（解析/配置/组装）的异常投影为退出码 2。
 *
 * 到达这里的异常都发生在命令执行之前，不可能是网络错误（网络对象尚未发起请求）；
 * 命令执行阶段的错误由 `commands.ts` 自行分类（1 或 3）。日志只包含白名单命令名和
 * 错误类型，用户原始 argv 与 data 绝不进入结构化日志。
 *
 * @param error 启动阶段抛出的任意异常。
 * @param argv 原始命令行参数（仅用于提取白名单命令名）。
 * @param dependencies 依赖集合（用于取 logger/output）。
 * @returns 固定 `EXIT_CODES.configError`（2）。
 *   示例：无参数运行 → usage 错误 → stderr 输出用法提示，返回 2。
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
