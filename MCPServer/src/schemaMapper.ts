import type { JSONObject, JSONValue } from "./types.js";

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
      inputSchema[key] = value;
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

function extensionValueLines(key: string, value: JSONValue): string[] {
  if (Array.isArray(value)) {
    return value.map(item => `${key}: ${String(item)}`);
  }
  return [`${key}: ${String(value)}`];
}
