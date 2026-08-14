/**
 * CLI 命令公共入口。
 *
 * 命令实现和内部策略位于 commandHandlers.ts；这里保留稳定的模块门面，
 * 让 argv 解析器、测试和外部调用方继续使用原来的导入路径。
 */
export {
  executeCLICommand,
  parseData,
  exitCodeForError,
  EXIT_CODES
} from "./commands/commandHandlers.js";
export type {
  CLICommandName,
  CallCommandOptions,
  CLICommandContext
} from "./commands/commandHandlers.js";
