#!/usr/bin/env node

/**
 * iOSDriver CLI 的 Node 可执行入口。
 *
 * 阅读入口只需要看本文件：`main` 把进程参数交给 CLI 应用，文件末尾确认当前模块确实由
 * Node 直接启动，然后把应用返回值设置为进程退出码。参数解析和执行编排分别位于
 * `arguments.ts` 与 `application.ts`，具体命令行为位于 `commands.ts`。
 */
import { realpathSync } from "node:fs";
import { fileURLToPath } from "node:url";
import {
  runCLI,
  type CLIApplicationDependencies
} from "./application.js";

/** 入口调用方可覆盖的依赖；CLI 文件路径默认取当前构建产物。 */
export type CLIMainDependencies = Omit<CLIApplicationDependencies, "cliEntryPath"> & {
  readonly cliEntryPath?: string;
};

/**
 * 运行一次 CLI 调用，但不主动终止 Node 进程。
 *
 * `argv` 默认去掉 node 与脚本路径。返回退出码而不是调用 `process.exit()`，确保 stdout
 * 写入和 MCP transport 有机会完成，也允许测试直接调用同一个真实入口。
 */
export async function main(
  argv: readonly string[] = process.argv.slice(2),
  dependencies: CLIMainDependencies = {}
): Promise<number> {
  return await runCLI(argv, {
    ...dependencies,
    cliEntryPath: dependencies.cliEntryPath ?? fileURLToPath(import.meta.url)
  });
}

/**
 * 判断当前 ES module 是否为 Node 直接启动的进程入口。
 *
 * `npm link` 场景下 `argv[1]` 是符号链接，而 `import.meta.url` 是真实 JS 文件；两边先
 * 解析真实路径再比较。被测试或其他模块 import 时返回 false，不会自动执行 CLI。
 */
export function isMainModule(metaURL: string, argv1 = process.argv[1]): boolean {
  if (argv1 === undefined) return false;
  return realpathSync(argv1) === realpathSync(fileURLToPath(metaURL));
}

// 唯一具有进程副作用的入口：库式调用 `main()` 只返回数字，不修改全局 exitCode。
if (isMainModule(import.meta.url)) {
  process.exitCode = await main();
}
