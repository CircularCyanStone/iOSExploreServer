/**
 * MCP 客户端注册公共入口。
 *
 * 注册实现位于 mcpClientSetupRuntime.ts，合同和依赖注入类型位于
 * mcpClientSetupTypes.ts。
 */
export { setupMCPClient } from "./mcpClientSetupRuntime.js";
export type {
  MCPClientName,
  MCPRegistrationScope,
  MCPLaunchCommand,
  MCPClientSetupInput,
  MCPClientSetupResult,
  MCPSetupFileSystem,
  MCPSetupCommandResult,
  MCPSetupCommandRunner,
  MCPClientSetupDependencies
} from "./mcpClientSetupTypes.js";
export { MCPClientSetupError } from "./mcpClientSetupTypes.js";
