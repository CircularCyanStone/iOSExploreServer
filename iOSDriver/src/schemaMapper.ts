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
  // 与新加入的字段合并去重。
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

  // 拍平顶层组合关键字（oneOf/anyOf/allOf）。Claude Code 的 MCP 客户端在 ListTools
  // 时不消化顶层 oneOf → 含该关键字的工具（ui.tap/ui.input/ui.control.sendAction，App 用
  // exactlyOneOf → 顶层 oneOf 表达 identifier/path 互斥）不会被暴露给 agent（F-02）。
  // 拍平后：分支 properties 合并进顶层、互斥替代项不强制 required、用 description 文本
  // 保留"二选一"语义，输出 schema 不再含顶层 oneOf/anyOf/allOf。运行时互斥仍由 App 端
  // CommandInput.parse（UIKitLocatorInput）精确校验，这里只做 schema 层适配。
  const compositionNote = flattenTopLevelComposition(inputSchema);

  let descriptionSuffix =
    extensionLines.length === 0
      ? ""
      : `\n\niOSExplore constraints:\n${extensionLines.map(line => `- ${line}`).join("\n")}`;
  if (compositionNote) {
    descriptionSuffix += `\n\n${compositionNote}`;
  }

  return { inputSchema, descriptionSuffix };
}

// 拍平顶层组合关键字，返回用于追加到工具 description 的说明文本。
// 详见 mapInputSchema 内调用处注释；只处理顶层组合关键字，不递归到 properties 内部。
function flattenTopLevelComposition(inputSchema: JSONObject): string | undefined {
  const notes: string[] = [];

  // oneOf / anyOf：分支表达"互斥二选一"或"多选一"替代项。
  for (const key of ["oneOf", "anyOf"] as const) {
    if (!Array.isArray(inputSchema[key])) continue;
    const alternates = collectAlternatesFromBranches(inputSchema[key] as unknown[], inputSchema);
    delete inputSchema[key];
    if (alternates.length >= 2) {
      removeFromRequired(inputSchema, alternates);
      augmentAlternateFields(inputSchema, alternates);
      notes.push(alternateNote(key, alternates));
    }
  }

  // allOf：每个子 schema 都必须满足（AND）。合并其 properties/required，
  // 并拍平子 schema 内嵌套的 oneOf/anyOf，否则输出仍含组合关键字。
  if (Array.isArray(inputSchema.allOf)) {
    const subs = (inputSchema.allOf as unknown[]).filter(isPlainObject);
    delete inputSchema.allOf;
    for (const sub of subs) {
      mergePropertiesInto(inputSchema, sub);
      addToRequired(inputSchema, requiredStrings(sub));
      for (const key of ["oneOf", "anyOf"] as const) {
        if (Array.isArray(sub[key])) {
          const alternates = collectAlternatesFromBranches(sub[key] as unknown[], inputSchema);
          if (alternates.length >= 2) {
            removeFromRequired(inputSchema, alternates);
            augmentAlternateFields(inputSchema, alternates);
            notes.push(alternateNote(key, alternates));
          }
        }
      }
    }
  }

  return notes.length > 0 ? notes.join("; ") : undefined;
}

// 从组合分支里收集"替代字段"（各分支 required 的并集），同时把分支的 properties 合并进顶层。
function collectAlternatesFromBranches(branches: unknown[], inputSchema: JSONObject): string[] {
  const alternates = new Set<string>();
  for (const branch of branches) {
    if (!isPlainObject(branch)) continue;
    mergePropertiesInto(inputSchema, branch);
    for (const field of requiredStrings(branch)) {
      alternates.add(field);
    }
  }
  return [...alternates];
}

function alternateNote(key: "oneOf" | "anyOf", alternates: string[]): string {
  const joined = alternates.join(" / ");
  return key === "oneOf"
    ? `${joined} 二选一(互斥:必须且只能提供其中一个)`
    : `${joined} 至少提供一个(多选一)`;
}

// 把 source.properties 的字段合并进 inputSchema.properties；已存在的字段不覆盖。
function mergePropertiesInto(inputSchema: JSONObject, source: JSONObject): void {
  const srcProps = source.properties;
  if (!isPlainObject(srcProps)) return;
  let destProps = isPlainObject(inputSchema.properties)
    ? (inputSchema.properties as JSONObject)
    : undefined;
  if (!destProps) {
    destProps = {};
    inputSchema.properties = destProps;
  }
  for (const [name, schema] of Object.entries(srcProps)) {
    if (!isPlainObject(destProps[name])) {
      destProps[name] = normalizeSchemaValue(schema);
    }
  }
}

function requiredStrings(schema: JSONObject): string[] {
  return Array.isArray(schema.required)
    ? schema.required.filter((f): f is string => typeof f === "string")
    : [];
}

function removeFromRequired(inputSchema: JSONObject, fields: string[]): void {
  if (!Array.isArray(inputSchema.required)) return;
  const remove = new Set(fields);
  inputSchema.required = (inputSchema.required as unknown[]).filter(
    (f) => typeof f !== "string" || !remove.has(f)
  );
}

function addToRequired(inputSchema: JSONObject, fields: string[]): void {
  if (fields.length === 0) return;
  const current = Array.isArray(inputSchema.required) ? (inputSchema.required as unknown[]) : [];
  const merged = new Set<string>();
  for (const field of current) {
    if (typeof field === "string") merged.add(field);
  }
  for (const field of fields) {
    merged.add(field);
  }
  inputSchema.required = [...merged];
}

// 在替代字段的 property description 里追加"二选一, 互斥"提示，让 agent 填写工具参数时
// 直接看到互斥关系（description 文本对模型可见）。
function augmentAlternateFields(inputSchema: JSONObject, alternates: string[]): void {
  const props = isPlainObject(inputSchema.properties)
    ? (inputSchema.properties as JSONObject)
    : undefined;
  if (!props) return;
  for (const name of alternates) {
    const entry = props[name];
    if (!isPlainObject(entry)) continue;
    const others = alternates.filter((a) => a !== name).join(" / ");
    const hint = `⚠️ 与 ${others} 二选一(互斥):两字段中有且仅提供一个`;
    const desc = typeof entry.description === "string" ? entry.description.trim() : "";
    if (desc.includes("二选一")) continue;
    entry.description = desc ? `${desc}\n${hint}` : hint;
  }
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
    // 当 type 包含 "array" 时，顶级 enum 通常是数组元素取值范围而非字段自身取值范围；
    // 将其移入 items.enum 使 MCP 客户端能正确理解（如 sources: ["explore","bridge"]）。
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
