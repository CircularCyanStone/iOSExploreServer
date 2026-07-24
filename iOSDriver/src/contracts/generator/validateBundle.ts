import { posix } from "node:path";
import type {
  ContractJSONValue,
  DriverContractBundle,
  JsonSchema,
  JsonSchemaType,
  RawDriverContractBundle
} from "./model.js";

/** Stable categories emitted when a canonical contract bundle is invalid. */
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

/** Validation failure with a machine-readable category and non-sensitive location. */
export class ContractValidationError extends Error {
  readonly code: ContractValidationCode;
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

const errorSources = new Set(["appEnvelope", "transport", "http", "protocol", "contract", "config", "workflow", "artifact"]);
const providers = new Set(["core", "uikit", "diagnostics", "extension"]);
const stabilities = new Set(["public", "experimental", "internal"]);
const idempotencies = new Set(["readOnly", "idempotent", "sideEffecting"]);
const timeoutClasses = new Set(["standard", "wait", "screenshot"]);
const resultKinds = new Set(["json", "image", "text"]);

/** Validate metadata, error references, and every schema in a loaded bundle. */
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

function validateManifest(files: string[]): void {
  if (!Array.isArray(files) || files.length === 0) fail("invalid_bundle", "bundle.files", "must not be empty");
  const seen = new Set<string>();
  for (const [index, file] of files.entries()) {
    requireNonEmptyString(file, `bundle.files[${index}]`, "invalid_bundle");
    if (seen.has(file)) fail("invalid_bundle", `bundle.files[${index}]`, `duplicate file ${file}`);
    seen.add(file);
  }
}

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

function validateHostOperation(operation: unknown, source: string, bundle: RawDriverContractBundle): string {
  if (!isRecord(operation) || operation.kind !== "hostOperation") fail("invalid_contract", source, "must be a hostOperation");
  requireNonEmptyString(operation.operation, `${source}.operation`, "invalid_contract");
  requireNonEmptyString(operation.description, `${source}.description`, "invalid_contract");
  validateResult(operation.result, `${source}.result`);
  validateErrorCodes(operation.errors, `${source}.errors`, bundle.errors);
  validateSchema(operation.inputSchema, `${source}.inputSchema`, source, bundle, []);
  return operation.operation;
}

function validateResult(result: unknown, path: string): void {
  if (!isRecord(result) || !isAllowedString(result.kind, resultKinds)) {
    fail("invalid_contract", path, "kind must be json, image, or text");
  }
}

function validateErrorCodes(codes: unknown, path: string, errors: object): void {
  if (!Array.isArray(codes) || codes.some(code => typeof code !== "string")) {
    fail("invalid_contract", path, "must be an array of error code strings");
  }
  for (const [index, code] of codes.entries()) {
    if (!Object.hasOwn(errors, code)) fail("unknown_error_code", `${path}[${index}]`, `unknown error code ${code}`);
  }
}

function validateSchema(
  schema: unknown,
  path: string,
  sourceFile: string,
  bundle: RawDriverContractBundle,
  refStack: string[]
): void {
  if (!isRecord(schema)) fail("invalid_contract", path, "schema must contain an object");
  const typedSchema = schema as JsonSchema;
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

  for (const keyword of ["minimum", "maximum", "exclusiveMinimum", "exclusiveMaximum"] as const) {
    const value = typedSchema[keyword];
    if (value !== undefined) {
      if (type !== "number" && type !== "integer") fail("invalid_contract", `${path}.${keyword}`, "requires number or integer type");
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
  if (typedSchema["x-iosExplore-constraints"] !== undefined && !isRecord(typedSchema["x-iosExplore-constraints"])) {
    fail("invalid_contract", `${path}.x-iosExplore-constraints`, "must contain an object");
  }
}

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

function requireSchemaType(actual: JsonSchemaType | JsonSchemaType[] | undefined, expected: JsonSchemaType, path: string): void {
  if (actual === undefined) fail("invalid_contract", path, `requires schema type ${expected}`);
  if (Array.isArray(actual)) {
    if (!actual.includes(expected)) fail("invalid_contract", path, `requires schema type ${expected}`);
    return;
  }
  if (actual !== expected) fail("invalid_contract", path, `requires schema type ${expected}`);
}

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

function requireNonEmptyString(value: unknown, path: string, code: ContractValidationCode): asserts value is string {
  if (typeof value !== "string" || value.length === 0) fail(code, path, "must be a non-empty string");
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isAllowedString(value: unknown, values: ReadonlySet<string>): value is string {
  return typeof value === "string" && values.has(value);
}

function fail(code: ContractValidationCode, path: string, message: string): never {
  throw new ContractValidationError(code, path, message);
}
