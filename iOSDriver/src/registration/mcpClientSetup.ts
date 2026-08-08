/**
 * MCP 客户端注册：把「如何启动 iosdriver mcp」写入指定 AI 客户端的配置。
 *
 * 三种客户端三种机制：
 * - Codex：通过官方 `codex mcp get/add` CLI 管理（本模块不直接改文件）；
 * - Claude Code：JSON 文件（user: ~/.claude.json 或 CLAUDE_CONFIG_DIR；project: .mcp.json）；
 * - TRAE：project 级 .trae/mcp.json。
 *
 * 通用保证：保留客户端配置中的其他 server 与未知顶层字段；同名但启动参数不同的
 * 已有注册默认拒绝覆盖（需要 --force）；JSON 写入采用临时文件 + rename 原子替换，
 * setup 可重复执行且不会留下半写文件。
 *
 * 注册内容示例（launch）：
 *   { command: "/usr/local/bin/node",
 *     args: ["/abs/main.js", "mcp", "--config", "/abs/config.json"] }
 *
 * 路径归属（与 application.ts 文件头「路径的两个世界」一致）：
 * - 【项目侧】`MCPClientSetupInput.cwd`：目标 iOS 项目根目录，决定 project scope
 *   的配置文件写在哪（`<cwd>/.mcp.json`、`<cwd>/.trae/mcp.json`），也是 Codex
 *   子进程的工作目录；
 * - 【Host 侧】`homeDir`/`launch`：本机用户目录与 iOSDriver 自身的绝对启动路径
 *   （Node、main.js、--config 配置），与目标项目无关。
 */
import { spawn } from "node:child_process";
import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import { dirname, isAbsolute, join, resolve } from "node:path";

/** 注册到客户端配置中的固定名字（客户端用它标识本 server）。 */
const REGISTRATION_NAME = "iOSDriver";

export type MCPClientName = "codex" | "claude" | "trae";
export type MCPRegistrationScope = "user" | "project";

/** 写入客户端配置的完整 stdio 启动命令（全部为【Host 侧】绝对路径：
 * Node 在哪、main.js 在哪、iOSDriver 自身配置在哪）。
 * 客户端将来可能在任意目录启动该命令，所以不能出现相对路径。 */
export interface MCPLaunchCommand {
  /** setup 调用方已解析出的绝对 Node 可执行文件路径。 */
  readonly command: string;
  /** 固定参数：绝对 CLI 入口 + "mcp" + "--config <绝对路径>"。 */
  readonly args: readonly string[];
}

/** `setupMCPClient` 的输入。 */
export interface MCPClientSetupInput {
  readonly client: MCPClientName;
  /** 注册作用域；省略时按客户端默认（codex=user，claude/trae=project）。 */
  readonly scope?: MCPRegistrationScope;
  /** true=只计算并返回 create/update 计划，不运行命令或写 JSON。 */
  readonly dryRun?: boolean;
  /** true=允许替换同名但启动参数不同的已有注册；完全相同仍返回 unchanged。 */
  readonly force?: boolean;
  /** 【项目侧】目标 iOS 项目根目录（由 application.ts 从 `--project-dir` 解析，
   * 缺省=当前工作目录）。project scope 的 `.mcp.json`/`.trae/mcp.json` 以此为
   * 定位基准（见 `jsonConfigPath`），也是 Codex 子命令的工作目录。 */
  readonly cwd: string;
  /** 【Host 侧】Claude user scope 默认配置位置（.claude.json）的解析基准。 */
  readonly homeDir: string;
  /** 透传给 Codex CLI，并读取 CLAUDE_CONFIG_DIR。 */
  readonly env: NodeJS.ProcessEnv;
  /** 要写入客户端的完整 stdio 启动合同。 */
  readonly launch: MCPLaunchCommand;
}

/** 注册结果（stdout 输出的 JSON 结构）。 */
export interface MCPClientSetupResult {
  readonly client: MCPClientName;
  readonly scope: MCPRegistrationScope;
  /** created=新写入；updated=覆盖；unchanged=完全相同未写；planned=dry-run 计划。 */
  readonly status: "created" | "updated" | "unchanged" | "planned";
  /** planned 时表示将执行的动作；unchanged 时为 none。 */
  readonly operation: "create" | "update" | "none";
  readonly registrationName: typeof REGISTRATION_NAME;
  /** codex-cli=走官方 CLI；json-file=直接写 JSON 文件。 */
  readonly manager: "codex-cli" | "json-file";
  /** JSON 客户端的目标文件路径；Codex 由 CLI 管理，不暴露内部路径。 */
  readonly configPath?: string;
  readonly launch: MCPLaunchCommand;
}

export interface MCPSetupFileSystem {
  /** 缺失配置必须以 `code: ENOENT` 表示，setup 才会按空文档创建。 */
  readonly readFile: (path: string) => Promise<string>;
  /** 实现需支持递归父目录创建。 */
  readonly mkdir: (path: string) => Promise<void>;
  /** 只用于同目录临时文件，生产实现权限固定为 0600。 */
  readonly writeFile: (path: string, data: string) => Promise<void>;
  /** 原子替换最终配置，失败时由 setup 转为稳定错误。 */
  readonly rename: (from: string, to: string) => Promise<void>;
}

/** 外部客户端管理命令的完整捕获结果；不会直接继承到当前进程 stdout/stderr。 */
export interface MCPSetupCommandResult {
  readonly exitCode: number;
  /** Codex `mcp get --json` 的解析来源，失败时最多取 500 字符作为摘要。 */
  readonly stdout: string;
  /** 优先用于构造外部命令失败摘要。 */
  readonly stderr: string;
}

export type MCPSetupCommandRunner = (
  command: string,
  args: readonly string[],
  options: { readonly cwd: string; readonly env: NodeJS.ProcessEnv }
) => Promise<MCPSetupCommandResult>;

/**
 * `setupMCPClient` 的注入依赖（测试替换 IO 边界）。
 *
 * 生产调用方（`application.ts`）**从不传这两个字段**——省略时分别落到
 * `runCommand`（真实 spawn）与 `defaultFileSystem`（真实 fs）。只有单元测试
 * 才注入 fake，以在内存中验证流程而不碰真实磁盘/子进程。
 * 阅读代码时遇到 `?? defaultXxx` / `= {}` 的注入点，可以直接当成默认实现，无需追测试。
 */
export interface MCPClientSetupDependencies {
  /** Claude/TRAE JSON 写入边界；Codex 路径不使用。省略=`defaultFileSystem`（真实 fs）。 */
  readonly fileSystem?: MCPSetupFileSystem;
  /** Codex CLI 执行边界；JSON 客户端路径不使用。省略=`runCommand`（真实 spawn）。 */
  readonly runCommand?: MCPSetupCommandRunner;
}

/**
 * 注册失败时抛出的错误（code 固定 "mcp_setup_failed"）。
 */
export class MCPClientSetupError extends Error {
  readonly code = "mcp_setup_failed";

  constructor(message: string) {
    super(message);
    this.name = "MCPClientSetupError";
  }
}

/** 生产默认文件系统实现：直接代理 node:fs/promises（写配置固定 0o600）。 */
const defaultFileSystem: MCPSetupFileSystem = {
  readFile: path => readFile(path, "utf8"),
  mkdir: path => mkdir(path, { recursive: true }).then(() => undefined),
  writeFile: (path, data) => writeFile(path, data, { encoding: "utf8", mode: 0o600 }),
  rename
};

/**
 * 把 iOSDriver 注册到指定 MCP 客户端。
 *
 * 先解析 client/scope 的合法组合（codex 只支持 user、trae 只支持 project），
 * 再路由到官方 CLI（codex）或 JSON 文件（claude/trae）管理器。本函数**不检查 App
 * 连接**——注册只描述未来如何启动 `iosdriver mcp`，与 App 是否在线无关。
 *
 * @param input 注册输入（client/scope/dryRun/force/launch 等）。
 * @param dependencies 可注入的文件系统与命令执行边界。
 * @returns 注册结果（status/operation/configPath/launch）。
 * @throws {MCPClientSetupError} scope 组合非法、已有同名不同配置且无 --force、
 *   codex CLI 失败或 JSON 写入失败时抛出。
 */
export async function setupMCPClient(
  input: MCPClientSetupInput,
  dependencies: MCPClientSetupDependencies = {}
): Promise<MCPClientSetupResult> {
  const scope = resolvedScope(input.client, input.scope);
  if (input.client === "codex") {
    return setupCodex(input, scope, dependencies.runCommand ?? runCommand);
  }
  return setupJSONClient(input, scope, dependencies.fileSystem ?? defaultFileSystem);
}

/**
 * 解析注册作用域：调用方未指定时按客户端默认（codex=user，claude/trae=project），
 * 并校验客户端支持的 scope 组合。
 *
 * @param client 目标客户端。
 * @param requested 调用方请求的 scope（可能 undefined）。
 * @returns 最终作用域。
 * @throws {MCPClientSetupError} codex 非 user、trae 非 project 时抛出。
 */
function resolvedScope(client: MCPClientName, requested: MCPRegistrationScope | undefined): MCPRegistrationScope {
  const scope = requested ?? (client === "codex" ? "user" : "project");
  if (client === "codex" && scope !== "user") {
    throw new MCPClientSetupError("Codex 当前只支持 user scope");
  }
  if (client === "trae" && scope !== "project") {
    throw new MCPClientSetupError("TRAE 当前只支持 project scope（<project>/.trae/mcp.json）");
  }
  return scope;
}

/**
 * 通过官方 `codex mcp` CLI 注册（Codex 路径）。
 *
 * 流程：先 `codex mcp get` 读取现状（幂等与冲突保护的前提）→ 相同配置返回 unchanged
 * → 不同配置无 --force 报错 → dry-run 返回 planned → 否则 `codex mcp add` 写入。
 *
 * @param input 注册输入。
 * @param scope 已解析的作用域（codex 恒为 user）。
 * @param run 命令执行边界。
 * @returns 注册结果。
 * @throws {MCPClientSetupError} codex CLI 失败时抛出（含截断的 stderr 摘要）。
 */
async function setupCodex(
  input: MCPClientSetupInput,
  scope: MCPRegistrationScope,
  run: MCPSetupCommandRunner
): Promise<MCPClientSetupResult> {
  // 先读取现状实现幂等与冲突保护；--force 只允许更新，不会跳过读取。
  const current = await readCodexRegistration(input, run);
  if (current !== undefined && launchMatches(current, input.launch, true)) {
    return result(input, scope, "unchanged", "none", "codex-cli");
  }
  if (current !== undefined && input.force !== true) {
    throw new MCPClientSetupError(`Codex 已存在不同的 ${REGISTRATION_NAME} 配置；使用 --force 更新`);
  }

  const operation = current === undefined ? "create" : "update";
  if (input.dryRun === true) return result(input, scope, "planned", operation, "codex-cli");

  const added = await run(
    "codex",
    ["mcp", "add", REGISTRATION_NAME, "--", input.launch.command, ...input.launch.args],
    { cwd: input.cwd, env: input.env }
  );
  if (added.exitCode !== 0) throw commandError("codex mcp add", added);
  return result(input, scope, operation === "create" ? "created" : "updated", operation, "codex-cli");
}

/**
 * 读取 codex 中现有的 iOSDriver 注册（--json 输出）。
 *
 * @param input 注册输入。
 * @param run 命令执行边界。
 * @returns 现有注册对象；不存在时 undefined。
 * @throws {MCPClientSetupError} codex mcp get 非预期失败或返回非法 JSON 时抛出。
 */
async function readCodexRegistration(
  input: MCPClientSetupInput,
  run: MCPSetupCommandRunner
): Promise<Record<string, unknown> | undefined> {
  const inspected = await run("codex", ["mcp", "get", REGISTRATION_NAME, "--json"], {
    cwd: input.cwd,
    env: input.env
  });
  if (inspected.exitCode !== 0) {
    if (`${inspected.stdout}\n${inspected.stderr}`.includes(`No MCP server named '${REGISTRATION_NAME}'`)) return undefined;
    throw commandError("codex mcp get", inspected);
  }
  try {
    const parsed: unknown = JSON.parse(inspected.stdout);
    if (!isRecord(parsed)) throw new Error("response must be an object");
    return parsed;
  } catch (error) {
    throw new MCPClientSetupError(`codex mcp get 返回了非法 JSON：${errorMessage(error)}`);
  }
}

/**
 * 通过直接写 JSON 文件注册（Claude Code / TRAE 路径）。
 *
 * 流程：定位配置文件 → 读取现状（缺失视为空文档）→ 比较现有注册（相同=unchanged，
 * 不同且无 --force=报错）→ dry-run 返回 planned → 否则原子写入（临时文件 + rename）。
 * 写入时展开原文档并只替换 `mcpServers.iOSDriver`——其他 server 与未知字段全部保留。
 *
 * @param input 注册输入。
 * @param scope 已解析的作用域（决定配置文件位置）。
 * @param fileSystem 文件 IO 边界。
 * @returns 注册结果（含 configPath）。
 * @throws {MCPClientSetupError} 配置非合法 JSON、写入失败时抛出。
 */
async function setupJSONClient(
  input: MCPClientSetupInput,
  scope: MCPRegistrationScope,
  fileSystem: MCPSetupFileSystem
): Promise<MCPClientSetupResult> {
  const configPath = jsonConfigPath(input, scope);
  const document = await readJSONDocument(configPath, fileSystem);
  const serversValue = document.mcpServers;
  if (serversValue !== undefined && !isRecord(serversValue)) {
    throw new MCPClientSetupError(`MCP 配置的 mcpServers 必须是 JSON 对象：${configPath}`);
  }
  const servers = serversValue ?? {};
  const desired = jsonRegistration(input.client, input.launch);
  const current = servers[REGISTRATION_NAME];
  if (current !== undefined && jsonEqual(current, desired)) {
    return result(input, scope, "unchanged", "none", "json-file", configPath);
  }
  if (current !== undefined && input.force !== true) {
    throw new MCPClientSetupError(`${input.client} 已存在不同的 ${REGISTRATION_NAME} 配置；使用 --force 更新`);
  }

  const operation = current === undefined ? "create" : "update";
  if (input.dryRun === true) return result(input, scope, "planned", operation, "json-file", configPath);

  const next = {
    // 保留客户端配置中的其他功能和 server，只替换固定注册名 iOSDriver。
    ...document,
    mcpServers: {
      ...servers,
      [REGISTRATION_NAME]: desired
    }
  };
  await writeJSONDocument(configPath, next, fileSystem);
  return result(
    input,
    scope,
    operation === "create" ? "created" : "updated",
    operation,
    "json-file",
    configPath
  );
}

/**
 * 按客户端官方约定解析配置文件位置（注意路径归属不同）：
 * - 【项目侧】trae：<project>/.trae/mcp.json；claude project：<cwd>/.mcp.json；
 * - 【Host 侧】claude user：CLAUDE_CONFIG_DIR 或 ~/.claude.json。
 *
 * 其中 <project> 与 <cwd> 就是 `MCPClientSetupInput.cwd`（目标 iOS 项目根目录）——
 * 这是「项目侧路径」真正的落点。
 *
 * @param input 注册输入。
 * @param scope 注册作用域。
 * @returns 配置文件绝对路径。
 */
function jsonConfigPath(input: MCPClientSetupInput, scope: MCPRegistrationScope): string {
  if (input.client === "trae") return join(input.cwd, ".trae", "mcp.json");
  if (scope === "project") return join(input.cwd, ".mcp.json");
  const configuredDirectory = input.env.CLAUDE_CONFIG_DIR?.trim();
  if (configuredDirectory === undefined || configuredDirectory.length === 0) return join(input.homeDir, ".claude.json");
  const directory = isAbsolute(configuredDirectory) ? configuredDirectory : resolve(input.cwd, configuredDirectory);
  return join(directory, ".claude.json");
}

/**
 * 构造要写入的 iOSDriver 注册对象（claude 额外带 type:"stdio"）。
 *
 * @param client 目标客户端。
 * @param launch 启动合同。
 * @returns mcpServers 中 iOSDriver 的值。
 */
function jsonRegistration(client: MCPClientName, launch: MCPLaunchCommand): Record<string, unknown> {
  return {
    ...(client === "claude" ? { type: "stdio" } : {}),
    command: launch.command,
    args: [...launch.args]
  };
}

/**
 * 读取客户端 JSON 配置：缺失（ENOENT）视为空文档；损坏（非 JSON）报错。
 *
 * @param path 配置文件路径。
 * @param fileSystem 文件 IO 边界。
 * @returns 配置对象（可能为空）。
 * @throws {MCPClientSetupError} 内容非对象或非法 JSON 时抛出。
 */
async function readJSONDocument(path: string, fileSystem: MCPSetupFileSystem): Promise<Record<string, unknown>> {
  try {
    const raw = await fileSystem.readFile(path);
    const parsed: unknown = JSON.parse(raw);
    if (!isRecord(parsed)) throw new MCPClientSetupError(`MCP 配置必须是 JSON 对象：${path}`);
    return parsed;
  } catch (error) {
    if (error instanceof MCPClientSetupError) throw error;
    if (isMissingFile(error)) return {};
    if (error instanceof SyntaxError) throw new MCPClientSetupError(`MCP 配置不是合法 JSON：${path}`);
    throw new MCPClientSetupError(`无法读取 MCP 配置 ${path}：${errorMessage(error)}`);
  }
}

/**
 * 原子写入 JSON 配置：先写同目录临时文件（pid+随机串防并发冲突）再 rename。
 *
 * @param path 目标路径。
 * @param document 完整配置对象。
 * @param fileSystem 文件 IO 边界。
 * @throws {MCPClientSetupError} rename 失败时抛出。
 */
async function writeJSONDocument(
  path: string,
  document: Record<string, unknown>,
  fileSystem: MCPSetupFileSystem
): Promise<void> {
  await fileSystem.mkdir(dirname(path));
  const temporary = `${path}.${process.pid}.${Math.random().toString(16).slice(2)}.tmp`;
  await fileSystem.writeFile(temporary, `${JSON.stringify(document, null, 2)}\n`);
  try {
    await fileSystem.rename(temporary, path);
  } catch (error) {
    throw new MCPClientSetupError(`无法写入 MCP 配置 ${path}：${errorMessage(error)}`);
  }
}

/**
 * 构造统一的结果对象。
 *
 * @param input 注册输入。
 * @param scope 最终作用域。
 * @param status 结果状态。
 * @param operation 实际/计划操作。
 * @param manager 管理器类型。
 * @param configPath JSON 客户端的配置文件路径（可选）。
 * @returns 注册结果。
 */
function result(
  input: MCPClientSetupInput,
  scope: MCPRegistrationScope,
  status: MCPClientSetupResult["status"],
  operation: MCPClientSetupResult["operation"],
  manager: MCPClientSetupResult["manager"],
  configPath?: string
): MCPClientSetupResult {
  return {
    client: input.client,
    scope,
    status,
    operation,
    registrationName: REGISTRATION_NAME,
    manager,
    ...(configPath === undefined ? {} : { configPath }),
    launch: { command: input.launch.command, args: [...input.launch.args] }
  };
}

/**
 * 比较真正影响 stdio 启动的字段（command/args/非空 env），用于幂等判断。
 * Codex 的 JSON 把启动配置嵌在 transport 字段中；空 env 与省略 env 等价。
 *
 * @param current 现有注册（codex 可能带 transport 包装）。
 * @param launch 期望启动合同。
 * @param codex 是否为 codex 格式（需要解包 transport）。
 * @returns true=启动配置相同（幂等，可跳过）。
 */
function launchMatches(current: Record<string, unknown>, launch: MCPLaunchCommand, codex: boolean): boolean {
  const transport = codex && isRecord(current.transport) ? current.transport : current;
  if (transport.type !== undefined && transport.type !== "stdio") return false;
  if (transport.command !== launch.command || !stringArrayEqual(transport.args, launch.args)) return false;
  const environment = transport.env;
  return environment === undefined || environment === null || (isRecord(environment) && Object.keys(environment).length === 0);
}

/** 逐元素比较字符串数组是否完全相等。 */
function stringArrayEqual(value: unknown, expected: readonly string[]): boolean {
  return Array.isArray(value)
    && value.length === expected.length
    && value.every((item, index) => item === expected[index]);
}

/**
 * 与对象键顺序无关的 JSON 深比较，用于识别可幂等跳过的现有注册。
 *
 * @param left 左值。
 * @param right 右值。
 * @returns true=结构相等。
 */
function jsonEqual(left: unknown, right: unknown): boolean {
  if (left === right) return true;
  if (Array.isArray(left) || Array.isArray(right)) {
    return Array.isArray(left)
      && Array.isArray(right)
      && left.length === right.length
      && left.every((item, index) => jsonEqual(item, right[index]));
  }
  if (!isRecord(left) || !isRecord(right)) return false;
  const leftKeys = Object.keys(left).sort();
  const rightKeys = Object.keys(right).sort();
  return stringArrayEqual(leftKeys, rightKeys) && leftKeys.every(key => jsonEqual(left[key], right[key]));
}

/**
 * 构造外部命令失败的稳定错误（stderr/stdout 摘要最多 500 字符）。
 *
 * @param command 失败的命令描述（如 "codex mcp add"）。
 * @param resultValue 命令执行结果。
 * @returns MCPClientSetupError。
 */
function commandError(command: string, resultValue: MCPSetupCommandResult): MCPClientSetupError {
  const detail = (resultValue.stderr.trim() || resultValue.stdout.trim()).slice(0, 500);
  return new MCPClientSetupError(`${command} 失败（exit ${resultValue.exitCode}）${detail.length === 0 ? "" : `：${detail}`}`);
}

/**
 * 生产命令执行边界：spawn 外部命令并完整捕获输出。
 *
 * 不继承 stdin（防止 setup 卡在交互提示）；输出只用于分类与截断的错误摘要。
 *
 * @param command 可执行文件路径。
 * @param args 参数列表。
 * @param options cwd 与 env。
 * @returns 退出码与完整 stdout/stderr。
 * @throws {MCPClientSetupError} 无法启动命令时抛出。
 */
async function runCommand(
  command: string,
  args: readonly string[],
  options: { readonly cwd: string; readonly env: NodeJS.ProcessEnv }
): Promise<MCPSetupCommandResult> {
  // 不继承 stdin，防止 setup 卡在交互提示；完整输出只用于分类并截断错误摘要。
  return new Promise((resolvePromise, rejectPromise) => {
    const child = spawn(command, [...args], {
      cwd: options.cwd,
      env: options.env,
      stdio: ["ignore", "pipe", "pipe"]
    });
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", chunk => { stdout += chunk.toString(); });
    child.stderr.on("data", chunk => { stderr += chunk.toString(); });
    child.once("error", error => rejectPromise(new MCPClientSetupError(`无法启动 ${command}：${error.message}`)));
    child.once("close", code => resolvePromise({ exitCode: code ?? 1, stdout, stderr }));
  });
}

/** 类型守卫：未知值是否为普通对象（非 null、非数组）。 */
function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/** 判断错误是否为文件不存在（ENOENT）。 */
function isMissingFile(error: unknown): boolean {
  return isRecord(error) && error.code === "ENOENT";
}

/** 安全提取错误消息（非 Error 不崩溃）。 */
function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}
