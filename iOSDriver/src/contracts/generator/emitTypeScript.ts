/**
 * 合同预处理、canonical hash 与 TypeScript 产物生成。
 *
 * 所有 emitter 共用 `PreparedContractBundle`：先展开本地 `$ref`、规范排序并计算一次 hash，
 * 再分别生成 TS、Swift 和文档。这样各平台不会因为独立实现 normalization 而得到不同
 * 的兼容性标识。
 */
import { createHash } from "node:crypto";
import type {
  ContractJSONValue,
  DeviceActionContract,
  DriverContractBundle,
  HostOperationSpec,
  JsonSchema
} from "./model.js";

/** 一个可确定复现的生成文件；路径始终相对仓库根。 */
export interface GeneratedArtifact {
  /** emitter 允许写入的仓库相对目标。 */
  readonly path: string;
  /** 完整文件内容，生成和漂移检查逐字节比较。 */
  readonly content: string;
}

/**
 * 用于 hash 和生成的纯源合同表示。
 * 有意排除 `sourceFiles` 等本机加载状态，避免相同合同在不同目录产生不同 hash。
 */
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

/** 所有 emitter 共用的已预处理合同与唯一 hash。 */
export interface PreparedContractBundle {
  readonly bundle: CanonicalContractBundle;
  readonly hash: string;
}

/**
 * 在生成前展开本地 definition 引用并创建 canonical bundle。
 * 返回值有意排除 `sourceFiles` 和已生成元数据，hash 只由事实源内容决定。
 */
export function prepareContractBundle(bundle: DriverContractBundle): PreparedContractBundle {
  const definitions: Record<string, JsonSchema> = {};
  for (const name of Object.keys(bundle.definitions).sort()) {
    definitions[name] = expandSchema(bundle.definitions[name]!, name, bundle, []);
  }

  // action/operation/error/definition 的集合顺序不应影响 hash，因此按稳定标识排序。
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
  const normalized = stableNormalize(canonical);
  const hash = `sha256:${createHash("sha256").update(JSON.stringify(normalized), "utf8").digest("hex")}`;

  // emitter 保留 schema 属性声明顺序：Swift 会把它发布为 propertyOrder，兼容检查也将其
  // 视为合同的一部分；只有普通对象键才在 stableNormalize 中排序。
  return { bundle: canonical, hash };
}

/**
 * 生成 device action、host operation 和 bundle metadata 三个 TypeScript 模块。
 * 输出只包含 `as const` 数据与派生类型，不把校验器逻辑复制进 generated 目录。
 */
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

/**
 * 把合同值转换为可稳定序列化的 JSON。
 * 普通对象键排序，schema `properties` 保留声明顺序，因为该顺序属于公开元数据。
 */
export function stableNormalize(value: unknown): ContractJSONValue {
  return stableNormalizeValue(value, false);
}

/** 递归 normalization；第二个参数只在进入 `properties` 对象时为 true。 */
function stableNormalizeValue(value: unknown, preserveObjectKeyOrder: boolean): ContractJSONValue {
  if (Array.isArray(value)) return value.map(item => stableNormalizeValue(item, false));
  if (value !== null && typeof value === "object") {
    const normalized: Record<string, ContractJSONValue> = {};
    const object = value as Record<string, unknown>;
    const keys = Object.keys(object);
    if (!preserveObjectKeyOrder) keys.sort();
    for (const key of keys) {
      normalized[key] = stableNormalizeValue(object[key], key === "properties");
    }
    return normalized;
  }
  if (value === null || typeof value === "string" || typeof value === "boolean") return value;
  if (typeof value === "number" && Number.isFinite(value)) return value;
  throw new Error("canonical contract bundle contains a non-JSON value");
}

/**
 * 展开单个 schema 的本地 `$ref`。
 * 引用目标先展开，再让引用节点上的其他 keyword 覆盖目标；refStack 防止 definitions 环。
 */
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

/** 对 properties/items/composite/additionalProperties 中的嵌套 schema 继续展开引用。 */
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
    for (const key of Object.keys(result.properties)) {
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

/** 解析相对源文件的 definition 引用；合法性已经由 validator 保证。 */
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

/** 每个 TS 产物写入同一 hash 和禁止手改提示，便于代码审查识别来源。 */
function generatedHeader(hash: string): string {
  return `// Generated from contracts/ by the contract generator.\n// Contract hash: ${hash}\n// Do not edit this file directly.`;
}
