/**
 * CLI 配置的读取、合并与原子初始化。
 *
 * 有效值优先级固定为 CLI override > 环境变量 > 配置文件 > 默认值。读取时同时接受
 * 早期 snake_case 键，但初始化只补写 canonical camelCase 键，并始终保留未知字段。
 */
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import type { JSONObject } from "../../types.js";

/** CLI 可覆盖的配置字段。值在解析时会被规范化并冻结。 */
export interface CLIConfigOverrides {
  /** 最高优先级 endpoint 覆盖值。 */
  readonly baseURL?: string;
  /** 最高优先级请求超时覆盖值，必须为毫秒正整数。 */
  readonly requestTimeoutMs?: number;
  /** 同时决定读取位置和 `init` 写入位置。 */
  readonly configPath?: string;
}

/** iosdriver 使用的不可变配置，以及 init 所需的原始用户字段。 */
export interface CLIConfig {
  /** 已规范化为 http(s) 且 pathname 以 `/` 结尾。 */
  readonly baseURL: string;
  /** 已验证的毫秒正整数。 */
  readonly requestTimeoutMs: number;
  /** 预留 header token；当前 App 产品开关关闭，不执行校验。 */
  readonly authToken?: string;
  /** 本次解析实际使用的配置文件路径，即使文件尚不存在也会返回。 */
  readonly configPath: string;
  /** 未经丢字段投影的原始文件对象，供 `init` 幂等合并。 */
  readonly fileValues: Readonly<Record<string, unknown>>;
}

/** 配置错误；main 将其映射为固定 exit code 2。 */
export class CLIConfigError extends Error {
  readonly code = "invalid_config";

  constructor(message: string) {
    super(message);
    this.name = "CLIConfigError";
  }
}

/** 配置文件 IO 边界，测试可注入内存或临时文件实现。 */
export interface ConfigFileSystem {
  /** 缺失文件应以带 `code: ENOENT` 的错误表示。 */
  readonly readFile: (path: string) => Promise<string>;
  /** 实现必须支持递归创建父目录。 */
  readonly mkdir: (path: string) => Promise<void>;
  /** 临时文件按仅当前用户可读写的权限创建。 */
  readonly writeFile: (path: string, data: string) => Promise<void>;
  /** 最终替换步骤；生产实现借此避免留下半写配置。 */
  readonly rename: (from: string, to: string) => Promise<void>;
}

const defaultFileSystem: ConfigFileSystem = {
  readFile: path => readFile(path, "utf8"),
  mkdir: path => mkdir(path, { recursive: true }).then(() => undefined),
  writeFile: (path, data) => writeFile(path, data, { encoding: "utf8", mode: 0o600 }),
  rename
};

/** 计算配置文件路径：显式变量 > XDG_CONFIG_HOME > 用户目录回退。 */
export function configPathFor(env: NodeJS.ProcessEnv = process.env, home = homedir()): string {
  if (env.IOSDRIVER_CONFIG?.trim()) return env.IOSDRIVER_CONFIG;
  if (env.XDG_CONFIG_HOME?.trim()) return join(env.XDG_CONFIG_HOME, "iosdriver", "config.json");
  return join(home, ".config", "iosdriver", "config.json");
}

/**
 * 解析 CLI、环境变量、配置文件和默认值，并拒绝无效配置。
 *
 * 返回对象及 `fileValues` 均被冻结，后续 runtime/adapter 只能消费，不能在命令执行
 * 过程中改变已解析配置。该函数只读，不会因为配置文件缺失而创建文件。
 */
export async function resolveCLIConfig(
  overrides: CLIConfigOverrides = {},
  env: NodeJS.ProcessEnv = process.env,
  fileSystem: ConfigFileSystem = defaultFileSystem
): Promise<CLIConfig> {
  const configPath = overrides.configPath ?? configPathFor(env);
  const fileValues = await readConfigFile(configPath, fileSystem);
  const baseURL = normalizeBaseURL(
    overrides.baseURL ?? env.IOS_EXPLORE_BASE_URL ?? stringValue(fileValues.baseURL, fileValues.baseUrl) ?? "http://localhost:38321/"
  );
  const timeoutRaw = overrides.requestTimeoutMs
    ?? parseOptionalNumber(env.IOS_EXPLORE_REQUEST_TIMEOUT_MS)
    ?? numberValue(fileValues.requestTimeoutMs, fileValues.request_timeout_ms)
    ?? 10_000;
  const requestTimeoutMs = positiveInteger(timeoutRaw, "requestTimeoutMs");
  const authToken = authTokenValue(env.IOS_EXPLORE_AUTH_TOKEN) ?? authTokenValue(stringValue(fileValues.authToken, fileValues.auth_token));
  return Object.freeze({
    baseURL,
    requestTimeoutMs,
    ...(authToken === undefined ? {} : { authToken }),
    configPath,
    fileValues: Object.freeze({ ...fileValues })
  });
}

/**
 * 原子、幂等地初始化配置；保留已有用户字段和未知字段。
 *
 * 环境变量只影响本次解析，不会把 `IOS_EXPLORE_AUTH_TOKEN` 等进程秘密持久化到磁盘。
 * 需要写入时先创建同目录临时文件再 rename；序列化内容未变化时完全不触碰文件系统。
 */
export async function initCLIConfig(
  overrides: CLIConfigOverrides = {},
  env: NodeJS.ProcessEnv = process.env,
  fileSystem: ConfigFileSystem = defaultFileSystem
): Promise<{ readonly config: CLIConfig; readonly configChanged: boolean }> {
  const configPath = overrides.configPath ?? configPathFor(env);
  const existing = await readConfigFile(configPath, fileSystem);
  const baseURL = normalizeBaseURL(
    overrides.baseURL ?? env.IOS_EXPLORE_BASE_URL ?? stringValue(existing.baseURL, existing.baseUrl) ?? "http://localhost:38321/"
  );
  const requestTimeoutMs = positiveInteger(
    overrides.requestTimeoutMs
      ?? parseOptionalNumber(env.IOS_EXPLORE_REQUEST_TIMEOUT_MS)
      ?? numberValue(existing.requestTimeoutMs, existing.request_timeout_ms)
      ?? 10_000,
    "requestTimeoutMs"
  );
  const authToken = authTokenValue(env.IOS_EXPLORE_AUTH_TOKEN) ?? authTokenValue(stringValue(existing.authToken, existing.auth_token));
  const next: Record<string, unknown> = {
    ...existing,
    baseURL: existing.baseURL ?? baseURL,
    requestTimeoutMs: existing.requestTimeoutMs ?? requestTimeoutMs
  };
  const serialized = `${JSON.stringify(next, null, 2)}\n`;
  const previous = Object.keys(existing).length === 0 ? undefined : `${JSON.stringify(existing, null, 2)}\n`;
  let configChanged = false;
  if (serialized !== previous) {
    await fileSystem.mkdir(dirname(configPath));
    const temporary = `${configPath}.${process.pid}.${Math.random().toString(16).slice(2)}.tmp`;
    await fileSystem.writeFile(temporary, serialized);
    await fileSystem.rename(temporary, configPath);
    configChanged = true;
  }
  return {
    config: Object.freeze({
      baseURL,
      requestTimeoutMs,
      ...(authToken === undefined ? {} : { authToken }),
      configPath,
      fileValues: Object.freeze(next)
    }),
    configChanged
  };
}

async function readConfigFile(path: string, fileSystem: ConfigFileSystem): Promise<Record<string, unknown>> {
  try {
    const raw = await fileSystem.readFile(path);
    const parsed: unknown = JSON.parse(raw);
    if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) {
      throw new CLIConfigError(`配置文件必须是 JSON 对象: ${path}`);
    }
    return parsed as Record<string, unknown>;
  } catch (error) {
    if (error instanceof CLIConfigError) throw error;
    if (isMissingFile(error)) return {};
    throw new CLIConfigError(`无法读取配置文件 ${path}: ${errorMessage(error)}`);
  }
}

/** 规范化 endpoint，确保相对 URL 解析和固定 `POST /` 行为不会受缺失尾斜杠影响。 */
function normalizeBaseURL(raw: unknown): string {
  if (typeof raw !== "string" || raw.trim().length === 0) throw new CLIConfigError("baseURL 必须是非空 URL");
  let url: URL;
  try { url = new URL(raw); } catch { throw new CLIConfigError(`baseURL 不是有效 URL: ${raw}`); }
  if (url.protocol !== "http:" && url.protocol !== "https:") throw new CLIConfigError("baseURL 必须使用 http 或 https");
  if (!url.pathname.endsWith("/")) url.pathname += "/";
  return url.toString();
}

function positiveInteger(raw: unknown, field: string): number {
  if (typeof raw !== "number" || !Number.isInteger(raw) || raw <= 0) throw new CLIConfigError(`${field} 必须是正整数`);
  return raw;
}

function stringValue(...values: unknown[]): string | undefined {
  return values.find(value => typeof value === "string") as string | undefined;
}

function numberValue(...values: unknown[]): number | undefined {
  return values.find(value => typeof value === "number") as number | undefined;
}

function parseOptionalNumber(value: string | undefined): number | undefined {
  if (value === undefined) return undefined;
  const number = Number(value);
  if (!Number.isInteger(number)) throw new CLIConfigError("IOS_EXPLORE_REQUEST_TIMEOUT_MS 必须是正整数");
  return number;
}

/** 空白 token 等价于未配置，避免发送无意义的认证 header。 */
function authTokenValue(value: string | undefined): string | undefined {
  const token = value?.trim();
  return token === undefined || token.length === 0 ? undefined : token;
}

function isMissingFile(error: unknown): boolean {
  return typeof error === "object" && error !== null && (error as { code?: unknown }).code === "ENOENT";
}

function errorMessage(error: unknown): string { return error instanceof Error ? error.message : String(error); }

/**
 * 将 CLI 传入的 data 限制为 JSON 对象。
 *
 * App wire 协议固定要求 `data` 为对象；数组、null 和标量在发送网络请求前就应失败。
 */
export function asJSONObject(value: unknown): JSONObject {
  if (typeof value !== "object" || value === null || Array.isArray(value)) throw new CLIConfigError("data 必须是 JSON 对象");
  return value as JSONObject;
}
