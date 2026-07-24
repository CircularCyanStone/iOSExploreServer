/** 新 MCP adapter handler 工厂的兼容入口。 */
export { createMCPToolHandlers as createToolHandlers } from "./adapters/mcp/server.js";
/** 新 stdio MCP server 启动函数的兼容入口。 */
export { startMCPStdioServer as startStdioServer } from "./adapters/mcp/server.js";
/** MCP adapter 公开类型的兼容导出。 */
export type {
  MCPAdapterOptions,
  MCPCapabilityProbe,
  MCPRuntime,
  MCPToolHandlers,
  MCPWorkflowRunner
} from "./adapters/mcp/server.js";
