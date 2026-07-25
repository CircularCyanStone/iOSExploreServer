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
/** Host logger 工厂与注入类型，供嵌入式调用方复用同一 stderr-safe 日志链。 */
export { createHostLogger, defaultHostLogger, noopHostLogger } from "./runtime/hostLogger.js";
export type { HostLogger, HostLoggerOptions, HostLogFields, HostLogLevel, HostLogSink } from "./runtime/hostLogger.js";
