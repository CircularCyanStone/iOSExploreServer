/**
 * CLI 应用公共入口。
 *
 * 编排实现位于 applicationRuntime.ts；类型定义位于 applicationTypes.ts。
 */
export { runCLI } from "./application/applicationRuntime.js";
export type { CLIApplicationDependencies } from "./application/applicationTypes.js";
