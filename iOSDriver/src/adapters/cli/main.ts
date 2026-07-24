#!/usr/bin/env node

import { pathToFileURL } from "node:url";
import { CapabilityProbe } from "../../runtime/capabilityProbe.js";
import { DriverRuntime } from "../../runtime/driverRuntime.js";
import { HttpActionTransport } from "../../runtime/httpActionTransport.js";
import { WorkflowRunner } from "../../workflows/workflowRunner.js";
import { resolveCLIConfig, CLIConfigError, type CLIConfigOverrides } from "./config.js";
import { executeCLICommand, EXIT_CODES, type CallCommandOptions, type CLICommandContext, type CLICommandName } from "./commands.js";
import { processOutput, type CLIOutput } from "./output.js";
import { startMCPStdioServer } from "../mcp/server.js";

/** 解析 CLI 参数并执行固定命令；可注入 argv、输出和 SIGINT 行为供测试使用。 */
export async function main(
  argv: readonly string[] = process.argv.slice(2),
  dependencies: {
    readonly output?: CLIOutput;
    readonly env?: NodeJS.ProcessEnv;
    readonly nodeVersion?: string;
  } = {}
): Promise<number> {
  const output = dependencies.output ?? processOutput;
  const controller = new AbortController();
  const onSIGINT = () => controller.abort(new Error("SIGINT"));
  let handlesSIGINT = false;
  try {
    const parsed = parseArguments(argv);
    handlesSIGINT = parsed.command === "call";
    if (handlesSIGINT) process.once("SIGINT", onSIGINT);
    const config = await resolveCLIConfig(parsed.config, dependencies.env ?? process.env);
    const runtime = new DriverRuntime({
      transport: new HttpActionTransport(config.baseURL),
      configuredRequestTimeoutMs: config.requestTimeoutMs
    });
    const capabilityProbe = new CapabilityProbe(runtime);
    const workflowRunner = new WorkflowRunner({ runtime });
    const context: CLICommandContext = {
      config,
      output,
      runtime,
      capabilityProbe,
      workflowRunner,
      ...(dependencies.nodeVersion === undefined ? {} : { nodeVersion: dependencies.nodeVersion }),
      env: dependencies.env ?? process.env,
      signal: controller.signal,
      ...(parsed.human ? { human: true } : {})
    };
    if (parsed.command === "call") return await executeCLICommand("call", context, parsed.call);
    return await executeCLICommand(parsed.command, {
      ...context,
      startMCP: () => startMCPStdioServer({ runtime, capabilityProbe, workflowRunner })
    });
  } catch (error) {
    if (error instanceof CLIConfigError) {
      output.stderr(`${error.message}\n`);
      return EXIT_CODES.configError;
    }
    output.stderr(`${error instanceof Error ? error.message : String(error)}\n`);
    return EXIT_CODES.configError;
  } finally {
    if (handlesSIGINT) process.off("SIGINT", onSIGINT);
  }
}

/** 仅在作为可执行文件运行时退出；被测试 import 时不会启动网络或写流。 */
export function isMainModule(metaURL: string, argv1 = process.argv[1]): boolean {
  return argv1 !== undefined && pathToFileURL(argv1).href === metaURL;
}

if (isMainModule(import.meta.url)) {
  const exitCode = await main();
  process.exitCode = exitCode;
}

function parseArguments(argv: readonly string[]): {
  readonly command: CLICommandName;
  readonly config: CLIConfigOverrides;
  readonly call: CallCommandOptions;
  readonly human: boolean;
} {
  const command = argv[0] as CLICommandName | undefined;
  if (command !== "init" && command !== "doctor" && command !== "call" && command !== "mcp") {
    throw new CLIConfigError("用法: iosdriver init|doctor|call <action> [--data JSON|@file] [--output path]|mcp");
  }
  let baseURL: string | undefined;
  let requestTimeoutMs: number | undefined;
  let configPath: string | undefined;
  let data: string | undefined;
  let output: string | undefined;
  let human = false;
  let action = command === "call" ? argv[1] ?? "" : "";
  let index = command === "call" ? 2 : 1;
  while (index < argv.length) {
    const flag = argv[index]!;
    if (flag === "--base-url") baseURL = requiredValue(argv, ++index, flag);
    else if (flag === "--timeout") requestTimeoutMs = parseTimeout(requiredValue(argv, ++index, flag));
    else if (flag === "--config") configPath = requiredValue(argv, ++index, flag);
    else if (command === "call" && flag === "--data") data = requiredValue(argv, ++index, flag);
    else if (command === "call" && flag === "--output") output = requiredValue(argv, ++index, flag);
    else if (flag === "--human") human = true;
    else if (command === "call" && !flag.startsWith("-")) action = flag;
    else throw new CLIConfigError(`未知参数: ${flag}`);
    index += 1;
  }
  return {
    command,
    config: {
      ...(baseURL === undefined ? {} : { baseURL }),
      ...(requestTimeoutMs === undefined ? {} : { requestTimeoutMs }),
      ...(configPath === undefined ? {} : { configPath })
    },
    human,
    call: {
      action,
      ...(data === undefined ? {} : { data }),
      ...(output === undefined ? {} : { output })
    }
  };
}

function requiredValue(argv: readonly string[], index: number, flag: string): string {
  const value = argv[index];
  if (value === undefined || value.startsWith("-")) throw new CLIConfigError(`${flag} 需要参数`);
  return value;
}

function parseTimeout(raw: string): number {
  const value = Number(raw);
  if (!Number.isInteger(value) || value <= 0) throw new CLIConfigError("--timeout 必须是正整数");
  return value;
}
