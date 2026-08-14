import type { ActionTransport } from "./actionTransport.js";
import type { ArtifactDecoder } from "./artifacts.js";
import type { HostLogger } from "./hostLogger.js";

export interface DriverRuntimeOptions {
  readonly transport: ActionTransport;
  readonly configuredRequestTimeoutMs: number;
  readonly artifactDecoder?: ArtifactDecoder;
  readonly logger?: HostLogger;
}

export interface InvocationOptions {
  readonly signal?: AbortSignal;
  readonly policy?: InvocationPolicy;
}

export interface InvocationPolicy {
  readonly idempotency: "readOnly" | "idempotent" | "sideEffecting";
  readonly timeoutClass: "standard" | "wait" | "screenshot";
}
