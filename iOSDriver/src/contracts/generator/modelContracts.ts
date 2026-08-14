import type { ContractJSONValue, JsonSchema } from "./modelSchema.js";

export type ContractProvider = "core" | "uikit" | "diagnostics" | "extension";
export type ContractStability = "public" | "experimental" | "internal";

export interface ResultSpec {
  kind: "json" | "image" | "text";
}

export type ContractIdempotency = "readOnly" | "idempotent" | "sideEffecting";
export type ContractTimeoutClass = "standard" | "wait" | "screenshot";

export interface DeviceActionContract {
  kind: "deviceAction";
  action: string;
  description: string;
  provider: ContractProvider;
  stability: ContractStability;
  inputSchema: JsonSchema;
  result: ResultSpec;
  errors: string[];
  idempotency: ContractIdempotency;
  timeoutClass: ContractTimeoutClass;
}

export interface HostOperationSpec {
  kind: "hostOperation";
  operation: string;
  description: string;
  inputSchema: JsonSchema;
  result: ResultSpec;
  errors: string[];
}

export interface ErrorContract {
  source: "appEnvelope" | "transport" | "http" | "protocol" | "contract" | "config" | "workflow" | "artifact";
  retryable: boolean;
  terminal: boolean;
}

export type RawContractDocument = Record<string, unknown>;

export type { ContractJSONValue, JsonSchema };
