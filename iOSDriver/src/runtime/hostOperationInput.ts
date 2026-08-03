/**
 * host operation 输入的轻量合同校验器。
 *
 * 职责边界：只校验**在 Mac 上执行**的包装层参数（`call_action` 与 workflow 的
 * 输入）；device action 的业务 data 仍由 App 端 Foundation-only 的 `CommandInput`
 * 解析——避免 TypeScript 和 Swift 对同一 action 维护两套默认值与约束逻辑。
 *
 * 校验基于生成的 host schema（src/generated/hostOperationSpecs.ts），实现的是受控的
 * JSON Schema 子集（type/enum/数值范围/数组约束/required/additionalProperties/
 * allOf/oneOf/not + 跨字段扩展约束）。错误只携带字段路径，不回显用户值。
 */
import { HOST_OPERATION_SPECS, type HostOperationSpec } from "../generated/hostOperationSpecs.js";
import type { JSONObject } from "../types.js";

type HostOperation = HostOperationSpec["operation"];
type SchemaType = "object" | "array" | "string" | "number" | "integer" | "boolean" | "null";

/** 受控 JSON Schema 子集的运行时表示（只包含生成器实际会输出的关键字）。 */
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
  /** 标准 JSON Schema 之外的跨字段约束（exactlyOneOf/mutuallyExclusive）。 */
  readonly "x-iosExplore-constraints"?: Readonly<Record<string, unknown>>;
}

/** 单个校验失败：只含合同字段位置与稳定原因，不含用户实际值（防泄漏）。 */
interface ValidationIssue {
  /** JSON 风格字段路径，如 "$.data.timeoutMs"。 */
  readonly path: string;
  /** 稳定、无 payload 的失败原因（英文，供机器识别）。 */
  readonly reason: string;
}

/** 构建时从生成产物建立的「operation 名 → 输入 schema」索引。 */
const HOST_INPUT_SCHEMAS = new Map<string, RuntimeSchema>(
  HOST_OPERATION_SPECS.map(spec => [spec.operation, spec.inputSchema as unknown as RuntimeSchema])
);

/**
 * host operation 输入不符合 generated contract 时抛出的错误。
 */
export class HostOperationInputValidationError extends Error {
  /** 失败所属 host operation（供 adapter 记录安全上下文）。 */
  readonly operation: HostOperation;
  /** 第一个失败字段的 JSON 风格路径（如 "$.data"）。 */
  readonly path: string;

  constructor(operation: HostOperation, issue: ValidationIssue) {
    super(`Invalid ${operation} input at ${issue.path}: ${issue.reason}`);
    this.name = "HostOperationInputValidationError";
    this.operation = operation;
    this.path = issue.path;
  }
}

/**
 * 按 generated host-operation contract 校验包装层输入（只用于 Mac 侧 host operation）。
 *
 * @param operation host operation 名称（如 "call_action"、"wait_and_inspect"）。
 * @param input MCP/CLI 提供的原始包装层输入（任意 JSON 值）。
 * @returns 已确认符合 object schema 的输入对象；**不会**填充或改写默认值。
 * @throws {HostOperationInputValidationError} 首个不合规字段（错误只含合同路径，
 *   不回显用户值）；schema 缺失时抛普通 Error。
 */
export function validateHostOperationInput(operation: HostOperation, input: unknown): JSONObject {
  const schema = HOST_INPUT_SCHEMAS.get(operation);
  if (schema === undefined) throw new Error(`Missing generated host operation contract: ${operation}`);
  const issue = firstIssue(schema, input, "$");
  if (issue !== undefined) throw new HostOperationInputValidationError(operation, issue);
  return input as JSONObject;
}

/**
 * 深度校验任意值是否符合 schema，返回**第一个**问题（检查顺序固定，错误可预期）。
 *
 * 检查顺序：type → enum → 数值范围 → 数组约束 → 对象字段（required → 声明字段 →
 * additionalProperties → 扩展约束）→ allOf/oneOf/not。数组项与嵌套对象递归。
 *
 * @param schema 节点 schema。
 * @param value 待校验值。
 * @param path 当前 JSON 路径（如 "$.data"）。
 * @returns 第一个问题；全部通过返回 undefined。
 */
function firstIssue(schema: RuntimeSchema, value: unknown, path: string): ValidationIssue | undefined {
  // 按 type -> enum/range -> container -> composite 顺序返回首个问题，使错误位置确定且简短。
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
    // 先检查已声明字段，再处理 additionalProperties，避免未知字段掩盖更具体的字段错误。
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

/** 执行标准 JSON Schema 无法直接表达的跨字段 exactly-one/mutual-exclusion 约束。 */
/**
 * 执行标准 JSON Schema 无法表达的跨字段约束（exactlyOneOf/mutuallyExclusive）。
 *
 * @param schema 含 x-iosExplore-constraints 的节点 schema。
 * @param value 待校验对象。
 * @param path 当前 JSON 路径。
 * @returns 约束违规的问题；无约束或通过返回 undefined。
 */
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

/**
 * 校验值是否匹配类型（支持 "type": ["string","null"] 这类联合类型）。
 *
 * @param value 待校验值。
 * @param type 类型或类型数组。
 * @returns true=匹配。
 */
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

/** 把类型（或类型数组）转为错误信息可读的描述。 */
function describeType(type: SchemaType | readonly SchemaType[]): string {
  return typeof type === "string" ? type : type.join(" or ");
}

/** 类型守卫：未知值是否为 JSON 对象（非 null、非数组）。 */
function isObject(value: unknown): value is JSONObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/** 判断字段是否存在且非 null（用于跨字段约束的「提供」判定）。 */
function hasNonNullValue(value: JSONObject, name: string): boolean {
  return Object.hasOwn(value, name) && value[name] !== null;
}

/** 提取字符串数组；非全字符串数组返回 undefined（约束声明非法则忽略）。 */
function stringArray(value: unknown): readonly string[] | undefined {
  return Array.isArray(value) && value.every(item => typeof item === "string")
    ? value as string[]
    : undefined;
}

/**
 * 使用结构化 JSON 相等（而非对象引用相等）实现 uniqueItems。
 *
 * @param values 待检查数组。
 * @returns true=存在重复项。
 */
function hasDuplicate(values: readonly unknown[]): boolean {
  return values.some((value, index) => values.slice(0, index).some(previous => jsonEqual(previous, value)));
}

/**
 * 与对象键顺序无关的递归 JSON 相等比较。
 *
 * @param left 左值。
 * @param right 右值。
 * @returns true=结构相等（键顺序不影响）。
 */
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
