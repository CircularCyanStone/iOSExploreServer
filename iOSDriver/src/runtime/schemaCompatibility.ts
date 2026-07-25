import type { DeviceActionContract } from "../generated/deviceActionContracts.js";

/** 受控输入 schema 的 JSON 值。 */
export type SchemaValue =
  | string
  | number
  | boolean
  | null
  | { readonly [key: string]: SchemaValue }
  | readonly SchemaValue[];

/** schema 比较的结论；unknown 表示无法安全判断。 */
export type SchemaCompatibility = "exact" | "additive" | "breaking" | "unknown";

/** 一条可供 doctor/health 展示的 schema 差异。 */
export interface SchemaDifference {
  /** 差异类别。 */
  readonly kind: "missing" | "added" | "changed" | "invalid";
  /** 发生差异的 schema 路径。 */
  readonly path: string;
  /** 面向诊断输出的简短说明。 */
  readonly message: string;
  /** 是否会阻断当前合同消费者。 */
  readonly breaking: boolean;
}

/** 单个 action 的 schema 兼容性报告。 */
export interface ActionSchemaCompatibility {
  /** 对应的 device action。 */
  readonly action: string;
  /** 当前 action 的兼容性结论。 */
  readonly status: SchemaCompatibility;
  /** 按固定比较顺序排列的差异。 */
  readonly differences: readonly SchemaDifference[];
}

/** Help 返回的 command 最小结构。 */
export interface HelpCommandLike {
  /** help entry 的 action 名。 */
  readonly action?: unknown;
  /** help entry 的输入 schema。 */
  readonly inputSchema?: unknown;
}

/** 比较生成合同与 App help 返回的 action schema。 */
export function compareActionSchema(
  expected: DeviceActionContract | { readonly action: string; readonly inputSchema: unknown },
  actual: HelpCommandLike | undefined
): ActionSchemaCompatibility {
  const action = expected.action;
  if (!actual || actual.action !== action) {
    return {
      action,
      status: "breaking",
      differences: [{ kind: "missing", path: action, message: "action 未注册", breaking: true }]
    };
  }
  return compareSchemaForAction(action, projectContractInputSchemaToSwiftHelp(expected.inputSchema), actual.inputSchema);
}

/** 比较两个 JSON Schema；只判断合同支持的输入 object 子集。 */
export function compareSchemas(
  expected: unknown,
  actual: unknown,
  action = "inputSchema"
): ActionSchemaCompatibility {
  return compareSchemaForAction(action, expected, actual);
}

/** 批量比较 action，并按 expected 的顺序返回稳定结果。 */
export function compareContractSchemas(
  expected: readonly DeviceActionContract[],
  commands: readonly HelpCommandLike[]
): readonly ActionSchemaCompatibility[] {
  const byAction = new Map<string, HelpCommandLike>();
  for (const command of commands) {
    if (typeof command.action === "string" && !byAction.has(command.action)) byAction.set(command.action, command);
  }
  return expected.map(contract => compareActionSchema(contract, byAction.get(contract.action)));
}

function compareSchemaForAction(action: string, expected: unknown, actual: unknown): ActionSchemaCompatibility {
  const differences: SchemaDifference[] = [];
  if (!isObjectSchema(expected) || !isObjectSchema(actual)) {
    differences.push({ kind: "invalid", path: action, message: "inputSchema 必须是合法 object schema", breaking: true });
    return { action, status: "unknown", differences };
  }
  compareDefault(expected, actual, action, differences);
  compareObjectSchema(expected, actual, action, differences);
  const hasInvalid = differences.some(difference => difference.kind === "invalid");
  const hasBreaking = differences.some(difference => difference.breaking);
  const status: SchemaCompatibility = hasInvalid
    ? "unknown"
    : hasBreaking
    ? "breaking"
    : differences.length > 0 ? "additive" : "exact";
  return { action, status, differences };
}

function compareObjectSchema(
  expected: SchemaObject,
  actual: SchemaObject,
  path: string,
  differences: SchemaDifference[]
): void {
  compareType(expected, actual, path, differences);
  const expectedProperties = objectValue(expected.properties);
  const actualProperties = objectValue(actual.properties);
  if (expected.properties !== undefined && expectedProperties === undefined) {
    differences.push({ kind: "invalid", path: `${path}.properties`, message: "properties 必须是 object", breaking: true });
    return;
  }
  if (actual.properties !== undefined && actualProperties === undefined) {
    differences.push({ kind: "invalid", path: `${path}.properties`, message: "properties 必须是 object", breaking: true });
    return;
  }
  const expectedRequired = stringSet(expected.required, `${path}.required`, differences);
  const actualRequired = stringSet(actual.required, `${path}.required`, differences);
  for (const name of expectedRequired) {
    if (!actualRequired.has(name)) differences.push({ kind: "changed", path: `${path}.required`, message: `required 移除 ${name}`, breaking: false });
  }
  for (const name of actualRequired) {
    if (!expectedRequired.has(name)) differences.push({ kind: "changed", path: `${path}.required`, message: `required 新增 ${name}`, breaking: true });
  }

  const expectedNames = new Set(Object.keys(expectedProperties ?? {}));
  const actualNames = new Set(Object.keys(actualProperties ?? {}));
  for (const name of expectedNames) {
    const expectedProperty = expectedProperties?.[name];
    const actualProperty = actualProperties?.[name];
    if (actualProperty === undefined) {
      differences.push({ kind: "missing", path: `${path}.properties.${name}`, message: "属性移除", breaking: true });
      continue;
    }
    if (!isSchema(expectedProperty) || !isSchema(actualProperty)) {
      differences.push({ kind: "invalid", path: `${path}.properties.${name}`, message: "属性 schema 非法", breaking: true });
      continue;
    }
    compareSchemaNode(expectedProperty, actualProperty, `${path}.properties.${name}`, differences);
  }
  for (const name of actualNames) {
    if (!expectedNames.has(name)) {
      const optional = !actualRequired.has(name);
      differences.push({ kind: "added", path: `${path}.properties.${name}`, message: optional ? "新增 optional 属性" : "新增 required 属性", breaking: !optional });
    }
  }
  compareAdditionalProperties(expected, actual, path, differences);
  compareBehaviorConstraints(expected, actual, path, differences);
}

function compareSchemaNode(expected: SchemaObject, actual: SchemaObject, path: string, differences: SchemaDifference[]): void {
  compareDefault(expected, actual, path, differences);
  compareType(expected, actual, path, differences);
  if (typeSet(expected.type)?.has("object") && typeSet(actual.type)?.has("object")) {
    compareObjectSchema(expected, actual, path, differences);
    return;
  }
  compareEnum(expected, actual, path, differences);
  compareNumberBound(expected, actual, "minimum", path, differences, true);
  compareNumberBound(expected, actual, "exclusiveMinimum", path, differences, true);
  compareNumberBound(expected, actual, "maximum", path, differences, false);
  compareNumberBound(expected, actual, "exclusiveMaximum", path, differences, false);
  compareNumberBound(expected, actual, "minItems", path, differences, true);
  compareNumberBound(expected, actual, "maxItems", path, differences, false);
  validateBoundaryRelationships(expected, path, differences, "合同");
  validateBoundaryRelationships(actual, path, differences, "App");
  if (expected.items !== undefined || actual.items !== undefined) {
    if (expected.items !== undefined && !isSchema(expected.items)
        || actual.items !== undefined && !isSchema(actual.items)) {
      differences.push({ kind: "invalid", path: `${path}.items`, message: "array items schema 非法", breaking: true });
    } else if (expected.items === undefined || actual.items === undefined) {
      differences.push({
        kind: "changed",
        path: `${path}.items`,
        message: "array items schema 变化",
        breaking: expected.items === undefined
      });
    } else {
      compareSchemaNode(expected.items as SchemaObject, actual.items as SchemaObject, `${path}.items`, differences);
    }
  }
  compareAdditionalProperties(expected, actual, path, differences);
  compareBehaviorConstraints(expected, actual, path, differences);
}

/**
 * Canonical contracts and Swift help intentionally use different representations for the root
 * CommandInputSchema. Project only those documented generator transformations before comparison;
 * nested schemas are emitted verbatim through CommandFieldSchema.extraSchema.
 */
export function projectContractInputSchemaToSwiftHelp(value: unknown): unknown {
  if (!isObjectSchema(value)) return value;
  const projected: Record<string, unknown> = { ...value };
  const properties = objectValue(value.properties);
  if (properties !== undefined) {
    const projectedProperties: Record<string, unknown> = {};
    const required = new Set(Array.isArray(value.required) ? value.required.filter(item => typeof item === "string") : []);
    for (const [name, property] of Object.entries(properties)) {
      projectedProperties[name] = projectRootFieldSchema(property, required.has(name));
    }
    projected.properties = projectedProperties;
    projected["x-iosExplore-propertyOrder"] = Object.keys(properties);
  }

  const extension = objectValue(value["x-iosExplore-constraints"]);
  if (extension === undefined) return projected;
  delete projected["x-iosExplore-constraints"];

  const exactlyOneOf = stringArray(extension.exactlyOneOf);
  if (exactlyOneOf !== undefined) {
    const generatedOneOf = exactlyOneOf.map(name => ({ required: [name] }));
    if (projected.oneOf === undefined && projected.allOf === undefined) {
      projected.oneOf = generatedOneOf;
    } else {
      const units: unknown[] = [];
      if (projected.oneOf !== undefined) units.push({ oneOf: projected.oneOf });
      if (Array.isArray(projected.allOf)) units.push(...projected.allOf);
      units.push({ oneOf: generatedOneOf });
      delete projected.oneOf;
      projected.allOf = units;
    }
  }

  const messages: string[] = [];
  const mutuallyExclusive = stringArray(extension.mutuallyExclusive);
  if (mutuallyExclusive !== undefined) messages.push(`mutuallyExclusive: ${mutuallyExclusive.join(", ")}`);
  if (typeof extension.note === "string") messages.push(extension.note);
  if (messages.length > 0) projected["x-iosExplore-constraints"] = messages;
  return projected;
}

function projectRootFieldSchema(value: unknown, required: boolean): unknown {
  if (!isSchema(value)) return value;
  const projected: Record<string, unknown> = { ...value };
  const types = typeSet(value.type);
  if (!required && types?.has("string") && types.has("null") && Array.isArray(value.enum)
      && value.enum.every(item => typeof item === "string")) {
    projected.enum = [...value.enum, null];
  }
  return projected;
}

function compareBehaviorConstraints(
  expected: SchemaObject,
  actual: SchemaObject,
  path: string,
  differences: SchemaDifference[]
): void {
  compareUniqueItems(expected, actual, path, differences);
  for (const key of ["oneOf", "allOf", "not"] as const) {
    compareCompositeConstraint(expected, actual, key, path, differences);
  }
  compareExtensionConstraint(expected, actual, path, differences);
  comparePropertyOrder(expected, actual, path, differences);
}

function compareUniqueItems(
  expected: SchemaObject,
  actual: SchemaObject,
  path: string,
  differences: SchemaDifference[]
): void {
  if (expected.uniqueItems !== undefined && typeof expected.uniqueItems !== "boolean"
      || actual.uniqueItems !== undefined && typeof actual.uniqueItems !== "boolean") {
    differences.push({ kind: "invalid", path: `${path}.uniqueItems`, message: "uniqueItems 必须是 boolean", breaking: true });
    return;
  }
  const before = expected.uniqueItems === true;
  const after = actual.uniqueItems === true;
  if (before !== after) {
    differences.push({ kind: "changed", path: `${path}.uniqueItems`, message: "uniqueItems 约束变化", breaking: after });
  }
}

function compareCompositeConstraint(
  expected: SchemaObject,
  actual: SchemaObject,
  key: "oneOf" | "allOf" | "not",
  path: string,
  differences: SchemaDifference[]
): void {
  const beforePresent = expected[key] !== undefined;
  const afterPresent = actual[key] !== undefined;
  if (!beforePresent && !afterPresent) return;
  if (beforePresent && !validCompositeConstraint(key, expected[key])
      || afterPresent && !validCompositeConstraint(key, actual[key])) {
    differences.push({ kind: "invalid", path: `${path}.${key}`, message: `${key} 约束非法`, breaking: true });
    return;
  }
  if (beforePresent && afterPresent && sameJSONValue(expected[key], actual[key])) return;
  differences.push({
    kind: "changed",
    path: `${path}.${key}`,
    message: `${key} 约束变化`,
    breaking: afterPresent
  });
}

function validCompositeConstraint(key: "oneOf" | "allOf" | "not", value: unknown): boolean {
  if (key === "not") return isSchema(value);
  return Array.isArray(value) && value.length > 0 && value.every(isSchema);
}

function compareExtensionConstraint(
  expected: SchemaObject,
  actual: SchemaObject,
  path: string,
  differences: SchemaDifference[]
): void {
  const key = "x-iosExplore-constraints";
  const beforePresent = expected[key] !== undefined;
  const afterPresent = actual[key] !== undefined;
  if (!beforePresent && !afterPresent) return;
  if (beforePresent && !validExtensionConstraint(expected[key])
      || afterPresent && !validExtensionConstraint(actual[key])) {
    differences.push({ kind: "invalid", path: `${path}.${key}`, message: `${key} 必须是 object 或字符串数组`, breaking: true });
    return;
  }
  if (beforePresent && afterPresent && sameJSONValue(expected[key], actual[key])) return;
  differences.push({ kind: "changed", path: `${path}.${key}`, message: `${key} 约束变化`, breaking: afterPresent });
}

function validExtensionConstraint(value: unknown): boolean {
  return isSchema(value) || Array.isArray(value) && value.every(item => typeof item === "string");
}

function comparePropertyOrder(
  expected: SchemaObject,
  actual: SchemaObject,
  path: string,
  differences: SchemaDifference[]
): void {
  const key = "x-iosExplore-propertyOrder";
  if (expected[key] === undefined) return;
  const before = stringArray(expected[key]);
  const after = stringArray(actual[key]);
  if (before === undefined || after === undefined) {
    differences.push({ kind: "invalid", path: `${path}.${key}`, message: `${key} 必须是字符串数组`, breaking: true });
    return;
  }
  if (before.length !== after.length || before.some((value, index) => after[index] !== value)) {
    differences.push({ kind: "changed", path: `${path}.${key}`, message: `${key} 字段顺序变化`, breaking: true });
  }
}

function compareType(expected: SchemaObject, actual: SchemaObject, path: string, differences: SchemaDifference[]): void {
  const expectedTypes = typeSet(expected.type);
  const actualTypes = typeSet(actual.type);
  if (!expectedTypes || !actualTypes) {
    differences.push({ kind: "invalid", path: `${path}.type`, message: "type 必须是受控类型", breaking: true });
  } else if (!sameTypeSet(expectedTypes, actualTypes)) {
    const breaking = !isTypeSubset(expectedTypes, actualTypes);
    differences.push({ kind: "changed", path: `${path}.type`, message: "property type 变化", breaking });
  }
}

function compareDefault(expected: SchemaObject, actual: SchemaObject, path: string, differences: SchemaDifference[]): void {
  const beforePresent = expected.default !== undefined;
  const afterPresent = actual.default !== undefined;
  if (!beforePresent && !afterPresent) return;
  if (beforePresent !== afterPresent || !sameJSONValue(expected.default, actual.default)) {
    differences.push({ kind: "changed", path: `${path}.default`, message: "default 变化", breaking: true });
  }
}

function compareEnum(expected: SchemaObject, actual: SchemaObject, path: string, differences: SchemaDifference[]): void {
  if (expected.enum === undefined && actual.enum === undefined) return;
  if (expected.enum !== undefined && !Array.isArray(expected.enum)
      || actual.enum !== undefined && !Array.isArray(actual.enum)) {
    differences.push({ kind: "invalid", path: `${path}.enum`, message: "enum 必须是数组", breaking: true });
    return;
  }
  const expectedValues = expected.enum?.map(stableValue);
  const actualValues = actual.enum?.map(stableValue);
  if (expectedValues === undefined || actualValues === undefined) {
    differences.push({
      kind: "changed",
      path: `${path}.enum`,
      message: "enum 取值集合变化",
      breaking: expectedValues === undefined
    });
    return;
  }
  if (sameSet(new Set(expectedValues), new Set(actualValues))) return;
  const breaking = !expectedValues.every(value => actualValues.includes(value));
  differences.push({ kind: "changed", path: `${path}.enum`, message: "enum 取值集合变化", breaking });
}

function compareNumberBound(expected: SchemaObject, actual: SchemaObject, key: string, path: string, differences: SchemaDifference[], lower: boolean): void {
  const beforePresent = expected[key] !== undefined;
  const afterPresent = actual[key] !== undefined;
  if (!beforePresent && !afterPresent) return;
  const before = beforePresent ? validBound(key, expected[key]) : undefined;
  const after = afterPresent ? validBound(key, actual[key]) : undefined;
  if (beforePresent && before === undefined || afterPresent && after === undefined) {
    differences.push({ kind: "invalid", path: `${path}.${key}`, message: `${key} 约束值非法`, breaking: true });
    return;
  }
  if (!beforePresent || !afterPresent) {
    differences.push({ kind: "changed", path: `${path}.${key}`, message: `${key} 约束变化`, breaking: !beforePresent });
    return;
  }
  const narrowed = lower ? after! > before! : after! < before!;
  if (after !== before) differences.push({ kind: "changed", path: `${path}.${key}`, message: `${key} 约束变化`, breaking: narrowed });
}

function validateBoundaryRelationships(
  schema: SchemaObject,
  path: string,
  differences: SchemaDifference[],
  source: string
): void {
  const minItems = validBound("minItems", schema.minItems);
  const maxItems = validBound("maxItems", schema.maxItems);
  if (minItems !== undefined && maxItems !== undefined && minItems > maxItems) {
    differences.push({
      kind: "invalid",
      path: `${path}.minItems/maxItems`,
      message: `${source} minItems 不能大于 maxItems`,
      breaking: true
    });
  }

  const lowerBounds = [
    boundCandidate(schema, "minimum", false),
    boundCandidate(schema, "exclusiveMinimum", true)
  ].filter((candidate): candidate is BoundCandidate => candidate !== undefined);
  const upperBounds = [
    boundCandidate(schema, "maximum", false),
    boundCandidate(schema, "exclusiveMaximum", true)
  ].filter((candidate): candidate is BoundCandidate => candidate !== undefined);
  if (lowerBounds.length === 0 || upperBounds.length === 0) return;

  const lower = lowerBounds.reduce((current, candidate) =>
    candidate.value > current.value
      || candidate.value === current.value && candidate.exclusive ? candidate : current);
  const upper = upperBounds.reduce((current, candidate) =>
    candidate.value < current.value
      || candidate.value === current.value && candidate.exclusive ? candidate : current);
  if (lower.value > upper.value
      || lower.value === upper.value && (lower.exclusive || upper.exclusive)) {
    differences.push({
      kind: "invalid",
      path: `${path}.minimum/maximum`,
      message: `${source} 数值上下界冲突`,
      breaking: true
    });
  }
}

function compareAdditionalProperties(expected: SchemaObject, actual: SchemaObject, path: string, differences: SchemaDifference[]): void {
  const before = expected.additionalProperties === undefined ? true : expected.additionalProperties;
  const after = actual.additionalProperties === undefined ? true : actual.additionalProperties;
  if (typeof before !== "boolean" || typeof after !== "boolean") {
    differences.push({ kind: "invalid", path: `${path}.additionalProperties`, message: "additionalProperties 必须是 boolean", breaking: true });
  } else if (before !== after) {
    differences.push({ kind: "changed", path: `${path}.additionalProperties`, message: "additionalProperties 约束变化", breaking: before && !after });
  }
}

type SchemaObject = { readonly [key: string]: unknown };

function isObjectSchema(value: unknown): value is SchemaObject {
  const types = isSchema(value) ? typeSet(value.type) : undefined;
  return types?.size === 1 && types.has("object");
}
function isSchema(value: unknown): value is SchemaObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
function objectValue(value: unknown): SchemaObject | undefined {
  return isSchema(value) ? value : undefined;
}
function typeSet(value: unknown): Set<string> | undefined {
  const values = typeof value === "string" ? [value] : Array.isArray(value) && value.every(item => typeof item === "string") ? value : undefined;
  if (!values || values.length === 0 || values.some(item => !["object", "array", "string", "number", "integer", "boolean", "null"].includes(item))) return undefined;
  return new Set(values);
}
function stringSet(value: unknown, path: string, differences: SchemaDifference[]): Set<string> {
  if (value === undefined) return new Set();
  if (!Array.isArray(value) || value.some(item => typeof item !== "string")) {
    differences.push({ kind: "invalid", path, message: "required 必须是字符串数组", breaking: true });
    return new Set();
  }
  return new Set(value);
}
function stringArray(value: unknown): string[] | undefined {
  return Array.isArray(value) && value.every(item => typeof item === "string") ? value : undefined;
}
interface BoundCandidate {
  readonly value: number;
  readonly exclusive: boolean;
}

function boundCandidate(schema: SchemaObject, key: string, exclusive: boolean): BoundCandidate | undefined {
  const value = validBound(key, schema[key]);
  return value === undefined ? undefined : { value, exclusive };
}

function validBound(key: string, value: unknown): number | undefined {
  if (value === undefined || typeof value !== "number" || !Number.isFinite(value)) return undefined;
  if ((key === "minItems" || key === "maxItems") && (!Number.isInteger(value) || value < 0)) return undefined;
  return value;
}

function sameSet(left: Set<string>, right: Set<string>): boolean { return left.size === right.size && [...left].every(value => right.has(value)); }
function sameTypeSet(left: Set<string>, right: Set<string>): boolean {
  return isTypeSubset(left, right) && isTypeSubset(right, left);
}
function isTypeSubset(left: Set<string>, right: Set<string>): boolean {
  return [...left].every(value => right.has(value) || value === "integer" && right.has("number"));
}
function sameJSONValue(left: unknown, right: unknown): boolean {
  if (left === right) return true;
  if (Array.isArray(left) || Array.isArray(right)) {
    return Array.isArray(left)
      && Array.isArray(right)
      && left.length === right.length
      && left.every((value, index) => sameJSONValue(value, right[index]));
  }
  if (!isSchema(left) || !isSchema(right)) return false;
  const leftKeys = Object.keys(left);
  const rightKeys = Object.keys(right);
  return leftKeys.length === rightKeys.length
    && leftKeys.every(key => Object.prototype.hasOwnProperty.call(right, key) && sameJSONValue(left[key], right[key]));
}
function stableValue(value: unknown): string { try { return JSON.stringify(value); } catch { return String(value); } }
