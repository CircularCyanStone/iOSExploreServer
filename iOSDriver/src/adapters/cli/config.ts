/**
 * CLI 配置公共入口。
 *
 * 该文件只负责来源合并和初始化编排；类型、文件 IO 与纯值校验分别位于
 * configTypes.ts、configFile.ts、configValues.ts。
 */
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import type { JSONObject } from "../../types.js";
import {
  defaultConfigFileSystem,
  readConfigFile
} from "./config/configFile.js";
import {
  asJSONObject as parseJSONObject,
  authTokenValue,
  normalizeBaseURL,
  numberValue,
  parseOptionalNumber,
  positiveInteger,
  stringValue
} from "./config/configValues.js";
import type { CLIConfig, CLIConfigOverrides, ConfigFileSystem } from "./config/configTypes.js";
import { CLIConfigError } from "./config/configTypes.js";

export type { CLIConfig, CLIConfigOverrides, ConfigFileSystem } from "./config/configTypes.js";
export { CLIConfigError } from "./config/configTypes.js";

export function configPathFor(env: NodeJS.ProcessEnv = process.env, home = homedir()): string {
  if (env.IOSDRIVER_CONFIG?.trim()) return env.IOSDRIVER_CONFIG;
  if (env.XDG_CONFIG_HOME?.trim()) return join(env.XDG_CONFIG_HOME, "iosdriver", "config.json");
  return join(home, ".iosdriver", "config.json");
}

export async function resolveCLIConfig(
  overrides: CLIConfigOverrides = {},
  env: NodeJS.ProcessEnv = process.env,
  fileSystem: ConfigFileSystem = defaultConfigFileSystem
): Promise<CLIConfig> {
  const configPath = overrides.configPath ?? configPathFor(env);
  const fileValues = await readConfigFile(configPath, fileSystem);
  const baseURL = normalizeBaseURL(
    overrides.baseURL
      ?? env.IOS_EXPLORE_BASE_URL
      ?? stringValue(fileValues.baseURL, fileValues.baseUrl)
      ?? "http://localhost:38321/"
  );
  const requestTimeoutMs = positiveInteger(
    overrides.requestTimeoutMs
      ?? parseOptionalNumber(env.IOS_EXPLORE_REQUEST_TIMEOUT_MS)
      ?? numberValue(fileValues.requestTimeoutMs, fileValues.request_timeout_ms)
      ?? 10_000,
    "requestTimeoutMs"
  );
  const authToken = authTokenValue(env.IOS_EXPLORE_AUTH_TOKEN)
    ?? authTokenValue(stringValue(fileValues.authToken, fileValues.auth_token));
  return Object.freeze({
    baseURL,
    requestTimeoutMs,
    ...(authToken === undefined ? {} : { authToken }),
    configPath,
    fileValues: Object.freeze({ ...fileValues })
  });
}

export async function initCLIConfig(
  overrides: CLIConfigOverrides = {},
  env: NodeJS.ProcessEnv = process.env,
  fileSystem: ConfigFileSystem = defaultConfigFileSystem
): Promise<{ readonly config: CLIConfig; readonly configChanged: boolean }> {
  const configPath = overrides.configPath ?? configPathFor(env);
  const existing = await readConfigFile(configPath, fileSystem);
  const baseURL = normalizeBaseURL(
    overrides.baseURL
      ?? env.IOS_EXPLORE_BASE_URL
      ?? stringValue(existing.baseURL, existing.baseUrl)
      ?? "http://localhost:38321/"
  );
  const requestTimeoutMs = positiveInteger(
    overrides.requestTimeoutMs
      ?? parseOptionalNumber(env.IOS_EXPLORE_REQUEST_TIMEOUT_MS)
      ?? numberValue(existing.requestTimeoutMs, existing.request_timeout_ms)
      ?? 10_000,
    "requestTimeoutMs"
  );
  const authToken = authTokenValue(env.IOS_EXPLORE_AUTH_TOKEN)
    ?? authTokenValue(stringValue(existing.authToken, existing.auth_token));
  const next: Record<string, unknown> = {
    ...existing,
    baseURL: existing.baseURL ?? baseURL,
    requestTimeoutMs: existing.requestTimeoutMs ?? requestTimeoutMs
  };
  const serialized = `${JSON.stringify(next, null, 2)}\n`;
  const previous = Object.keys(existing).length === 0
    ? undefined
    : `${JSON.stringify(existing, null, 2)}\n`;
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

export function asJSONObject(value: unknown): JSONObject {
  return parseJSONObject(value);
}
