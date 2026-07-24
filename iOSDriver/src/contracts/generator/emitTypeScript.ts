import { createHash } from "node:crypto";
import type {
  ContractJSONValue,
  DeviceActionContract,
  DriverContractBundle,
  HostOperationSpec,
  JsonSchema
} from "./model.js";

/** A deterministic generated file. Paths are always repository-relative. */
export interface GeneratedArtifact {
  readonly path: string;
  readonly content: string;
}

/** The source-only canonical representation used for hashing and generation. */
export interface CanonicalContractBundle {
  readonly protocolVersion: string;
  readonly contractVersion: string;
  readonly generatorVersion: string;
  readonly files: readonly string[];
  readonly deviceActions: readonly DeviceActionContract[];
  readonly hostOperations: readonly HostOperationSpec[];
  readonly errors: Readonly<Record<string, { source: string; retryable: boolean; terminal: boolean }>>;
  readonly definitions: Readonly<Record<string, JsonSchema>>;
}

/** Result shared by all emitters. */
export interface PreparedContractBundle {
  readonly bundle: CanonicalContractBundle;
  readonly hash: string;
}

/**
 * Expand local definition references and normalize the source bundle before emitting anything.
 * The returned value intentionally excludes `sourceFiles` and any generated metadata.
 */
export function prepareContractBundle(bundle: DriverContractBundle): PreparedContractBundle {
  const definitions: Record<string, JsonSchema> = {};
  for (const name of Object.keys(bundle.definitions).sort()) {
    definitions[name] = expandSchema(bundle.definitions[name]!, name, bundle, []);
  }

  const deviceActions = bundle.deviceActions
    .map(contract => {
      const source = bundle.sourceFiles.get(contract) ?? `device-actions/${contract.action}.json`;
      return {
        ...contract,
        inputSchema: expandSchema(contract.inputSchema, source, bundle, []),
        errors: [...contract.errors].sort()
      };
    })
    .sort((left, right) => left.action.localeCompare(right.action));

  const hostOperations = bundle.hostOperations
    .map(operation => {
      const source = bundle.sourceFiles.get(operation) ?? `host-operations/${operation.operation}.json`;
      return {
        ...operation,
        inputSchema: expandSchema(operation.inputSchema, source, bundle, []),
        errors: [...operation.errors].sort()
      };
    })
    .sort((left, right) => left.operation.localeCompare(right.operation));

  const errors: Record<string, { source: string; retryable: boolean; terminal: boolean }> = {};
  for (const name of Object.keys(bundle.errors).sort()) errors[name] = { ...bundle.errors[name]! };

  const canonical: CanonicalContractBundle = {
    protocolVersion: bundle.protocolVersion,
    contractVersion: bundle.contractVersion,
    generatorVersion: bundle.generatorVersion,
    files: [...bundle.files].sort(),
    deviceActions,
    hostOperations,
    errors,
    definitions
  };
  const source = stableNormalize(canonical);
  const hash = `sha256:${createHash("sha256").update(JSON.stringify(source), "utf8").digest("hex")}`;
  return { bundle: source as unknown as CanonicalContractBundle, hash };
}

/** Emit the three TypeScript contract modules. */
export function emitTypeScript(prepared: PreparedContractBundle): GeneratedArtifact[] {
  const { bundle, hash } = prepared;
  const header = generatedHeader(hash);
  const deviceActions = JSON.stringify(bundle.deviceActions, null, 2);
  const hostOperations = JSON.stringify(bundle.hostOperations, null, 2);
  const metadata = JSON.stringify(
    {
      protocolVersion: bundle.protocolVersion,
      contractVersion: bundle.contractVersion,
      generatorVersion: bundle.generatorVersion,
      contractHash: hash
    },
    null,
    2
  );
  const errorIndex = JSON.stringify(bundle.errors, null, 2);

  return [
    {
      path: "iOSDriver/src/generated/deviceActionContracts.ts",
      content: `${header}\nexport const DEVICE_ACTION_CONTRACTS = ${deviceActions} as const;\n\nexport type DeviceActionContract = typeof DEVICE_ACTION_CONTRACTS[number];\n`
    },
    {
      path: "iOSDriver/src/generated/hostOperationSpecs.ts",
      content: `${header}\nexport const HOST_OPERATION_SPECS = ${hostOperations} as const;\n\nexport type HostOperationSpec = typeof HOST_OPERATION_SPECS[number];\n`
    },
    {
      path: "iOSDriver/src/generated/contractBundle.ts",
      content: `${header}\nimport { DEVICE_ACTION_CONTRACTS } from "./deviceActionContracts.js";\nimport { HOST_OPERATION_SPECS } from "./hostOperationSpecs.js";\n\nexport const CONTRACT_BUNDLE_METADATA = ${metadata} as const;\n\nexport const CONTRACT_ERROR_INDEX = ${errorIndex} as const;\n\nexport const CONTRACT_BUNDLE = {\n  ...CONTRACT_BUNDLE_METADATA,\n  deviceActions: DEVICE_ACTION_CONTRACTS,\n  hostOperations: HOST_OPERATION_SPECS,\n  errors: CONTRACT_ERROR_INDEX\n} as const;\n`
    }
  ];
}

/** Convert any contract value into a recursively key-sorted JSON value. */
export function stableNormalize(value: unknown): ContractJSONValue {
  if (Array.isArray(value)) return value.map(item => stableNormalize(item));
  if (value !== null && typeof value === "object") {
    const normalized: Record<string, ContractJSONValue> = {};
    const object = value as Record<string, unknown>;
    for (const key of Object.keys(object).sort()) normalized[key] = stableNormalize(object[key]);
    return normalized;
  }
  if (value === null || typeof value === "string" || typeof value === "boolean") return value;
  if (typeof value === "number" && Number.isFinite(value)) return value;
  throw new Error("canonical contract bundle contains a non-JSON value");
}

function expandSchema(
  schema: JsonSchema,
  sourceFile: string,
  bundle: DriverContractBundle,
  refStack: readonly string[]
): JsonSchema {
  if (schema.$ref === undefined) {
    return recursivelyExpandSchema(schema, sourceFile, bundle, refStack);
  }

  const reference = resolveReference(sourceFile, schema.$ref);
  if (refStack.includes(reference)) throw new Error(`cyclic local contract ref: ${reference}`);
  const target = bundle.definitions[reference];
  if (target === undefined) throw new Error(`unknown local contract ref: ${schema.$ref}`);
  const expandedTarget = expandSchema(target, reference, bundle, [...refStack, reference]);
  const overrides = { ...schema };
  delete overrides.$ref;
  return recursivelyExpandSchema({ ...expandedTarget, ...overrides }, sourceFile, bundle, refStack);
}

function recursivelyExpandSchema(
  schema: JsonSchema,
  sourceFile: string,
  bundle: DriverContractBundle,
  refStack: readonly string[]
): JsonSchema {
  const result: JsonSchema = { ...schema };
  delete result.$ref;
  if (result.properties !== undefined) {
    const properties: Record<string, JsonSchema> = {};
    for (const key of Object.keys(result.properties).sort()) {
      properties[key] = expandSchema(result.properties[key]!, sourceFile, bundle, refStack);
    }
    result.properties = properties;
  }
  if (result.items !== undefined) result.items = expandSchema(result.items, sourceFile, bundle, refStack);
  if (result.oneOf !== undefined) result.oneOf = result.oneOf.map(item => expandSchema(item, sourceFile, bundle, refStack));
  if (result.allOf !== undefined) result.allOf = result.allOf.map(item => expandSchema(item, sourceFile, bundle, refStack));
  if (result.not !== undefined) result.not = expandSchema(result.not, sourceFile, bundle, refStack);
  if (result.additionalProperties !== undefined && typeof result.additionalProperties === "object") {
    result.additionalProperties = expandSchema(result.additionalProperties, sourceFile, bundle, refStack);
  }
  return result;
}

function resolveReference(sourceFile: string, reference: string): string {
  if (reference.startsWith("definitions/")) return normalizePosix(reference);
  const sourceDirectory = sourceFile.slice(0, sourceFile.lastIndexOf("/"));
  return normalizePosix(`${sourceDirectory}/${reference}`);
}

function normalizePosix(value: string): string {
  const parts: string[] = [];
  for (const part of value.split("/")) {
    if (part === "" || part === ".") continue;
    if (part === "..") parts.pop();
    else parts.push(part);
  }
  return parts.join("/");
}

function generatedHeader(hash: string): string {
  return `// Generated from contracts/ by the contract generator.\n// Contract hash: ${hash}\n// Do not edit this file directly.`;
}
