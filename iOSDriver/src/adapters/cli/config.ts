/**
 * CLI 配置层：配置值的读取、四层优先级合并、校验与原子初始化。
 *
 * 程序运行需要三个值：App 地址（baseURL）、请求超时（requestTimeoutMs）、预留认证
 * token（authToken）。每个值都有四个可能来源，优先级固定为：
 *
 *   命令行参数（--base-url/--timeout/--config）> 环境变量（IOS_EXPLORE_*）
 *     > 配置文件（~/.config/iosdriver/config.json）> 默认值
 *
 * 职责划分：
 * - `resolveCLIConfig`：只读合并，供所有命令使用（文件缺失时用默认值，不创建文件）；
 * - `initCLIConfig`：写路径，供 `iosdriver init` 使用（保留已有字段、原子写入）；
 * - `CLIConfigError`：本层所有错误的统一类型，上层映射为退出码 2。
 *
 * 兼容性：读取时同时接受早期 snake_case 键（baseUrl/request_timeout_ms），
 * 但写入只补 canonical camelCase 键，且始终保留文件中的未知字段。
 */
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import type { JSONObject } from "../../types.js";

/**
 * 命令行可覆盖的配置字段（来自 `arguments.ts` 的解析结果）。
 *
 * 三个字段全部可选，且对象中**只存在用户实际传入的字段**（条件展开保证）——
 * 这是四层优先级合并的前提：只有「用户真的传了」才覆盖下层来源。
 */
export interface CLIConfigOverrides {
  /** App HTTP endpoint 覆盖值，如 "http://192.168.1.5:38321/"。 */
  readonly baseURL?: string;
  /** 请求超时覆盖值，毫秒正整数，如 2500。 */
  readonly requestTimeoutMs?: number;
  /** 配置文件路径覆盖值；同时决定读取位置和 `init` 写入位置。 */
  readonly configPath?: string;
}

/**
 * 合并完成后的最终配置（不可变）。
 *
 * 由 `resolveCLIConfig`/`initCLIConfig` 返回；整体被 `Object.freeze`，
 * runtime/adapter 只能消费不能修改——防止某处偷偷改 baseURL 导致请求打到别处。
 */
export interface CLIConfig {
  /** 已规范化的 App 地址：必须 http(s) 且 pathname 以 `/` 结尾（保证请求打到 `POST /`）。 */
  readonly baseURL: string;
  /** 已验证的请求超时，毫秒正整数，默认 10000。 */
  readonly requestTimeoutMs: number;
  /** 预留的认证 token（当前 App 不校验）；配置为空时该字段不存在。 */
  readonly authToken?: string;
  /** 本次解析实际使用的配置文件路径；即使文件尚不存在也会返回（供 init 使用）。 */
  readonly configPath: string;
  /** 配置文件的原始内容（含未知字段，未做投影）；供 `init` 幂等合并时保留用户字段。 */
  readonly fileValues: Readonly<Record<string, unknown>>;
}

/**
 * 配置层错误（非法值、文件损坏、无法写入等）。
 *
 * 上层（commands.ts / application.ts）用 `error instanceof CLIConfigError` 判断
 * 「这是配置问题」→ 映射退出码 2；其他错误类型不会被误判为配置问题。
 * `code` 字段供脚本做稳定判断。
 */
export class CLIConfigError extends Error {
  /** 稳定错误码："invalid_config"。 */
  readonly code = "invalid_config";

  constructor(message: string) {
    super(message);
    // 不设置 name，Error 堆栈会显示 "Error" 而不是类名；这里显式覆盖。
    this.name = "CLIConfigError";
  }
}

/**
 * 配置文件 IO 边界（依赖注入插头）。
 *
 * 生产实现 `defaultFileSystem` 用 Node 真实 fs；测试注入内存/临时文件实现，
 * 使合并、幂等、原子写入逻辑可以在不碰磁盘的情况下毫秒级验证。
 */
export interface ConfigFileSystem {
  /** 读文件；文件缺失时必须以带 `code: "ENOENT"` 的错误拒绝（调用方据此视为空配置）。 */
  readonly readFile: (path: string) => Promise<string>;
  /** 创建目录；实现必须支持递归创建父目录。 */
  readonly mkdir: (path: string) => Promise<void>;
  /** 写文件；生产实现按仅当前用户可读写的权限（0o600）创建。 */
  readonly writeFile: (path: string, data: string) => Promise<void>;
  /** 原子替换：把临时文件改为最终路径；生产实现借此避免留下半写配置。 */
  readonly rename: (from: string, to: string) => Promise<void>;
}

/**
 * 生产环境默认文件系统实现：直接代理 `node:fs/promises`。
 *
 * `writeFile` 固定 0o600 权限（仅当前用户可读写）——配置文件可能含 authToken，
 * 不能让其他用户读取。
 */
const defaultFileSystem: ConfigFileSystem = {
  readFile: path => readFile(path, "utf8"),
  mkdir: path => mkdir(path, { recursive: true }).then(() => undefined),
  writeFile: (path, data) => writeFile(path, data, { encoding: "utf8", mode: 0o600 }),
  rename
};

/**
 * 计算配置文件路径：显式变量 > XDG_CONFIG_HOME > 用户目录回退。
 *
 * 三档优先级：
 * 1. `IOSDRIVER_CONFIG`：用户显式指定完整路径，直接返回；
 * 2. `XDG_CONFIG_HOME`：Linux 惯例的配置根目录，拼 `iosdriver/config.json`；
 * 3. 回退 `~/.config/iosdriver/config.json`（macOS 实际命中这一档）。
 *
 * @param env 环境变量集合（默认 `process.env`）。
 * @param home 用户主目录（默认 `os.homedir()`）。
 * @returns 配置文件绝对路径。
 *   示例（macOS 无显式变量）："/Users/coo/.config/iosdriver/config.json"。
 */
export function configPathFor(env: NodeJS.ProcessEnv = process.env, home = homedir()): string {
  if (env.IOSDRIVER_CONFIG?.trim()) return env.IOSDRIVER_CONFIG;
  if (env.XDG_CONFIG_HOME?.trim()) return join(env.XDG_CONFIG_HOME, "iosdriver", "config.json");
  return join(home, ".config", "iosdriver", "config.json");
}

/**
 * 合并四层来源并校验，返回不可变配置（只读路径，不创建文件）。
 *
 * 每个字段的合并链都是：`命令行 ?? 环境变量 ?? 配置文件 ?? 默认值`。
 * 为什么用 `??` 而不是 `||`：`||` 会把空串/0/false 当假值跳过，而空串在这里是
 * 非法值（应交由 normalizeBaseURL 报错），不该被静默跳过。
 * 注意环境变量永远是字符串（要先 parseOptionalNumber 转数字），而配置文件里是
 * JSON 原生 number——所以同一个字段要分 string/number 两套取值函数。
 *
 * @param overrides 命令行覆盖项（只含用户实际传入的字段），默认空对象。
 * @param env 环境变量集合，默认 `process.env`。
 * @param fileSystem 文件 IO 边界，默认真实 fs。
 * @returns 冻结的 `CLIConfig`（含 fileValues 原始文件内容）。
 *   示例：无命令行、无环境变量、文件不存在 →
 *     { baseURL:"http://localhost:38321/", requestTimeoutMs:10000, configPath, fileValues:{} }
 * @throws {CLIConfigError} baseURL 非法、timeout 非正整数、文件损坏时抛出。
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
 * 创建/补全配置文件（`iosdriver init` 的实现），保留已有字段与未知字段。
 *
 * 与 `resolveCLIConfig` 的差异：多一个「写入」步骤，且遵循三条规则——
 * 1. **已有值优先**：`existing.baseURL ?? baseURL`，文件里已有字段绝不被环境变量/默认值覆盖；
 * 2. **保留未知字段**：`...existing` 展开保留用户自定义字段，只补缺失的 baseURL/requestTimeoutMs；
 * 3. **幂等 + 原子**：序列化内容与之前相同则不碰磁盘；需要写入时先写同目录临时文件
 *    （带 pid+随机串防并发冲突）再 `rename` 原子替换——rename 不存在「写一半」的中间态。
 *
 * authToken 特殊处理：即使环境变量/文件里有 token，也**不会**写入文件——
 * 进程秘密不持久化到磁盘。
 *
 * @param overrides 命令行覆盖项。
 * @param env 环境变量集合。
 * @param fileSystem 文件 IO 边界。
 * @returns `{ config, configChanged }`：config 为最终冻结配置；configChanged 表示
 *   本次是否实际写了文件（安装脚本据此区分首次写入与幂等执行）。
 *   示例：首次执行 → configChanged=true；再次执行（内容未变）→ configChanged=false。
 * @throws {CLIConfigError} 值非法或文件写入失败（如 EPERM）时抛出。
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

/**
 * 读取配置文件并解析为 JSON 对象，处理三种边界情况。
 *
 * - 文件不存在（ENOENT）→ 返回 `{}`（空配置，继续用默认值，**不是错误**）；
 * - JSON 不是对象（数组/字符串/数字）→ CLIConfigError；
 * - JSON 解析失败（文件损坏）→ 包装成 CLIConfigError。
 *
 * @param path 配置文件路径。
 * @param fileSystem 文件 IO 边界。
 * @returns 配置文件的原始内容（Record 类型，未校验字段值）。
 * @throws {CLIConfigError} 文件损坏或内容不是 JSON 对象时抛出。
 */
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

/**
 * 规范化 baseURL：非空字符串 → 合法 URL → http/https → 补尾斜杠。
 *
 * 尾斜杠是生死问题：App 的端点固定是 `POST /`。无尾斜杠的 `http://localhost:38321`
 * pathname 为空，请求可能打到别的路径；补上 `/` 才能保证 `POST /` 语义。
 *
 * @param raw 原始输入（可能来自命令行、环境变量、文件或默认值）。
 * @returns 规范化后的 URL 字符串（如 "http://localhost:38321/"）。
 * @throws {CLIConfigError} 非字符串、空串、URL 无法解析、协议非 http/https 时抛出。
 *   示例："http://localhost:38321" → "http://localhost:38321/"；
 *         "ftp://x" → 抛错。
 */
function normalizeBaseURL(raw: unknown): string {
  if (typeof raw !== "string" || raw.trim().length === 0) throw new CLIConfigError("baseURL 必须是非空 URL");
  let url: URL;
  try { url = new URL(raw); } catch { throw new CLIConfigError(`baseURL 不是有效 URL: ${raw}`); }
  if (url.protocol !== "http:" && url.protocol !== "https:") throw new CLIConfigError("baseURL 必须使用 http 或 https");
  if (!url.pathname.endsWith("/")) url.pathname += "/";
  return url.toString();
}

/**
 * 校验未知来源的 timeout 值必须是正整数毫秒数。
 *
 * @param raw 待校验值（来自命令行解析或环境变量转换）。
 * @param field 字段名（仅用于报错信息，如 "requestTimeoutMs"）。
 * @returns 原样返回通过校验的数字。
 * @throws {CLIConfigError} 非 number、非整数、<=0 时抛出。
 */
function positiveInteger(raw: unknown, field: string): number {
  if (typeof raw !== "number" || !Number.isInteger(raw) || raw <= 0) throw new CLIConfigError(`${field} 必须是正整数`);
  return raw;
}

/**
 * 从多个候选值中取第一个 string 类型的值。
 *
 * 用途：配置文件的字段可能是任意 JSON 类型（比如被塞了个数字），
 * 这里只认字符串并跳过其他类型，而不是直接报错。
 *
 * @param values 候选值列表（通常来自文件的不同键名，如 baseURL/baseUrl）。
 * @returns 第一个 string 值；全部不是 string 则返回 undefined。
 */
function stringValue(...values: unknown[]): string | undefined {
  return values.find(value => typeof value === "string") as string | undefined;
}

/**
 * 从多个候选值中取第一个 number 类型的值（与 `stringValue` 对称）。
 *
 * @param values 候选值列表（通常来自文件的不同键名，如 requestTimeoutMs/request_timeout_ms）。
 * @returns 第一个 number 值；全部不是 number 则返回 undefined。
 */
function numberValue(...values: unknown[]): number | undefined {
  return values.find(value => typeof value === "number") as number | undefined;
}

/**
 * 把环境变量字符串转成正整数（环境变量永远是字符串，需要转换）。
 *
 * @param value 环境变量原始字符串（如 "2500"）；未设置/undefined 直接返回 undefined。
 * @returns 正整数；未设置时 undefined。
 * @throws {CLIConfigError} 非整数（如 "abc"、"1.5"）时抛出——负数/0 在此不拦，
 *   由调用方后续的 `positiveInteger` 统一校验。
 */
function parseOptionalNumber(value: string | undefined): number | undefined {
  if (value === undefined) return undefined;
  const number = Number(value);
  if (!Number.isInteger(number)) throw new CLIConfigError("IOS_EXPLORE_REQUEST_TIMEOUT_MS 必须是正整数");
  return number;
}

/**
 * 规范化 token：空白串等价于未配置。
 *
 * 避免发送无意义的空认证 header；同时 init 用它保证「空白 token 不写入文件」。
 *
 * @param value 原始 token 字符串。
 * @returns trim 后的非空 token；undefined/空白串返回 undefined。
 *   示例：" abc " → "abc"；"  " → undefined。
 */
function authTokenValue(value: string | undefined): string | undefined {
  const token = value?.trim();
  return token === undefined || token.length === 0 ? undefined : token;
}

/**
 * 判断错误是否为「文件不存在」（Node 文件系统错误码约定）。
 *
 * @param error 任意异常。
 * @returns true=错误带 `code: "ENOENT"`（直接或 cause 嵌套）。
 */
function isMissingFile(error: unknown): boolean {
  return typeof error === "object" && error !== null && (error as { code?: unknown }).code === "ENOENT";
}

/**
 * 安全提取错误消息（未知类型不会崩溃）。
 *
 * @param error 任意异常。
 * @returns Error 实例的 message，非 Error 则 String() 转换。
 */
function errorMessage(error: unknown): string { return error instanceof Error ? error.message : String(error); }

/**
 * 把 `call --data` 的解析结果限制为 JSON 对象。
 *
 * App wire 协议固定要求 `data` 为对象（`{"action":…,"data":{…}}`）；数组、null、
 * 标量在发出网络请求**之前**就应失败，而不是等 App 报协议错误。
 *
 * @param value 任意 JSON 解析结果。
 * @returns 原对象（类型收窄为 JSONObject）。
 * @throws {CLIConfigError} 非对象、null、数组时抛出，消息 "data 必须是 JSON 对象"。
 *   示例：`{"mode":"minimal"}` → 通过；`[1,2]` → 抛错。
 */
export function asJSONObject(value: unknown): JSONObject {
  if (typeof value !== "object" || value === null || Array.isArray(value)) throw new CLIConfigError("data 必须是 JSON 对象");
  return value as JSONObject;
}
