import { HOST_OPERATION_SPECS, type HostOperationSpec } from "../generated/hostOperationSpecs.js";
import type { JSONObject } from "../types.js";

type HostOperation = HostOperationSpec["operation"];
type SchemaType = "object" | "array" | "string" | "number" | "integer" | "boolean" | "null";

interface RuntimeSchema {
  readonly type?: SchemaType | readonly SchemaType[];
  readonly properties?: Readonly<Record<string, RuntimeSchema>>;
  readonly required?: readonly string[];
  readonly additionalProperties?: boolean | RuntimeSchema;
  readonly items?: RuntimeSchema;
  readonly minItems?: number;
  readonly maxItems?: number;
  readonly uniqueItems?: boolean;
  readonly enum?: readonly unknown[];
  readonly minimum?: number;
  readonly maximum?: number;
  readonly exclusiveMinimum?: number;
  readonly exclusiveMaximum?: number;
  readonly oneOf?: readonly RuntimeSchema[];
  readonly allOf?: readonly RuntimeSchema[];
  readonly not?: RuntimeSchema;
  readonly "x-iosExplore-constraints"?: Readonly<Record<string, unknown>>;
}

interface ValidationIssue {
  readonly path: string;
  readonly reason: string;
}

const HOST_INPUT_SCHEMAS = new Map<string, RuntimeSchema>(
  HOST_OPERATION_SPECS.map(spec => [spec.operation, spec.inputSchema as unknown as RuntimeSchema])
);

/** Host operation 输入不符合 generated contract。 */
export class HostOperationInputValidationError extends Error {
  readonly operation: HostOperation;
  readonly path: string;

  constructor(operation: HostOperation, issue: ValidationIssue) {
    super(`Invalid ${operation} input at ${issue.path}: ${issue.reason}`);
    this.name = "HostOperationInputValidationError";
    this.operation = operation;
    this.path = issue.path;
  }
}

/**
 * 按 generated host-operation contract 校验包装层输入。
 *
 * 该入口只用于在 Mac 上执行的 host operation。device action data 必须继续由 App 端
 * `CommandInput.parse(from:)` 校验，避免 Swift 与 TypeScript 各维护一套业务 parser。
 *
 * @param operation host operation 名称。
 * @param input MCP/CLI 提供的原始包装层输入。
 * @returns 已确认符合 object schema 的输入对象；不会填充或改写默认值。
 * @throws `HostOperationInputValidationError`，错误只包含合同路径，不回显用户值。
 */
export function validateHostOperationInput(operation: HostOperation, input: unknown): JSONObject {
  const schema = HOST_INPUT_SCHEMAS.get(operation);
  if (schema === undefined) throw new Error(`Missing generated host operation contract: ${operation}`);
  const issue = firstIssue(schema, input, "$");
  if (issue !== undefined) throw new HostOperationInputValidationError(operation, issue);
  return input as JSONObject;
}

function firstIssue(schema: RuntimeSchema, value: unknown, path: string): ValidationIssue | undefined {
  if (schema.type !== undefined && !matchesType(value, schema.type)) {
    return { path, reason: `expected ${describeType(schema.type)}` };
  }

  if (schema.enum !== undefined && !schema.enum.some(candidate => jsonEqual(candidate, value))) {
    return { path, reason: "value is not in the allowed enum" };
  }

  if (typeof value === "number") {
    if (!Number.isFinite(value)) return { path, reason: "expected a finite number" };
    if (schema.minimum !== undefined && value < schema.minimum) return { path, reason: `must be >= ${schema.minimum}` };
    if (schema.maximum !== undefined && value > schema.maximum) return { path, reason: `must be <= ${schema.maximum}` };
    if (schema.exclusiveMinimum !== undefined && value <= schema.exclusiveMinimum) {
      return { path, reason: `must be > ${schema.exclusiveMinimum}` };
    }
    if (schema.exclusiveMaximum !== undefined && value >= schema.exclusiveMaximum) {
      return { path, reason: `must be < ${schema.exclusiveMaximum}` };
    }
  }

  if (Array.isArray(value)) {
    if (schema.minItems !== undefined && value.length < schema.minItems) {
      return { path, reason: `must contain at least ${schema.minItems} items` };
    }
    if (schema.maxItems !== undefined && value.length > schema.maxItems) {
      return { path, reason: `must contain at most ${schema.maxItems} items` };
    }
    if (schema.uniqueItems === true && hasDuplicate(value)) {
      return { path, reason: "items must be unique" };
    }
    if (schema.items !== undefined) {
      for (const [index, item] of value.entries()) {
        const issue = firstIssue(schema.items, item, `${path}[${index}]`);
        if (issue !== undefined) return issue;
      }
    }
  }

  if (isObject(value)) {
    const properties = schema.properties ?? {};
    for (const name of schema.required ?? []) {
      if (!Object.hasOwn(value, name)) return { path: `${path}.${name}`, reason: "field is required" };
    }
    for (const [name, propertySchema] of Object.entries(properties)) {
      if (!Object.hasOwn(value, name)) continue;
      const issue = firstIssue(propertySchema, value[name], `${path}.${name}`);
      if (issue !== undefined) return issue;
    }
    for (const [name, propertyValue] of Object.entries(value)) {
      if (Object.hasOwn(properties, name)) continue;
      if (schema.additionalProperties === false) {
        return { path, reason: "contains an unsupported field" };
      }
      if (typeof schema.additionalProperties === "object") {
        const issue = firstIssue(schema.additionalProperties, propertyValue, `${path}.*`);
        if (issue !== undefined) return issue;
      }
    }
    const constraintIssue = validateExtensionConstraints(schema, value, path);
    if (constraintIssue !== undefined) return constraintIssue;
  }

  if (schema.allOf !== undefined) {
    for (const branch of schema.allOf) {
      const issue = firstIssue(branch, value, path);
      if (issue !== undefined) return { path, reason: "does not satisfy all required schema branches" };
    }
  }
  if (schema.oneOf !== undefined) {
    const matches = schema.oneOf.filter(branch => firstIssue(branch, value, path) === undefined).length;
    if (matches !== 1) return { path, reason: "must satisfy exactly one schema branch" };
  }
  if (schema.not !== undefined && firstIssue(schema.not, value, path) === undefined) {
    return { path, reason: "matches a forbidden schema" };
  }
  return undefined;
}

function validateExtensionConstraints(
  schema: RuntimeSchema,
  value: JSONObject,
  path: string
): ValidationIssue | undefined {
  const constraints = schema["x-iosExplore-constraints"];
  if (constraints === undefined) return undefined;

  const exactlyOneOf = stringArray(constraints.exactlyOneOf);
  if (exactlyOneOf !== undefined && exactlyOneOf.filter(name => hasNonNullValue(value, name)).length !== 1) {
    return { path, reason: "must provide exactly one of the declared fields" };
  }

  const mutuallyExclusive = stringArray(constraints.mutuallyExclusive);
  if (mutuallyExclusive !== undefined && mutuallyExclusive.filter(name => hasNonNullValue(value, name)).length > 1) {
    return { path, reason: "contains mutually exclusive fields" };
  }
  return undefined;
}

function matchesType(value: unknown, type: SchemaType | readonly SchemaType[]): boolean {
  if (typeof type !== "string") return type.some(candidate => matchesType(value, candidate));
  switch (type) {
    case "object": return isObject(value);
    case "array": return Array.isArray(value);
    case "string": return typeof value === "string";
    case "number": return typeof value === "number" && Number.isFinite(value);
    case "integer": return typeof value === "number" && Number.isInteger(value);
    case "boolean": return typeof value === "boolean";
    case "null": return value === null;
  }
  return false;
}

function describeType(type: SchemaType | readonly SchemaType[]): string {
  return typeof type === "string" ? type : type.join(" or ");
}

function isObject(value: unknown): value is JSONObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function hasNonNullValue(value: JSONObject, name: string): boolean {
  return Object.hasOwn(value, name) && value[name] !== null;
}

function stringArray(value: unknown): readonly string[] | undefined {
  return Array.isArray(value) && value.every(item => typeof item === "string")
    ? value as string[]
    : undefined;
}

function hasDuplicate(values: readonly unknown[]): boolean {
  return values.some((value, index) => values.slice(0, index).some(previous => jsonEqual(previous, value)));
}

function jsonEqual(left: unknown, right: unknown): boolean {
  if (Object.is(left, right)) return true;
  if (Array.isArray(left) && Array.isArray(right)) {
    return left.length === right.length && left.every((value, index) => jsonEqual(value, right[index]));
  }
  if (isObject(left) && isObject(right)) {
    const leftKeys = Object.keys(left).sort();
    const rightKeys = Object.keys(right).sort();
    return leftKeys.length === rightKeys.length
      && leftKeys.every((key, index) => key === rightKeys[index] && jsonEqual(left[key], right[key]));
  }
  return false;
}
