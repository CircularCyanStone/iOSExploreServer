import type { JSONObject } from "./types.js";

export type MCPServerConfig = {
  baseURL: string;
  requestTimeoutMs: number;
};

export function loadConfig(env: NodeJS.ProcessEnv = process.env): MCPServerConfig {
  const rawBaseURL = env.IOS_EXPLORE_BASE_URL ?? "http://localhost:38321/";
  let baseURL: URL;
  try {
    baseURL = new URL(rawBaseURL);
  } catch {
    throw new Error(`IOS_EXPLORE_BASE_URL must be a valid URL, got '${rawBaseURL}'`);
  }
  if (baseURL.protocol !== "http:" && baseURL.protocol !== "https:") {
    throw new Error(`IOS_EXPLORE_BASE_URL must use http or https, got '${rawBaseURL}'`);
  }
  if (!baseURL.pathname.endsWith("/")) {
    baseURL.pathname = `${baseURL.pathname}/`;
  }

  const timeoutRaw = env.IOS_EXPLORE_REQUEST_TIMEOUT_MS ?? "10000";
  const requestTimeoutMs = Number(timeoutRaw);
  if (!Number.isInteger(requestTimeoutMs) || requestTimeoutMs <= 0) {
    throw new Error(`IOS_EXPLORE_REQUEST_TIMEOUT_MS must be a positive integer, got '${timeoutRaw}'`);
  }

  return {
    baseURL: baseURL.toString(),
    requestTimeoutMs
  };
}

export function requestTimeoutForAction(config: MCPServerConfig, action: string, data: JSONObject = {}): number {
  if (action !== "ui.wait" && action !== "ui.waitAny") {
    return config.requestTimeoutMs;
  }
  const timeoutMs = typeof data.timeoutMs === "number" ? data.timeoutMs : 0;
  return Math.max(config.requestTimeoutMs, timeoutMs + 5000);
}
