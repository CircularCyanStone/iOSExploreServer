import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { CallToolRequestSchema, ListToolsRequestSchema } from "@modelcontextprotocol/sdk/types.js";
import { errorResult, jsonResult } from "./result.js";
import type { IOSExploreCaller } from "./toolRegistry.js";
import type { JSONObject, MCPToolResult, ToolDefinition } from "./types.js";

type StaticToolLike = {
  name: string;
  description: string;
  inputSchema: JSONObject;
  handler(input: JSONObject): Promise<MCPToolResult>;
};

type RegistryLike = {
  tools(): ToolDefinition[];
  findByName(name: string): ToolDefinition | undefined;
};

export function createToolHandlers(options: {
  staticTools: Record<string, StaticToolLike>;
  registry: RegistryLike;
  client: IOSExploreCaller;
}) {
  return {
    async listTools() {
      return {
        tools: [
          ...Object.values(options.staticTools).map(toMCPTool),
          ...options.registry.tools().map(toMCPTool)
        ]
      };
    },
    async callTool(name: string, args: JSONObject = {}): Promise<MCPToolResult> {
      const fixed = options.staticTools[name];
      if (fixed) {
        return fixed.handler(args);
      }
      const dynamic = options.registry.findByName(name);
      if (dynamic?.action) {
        try {
          const data = await options.client.call(dynamic.action, args);
          if (dynamic.action === "ui.screenshot" && typeof data.image === "string" && data.format === "png") {
            const { image, ...rest } = data;
            return {
              content: [
                { type: "image", data: image, mimeType: "image/png" },
                { type: "text", text: JSON.stringify(rest) }
              ]
            };
          }
          return jsonResult(data);
        } catch (error) {
          return errorResult(normalizeUnknownError(error));
        }
      }
      return errorResult({
        source: "mcp_server",
        code: "unknown_tool",
        message: `Unknown tool '${name}'`
      });
    }
  };
}

export async function startStdioServer(options: {
  staticTools: Record<string, StaticToolLike>;
  registry: RegistryLike;
  client: IOSExploreCaller;
}) {
  const server = new Server(
    { name: "ios-explore-mcp-server", version: "0.1.0" },
    { capabilities: { tools: {} } }
  );
  const handlers = createToolHandlers(options);

  server.setRequestHandler(ListToolsRequestSchema, async () => handlers.listTools());
  server.setRequestHandler(CallToolRequestSchema, async request => {
    const name = request.params.name;
    const args = (request.params.arguments ?? {}) as JSONObject;
    return handlers.callTool(name, args);
  });

  await server.connect(new StdioServerTransport());
}

function toMCPTool(tool: StaticToolLike | ToolDefinition) {
  return {
    name: tool.name,
    description: tool.description,
    inputSchema: tool.inputSchema
  };
}

function normalizeUnknownError(error: unknown) {
  if (typeof error === "object" && error !== null && "source" in error && "message" in error) {
    return error as { source: "mcp_server"; message: string; code?: string };
  }
  return {
    source: "mcp_server" as const,
    code: "unexpected_error",
    message: error instanceof Error ? error.message : String(error)
  };
}
