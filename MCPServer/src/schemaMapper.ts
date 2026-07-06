import type { JSONObject } from "./types.js";

export type SchemaMapping = {
  inputSchema: JSONObject;
  descriptionSuffix: string;
};

export function mapInputSchema(schema: JSONObject): SchemaMapping {
  const inputSchema: JSONObject = {};
  const extensionLines: string[] = [];

  for (const [key, value] of Object.entries(schema)) {
    if (key.startsWith("x-iosExplore-")) {
      extensionLines.push(...extensionValueLines(key, value));
    } else {
      inputSchema[key] = normalizeSchemaValue(value);
    }
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
