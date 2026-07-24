/** JSON values accepted by contract files. */
export type ContractJSONValue =
  | null
  | boolean
  | number
  | string
  | ContractJSONValue[]
  | { [key: string]: ContractJSONValue };

/** Primitive and container types supported by the controlled schema dialect. */
export type JsonSchemaType = "object" | "array" | "string" | "number" | "integer" | "boolean" | "null";

/** The controlled JSON Schema subset shared by Swift and TypeScript generators. */
export interface JsonSchema {
  $ref?: string;
  type?: JsonSchemaType;
  properties?: Record<string, JsonSchema>;
  required?: string[];
  additionalProperties?: boolean | JsonSchema;
  items?: JsonSchema;
  minItems?: number;
  maxItems?: number;
  uniqueItems?: boolean;
  enum?: ContractJSONValue[];
  default?: ContractJSONValue;
  minimum?: number;
  maximum?: number;
  exclusiveMinimum?: number;
  exclusiveMaximum?: number;
  oneOf?: JsonSchema[];
  allOf?: JsonSchema[];
  not?: JsonSchema;
  description?: string;
  "x-iosExplore-constraints"?: Record<string, ContractJSONValue>;
}

/** Module that provides an App action. */
export type ContractProvider = "core" | "uikit" | "diagnostics" | "extension";

/** Publication status used by generated adapters. */
export type ContractStability = "public" | "experimental" | "internal";

/** Result representation used by host adapters. */
export interface ResultSpec {
  kind: "json" | "image" | "text";
}

/** Retry safety classification for a device action. */
export type ContractIdempotency = "readOnly" | "idempotent" | "sideEffecting";

/** Request timeout policy selected by the host runtime. */
export type ContractTimeoutClass = "standard" | "wait" | "screenshot";

/** Canonical wire contract for one App action. */
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

/** Canonical contract for one host-side operation or workflow. */
export interface HostOperationSpec {
  kind: "hostOperation";
  operation: string;
  description: string;
  inputSchema: JsonSchema;
  result: ResultSpec;
  errors: string[];
}

/** Stable machine semantics for an error code. */
export interface ErrorContract {
  source: "appEnvelope" | "transport" | "http" | "protocol" | "contract" | "config" | "workflow" | "artifact";
  retryable: boolean;
  terminal: boolean;
}

/** 未经完整契约校验的 JSON 对象。 */
export type RawContractDocument = Record<string, unknown>;

/** 由加载器读取、等待 `validateContractBundle` 完整校验的原始 bundle。 */
export interface RawDriverContractBundle {
  protocolVersion: string;
  contractVersion: string;
  generatorVersion: string;
  files: string[];
  deviceActions: object[];
  hostOperations: object[];
  errors: object;
  definitions: Record<string, object>;
  sourceFiles: ReadonlyMap<object, string>;
}

/** 已通过完整契约校验的 canonical bundle。 */
export interface DriverContractBundle {
  protocolVersion: string;
  contractVersion: string;
  generatorVersion: string;
  files: string[];
  deviceActions: DeviceActionContract[];
  hostOperations: HostOperationSpec[];
  errors: Record<string, ErrorContract>;
  definitions: Record<string, JsonSchema>;
  sourceFiles: ReadonlyMap<object, string>;
}
