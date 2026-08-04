#!/usr/bin/env node

/**
 * iOSDriver CLI 的进程入口文件（`package.json` 的 `bin` 字段指向它，`npm link` 后
 * 全局命令 `iosdriver` 实际执行的就是编译产物 `dist/adapters/cli/main.js`）。
 *
 * 本文件的职责只有三件：
 *
 * 1. 定义 `main()`：接收进程参数（argv），转交 `application.ts` 的 `runCLI()` 编排
 *    一次完整调用，最终返回退出码数字；
 * 2. 定义 `isMainModule()`：判断本文件是被 `node` 直接执行还是被其他模块 import，
 *    决定文件末尾是否自动启动 CLI；
 * 3. 文件末尾：仅在「本文件是进程入口」时执行 `process.exitCode = await main()`。
 *
 * 业务逻辑不在这里：参数解析在 `arguments.ts`、配置合并在 `config.ts`、依赖组装在
 * `application.ts`、命令行为在 `commands.ts`。
 *
 * 典型调用链（`node main.js call ping`）：
 *   main(["call", "ping"]) → runCLI → parseCLIArguments → … → 退出码数字 → process.exitCode
 */
import { realpathSync } from "node:fs";
import { fileURLToPath } from "node:url";
import {
  runCLI,
  type CLIApplicationDependencies
} from "./application.js";

/**
 * `main()` 的依赖注入对象类型。
 *
 * 与 `CLIApplicationDependencies`（application.ts 定义）几乎相同，唯一差异是
 * `cliEntryPath` 从「必填」降级为「可选」：`main()` 自己能通过
 * `fileURLToPath(import.meta.url)` 算出本文件的绝对路径当默认值，所以调用方
 * （通常只有测试）可以不传。其余字段（output/env/logger/cwd 等）语义见
 * `CLIApplicationDependencies` 的字段注释。
 */
export type CLIMainDependencies = Omit<CLIApplicationDependencies, "cliEntryPath"> & {
  /** 【Host 侧】本文件（main.js）的绝对路径，用于生成 MCP 客户端启动命令；
   * 不传时取当前模块自身路径。它与目标 iOS 项目目录无关。 */
  readonly cliEntryPath?: string;
};

/**
 * 运行一次完整的 CLI 调用，返回退出码数字，但不主动终止 Node 进程。
 *
 * 为什么返回数字而不是 `process.exit(code)`：`exit()` 会立刻杀死进程，stdout 缓冲区
 * 里尚未写完的内容（如 `call` 的结果 JSON）可能丢失，MCP stdio 连接也会被粗暴掐断。
 * 返回数字由调用方决定：入口文件把它赋给 `process.exitCode` 让 Node 自然退出；测试
 * 直接断言数字，不产生任何进程副作用。
 *
 * @param argv 命令行参数（已去掉 node 与脚本路径两项）。
 *   默认 `process.argv.slice(2)`。
 *   示例：`node main.js call ping` → `["call", "ping"]`
 * @param dependencies 可注入的进程/IO 依赖（输出流、环境变量、logger 等）；测试传入
 *   fake 以替换真实 IO，生产环境传 `{}` 即可（各字段有默认实现）。
 * @returns CLI 退出码：0=成功，1=App 业务失败，2=配置/参数错误，3=网络/协议失败。
 *   示例：App 离线时执行 `call ping` → 返回 3。
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
 * 判断「当前模块」是否就是被 `node` 直接执行的进程入口文件。
 *
 * 同一个文件身兼两职：作为「程序」被 `node main.js` 执行，或作为「库」被测试等
 * 其他模块 import。只有前者才应触发 CLI 启动（见文件末尾的 if），所以需要本函数区分。
 *
 * 比较的是 realpath（真实路径）而非原始字符串：`npm link` 安装后，`process.argv[1]`
 * 是符号链接 `/usr/local/bin/iosdriver`，而 `import.meta.url` 是真实文件
 * `.../dist/adapters/cli/main.js`——两者指向同一文件但字符串不同，必须先
 * `realpathSync` 解开符号链接再比较，否则 `npm link` 安装的命令永远不会触发启动。
 *
 * @param metaURL 当前模块的 URL，调用时传 `import.meta.url`。
 * @param argv1 Node 认为的入口文件路径，默认 `process.argv[1]`。
 * @returns true=本文件是当前进程入口；false=被 import 或入口路径缺失。
 *   示例：`node main.js` 直接执行 → true；vitest import 本文件 → false。
 */
export function isMainModule(metaURL: string, argv1 = process.argv[1]): boolean {
  if (argv1 === undefined) return false;
  return realpathSync(argv1) === realpathSync(fileURLToPath(metaURL));
}

// 全文件唯一有进程副作用的位置：
// - 直接执行（node main.js …）时：把 main() 的返回码写入 process.exitCode，
//   让 Node 在 stdout/stderr 写完、MCP transport 收尾后以该码自然退出；
// - 被 import 时（测试等）：isMainModule 返回 false，这里什么都不做，
//   调用方只能拿到 main() 的返回值，进程状态不受影响。
if (isMainModule(import.meta.url)) {
  process.exitCode = await main();
}
