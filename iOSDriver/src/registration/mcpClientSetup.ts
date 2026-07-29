/**
 * MCP 客户端注册的跨客户端实现。
 *
 * Codex 通过官方 `codex mcp` 命令管理配置；Claude Code/TRAE 使用各自 JSON 文件。本模块
 * 保留其他 server 和未知顶层字段，同名不同配置默认拒绝覆盖，JSON 写入采用临时文件
 * rename，确保 setup 可重复执行且不会留下半写文件。
 */
import { spawn } from "node:child_process";
import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import { dirname, isAbsolute, join, resolve } from "node:path";

const REGISTRATION_NAME = "iOSDriver";

export type MCPClientName = "codex" | "claude" | "trae";
export type MCPRegistrationScope = "user" | "project";

export interface MCPLaunchCommand {
  /** setup 调用方已解析出的绝对 Node 可执行文件。 */
  readonly command: string;
  /** 包含绝对 CLI 入口、`mcp --config <absolute-path>` 的固定参数。 */
  readonly args: readonly string[];
}

export interface MCPClientSetupInput {
  readonly client: MCPClientName;
  /** 省略时 Codex 默认 user，Claude/TRAE 默认 project。 */
  readonly scope?: MCPRegistrationScope;
  /** 计算并返回 create/update 计划，但不运行命令或写 JSON。 */
  readonly dryRun?: boolean;
  /** 只影响同名不同配置；完全相同的配置仍返回 unchanged。 */
  readonly force?: boolean;
  /** project 配置定位基准，也是 Codex 子命令的工作目录。 */
  readonly cwd: string;
  /** Claude user scope 默认配置位置的解析基准。 */
  readonly homeDir: string;
  /** 透传给 Codex CLI，并读取 `CLAUDE_CONFIG_DIR`。 */
  readonly env: NodeJS.ProcessEnv;
  /** 要写入客户端的完整 stdio 启动合同。 */
  readonly launch: MCPLaunchCommand;
}

export interface MCPClientSetupResult {
  readonly client: MCPClientName;
  readonly scope: MCPRegistrationScope;
  readonly status: "created" | "updated" | "unchanged" | "planned";
  /** planned 时表示将执行的动作；unchanged 时为 none。 */
  readonly operation: "create" | "update" | "none";
  readonly registrationName: typeof REGISTRATION_NAME;
  readonly manager: "codex-cli" | "json-file";
  /** JSON 客户端的目标文件；Codex 由 CLI 管理，不暴露内部路径。 */
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

export interface MCPClientSetupDependencies {
  /** Claude/TRAE JSON 写入边界；Codex 路径不使用。 */
  readonly fileSystem?: MCPSetupFileSystem;
  /** Codex CLI 执行边界；JSON 客户端路径不使用。 */
  readonly runCommand?: MCPSetupCommandRunner;
}

export class MCPClientSetupError extends Error {
  readonly code = "mcp_setup_failed";

  constructor(message: string) {
    super(message);
    this.name = "MCPClientSetupError";
  }
}

const defaultFileSystem: MCPSetupFileSystem = {
  readFile: path => readFile(path, "utf8"),
  mkdir: path => mkdir(path, { recursive: true }).then(() => undefined),
  writeFile: (path, data) => writeFile(path, data, { encoding: "utf8", mode: 0o600 }),
  rename
};

/**
 * 把 iOSDriver 注册到指定 MCP 客户端。
 *
 * 先解析 client/scope 的合法组合，再路由到官方 CLI 或 JSON 管理器。函数不检查 App
 * 连接，因为注册只描述未来如何启动 `iosdriver mcp`。
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

/** 按客户端官方约定解析配置位置；相对 CLAUDE_CONFIG_DIR 以 project cwd 为基准。 */
function jsonConfigPath(input: MCPClientSetupInput, scope: MCPRegistrationScope): string {
  if (input.client === "trae") return join(input.cwd, ".trae", "mcp.json");
  if (scope === "project") return join(input.cwd, ".mcp.json");
  const configuredDirectory = input.env.CLAUDE_CONFIG_DIR?.trim();
  if (configuredDirectory === undefined || configuredDirectory.length === 0) return join(input.homeDir, ".claude.json");
  const directory = isAbsolute(configuredDirectory) ? configuredDirectory : resolve(input.cwd, configuredDirectory);
  return join(directory, ".claude.json");
}

function jsonRegistration(client: MCPClientName, launch: MCPLaunchCommand): Record<string, unknown> {
  return {
    ...(client === "claude" ? { type: "stdio" } : {}),
    command: launch.command,
    args: [...launch.args]
  };
}

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
 * 比较真正影响 stdio 启动的字段。
 * Codex JSON 把启动配置嵌在 transport；空 env 与省略 env 等价，非空 env 视为不同配置。
 */
function launchMatches(current: Record<string, unknown>, launch: MCPLaunchCommand, codex: boolean): boolean {
  const transport = codex && isRecord(current.transport) ? current.transport : current;
  if (transport.type !== undefined && transport.type !== "stdio") return false;
  if (transport.command !== launch.command || !stringArrayEqual(transport.args, launch.args)) return false;
  const environment = transport.env;
  return environment === undefined || environment === null || (isRecord(environment) && Object.keys(environment).length === 0);
}

function stringArrayEqual(value: unknown, expected: readonly string[]): boolean {
  return Array.isArray(value)
    && value.length === expected.length
    && value.every((item, index) => item === expected[index]);
}

/** 与对象键顺序无关的 JSON 深比较，用于识别可幂等跳过的现有注册。 */
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

function commandError(command: string, resultValue: MCPSetupCommandResult): MCPClientSetupError {
  const detail = (resultValue.stderr.trim() || resultValue.stdout.trim()).slice(0, 500);
  return new MCPClientSetupError(`${command} 失败（exit ${resultValue.exitCode}）${detail.length === 0 ? "" : `：${detail}`}`);
}

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

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isMissingFile(error: unknown): boolean {
  return isRecord(error) && error.code === "ENOENT";
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}
