import type { JSONObject } from "./types.js";

export type SchemaMapping = {
  inputSchema: JSONObject;
  descriptionSuffix: string;
};

// 严格的 "<field> is required ..." 文本约束解析：
// 仅匹配 "<word> is required" 形式（word 仅字母数字下划线），
// 并校验 field 是 properties 中真实存在的顶层字段，
// 防止把 "conditions[].mode 必填字段" 之类的非顶层字段或
// "最多提供" 这种带斜杠的多字段约束误提升为 required。
const REQUIRED_CONSTRAINT_RE = /^([A-Za-z_][A-Za-z0-9_]*)\s+is\s+required\b/;

export function mapInputSchema(schema: JSONObject): SchemaMapping {
  const inputSchema: JSONObject = {};
  const extensionLines: string[] = [];
  const requiredFromConstraints: string[] = [];

  // properties 用来校验从 constraints 里抽出来的字段名是顶层字段而非子节点字段。
  const properties = isPlainObject(schema.properties) ? schema.properties : undefined;

  for (const [key, value] of Object.entries(schema)) {
    if (key.startsWith("x-iosExplore-")) {
      if (key === "x-iosExplore-constraints" && Array.isArray(value)) {
        for (const constraint of value) {
          if (typeof constraint !== "string") continue;
          const match = REQUIRED_CONSTRAINT_RE.exec(constraint.trim());
          if (match?.[1] && properties && Object.prototype.hasOwnProperty.call(properties, match[1])) {
            requiredFromConstraints.push(match[1]);
          }
        }
      }
      extensionLines.push(...extensionValueLines(key, value));
    } else {
      inputSchema[key] = normalizeSchemaValue(value);
    }
  }

  // 把 "<field> is required" 约束提取为 JSON Schema 真实 required，
  // 让 Agent 模型从 schema 的 required 字段直接看到 viewSnapshotID 等必填字段，
  // 而不是只从 description 里推断。已存在的 required（如 ui.control.sendAction 的 event）
  // 与新加入的字段合并去重。App 端的 oneOf（identifier/path 二选一）仍由 inputSchema.oneOf 表达。
  if (requiredFromConstraints.length > 0) {
    const existing = Array.isArray(inputSchema.required) ? (inputSchema.required as unknown[]) : [];
    const merged = new Set<string>();
    for (const field of existing) {
      if (typeof field === "string") merged.add(field);
    }
    for (const field of requiredFromConstraints) {
      merged.add(field);
    }
    inputSchema.required = Array.from(merged);
  }

  return {
    inputSchema,
    descriptionSuffix:
      extensionLines.length === 0
        ? ""
        : `\n\niOSExplore constraints:\n${extensionLines.map(line => `- ${line}`).join("\n")}`
  };
}

function normalizeSchemaValue(value: unknown): unknown {
  if (Array.isArray(value)) {
    return value.map(normalizeSchemaValue);
  }
  if (!isPlainObject(value)) {
    return value;
  }

  const normalized: JSONObject = {};
  for (const [key, child] of Object.entries(value)) {
    normalized[key] = normalizeSchemaValue(child);
  }

  const type = normalized.type;
  const isArrayType = type === "array" || (Array.isArray(type) && type.includes("array"));
  const enumValues = normalized.enum;
  if (isArrayType && Array.isArray(enumValues) && normalized.items === undefined) {
    delete normalized.enum;
    normalized.items = {
      type: "string",
      enum: enumValues
    };
  }

  return normalized;
}

function isPlainObject(value: unknown): value is JSONObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function extensionValueLines(key: string, value: unknown): string[] {
  if (Array.isArray(value)) {
    return value.map(item => `${key}: ${String(item)}`);
  }
  return [`${key}: ${String(value)}`];
}
