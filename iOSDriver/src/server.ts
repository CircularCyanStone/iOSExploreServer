import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { CallToolRequestSchema, ListToolsRequestSchema } from "@modelcontextprotocol/sdk/types.js";
import { errorResult } from "./result.js";
import type { JSONObject, MCPToolResult } from "./types.js";

type StaticToolLike = {
  name: string;
  description: string;
  inputSchema: JSONObject;
  handler(input: JSONObject): Promise<MCPToolResult>;
};

export function createToolHandlers(options: {
  staticTools: Record<string, StaticToolLike>;
}) {
  return {
    async listTools() {
      return {
        tools: [
          ...Object.values(options.staticTools).map(toMCPTool)
        ]
      };
    },
    async callTool(name: string, args: JSONObject = {}): Promise<MCPToolResult> {
      const fixed = options.staticTools[name];
      if (fixed) {
        return fixed.handler(args);
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

function toMCPTool(tool: StaticToolLike) {
  return {
    name: tool.name,
    description: tool.description,
    inputSchema: tool.inputSchema
  };
}
