import { readFile } from "node:fs/promises";
import type { DriverError } from "../../../runtime/driverErrors.js";
import { CLIConfigError, asJSONObject } from "../config.js";
import { EXIT_CODES } from "./commandTypes.js";

export async function parseData(
  raw: string | undefined,
  read: (path: string) => Promise<string> = path => readFile(path, "utf8")
): Promise<ReturnType<typeof asJSONObject>> {
  if (raw === undefined) return {};
  let source: string;
  if (raw.startsWith("@")) {
    try {
      source = await read(raw.slice(1));
    } catch {
      throw new CLIConfigError(`无法读取 data 文件: ${raw.slice(1)}`);
    }
  } else {
    source = raw;
  }
  let parsed: unknown;
  try {
    parsed = JSON.parse(source);
  } catch {
    throw new CLIConfigError("call --data 必须是合法 JSON");
  }
  return asJSONObject(parsed);
}

export function exitCodeForError(error: DriverError): number {
  if (error.source === "config") return EXIT_CODES.configError;
  if (
    error.source === "transport"
    || error.source === "http"
    || error.source === "protocol"
    || error.source === "artifact"
  ) {
    return EXIT_CODES.transportFailure;
  }
  return EXIT_CODES.appFailure;
}

export function minimumNodeVersion(version: string, minimumMajor: number): boolean {
  const major = Number.parseInt(version.split(".")[0] ?? "0", 10);
  return Number.isFinite(major) && major >= minimumMajor;
}
