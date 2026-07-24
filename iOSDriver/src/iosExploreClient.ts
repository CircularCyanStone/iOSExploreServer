import { requestTimeoutForAction, type MCPServerConfig } from "./config.js";
import { bodySnippet, IOSExploreStructuredError } from "./errors.js";
import { isFailureEnvelope, type IOSExploreEnvelope, type JSONObject } from "./types.js";

export class IOSExploreClient {
  constructor(private readonly config: MCPServerConfig) {}

  async call(action: string, data: JSONObject = {}): Promise<JSONObject> {
    const timeoutMs = requestTimeoutForAction(this.config, action, data);
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    let response: Response;

    try {
      response = await fetch(this.config.baseURL, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action, data }),
        signal: controller.signal
      });
    } catch (error) {
      const code = error instanceof Error && error.name === "AbortError" ? "request_timeout" : "connection_failed";
      throw new IOSExploreStructuredError({
        source: "transport",
        code,
        message: error instanceof Error ? error.message : String(error),
        action,
        baseURL: this.config.baseURL,
        timeoutMs
      });
    } finally {
      clearTimeout(timer);
    }

    const text = await response.text();
    if (!response.ok) {
      throw new IOSExploreStructuredError({
        source: "http",
        status: response.status,
        message: `HTTP ${response.status}`,
        action,
        bodySnippet: bodySnippet(text)
      });
    }

    let envelope: IOSExploreEnvelope;
    try {
      envelope = JSON.parse(text) as IOSExploreEnvelope;
    } catch {
      throw new IOSExploreStructuredError({
        source: "http",
        code: "invalid_json",
        message: "HTTP response was not valid JSON",
        action,
        bodySnippet: bodySnippet(text)
      });
    }

    if (isFailureEnvelope(envelope)) {
      const structured = {
        source: "ios_envelope",
        code: envelope.code,
        message: envelope.message,
        action
      } as const;
      const data = objectValue(envelope.data);
      throw new IOSExploreStructuredError(data ? { ...structured, data } : structured);
    }

    return envelope.data ?? {};
  }
}

function objectValue(value: unknown): JSONObject | undefined {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? (value as JSONObject)
    : undefined;
}
