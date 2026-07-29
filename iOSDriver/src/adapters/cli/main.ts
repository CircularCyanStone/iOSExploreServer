#!/usr/bin/env node

/**
 * iOSDriver CLI 的进程入口。
 *
 * 本模块只负责三件事：把 argv 解析为固定命令、按配置构造共享 runtime 依赖、把命令
 * 返回值映射到进程退出码。具体命令行为位于 `commands.ts`，因此测试 import 本模块时
 * 不会自动启动网络请求或 MCP stdio server。
 */
import { realpathSync } from "node:fs";
import { homedir } from "node:os";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { CapabilityProbe } from "../../runtime/capabilityProbe.js";
import { DriverRuntime } from "../../runtime/driverRuntime.js";
import { HttpActionTransport } from "../../runtime/httpActionTransport.js";
import { WorkflowRunner } from "../../workflows/workflowRunner.js";
import { configPathFor, resolveCLIConfig, CLIConfigError, type CLIConfigOverrides } from "./config.js";
import { executeCLICommand, EXIT_CODES, type CallCommandOptions, type CLICommandContext, type CLICommandName } from "./commands.js";
import { processOutput, type CLIOutput } from "./output.js";
import { startMCPStdioServer } from "../mcp/server.js";
import { defaultHostLogger, type HostLogger } from "../../runtime/hostLogger.js";
import {
  setupMCPClient,
  type MCPClientName,
  type MCPClientSetupInput,
  type MCPClientSetupResult,
  type MCPRegistrationScope
} from "../../registration/mcpClientSetup.js";

type OperationalArguments = {
  /** 区分普通 App 命令与不连接 App 的 MCP 客户端注册命令。 */
  readonly kind: "operational";
  /** 固定联合类型让命令分发保持穷尽检查，未知名称不会进入行为层。 */
  readonly command: CLICommandName;
  /** 只包含实际出现的 flags，未出现字段留给配置优先级解析。 */
  readonly config: CLIConfigOverrides;
  /** 仅 `call` 使用的 action/data/artifact 参数；其他命令保持空值。 */
  readonly call: CallCommandOptions;
  /** 是否请求面向人的简短输出；当前由 `doctor` 消费。 */
  readonly human: boolean;
};

type MCPSetupArguments = {
  /** setup 在配置加载前分流，不创建 App transport。 */
  readonly kind: "mcpSetup";
  /** 同时决定允许的 scope、配置位置和写入方式。 */
  readonly client: MCPClientName;
  /** 客户端配置的作用域；省略时由客户端类型决定默认值。 */
  readonly scope?: MCPRegistrationScope;
  /** 只计算计划，不修改客户端配置。 */
  readonly dryRun: boolean;
  /** 允许替换同名但启动参数不同的现有注册。 */
  readonly force: boolean;
  /** 注册后传给 `iosdriver mcp` 的 App 配置文件路径。 */
  readonly configPath?: string;
  /** project scope 的根目录，也是客户端配置文件的定位基准。 */
  readonly projectDir?: string;
};

/** argv 解析完成后的判别联合。 */
type ParsedArguments = OperationalArguments | MCPSetupArguments;

/**
 * 解析 CLI 参数并执行固定命令。
 *
 * 执行顺序是：解析 argv；若为 `mcp setup` 则直接注册客户端；否则解析 App 配置并
 * 构造 transport/runtime/probe/workflow；最后把命令交给 `executeCLICommand`。
 * `call` 期间收到 SIGINT 会通过 `AbortSignal` 取消当前 HTTP 请求。
 *
 * @param argv 不含 node 与入口文件的命令行参数，默认读取 `process.argv.slice(2)`。
 * @param dependencies 可注入的进程环境和 IO 边界，主要供单元测试使用。
 * @returns 固定 CLI 退出码；本函数本身不调用 `process.exit()`。
 */
export async function main(
  argv: readonly string[] = process.argv.slice(2),
  dependencies: {
    /** stdout/stderr 写入边界，测试注入后不会污染进程标准流。 */
    readonly output?: CLIOutput;
    /** 配置解析和 MCP 注册使用的环境变量集合。 */
    readonly env?: NodeJS.ProcessEnv;
    /** `doctor` 检查使用的 Node 版本，测试可注入旧版本。 */
    readonly nodeVersion?: string;
    /** 贯穿 CLI、runtime、workflow 和 MCP 的结构化日志器。 */
    readonly logger?: HostLogger;
    /** 相对 `--config`、`--project-dir` 的解析基准。 */
    readonly cwd?: string;
    /** 默认配置路径及 user scope 客户端配置的用户目录。 */
    readonly homeDir?: string;
    /** MCP 客户端注册使用的 Node 可执行文件绝对路径。 */
    readonly nodePath?: string;
    /** MCP 客户端注册使用的 CLI JS 入口绝对路径。 */
    readonly cliEntryPath?: string;
    /** MCP 注册实现；测试可替换以避免修改真实客户端配置。 */
    readonly setupMCPClient?: (input: MCPClientSetupInput) => Promise<MCPClientSetupResult>;
  } = {}
): Promise<number> {
  const output = dependencies.output ?? processOutput;
  const logger = dependencies.logger ?? defaultHostLogger;
  const env = dependencies.env ?? process.env;
  const cwd = dependencies.cwd ?? process.cwd();
  const homeDir = dependencies.homeDir ?? homedir();
  const controller = new AbortController();
  const onSIGINT = () => controller.abort(new Error("SIGINT"));
  let handlesSIGINT = false;
  try {
    const parsed = parseArguments(argv);
    // setup 只写 MCP 客户端配置，不需要 App 可达，也不应受 App 配置格式影响。
    if (parsed.kind === "mcpSetup") {
      logger.emit("info", "cli.command.start", { command: "mcp.setup", client: parsed.client });
      const rawConfigPath = parsed.configPath ?? configPathFor(env, homeDir);
      const configPath = resolve(cwd, rawConfigPath);
      const projectDir = resolve(cwd, parsed.projectDir ?? ".");
      const setup = dependencies.setupMCPClient ?? setupMCPClient;
      const result = await setup({
        client: parsed.client,
        ...(parsed.scope === undefined ? {} : { scope: parsed.scope }),
        dryRun: parsed.dryRun,
        force: parsed.force,
        cwd: projectDir,
        homeDir,
        env,
        launch: {
          command: dependencies.nodePath ?? process.execPath,
          args: [
            dependencies.cliEntryPath ?? fileURLToPath(import.meta.url),
            "mcp",
            "--config",
            configPath
          ]
        }
      });
      output.stdout(`${JSON.stringify(result, null, 2)}\n`);
      logger.emit("info", "cli.command.complete", {
        command: "mcp.setup",
        client: parsed.client,
        status: result.status,
        exitCode: EXIT_CODES.success
      });
      return EXIT_CODES.success;
    }
    // 只有可能进行一次性 HTTP 调用的 call 接管 SIGINT；stdio MCP 自行管理生命周期。
    handlesSIGINT = parsed.command === "call";
    if (handlesSIGINT) process.once("SIGINT", onSIGINT);
    const config = await resolveCLIConfig(parsed.config, env);
    const runtime = new DriverRuntime({
      transport: new HttpActionTransport(config.baseURL, {
        ...(config.authToken === undefined ? {} : { authToken: config.authToken })
      }),
      configuredRequestTimeoutMs: config.requestTimeoutMs,
      logger
    });
    const capabilityProbe = new CapabilityProbe(runtime, undefined, logger);
    const workflowRunner = new WorkflowRunner({ runtime, logger });
    // context 把进程依赖一次性组装好，commands 层无需读取全局单例或自行构造网络对象。
    const context: CLICommandContext = {
      config,
      output,
      runtime,
      capabilityProbe,
      workflowRunner,
      ...(dependencies.nodeVersion === undefined ? {} : { nodeVersion: dependencies.nodeVersion }),
      env,
      signal: controller.signal,
      logger,
      ...(parsed.human ? { human: true } : {})
    };
    if (parsed.command === "call") return await executeCLICommand("call", context, parsed.call);
    return await executeCLICommand(parsed.command, {
      ...context,
      startMCP: () => startMCPStdioServer({ runtime, capabilityProbe, workflowRunner, logger })
    });
  } catch (error) {
    logger.emit("error", "cli.command.error", {
      command: knownCommand(argv),
      exitCode: EXIT_CODES.configError,
      errorType: error instanceof Error ? error.name : typeof error,
      phase: "startup"
    });
    if (error instanceof CLIConfigError) {
      output.stderr(`${error.message}\n`);
      return EXIT_CODES.configError;
    }
    output.stderr(`${error instanceof Error ? error.message : String(error)}\n`);
    return EXIT_CODES.configError;
  } finally {
    if (handlesSIGINT) process.off("SIGINT", onSIGINT);
  }
}

/**
 * 判断当前模块是否为进程入口。
 *
 * `npm link` 会让 `argv[1]` 指向符号链接，因此双方先经 `realpathSync` 解析后再比较。
 * 被测试或其他模块 import 时返回 `false`，避免意外启动网络或写标准流。
 *
 * @param metaURL 当前模块的 `import.meta.url`。
 * @param argv1 Node 记录的入口路径。
 */
export function isMainModule(metaURL: string, argv1 = process.argv[1]): boolean {
  if (argv1 === undefined) return false;
  return realpathSync(argv1) === realpathSync(fileURLToPath(metaURL));
}

if (isMainModule(import.meta.url)) {
  const exitCode = await main();
  process.exitCode = exitCode;
}

/**
 * 把扁平 argv 解析为判别联合。
 * 普通命令共用一次 flag 扫描；`mcp setup` 在这里提前转入独立语法，防止 setup 专属参数
 * 被误传给 App 配置解析。
 */
function parseArguments(argv: readonly string[]): ParsedArguments {
  const command = argv[0] as CLICommandName | undefined;
  if (command !== "init" && command !== "doctor" && command !== "call" && command !== "mcp") {
    throw new CLIConfigError(usage());
  }
  if (command === "mcp" && argv[1] === "setup") return parseMCPSetupArguments(argv);
  let baseURL: string | undefined;
  let requestTimeoutMs: number | undefined;
  let configPath: string | undefined;
  let data: string | undefined;
  let output: string | undefined;
  let human = false;
  let action = command === "call" ? argv[1] ?? "" : "";
  let index = command === "call" ? 2 : 1;
  // 单次顺序扫描允许 flags 出现在 action 后；重复 flag 以最后一次出现为准。
  while (index < argv.length) {
    const flag = argv[index]!;
    if (flag === "--base-url") baseURL = requiredValue(argv, ++index, flag);
    else if (flag === "--timeout") requestTimeoutMs = parseTimeout(requiredValue(argv, ++index, flag));
    else if (flag === "--config") configPath = requiredValue(argv, ++index, flag);
    else if (command === "call" && flag === "--data") data = requiredValue(argv, ++index, flag);
    else if (command === "call" && flag === "--output") output = requiredValue(argv, ++index, flag);
    else if (flag === "--human") human = true;
    else if (command === "call" && !flag.startsWith("-")) action = flag;
    else throw new CLIConfigError(`未知参数: ${flag}`);
    index += 1;
  }
  return {
    kind: "operational",
    command,
    config: {
      ...(baseURL === undefined ? {} : { baseURL }),
      ...(requestTimeoutMs === undefined ? {} : { requestTimeoutMs }),
      ...(configPath === undefined ? {} : { configPath })
    },
    human,
    call: {
      action,
      ...(data === undefined ? {} : { data }),
      ...(output === undefined ? {} : { output })
    }
  };
}

/** 解析 `mcp setup` 专属参数，并在访问文件系统前拒绝不支持的 client/scope 值。 */
function parseMCPSetupArguments(argv: readonly string[]): MCPSetupArguments {
  const client = argv[2];
  if (client !== "codex" && client !== "claude" && client !== "trae") {
    throw new CLIConfigError("用法: iosdriver mcp setup <codex|claude|trae> [--scope user|project] [--project-dir path] [--dry-run] [--force] [--config path]");
  }
  let scope: MCPRegistrationScope | undefined;
  let configPath: string | undefined;
  let projectDir: string | undefined;
  let dryRun = false;
  let force = false;
  let index = 3;
  while (index < argv.length) {
    const flag = argv[index]!;
    if (flag === "--scope") {
      const value = requiredValue(argv, ++index, flag);
      if (value !== "user" && value !== "project") throw new CLIConfigError("--scope 必须是 user 或 project");
      scope = value;
    } else if (flag === "--config") {
      configPath = requiredValue(argv, ++index, flag);
    } else if (flag === "--project-dir") {
      projectDir = requiredValue(argv, ++index, flag);
    } else if (flag === "--dry-run") {
      dryRun = true;
    } else if (flag === "--force") {
      force = true;
    } else {
      throw new CLIConfigError(`未知参数: ${flag}`);
    }
    index += 1;
  }
  return {
    kind: "mcpSetup",
    client,
    ...(scope === undefined ? {} : { scope }),
    dryRun,
    force,
    ...(configPath === undefined ? {} : { configPath }),
    ...(projectDir === undefined ? {} : { projectDir })
  };
}

/** 读取需要紧随 flag 的值，避免把下一个 `--flag` 误当作普通字符串。 */
function requiredValue(argv: readonly string[], index: number, flag: string): string {
  const value = argv[index];
  if (value === undefined || value.startsWith("-")) throw new CLIConfigError(`${flag} 需要参数`);
  return value;
}

/** 在配置文件和网络初始化前拒绝小数、零、负数及非数值 timeout。 */
function parseTimeout(raw: string): number {
  const value = Number(raw);
  if (!Number.isInteger(value) || value <= 0) throw new CLIConfigError("--timeout 必须是正整数");
  return value;
}

/** 提取可安全写日志的已知命令名，不记录原始 argv。 */
function knownCommand(argv: readonly string[]): CLICommandName | "mcp.setup" | "unknown" {
  if (argv[0] === "mcp" && argv[1] === "setup") return "mcp.setup";
  const value = argv[0];
  return value === "init" || value === "doctor" || value === "call" || value === "mcp" ? value : "unknown";
}

/** 返回参数错误时的单行用法摘要；完整说明位于 `docs/cli-reference.md`。 */
function usage(): string {
  return "用法: iosdriver init|doctor|call <action> [--data JSON|@file] [--output path]|mcp|mcp setup <codex|claude|trae>";
}
