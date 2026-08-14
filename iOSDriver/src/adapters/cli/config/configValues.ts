import type { JSONObject } from "../../../types.js";
import { CLIConfigError } from "./configTypes.js";

export function normalizeBaseURL(raw: unknown): string {
  if (typeof raw !== "string" || raw.trim().length === 0) {
    throw new CLIConfigError("baseURL 必须是非空 URL");
  }
  let url: URL;
  try {
    url = new URL(raw);
  } catch {
    throw new CLIConfigError(`baseURL 不是有效 URL: ${raw}`);
  }
  if (url.protocol !== "http:" && url.protocol !== "https:") {
    throw new CLIConfigError("baseURL 必须使用 http 或 https");
  }
  if (!url.pathname.endsWith("/")) url.pathname += "/";
  return url.toString();
}

export function positiveInteger(raw: unknown, field: string): number {
  if (typeof raw !== "number" || !Number.isInteger(raw) || raw <= 0) {
    throw new CLIConfigError(`${field} 必须是正整数`);
  }
  return raw;
}

export function parseOptionalNumber(value: string | undefined): number | undefined {
  if (value === undefined) return undefined;
  const number = Number(value);
  if (!Number.isInteger(number)) {
    throw new CLIConfigError("IOS_EXPLORE_REQUEST_TIMEOUT_MS 必须是正整数");
  }
  return number;
}

export function stringValue(...values: unknown[]): string | undefined {
  return values.find(value => typeof value === "string") as string | undefined;
}

export function numberValue(...values: unknown[]): number | undefined {
  return values.find(value => typeof value === "number") as number | undefined;
}

export function authTokenValue(value: string | undefined): string | undefined {
  const token = value?.trim();
  return token === undefined || token.length === 0 ? undefined : token;
}

export function asJSONObject(value: unknown): JSONObject {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new CLIConfigError("data 必须是 JSON 对象");
  }
  return value as JSONObject;
}
