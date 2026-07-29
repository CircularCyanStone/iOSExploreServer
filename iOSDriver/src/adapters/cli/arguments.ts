/**
 * iOSDriver CLI 的 argv 解析模块。
 *
 * 本模块只把扁平字符串数组转换为判别联合，不读取环境变量、配置文件或网络。调用方可
 * 先根据 `kind` 分流 `mcp setup`，再决定是否需要构造连接 App 的 runtime。
 */
import type { MCPClientName, MCPRegistrationScope } from "../../registration/mcpClientSetup.js";
import { type CallCommandOptions, type CLICommandName } from "./commands.js";
import { CLIConfigError, type CLIConfigOverrides } from "./config.js";

/** 需要读取 App 配置并进入命令行为层的参数。 */
export interface OperationalArguments {
  readonly kind: "operational";
  /** 固定联合类型保证未知命令不会进入 `executeCLICommand`。 */
  readonly command: CLICommandName;
  /** 只保存命令行中实际出现的覆盖项，其余值稍后按配置优先级补齐。 */
  readonly config: CLIConfigOverrides;
  /** 仅 `call` 使用；其他命令保留空 action，不会消费此字段。 */
  readonly call: CallCommandOptions;
  /** 是否请求适合终端阅读的简短输出；当前由 `doctor` 消费。 */
  readonly human: boolean;
}

/** 不连接 App、只修改 MCP 客户端注册信息的参数。 */
export interface MCPSetupArguments {
  readonly kind: "mcpSetup";
  readonly client: MCPClientName;
  readonly scope?: MCPRegistrationScope;
  /** 只返回预计变更，不写客户端配置。 */
  readonly dryRun: boolean;
  /** 允许替换同名但启动参数不同的已有注册。 */
  readonly force: boolean;
  /** 注册后传给 `iosdriver mcp --config` 的 App 配置路径。 */
  readonly configPath?: string;
  /** project scope 的根目录，也是客户端配置文件的定位基准。 */
  readonly projectDir?: string;
}

/** CLI 应用可以直接按 `kind` 做穷尽分流的解析结果。 */
export type ParsedCLIArguments = OperationalArguments | MCPSetupArguments;

/**
 * 解析不包含 node 和入口文件路径的 argv。
 *
 * 第一层只识别固定命令名，并尽早分流语法独立的 `mcp setup`。这样 setup 专属参数不会
 * 落入普通命令扫描，也不会因为无关的 App 配置错误而失败。
 */
export function parseCLIArguments(argv: readonly string[]): ParsedCLIArguments {
  const command = parseCommandName(argv[0]);
  if (command === "mcp" && argv[1] === "setup") return parseMCPSetupArguments(argv);
  return parseOperationalArguments(command, argv);
}

/**
 * 提取可安全写入结构化日志的命令名。
 *
 * 未知输入统一返回 `unknown`，避免错误日志意外记录 action、data 或其他原始 argv。
 */
export function knownCLICommand(argv: readonly string[]): CLICommandName | "mcp.setup" | "unknown" {
  if (argv[0] === "mcp" && argv[1] === "setup") return "mcp.setup";
  const value = argv[0];
  return value === "init" || value === "doctor" || value === "call" || value === "mcp"
    ? value
    : "unknown";
}

/** 校验首个位置参数，并把字符串缩窄为命令联合类型。 */
function parseCommandName(value: string | undefined): CLICommandName {
  if (value === "init" || value === "doctor" || value === "call" || value === "mcp") return value;
  throw new CLIConfigError(usage());
}

/**
 * 解析 `init`、`doctor`、`call`、`mcp` 共用的 flag 集合。
 *
 * `call` 的首个 action 在扫描前读取，后续仍允许 action 出现在 flags 之后；顺序扫描也
 * 保留了重复 flag 以最后一个值为准的既有行为。
 */
function parseOperationalArguments(
  command: CLICommandName,
  argv: readonly string[]
): OperationalArguments {
  let baseURL: string | undefined;
  let requestTimeoutMs: number | undefined;
  let configPath: string | undefined;
  let data: string | undefined;
  let output: string | undefined;
  let human = false;
  let action = command === "call" ? argv[1] ?? "" : "";
  let index = command === "call" ? 2 : 1;

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

/**
 * 解析 `mcp setup` 的独立语法。
 *
 * client 和 scope 在任何路径解析或文件写入前完成校验，使参数错误始终是无副作用的。
 */
function parseMCPSetupArguments(argv: readonly string[]): MCPSetupArguments {
  const client = argv[2];
  if (client !== "codex" && client !== "claude" && client !== "trae") {
    throw new CLIConfigError(
      "用法: iosdriver mcp setup <codex|claude|trae> [--scope user|project] [--project-dir path] [--dry-run] [--force] [--config path]"
    );
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
      if (value !== "user" && value !== "project") {
        throw new CLIConfigError("--scope 必须是 user 或 project");
      }
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

/** 读取 flag 后的必填值，并拒绝把下一个 flag 当作普通字符串。 */
function requiredValue(argv: readonly string[], index: number, flag: string): string {
  const value = argv[index];
  if (value === undefined || value.startsWith("-")) throw new CLIConfigError(`${flag} 需要参数`);
  return value;
}

/** 在配置和网络初始化前拒绝小数、零、负数及非数值 timeout。 */
function parseTimeout(raw: string): number {
  const value = Number(raw);
  if (!Number.isInteger(value) || value <= 0) throw new CLIConfigError("--timeout 必须是正整数");
  return value;
}

/** 参数错误使用单行摘要；完整命令说明由 CLI reference 维护。 */
function usage(): string {
  return "用法: iosdriver init|doctor|call <action> [--data JSON|@file] [--output path]|mcp|mcp setup <codex|claude|trae>";
}
