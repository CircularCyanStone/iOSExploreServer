import type { StructuredError } from "./types.js";

export class IOSExploreStructuredError extends Error {
  readonly source: StructuredError["source"];
  readonly code?: string;
  readonly action?: string;
  readonly baseURL?: string;
  readonly status?: number;
  readonly timeoutMs?: number;
  readonly bodySnippet?: string;
  readonly data?: StructuredError["data"];
  readonly nextSteps?: StructuredError["nextSteps"];

  constructor(error: StructuredError) {
    super(error.message);
    this.name = "IOSExploreStructuredError";
    this.source = error.source;
    if (error.code !== undefined) this.code = error.code;
    if (error.action !== undefined) this.action = error.action;
    if (error.baseURL !== undefined) this.baseURL = error.baseURL;
    if (error.status !== undefined) this.status = error.status;
    if (error.timeoutMs !== undefined) this.timeoutMs = error.timeoutMs;
    if (error.bodySnippet !== undefined) this.bodySnippet = error.bodySnippet;
    if (error.data !== undefined) this.data = error.data;
    if (error.nextSteps !== undefined) this.nextSteps = error.nextSteps;
  }

  toJSON(): StructuredError {
    const result: StructuredError = { source: this.source, message: this.message };
    if (this.code !== undefined) result.code = this.code;
    if (this.action !== undefined) result.action = this.action;
    if (this.baseURL !== undefined) result.baseURL = this.baseURL;
    if (this.status !== undefined) result.status = this.status;
    if (this.timeoutMs !== undefined) result.timeoutMs = this.timeoutMs;
    if (this.bodySnippet !== undefined) result.bodySnippet = this.bodySnippet;
    if (this.data !== undefined) result.data = this.data;
    if (this.nextSteps !== undefined) result.nextSteps = this.nextSteps;
    return result;
  }
}

export function bodySnippet(body: string): string {
  return body.length > 500 ? `${body.slice(0, 500)}...` : body;
}
