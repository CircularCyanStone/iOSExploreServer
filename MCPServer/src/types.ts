export type JSONPrimitive = string | number | boolean | null;
export type JSONValue = JSONPrimitive | JSONObject | JSONValue[];
export type JSONObject = { [key: string]: unknown }; // loose object for JSON-serializable data

export type IOSExploreSuccessEnvelope = {
  code: "ok";
  data?: JSONObject;
};

export type IOSExploreFailureEnvelope = {
  code: string;
  message: string;
};

export type IOSExploreEnvelope = IOSExploreSuccessEnvelope | IOSExploreFailureEnvelope;

export function isFailureEnvelope(envelope: IOSExploreEnvelope): envelope is IOSExploreFailureEnvelope {
  return envelope.code !== "ok";
}

export type CommandMetadata = {
  action: string;
  description: string;
  inputSchema: JSONObject;
};

export type ToolDefinition = {
  name: string;
  description: string;
  inputSchema: JSONObject;
  action?: string;
};

export type StructuredError = {
  source: "mcp_server" | "transport" | "http" | "ios_envelope";
  code?: string;
  message: string;
  action?: string;
  baseURL?: string;
  status?: number;
  timeoutMs?: number;
  bodySnippet?: string;
};

export type MCPTextContent = {
  type: "text";
  text: string;
};

export type MCPImageContent = {
  type: "image";
  data: string;
  mimeType: string;
};

export type MCPToolResult = {
  content: Array<MCPTextContent | MCPImageContent>;
  isError?: boolean;
};
