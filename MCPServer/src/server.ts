import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { CallToolRequestSchema, ListToolsRequestSchema } from "@modelcontextprotocol/sdk/types.js";
import { IOSExploreStructuredError } from "./errors.js";
import { errorResult, jsonResult } from "./result.js";
import type { IOSExploreCaller } from "./toolRegistry.js";
import type { JSONObject, MCPToolResult, StructuredError, ToolDefinition } from "./types.js";

type StaticToolLike = {
  name: string;
  description: string;
  inputSchema: JSONObject;
  handler(input: JSONObject): Promise<MCPToolResult>;
};

type RegistryLike = {
  tools(): ToolDefinition[];
  findByName(name: string): ToolDefinition | undefined;
  refresh(): Promise<unknown>;
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
      let dynamic = options.registry.findByName(name);
      if (!dynamic && isIOSExploreDynamicToolName(name)) {
        await options.registry.refresh();
        dynamic = options.registry.findByName(name);
      }
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
          if (isTransportError(error)) {
            await sleep(200);
            try {
              return jsonResult(await options.client.call(dynamic.action, args));
            } catch (retryError) {
              if (isTransportError(retryError)) {
                return errorResult(await enrichTransportError(retryError, options.client));
              }
              return normalizedResult(retryError);
            }
          }
          return normalizedResult(error);
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

function isIOSExploreDynamicToolName(name: string): boolean {
  // T4 修复后动态工具名直接由 action 名派生（`toolNameForAction` 把 `ui.tap` 转成 `ui_tap`），
  // 不再带 `ios_` 前缀。识别动态工具用 `ui_` 前缀——所有 UIKit action 都是 `ui.*` 命名空间。
  // 静态工具（health_check / refresh_tools / call_action / wait_and_inspect）
  // 不会以 `ui_` 开头，不会误触发 refresh。
  return name.startsWith("ui_");
}

function isTransportError(error: unknown): error is IOSExploreStructuredError {
  return error instanceof IOSExploreStructuredError && error.source === "transport";
}

function sleep(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms));
}

async function enrichTransportError(error: IOSExploreStructuredError, client: IOSExploreCaller): Promise<StructuredError & JSONObject> {
  const normalized = normalizeUnknownError(error);
  return {
    ...normalized,
    retry: { attempted: true, delayMs: 200, succeeded: false },
    healthCheck: await pingHealthCheck(client),
    nextSteps: [
      "iOSExplore App 当前不可达；如果是真机调试，请确认 App 仍在运行、iproxy 仍在监听 38321，并用 XcodeBuildMCP launch_app_device 以 IOS_EXPLORE_AUTOSTART=1 重启后再试。"
    ]
  };
}

async function pingHealthCheck(client: IOSExploreCaller): Promise<JSONObject> {
  try {
    return { ok: true, ping: await client.call("ping") };
  } catch (error) {
    return { ok: false, error: normalizeUnknownError(error) };
  }
}

function normalizeUnknownError(error: unknown): StructuredError {
  if (error instanceof IOSExploreStructuredError) {
    return error.toJSON();
  }
  if (typeof error === "object" && error !== null && "source" in error && "message" in error) {
    return error as StructuredError;
  }
  return {
    source: "mcp_server" as const,
    code: "unexpected_error",
    message: error instanceof Error ? error.message : String(error)
  };
}

/**
 * 将动态工具执行中 catch 到的错误，按来源区分处理：
 * - ios_envelope（App 端业务失败）→ 正常响应 isError=false
 * - transport/http/mcp_server → 真实错误 isError=true
 */
function normalizedResult(error: unknown): MCPToolResult {
  const normalized = normalizeUnknownError(error);
  if (normalized.source === "ios_envelope") {
    return jsonResult(normalized as unknown as JSONObject, false);
  }
  return errorResult(normalized);
}
