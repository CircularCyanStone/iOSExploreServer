import type { JSONValue, MCPToolResult, StructuredError } from "./types.js";

export function jsonResult(value: JSONValue, isError = false): MCPToolResult {
  return {
    isError,
    content: [
      {
        type: "text",
        text: JSON.stringify(value, null, 2)
      }
    ]
  };
}

export function errorResult(error: StructuredError): MCPToolResult {
  return jsonResult(error, true);
}
