import { spawn } from "node:child_process";
import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import { dirname, isAbsolute, join, resolve } from "node:path";

const REGISTRATION_NAME = "iOSDriver";

export type MCPClientName = "codex" | "claude" | "trae";
export type MCPRegistrationScope = "user" | "project";

export interface MCPLaunchCommand {
  readonly command: string;
  readonly args: readonly string[];
}

export interface MCPClientSetupInput {
  readonly client: MCPClientName;
  readonly scope?: MCPRegistrationScope;
  readonly dryRun?: boolean;
  readonly force?: boolean;
  readonly cwd: string;
  readonly homeDir: string;
  readonly env: NodeJS.ProcessEnv;
  readonly launch: MCPLaunchCommand;
}

export interface MCPClientSetupResult {
  readonly client: MCPClientName;
  readonly scope: MCPRegistrationScope;
  readonly status: "created" | "updated" | "unchanged" | "planned";
  readonly operation: "create" | "update" | "none";
  readonly registrationName: typeof REGISTRATION_NAME;
  readonly manager: "codex-cli" | "json-file";
  readonly configPath?: string;
  readonly launch: MCPLaunchCommand;
}

export interface MCPSetupFileSystem {
  readonly readFile: (path: string) => Promise<string>;
  readonly mkdir: (path: string) => Promise<void>;
  readonly writeFile: (path: string, data: string) => Promise<void>;
  readonly rename: (from: string, to: string) => Promise<void>;
}

export interface MCPSetupCommandResult {
  readonly exitCode: number;
  readonly stdout: string;
  readonly stderr: string;
}

export type MCPSetupCommandRunner = (
  command: string,
  args: readonly string[],
  options: { readonly cwd: string; readonly env: NodeJS.ProcessEnv }
) => Promise<MCPSetupCommandResult>;

export interface MCPClientSetupDependencies {
  readonly fileSystem?: MCPSetupFileSystem;
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

/** 把 iOSDriver 注册到指定 MCP 客户端；客户端差异全部封装在本模块内。 */
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
