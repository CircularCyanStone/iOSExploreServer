import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import { CLIConfigError, type ConfigFileSystem } from "./configTypes.js";

export const defaultConfigFileSystem: ConfigFileSystem = {
  readFile: path => readFile(path, "utf8"),
  mkdir: path => mkdir(path, { recursive: true }).then(() => undefined),
  writeFile: (path, data) => writeFile(path, data, { encoding: "utf8", mode: 0o600 }),
  rename
};

export async function readConfigFile(
  path: string,
  fileSystem: ConfigFileSystem
): Promise<Record<string, unknown>> {
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

function isMissingFile(error: unknown): boolean {
  return typeof error === "object"
    && error !== null
    && (error as { code?: unknown }).code === "ENOENT";
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}
