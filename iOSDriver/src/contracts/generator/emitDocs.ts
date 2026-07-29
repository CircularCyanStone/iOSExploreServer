/**
 * canonical 合同的人类可读 Markdown emitter。
 *
 * 文档直接消费与代码生成相同的 prepared bundle，action 字段、默认值和错误列表因此无需
 * 在 README/CLI 文档中手写复制。所有表格内容在插入前转义，保证合同说明不会破坏结构。
 */
import type { ContractJSONValue, JsonSchema } from "./model.js";
import type { GeneratedArtifact, PreparedContractBundle } from "./emitTypeScript.js";

/** 生成包含版本、action、host operation 和 error index 的确定性 Markdown。 */
export function emitDocs(prepared: PreparedContractBundle): GeneratedArtifact {
  const { bundle, hash } = prepared;
  const lines = [
    "<!-- Generated from contracts/. Do not edit directly. -->",
    "# iOS Driver Contracts",
    "",
    `- Protocol version: \`${escapeInline(bundle.protocolVersion)}\``,
    `- Contract version: \`${escapeInline(bundle.contractVersion)}\``,
    `- Generator version: \`${escapeInline(bundle.generatorVersion)}\``,
    `- Contract hash: \`${hash}\``,
    `- Device actions: ${bundle.deviceActions.length}`,
    `- Host operations: ${bundle.hostOperations.length}`,
    "",
    "## Device Actions",
    ""
  ];

  for (const contract of bundle.deviceActions) {
    lines.push(
      `### \`${escapeInline(contract.action)}\``,
      "",
      contract.description,
      "",
      `- Provider: \`${contract.provider}\``,
      `- Stability: \`${contract.stability}\``,
      `- Idempotency: \`${contract.idempotency}\``,
      `- Timeout class: \`${contract.timeoutClass}\``,
      `- Result: \`${contract.result.kind}\``,
      `- Errors: ${formatErrors(contract.errors)}`,
      "",
      ...schemaSummary(contract.inputSchema),
      ""
    );
  }

  lines.push("## Host Operations", "");
  for (const operation of bundle.hostOperations) {
    lines.push(
      `### \`${escapeInline(operation.operation)}\``,
      "",
      operation.description,
      "",
      `- Result: \`${operation.result.kind}\``,
      `- Errors: ${formatErrors(operation.errors)}`,
      "",
      ...schemaSummary(operation.inputSchema),
      ""
    );
  }

  lines.push(
    "## Error Index",
    "",
    "| Code | Source | Retryable | Terminal |",
    "| --- | --- | --- | --- |"
  );
  for (const [code, error] of Object.entries(bundle.errors)) {
    lines.push(`| \`${escapeTable(code)}\` | \`${escapeTable(error.source)}\` | ${error.retryable} | ${error.terminal} |`);
  }
  lines.push("");

  return { path: "docs/generated/contracts.md", content: lines.join("\n") };
}

function schemaSummary(schema: JsonSchema): string[] {
  const fields = flattenFields(schema);
  if (fields.length === 0) return ["Input fields: none."];
  const lines = [
    "| Field | Type | Required | Default | Description |",
    "| --- | --- | --- | --- | --- |"
  ];
  for (const field of fields) {
    lines.push(
      `| \`${escapeTable(field.path)}\` | \`${escapeTable(field.type)}\` | ${field.required ? "yes" : "no"} | ${field.defaultValue} | ${escapeTable(field.description)} |`
    );
  }
  return lines;
}

/** 扁平字段表的一行；嵌套对象以点路径表示，object array 以 `[]` 表示。 */
interface FieldSummary {
  readonly path: string;
  readonly type: string;
  readonly required: boolean;
  readonly defaultValue: string;
  readonly description: string;
}

/** 深度优先展开属性，并按字段名排序以保持文档 diff 稳定。 */
function flattenFields(schema: JsonSchema, prefix = ""): FieldSummary[] {
  const properties = schema.properties ?? {};
  const required = new Set(schema.required ?? []);
  const fields: FieldSummary[] = [];
  for (const name of Object.keys(properties).sort()) {
    const property = properties[name]!;
    const path = prefix.length === 0 ? name : `${prefix}.${name}`;
    fields.push({
      path,
      type: schemaType(property),
      required: required.has(name),
      defaultValue: property.default === undefined ? "-" : `\`${escapeTable(formatJSON(property.default))}\``,
      description: property.description ?? ""
    });
    if (property.properties !== undefined) fields.push(...flattenFields(property, path));
    if (property.items?.properties !== undefined) fields.push(...flattenFields(property.items, `${path}[]`));
  }
  return fields;
}

function schemaType(schema: JsonSchema): string {
  const type = schema.type;
  if (Array.isArray(type)) return type.join(" | ");
  if (type === "array") return `${schemaType(schema.items ?? {})}[]`;
  return type ?? "any";
}

function formatErrors(errors: readonly string[]): string {
  return errors.length === 0 ? "none" : errors.map(error => `\`${escapeInline(error)}\``).join(", ");
}

function formatJSON(value: ContractJSONValue): string {
  return JSON.stringify(value);
}

function escapeInline(value: string): string {
  return value.replace(/`/g, "\\`");
}

/** 转义表格分隔符并压平换行，避免 description 注入额外 Markdown 行。 */
function escapeTable(value: string): string {
  return value.replace(/\|/g, "\\|").replace(/\r?\n/g, " ");
}
