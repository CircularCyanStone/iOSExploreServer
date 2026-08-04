/**
 * iOSDriver CLI 的 argv 解析层：把扁平字符串数组转换成类型安全的「判别联合」对象。
 *
 * 本模块是纯函数层——不读环境变量、不读文件、不发网络，同样的输入永远得到同样的
 * 输出；解析失败一律抛 `CLIConfigError`（由上层映射为退出码 2）。
 *
 * 输出是一个判别联合 `ParsedCLIArguments`：普通命令（init/doctor/call/mcp）与
 * `mcp setup` 的语法完全不同，分别解析成 `OperationalArguments` 和
 * `MCPSetupArguments`，靠 `kind` 字段区分，消费方 `switch(kind)` 后 TS 自动收窄类型。
 *
 * 示例：
 *   ["call", "ping"]
 *     → { kind:"operational", command:"call", config:{}, human:false,
 *         call:{ action:"ping" } }
 *   ["mcp", "setup", "codex", "--dry-run"]
 *     → { kind:"mcpSetup", client:"codex", dryRun:true, force:false }
 */
import type { MCPClientName, MCPRegistrationScope } from "../../registration/mcpClientSetup.js";
import { type CallCommandOptions, type CLICommandName } from "./commands.js";
import { CLIConfigError, type CLIConfigOverrides } from "./config.js";

/**
 * 普通命令（init/doctor/call/mcp）的解析结果。
 *
 * 当用户输入的命令不是 `mcp setup` 时产生；消费方（application.ts）看到
 * `kind === "operational"` 后，会继续解析配置并组装连接 App 的 runtime。
 */
export interface OperationalArguments {
  /** 判别字段：固定 "operational"，用于与 `MCPSetupArguments` 区分；
   * 配合联合类型保证未知命令不会进入 `executeCLICommand`。 */
  readonly kind: "operational";
  /** 命令名，白名单之一："init" | "doctor" | "call" | "mcp"。 */
  readonly command: CLICommandName;
  /** 命令行中实际出现的配置覆盖项（--base-url/--timeout/--config）；
   * 没出现的字段不存在（条件展开），由配置层按优先级补齐。 */
  readonly config: CLIConfigOverrides;
  /** call 专属参数（action/data/output）；非 call 命令保留空 action，不消费此字段。 */
  readonly call: CallCommandOptions;
  /** 是否传了 --human（请求适合终端阅读的简短输出）；当前由 doctor 消费。 */
  readonly human: boolean;
}

/**
 * `mcp setup` 的解析结果。
 *
 * 当用户输入 `mcp setup <codex|claude|trae> …` 时产生；消费方（application.ts）看到
 * `kind === "mcpSetup"` 后走 host-only 路径：不解析 App 配置、不组装 runtime，
 * 只把启动命令注册进客户端配置文件。
 *
 * 路径字段只有两个且归属不同（见 application.ts 文件头「路径的两个世界」）：
 * `configPath` 是【Host 侧】iOSDriver 自身配置；`projectDir` 是【项目侧】目标
 * iOS 项目根目录——别把两者当成同一个东西。
 */
export interface MCPSetupArguments {
  /** 判别字段：固定 "mcpSetup"。 */
  readonly kind: "mcpSetup";
  /** 目标 AI 客户端："codex" | "claude" | "trae"。 */
  readonly client: MCPClientName;
  /** 注册作用域（user/project）；省略时由注册层按客户端默认（codex=user，claude/trae=project）。 */
  readonly scope?: MCPRegistrationScope;
  /** true=只返回将执行的变更计划，不写客户端配置。 */
  readonly dryRun: boolean;
  /** true=允许替换同名但启动参数不同的已有注册。 */
  readonly force: boolean;
  /** 【Host 侧】注册后传给 `iosdriver mcp --config` 的 iOSDriver 自身配置路径
   * （含 baseURL，默认 ~/.config/iosdriver/config.json）；相对路径，组装层转绝对。 */
  readonly configPath?: string;
  /** 【项目侧】目标 iOS 项目根目录（相对路径，基于 cwd 解析）；
   * 是 `.mcp.json`/`.trae/mcp.json` 的定位基准，未传时默认当前工作目录。 */
  readonly projectDir?: string;
}

/**
 * 全部解析结果类型的并集：要么是普通命令参数，要么是 `mcp setup` 参数。
 *
 * 消费方用 `parsed.kind` 做穷尽分支（switch/if-else），TS 会在此收窄类型，
 * 写错分支属性时编译期直接报错。
 */
export type ParsedCLIArguments = OperationalArguments | MCPSetupArguments;

/**
 * 解析不包含 node 和入口文件路径的 argv，返回判别联合对象。
 *
 * 第一层只识别固定命令名，并**尽早分流** `mcp setup`：它是一套完全独立的语法
 * （`<client> [--scope …]`），且不需要 App 可达。分流后 setup 专属参数不会落入
 * 普通命令的 flag 扫描，也不会因为无关的 App 配置错误而失败。
 *
 * @param argv 命令行参数数组，如 `["call", "ping"]` 或 `["mcp", "setup", "codex"]`。
 * @returns `OperationalArguments`（普通命令）或 `MCPSetupArguments`（mcp setup）。
 * @throws {CLIConfigError} 命令名不在白名单、flag 缺值、timeout 非法时抛出
 *   （无副作用：解析失败前不产生任何 IO）。
 */
export function parseCLIArguments(argv: readonly string[]): ParsedCLIArguments {
  const command = parseCommandName(argv[0]);
  if (command === "mcp" && argv[1] === "setup") return parseMCPSetupArguments(argv);
  return parseOperationalArguments(command, argv);
}

/**
 * 从 argv 提取「可安全写入日志」的命令名。
 *
 * 只认白名单（init/doctor/call/mcp/mcp.setup），其他一律返回 "unknown"。
 * 为什么不能直接返回 `argv[0]`：argv 里可能装着秘密或敏感数据（如 `--data` 中的
 * token），日志绝不能记录原始用户输入；白名单机制保证写进日志的只有固定命令名。
 *
 * @param argv 原始命令行参数。
 * @returns 白名单命令名、"mcp.setup" 或 "unknown"。
 *   示例：["call", "ui.inspect", "--data", "secret"] → "call"；
 *         ["private-command", "secret"] → "unknown"。
 */
export function knownCLICommand(argv: readonly string[]): CLICommandName | "mcp.setup" | "unknown" {
  if (argv[0] === "mcp" && argv[1] === "setup") return "mcp.setup";
  const value = argv[0];
  return value === "init" || value === "doctor" || value === "call" || value === "mcp"
    ? value
    : "unknown";
}

/**
 * 校验第一个位置参数是否为合法命令名，并把字符串缩窄为 `CLICommandName` 类型。
 *
 * @param value `argv[0]`；类型为 `string | undefined` 是因为 `noUncheckedIndexedAccess`
 *   配置下数组下标访问可能越界（无参数启动时 argv 为空数组）。
 * @returns 白名单命令名。
 * @throws {CLIConfigError} 不是 init/doctor/call/mcp 之一，附带单行用法提示。
 *   示例："ping" → 抛错；"call" → "call"。
 */
function parseCommandName(value: string | undefined): CLICommandName {
  if (value === "init" || value === "doctor" || value === "call" || value === "mcp") return value;
  throw new CLIConfigError(usage());
}

/**
 * 解析 init/doctor/call/mcp 共用的 flag 集合，返回普通命令参数。
 *
 * 扫描规则：从 index=1（call 为 2，因为 argv[1] 是 action）开始顺序遍历；遇到 flag
 * 就消费它后面的值（`++index` 一次跳两个元素）；重复 flag 以最后一个值为准；
 * `call` 专属 flag（--data/--output/裸 action）仅在 command==="call" 时被识别。
 *
 * 返回的 `config`/`call` 对象只包含**实际出现**的字段（条件展开），这样上层才能
 * 区分「用户传了」与「没传」——提前填默认值会破坏配置优先级合并（config.ts）。
 *
 * @param command 已校验的命令名。
 * @param argv 完整参数数组。
 * @returns `OperationalArguments`。
 *   示例：["call", "ui.inspect", "--data", "{\"mode\":\"minimal\"}"]
 *     → { command:"call", config:{}, call:{ action:"ui.inspect",
 *         data:"{\"mode\":\"minimal\"}" } }
 * @throws {CLIConfigError} 未知 flag、flag 缺值时抛出。
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
 * 解析 `mcp setup` 的独立语法（与普通命令扫描完全分离）。
 *
 * 参数顺序固定为 `mcp setup <client> [flags]`：client 从 `argv[2]` 取，扫描从
 * index=3 开始。client 与 scope 在路径解析或文件写入**之前**完成校验，保证参数
 * 错误始终是无副作用的。
 *
 * @param argv 完整参数数组，如 `["mcp", "setup", "claude", "--scope", "project"]`。
 * @returns `MCPSetupArguments`（只含实际出现的可选字段）。
 * @throws {CLIConfigError} client 不是 codex/claude/trae、scope 不是 user/project、
 *   未知 flag 时抛出。
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

/**
 * 读取 flag 后面的必填值，并拒绝「把下一个 flag 当作值」的情况。
 *
 * 不检查这个，`--config --human` 会把 `--human` 当成配置文件路径，错误会延迟到
 * 很后面才暴露且信息莫名其妙；在这里当场拒绝，报错最清晰。
 *
 * @param argv 完整参数数组。
 * @param index 待取值的位置（调用方已 ++ 到值的位置）。
 * @param flag 当前 flag 名（仅用于报错信息，如 "--config"）。
 * @returns flag 后的参数值。
 * @throws {CLIConfigError} 值缺失（数组越界）或以 "-" 开头（是另一个 flag）。
 *   示例：`--config --human` → 抛 "--config 需要参数"；`--config a.json` → "a.json"。
 */
function requiredValue(argv: readonly string[], index: number, flag: string): string {
  const value = argv[index];
  if (value === undefined || value.startsWith("-")) throw new CLIConfigError(`${flag} 需要参数`);
  return value;
}

/**
 * 把字符串 timeout 转成数字并校验为正整数。
 *
 * 必须在解析阶段就管死：timeout 会直接作为毫秒数传给网络层的 setTimeout，
 * 0/负数/小数/非数字都会产生错误行为（如立即超时）。
 *
 * @param raw 原始字符串，如 "2500"。
 * @returns 正整数毫秒数。
 * @throws {CLIConfigError} 非整数、<=0、NaN（如 "abc"、"1.5"、"0"、"-5"）。
 *   示例："2500" → 2500。
 */
function parseTimeout(raw: string): number {
  const value = Number(raw);
  if (!Number.isInteger(value) || value <= 0) throw new CLIConfigError("--timeout 必须是正整数");
  return value;
}

/**
 * 返回单行用法摘要。
 *
 * 完整命令说明由 `docs/cli-reference.md` 维护，这里只提供足以让用户自查的提示。
 *
 * @returns 用法字符串，如 "用法: iosdriver init|doctor|call <action> …"。
 */
function usage(): string {
  return "用法: iosdriver init|doctor|call <action> [--data JSON|@file] [--output path]|mcp|mcp setup <codex|claude|trae>";
}
