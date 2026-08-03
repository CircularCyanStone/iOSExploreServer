/**
 * canonical 合同的完整语义校验器。
 *
 * 校验覆盖 bundle 元数据、唯一名称、错误引用、本地 `$ref` 和受控 JSON Schema 方言。
 * 通过后的 assertion 会把 raw bundle 收窄为 `DriverContractBundle`，因此 emitter 无需在
 * 每一步重复防御任意 JSON。新增 schema keyword 必须先在这里显式登记和验证。
 */
import { posix } from "node:path";
import type {
  ContractJSONValue,
  DriverContractBundle,
  JsonSchema,
  JsonSchemaType,
  RawDriverContractBundle
} from "./model.js";

/** 合同无效时供测试和构建脚本稳定判断的错误类别。 */
export type ContractValidationCode =
  | "invalid_bundle"
  | "invalid_contract"
  | "duplicate_action"
  | "duplicate_operation"
  | "unknown_error_code"
  | "unknown_schema_keyword"
  | "unknown_ref"
  | "cyclic_ref"
  | "required_property_missing"
  | "enum_type_mismatch";

/** 携带机器可读类别和相对合同位置的校验错误，不包含字段实际值。 */
export class ContractValidationError extends Error {
  /** 失败规则类别，避免调用方解析 message。 */
  readonly code: ContractValidationCode;
  /** `bundle.*` 或 contracts 相对文件内路径。 */
  readonly path: string;

  constructor(code: ContractValidationCode, path: string, message: string) {
    super(`${path}: ${message}`);
    this.name = "ContractValidationError";
    this.code = code;
    this.path = path;
  }
}

const schemaKeywords = new Set([
  "$ref",
  "type",
  "properties",
  "required",
  "additionalProperties",
  "items",
  "minItems",
  "maxItems",
  "uniqueItems",
  "enum",
  "default",
  "minimum",
  "maximum",
  "exclusiveMinimum",
  "exclusiveMaximum",
  "oneOf",
  "allOf",
  "not",
  "description",
  "x-iosExplore-constraints"
]);

const schemaTypes = new Set<JsonSchemaType>([
  "object",
  "array",
  "string",
  "number",
  "integer",
  "boolean",
  "null"
]);
const extensionConstraintKeywords = new Set(["exactlyOneOf", "mutuallyExclusive", "note"]);

const errorSources = new Set(["appEnvelope", "transport", "http", "protocol", "contract", "config", "workflow", "artifact"]);
const providers = new Set(["core", "uikit", "diagnostics", "extension"]);
const stabilities = new Set(["public", "experimental", "internal"]);
const idempotencies = new Set(["readOnly", "idempotent", "sideEffecting"]);
const timeoutClasses = new Set(["standard", "wait", "screenshot"]);
const resultKinds = new Set(["json", "image", "text"]);

/**
 * 校验元数据、错误引用及每个 schema，并把 raw bundle 收窄为 typed bundle。
 *
 * 执行顺序先验证全局元数据/error index，再验证 action/operation，最后验证 definitions。
 * action 中遇到 `$ref` 时也会即时递归验证目标，因此独立 definitions 的最后一轮校验用于
 * 覆盖尚未被任何合同引用的定义文件。
 */
export function validateContractBundle(bundle: RawDriverContractBundle): asserts bundle is DriverContractBundle {
  requireNonEmptyString(bundle.protocolVersion, "bundle.protocolVersion", "invalid_bundle");
  requireNonEmptyString(bundle.contractVersion, "bundle.contractVersion", "invalid_bundle");
  requireNonEmptyString(bundle.generatorVersion, "bundle.generatorVersion", "invalid_bundle");
  validateManifest(bundle.files);
  validateErrors(bundle.errors);

  const actionNames = new Set<string>();
  for (const contract of bundle.deviceActions) {
    const source = bundle.sourceFiles.get(contract) ?? "device-action";
    const action = validateDeviceAction(contract, source, bundle);
    if (actionNames.has(action)) {
      fail("duplicate_action", source, `duplicate action ${action}`);
    }
    actionNames.add(action);
  }

  const operationNames = new Set<string>();
  for (const operation of bundle.hostOperations) {
    const source = bundle.sourceFiles.get(operation) ?? "host-operation";
    const name = validateHostOperation(operation, source, bundle);
    if (operationNames.has(name)) {
      fail("duplicate_operation", source, `duplicate operation ${name}`);
    }
    operationNames.add(name);
  }

  for (const [source, schema] of Object.entries(bundle.definitions)) {
    validateSchema(schema, source, source, bundle, []);
  }
}

/** manifest 必须非空且无重复，路径安全性由 loader 在实际读取前负责。 */
function validateManifest(files: string[]): void {
  if (!Array.isArray(files) || files.length === 0) fail("invalid_bundle", "bundle.files", "must not be empty");
  const seen = new Set<string>();
  for (const [index, file] of files.entries()) {
    requireNonEmptyString(file, `bundle.files[${index}]`, "invalid_bundle");
    if (seen.has(file)) fail("invalid_bundle", `bundle.files[${index}]`, `duplicate file ${file}`);
    seen.add(file);
  }
}

/** 验证全局错误索引的稳定 source/retryable/terminal 三元语义。 */
function validateErrors(errors: unknown): void {
  if (!isRecord(errors)) fail("invalid_bundle", "errors.json", "must contain an object");
  for (const [code, contract] of Object.entries(errors)) {
    requireNonEmptyString(code, "errors.json", "invalid_bundle");
    if (!isRecord(contract)) fail("invalid_bundle", `errors.json.${code}`, "must contain an object");
    if (!isAllowedString(contract.source, errorSources)) fail("invalid_bundle", `errors.json.${code}.source`, "has unsupported source");
    if (typeof contract.retryable !== "boolean") fail("invalid_bundle", `errors.json.${code}.retryable`, "must be boolean");
    if (typeof contract.terminal !== "boolean") fail("invalid_bundle", `errors.json.${code}.terminal`, "must be boolean");
  }
}

/** 验证 device action 元数据，并返回已经收窄的 action 名供全局去重。 */
function validateDeviceAction(contract: unknown, source: string, bundle: RawDriverContractBundle): string {
  if (!isRecord(contract) || contract.kind !== "deviceAction") fail("invalid_contract", source, "must be a deviceAction");
  requireNonEmptyString(contract.action, `${source}.action`, "invalid_contract");
  requireNonEmptyString(contract.description, `${source}.description`, "invalid_contract");
  if (!isAllowedString(contract.provider, providers)) {
    fail("invalid_contract", `${source}.provider`, "has unsupported provider");
  }
  if (!isAllowedString(contract.stability, stabilities)) {
    fail("invalid_contract", `${source}.stability`, "has unsupported stability");
  }
  if (!isAllowedString(contract.idempotency, idempotencies)) {
    fail("invalid_contract", `${source}.idempotency`, "has unsupported idempotency");
  }
  if (!isAllowedString(contract.timeoutClass, timeoutClasses)) {
    fail("invalid_contract", `${source}.timeoutClass`, "has unsupported timeout class");
  }
  validateResult(contract.result, `${source}.result`);
  validateErrorCodes(contract.errors, `${source}.errors`, bundle.errors);
  validateSchema(contract.inputSchema, `${source}.inputSchema`, source, bundle, []);
  return contract.action;
}

/** 验证只在 host 执行的 operation；它没有 provider/idempotency/timeoutClass。 */
function validateHostOperation(operation: unknown, source: string, bundle: RawDriverContractBundle): string {
  if (!isRecord(operation) || operation.kind !== "hostOperation") fail("invalid_contract", source, "must be a hostOperation");
  requireNonEmptyString(operation.operation, `${source}.operation`, "invalid_contract");
  requireNonEmptyString(operation.description, `${source}.description`, "invalid_contract");
  validateResult(operation.result, `${source}.result`);
  validateErrorCodes(operation.errors, `${source}.errors`, bundle.errors);
  validateSchema(operation.inputSchema, `${source}.inputSchema`, source, bundle, []);
  return operation.operation;
}

/**
 * 校验 result 声明：kind 必须是 json/image/text 之一。
 *
 * @param result 原始 result 字段。
 * @param path 错误路径前缀。
 */
function validateResult(result: unknown, path: string): void {
  if (!isRecord(result) || !isAllowedString(result.kind, resultKinds)) {
    fail("invalid_contract", path, "kind must be json, image, or text");
  }
}

/**
 * 校验错误码数组：所有 action/operation 声明的错误都必须复用 `errors.json` 的机器语义。
 *
 * @param codes 原始 errors 数组。
 * @param path 错误路径前缀。
 * @param errors 全局错误索引。
 */
function validateErrorCodes(codes: unknown, path: string, errors: object): void {
  if (!Array.isArray(codes) || codes.some(code => typeof code !== "string")) {
    fail("invalid_contract", path, "must be an array of error code strings");
  }
  for (const [index, code] of codes.entries()) {
    if (!Object.hasOwn(errors, code)) fail("unknown_error_code", `${path}[${index}]`, `unknown error code ${code}`);
  }
}

/**
 * 递归校验单个 schema 节点（含 $ref 解析与循环检测）。
 *
 * 检查顺序：未知 keyword 拒绝 → $ref 解析（含循环检测）→ type 归一化 → 容器
 * keyword（properties/required/additionalProperties/items/数值约束）→ enum/default
 * 类型相容 → 复合 schema（oneOf/allOf/not）→ 扩展约束。
 *
 * @param schema 原始 schema 节点。
 * @param path 错误路径（如 "device-actions/core.ping.json.inputSchema"）。
 * @param sourceFile 当前源文件标签（用于解析相对 $ref）。
 * @param bundle 原始 bundle（用于查 definitions）。
 * @param refStack 当前 $ref 链（循环检测）。
 */
function validateSchema(
  schema: unknown,
  path: string,
  sourceFile: string,
  bundle: RawDriverContractBundle,
  refStack: string[]
): void {
  if (!isRecord(schema)) fail("invalid_contract", path, "schema must contain an object");
  const typedSchema = schema as JsonSchema;
  // 先拒绝未知 keyword，避免拼写错误被生成器无声忽略。
  for (const keyword of Object.keys(schema)) {
    if (!schemaKeywords.has(keyword)) fail("unknown_schema_keyword", `${path}.${keyword}`, `unsupported schema keyword ${keyword}`);
  }

  if (typedSchema.$ref !== undefined) {
    if (typeof typedSchema.$ref !== "string") fail("invalid_contract", `${path}.$ref`, "must be a string");
    const reference = resolveReference(sourceFile, typedSchema.$ref);
    const target = bundle.definitions[reference];
    if (target === undefined) fail("unknown_ref", `${path}.$ref`, `unknown local ref ${typedSchema.$ref}`);
    if (refStack.includes(reference)) fail("cyclic_ref", `${path}.$ref`, `cyclic local ref ${typedSchema.$ref}`);
    validateSchema(target, reference, reference, bundle, [...refStack, reference]);
  }

  // 后续 keyword 会反查 type；先把单类型/联合类型归一化并去重。
  let type: JsonSchemaType | JsonSchemaType[] | undefined;
  if (typedSchema.type !== undefined) {
    if (typeof typedSchema.type === "string") {
      if (!schemaTypes.has(typedSchema.type as JsonSchemaType)) {
        fail("invalid_contract", `${path}.type`, "has unsupported schema type");
      }
      type = typedSchema.type as JsonSchemaType;
    } else if (Array.isArray(typedSchema.type)) {
      if (typedSchema.type.length === 0) fail("invalid_contract", `${path}.type`, "must be a non-empty array");
      const types = typedSchema.type.map((item, index) => {
        if (typeof item !== "string" || !schemaTypes.has(item as JsonSchemaType)) {
          fail("invalid_contract", `${path}.type[${index}]`, "has unsupported schema type");
        }
        return item as JsonSchemaType;
      });
      type = [...new Set(types)];
    } else {
      fail("invalid_contract", `${path}.type`, "has unsupported schema type");
    }
  }

  // 容器 keyword 除校验自身外，还要求 schema 明确声明对应 object/array 类型。
  if (typedSchema.properties !== undefined) {
    requireSchemaType(type, "object", `${path}.properties`);
    if (!isRecord(typedSchema.properties)) fail("invalid_contract", `${path}.properties`, "must contain an object");
    for (const [name, property] of Object.entries(typedSchema.properties)) {
      validateSchema(property, `${path}.properties.${name}`, sourceFile, bundle, refStack);
    }
  }

  if (typedSchema.required !== undefined) {
    requireSchemaType(type, "object", `${path}.required`);
    if (!Array.isArray(typedSchema.required) || typedSchema.required.some(value => typeof value !== "string")) {
      fail("invalid_contract", `${path}.required`, "must be an array of strings");
    }
    const properties = isRecord(typedSchema.properties) ? typedSchema.properties : {};
    for (const [index, required] of typedSchema.required.entries()) {
      if (!(required in properties)) {
        fail("required_property_missing", `${path}.required[${index}]`, `required property ${required} is not declared`);
      }
    }
  }

  if (typedSchema.additionalProperties !== undefined) {
    requireSchemaType(type, "object", `${path}.additionalProperties`);
    if (typeof typedSchema.additionalProperties !== "boolean") {
      validateSchema(typedSchema.additionalProperties, `${path}.additionalProperties`, sourceFile, bundle, refStack);
    }
  }

  if (typedSchema.items !== undefined) {
    requireSchemaType(type, "array", `${path}.items`);
    validateSchema(typedSchema.items, `${path}.items`, sourceFile, bundle, refStack);
  }
  validateNonNegativeInteger(typedSchema.minItems, `${path}.minItems`, type, "array");
  validateNonNegativeInteger(typedSchema.maxItems, `${path}.maxItems`, type, "array");
  if (typedSchema.minItems !== undefined && typedSchema.maxItems !== undefined && typedSchema.minItems > typedSchema.maxItems) {
    fail("invalid_contract", path, "minItems must not exceed maxItems");
  }
  if (typedSchema.uniqueItems !== undefined) {
    requireSchemaType(type, "array", `${path}.uniqueItems`);
    if (typeof typedSchema.uniqueItems !== "boolean") fail("invalid_contract", `${path}.uniqueItems`, "must be boolean");
  }

  // enum/default 必须在生成前满足 type；运行时不接受合同自身携带非法默认值。
  if (typedSchema.enum !== undefined) {
    if (!Array.isArray(typedSchema.enum) || typedSchema.enum.length === 0) fail("invalid_contract", `${path}.enum`, "must be a non-empty array");
    if (type !== undefined) {
      for (const [index, value] of typedSchema.enum.entries()) {
        if (!matchesType(value, type)) fail("enum_type_mismatch", `${path}.enum[${index}]`, `value does not match type ${type}`);
      }
    }
  }
  if (typedSchema.default !== undefined && type !== undefined && !matchesType(typedSchema.default, type)) {
    fail("invalid_contract", `${path}.default`, `value does not match type ${type}`);
  }

  const hasNumericType = type === "number" || type === "integer" ||
    (Array.isArray(type) && (type.includes("number") || type.includes("integer")));
  for (const keyword of ["minimum", "maximum", "exclusiveMinimum", "exclusiveMaximum"] as const) {
    const value = typedSchema[keyword];
    if (value !== undefined) {
      if (!hasNumericType) fail("invalid_contract", `${path}.${keyword}`, "requires number or integer type");
      if (typeof value !== "number" || !Number.isFinite(value)) fail("invalid_contract", `${path}.${keyword}`, "must be a finite number");
    }
  }
  if (typedSchema.minimum !== undefined && typedSchema.maximum !== undefined && typedSchema.minimum > typedSchema.maximum) {
    fail("invalid_contract", path, "minimum must not exceed maximum");
  }
  if (typedSchema.exclusiveMinimum !== undefined && typedSchema.exclusiveMaximum !== undefined && typedSchema.exclusiveMinimum >= typedSchema.exclusiveMaximum) {
    fail("invalid_contract", path, "exclusiveMinimum must be less than exclusiveMaximum");
  }

  validateSchemaArray(typedSchema.oneOf, `${path}.oneOf`, sourceFile, bundle, refStack);
  validateSchemaArray(typedSchema.allOf, `${path}.allOf`, sourceFile, bundle, refStack);
  if (typedSchema.not !== undefined) validateSchema(typedSchema.not, `${path}.not`, sourceFile, bundle, refStack);
  if (typedSchema.description !== undefined && typeof typedSchema.description !== "string") {
    fail("invalid_contract", `${path}.description`, "must be a string");
  }
  if (typedSchema["x-iosExplore-constraints"] !== undefined) {
    validateExtensionConstraints(
      typedSchema["x-iosExplore-constraints"],
      type,
      isRecord(typedSchema.properties) ? typedSchema.properties : {},
      `${path}.x-iosExplore-constraints`
    );
  }
}

/**
 * 校验项目扩展的跨字段约束：
 * exactlyOneOf/mutuallyExclusive 只能引用同一 object 中已声明且不重复的属性名。
 *
 * @param value x-iosExplore-constraints 原始值。
 * @param schemaType 已归一化的 type（必须含 object）。
 * @param properties 已声明的属性表（约束引用的字段必须在此）。
 * @param path 错误路径前缀。
 */
function validateExtensionConstraints(
  value: Record<string, ContractJSONValue>,
  schemaType: JsonSchemaType | JsonSchemaType[] | undefined,
  properties: Record<string, unknown>,
  path: string
): void {
  if (!isRecord(value)) fail("invalid_contract", path, "must contain an object");
  for (const key of Object.keys(value)) {
    if (!extensionConstraintKeywords.has(key)) {
      fail("unknown_schema_keyword", `${path}.${key}`, `unsupported extension constraint ${key}`);
    }
  }

  for (const key of ["exactlyOneOf", "mutuallyExclusive"] as const) {
    const fields = value[key];
    if (fields === undefined) continue;
    requireSchemaType(schemaType, "object", `${path}.${key}`);
    if (!Array.isArray(fields) || fields.length < 2 || fields.some(field => typeof field !== "string")) {
      fail("invalid_contract", `${path}.${key}`, "must be an array of at least two property names");
    }
    const seen = new Set<string>();
    for (const [index, field] of fields.entries()) {
      const fieldName = field as string;
      if (seen.has(fieldName)) fail("invalid_contract", `${path}.${key}[${index}]`, "must not contain duplicates");
      seen.add(fieldName);
      if (!Object.prototype.hasOwnProperty.call(properties, fieldName)) {
        fail("required_property_missing", `${path}.${key}[${index}]`, `constraint property ${fieldName} is not declared`);
      }
    }
  }

  if (value.note !== undefined && typeof value.note !== "string") {
    fail("invalid_contract", `${path}.note`, "must be a string");
  }
}

/**
 * 校验 oneOf/allOf 数组：非空数组，逐项递归校验。
 *
 * @param schemas 原始数组（可能 undefined）。
 * @param path 错误路径。
 * @param sourceFile 源文件标签。
 * @param bundle 原始 bundle。
 * @param refStack $ref 链。
 */
function validateSchemaArray(
  schemas: JsonSchema[] | undefined,
  path: string,
  sourceFile: string,
  bundle: RawDriverContractBundle,
  refStack: string[]
): void {
  if (schemas === undefined) return;
  if (!Array.isArray(schemas) || schemas.length === 0) fail("invalid_contract", path, "must be a non-empty array");
  for (const [index, schema] of schemas.entries()) validateSchema(schema, `${path}[${index}]`, sourceFile, bundle, refStack);
}

/**
 * 把相对 `$ref` 规范化到 definitions 标签。
 * URI、fragment、绝对路径和逃出 definitions 的引用一律不属于受控方言。
 *
 * @param sourceFile 当前源文件标签（相对引用的基准目录）。
 * @param reference 原始 $ref 值。
 * @returns 规范化后的 definitions 标签（如 "definitions/locator.json"）。
 */
function resolveReference(sourceFile: string, reference: string): string {
  if (/^[A-Za-z][A-Za-z0-9+.-]*:/.test(reference) || reference.startsWith("/") || reference.includes("#")) {
    fail("unknown_ref", `${sourceFile}.$ref`, "only local definition file refs are supported");
  }
  const normalized = reference.startsWith("definitions/")
    ? posix.normalize(reference)
    : posix.normalize(posix.join(posix.dirname(sourceFile), reference));
  if (!normalized.startsWith("definitions/") || !normalized.endsWith(".json") || normalized.includes("..")) {
    fail("unknown_ref", `${sourceFile}.$ref`, "ref must resolve inside definitions/");
  }
  return normalized;
}

/**
 * 校验 minItems/maxItems：非负整数且 schema type 必须为 array。
 *
 * @param value 原始值（可能 undefined=未声明）。
 * @param path 错误路径。
 * @param schemaType 已归一化的 type。
 * @param requiredType 关键字要求的类型（array）。
 */
function validateNonNegativeInteger(
  value: number | undefined,
  path: string,
  schemaType: JsonSchemaType | JsonSchemaType[] | undefined,
  requiredType: JsonSchemaType
): void {
  if (value === undefined) return;
  requireSchemaType(schemaType, requiredType, path);
  if (!Number.isInteger(value) || value < 0) fail("invalid_contract", path, "must be a non-negative integer");
}

/**
 * 断言 schema type 必须包含期望类型（容器关键字出现时的前置条件）。
 *
 * @param actual 已归一化的 type（可能 undefined）。
 * @param expected 期望类型。
 * @param path 错误路径。
 */
function requireSchemaType(actual: JsonSchemaType | JsonSchemaType[] | undefined, expected: JsonSchemaType, path: string): void {
  if (actual === undefined) fail("invalid_contract", path, `requires schema type ${expected}`);
  if (Array.isArray(actual)) {
    if (!actual.includes(expected)) fail("invalid_contract", path, `requires schema type ${expected}`);
    return;
  }
  if (actual !== expected) fail("invalid_contract", path, `requires schema type ${expected}`);
}

/**
 * 判断值是否与（可能联合的）类型相容。
 *
 * @param value 待检查值。
 * @param type 类型或类型数组。
 * @returns true=相容。
 */
function matchesType(value: ContractJSONValue, type: JsonSchemaType | JsonSchemaType[]): boolean {
  if (Array.isArray(type)) return type.some(item => matchesType(value, item));
  switch (type) {
    case "object": return isRecord(value);
    case "array": return Array.isArray(value);
    case "string": return typeof value === "string";
    case "number": return typeof value === "number" && Number.isFinite(value);
    case "integer": return typeof value === "number" && Number.isInteger(value);
    case "boolean": return typeof value === "boolean";
    case "null": return value === null;
  }
}

/**
 * 断言值为非空字符串（校验后收窄类型）。
 *
 * @param value 待断言值。
 * @param path 错误路径。
 * @param code 错误类别。
 */
function requireNonEmptyString(value: unknown, path: string, code: ContractValidationCode): asserts value is string {
  if (typeof value !== "string" || value.length === 0) fail(code, path, "must be a non-empty string");
}

/** 类型守卫：未知值是否为普通对象（非 null、非数组）。 */
function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/** 类型守卫：值是否在允许的字符串集合内。 */
function isAllowedString(value: unknown, values: ReadonlySet<string>): value is string {
  return typeof value === "string" && values.has(value);
}

/**
 * 集中构造稳定错误，保证所有校验分支都带 code 与非敏感 path。
 *
 * @param code 错误类别。
 * @param path 错误路径。
 * @param message 错误描述。
 */
function fail(code: ContractValidationCode, path: string, message: string): never {
  throw new ContractValidationError(code, path, message);
}
