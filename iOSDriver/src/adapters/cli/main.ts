#!/usr/bin/env node

import { homedir } from "node:os";
import { resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { CapabilityProbe } from "../../runtime/capabilityProbe.js";
import { DriverRuntime } from "../../runtime/driverRuntime.js";
import { HttpActionTransport } from "../../runtime/httpActionTransport.js";
import { WorkflowRunner } from "../../workflows/workflowRunner.js";
import { configPathFor, resolveCLIConfig, CLIConfigError, type CLIConfigOverrides } from "./config.js";
import { executeCLICommand, EXIT_CODES, type CallCommandOptions, type CLICommandContext, type CLICommandName } from "./commands.js";
import { processOutput, type CLIOutput } from "./output.js";
import { startMCPStdioServer } from "../mcp/server.js";
import { defaultHostLogger, type HostLogger } from "../../runtime/hostLogger.js";
import {
  setupMCPClient,
  type MCPClientName,
  type MCPClientSetupInput,
  type MCPClientSetupResult,
  type MCPRegistrationScope
} from "../../registration/mcpClientSetup.js";

type OperationalArguments = {
  readonly kind: "operational";
  readonly command: CLICommandName;
  readonly config: CLIConfigOverrides;
  readonly call: CallCommandOptions;
  readonly human: boolean;
};

type MCPSetupArguments = {
  readonly kind: "mcpSetup";
  readonly client: MCPClientName;
  readonly scope?: MCPRegistrationScope;
  readonly dryRun: boolean;
  readonly force: boolean;
  readonly configPath?: string;
  readonly projectDir?: string;
};

type ParsedArguments = OperationalArguments | MCPSetupArguments;

/** 解析 CLI 参数并执行固定命令；可注入 argv、输出和 SIGINT 行为供测试使用。 */
export async function main(
  argv: readonly string[] = process.argv.slice(2),
  dependencies: {
    readonly output?: CLIOutput;
    readonly env?: NodeJS.ProcessEnv;
    readonly nodeVersion?: string;
    readonly logger?: HostLogger;
    readonly cwd?: string;
    readonly homeDir?: string;
    readonly nodePath?: string;
    readonly cliEntryPath?: string;
    readonly setupMCPClient?: (input: MCPClientSetupInput) => Promise<MCPClientSetupResult>;
  } = {}
): Promise<number> {
  const output = dependencies.output ?? processOutput;
  const logger = dependencies.logger ?? defaultHostLogger;
  const env = dependencies.env ?? process.env;
  const cwd = dependencies.cwd ?? process.cwd();
  const homeDir = dependencies.homeDir ?? homedir();
  const controller = new AbortController();
  const onSIGINT = () => controller.abort(new Error("SIGINT"));
  let handlesSIGINT = false;
  try {
    const parsed = parseArguments(argv);
    if (parsed.kind === "mcpSetup") {
      logger.emit("info", "cli.command.start", { command: "mcp.setup", client: parsed.client });
      const rawConfigPath = parsed.configPath ?? configPathFor(env, homeDir);
      const configPath = resolve(cwd, rawConfigPath);
      const projectDir = resolve(cwd, parsed.projectDir ?? ".");
      const setup = dependencies.setupMCPClient ?? setupMCPClient;
      const result = await setup({
        client: parsed.client,
        ...(parsed.scope === undefined ? {} : { scope: parsed.scope }),
        dryRun: parsed.dryRun,
        force: parsed.force,
        cwd: projectDir,
        homeDir,
        env,
        launch: {
          command: dependencies.nodePath ?? process.execPath,
          args: [
            dependencies.cliEntryPath ?? fileURLToPath(import.meta.url),
            "mcp",
            "--config",
            configPath
          ]
        }
      });
      output.stdout(`${JSON.stringify(result, null, 2)}\n`);
      logger.emit("info", "cli.command.complete", {
        command: "mcp.setup",
        client: parsed.client,
        status: result.status,
        exitCode: EXIT_CODES.success
      });
      return EXIT_CODES.success;
    }
    handlesSIGINT = parsed.command === "call";
    if (handlesSIGINT) process.once("SIGINT", onSIGINT);
    const config = await resolveCLIConfig(parsed.config, env);
    const runtime = new DriverRuntime({
      transport: new HttpActionTransport(config.baseURL, {
        ...(config.authToken === undefined ? {} : { authToken: config.authToken })
      }),
      configuredRequestTimeoutMs: config.requestTimeoutMs,
      logger
    });
    const capabilityProbe = new CapabilityProbe(runtime, undefined, logger);
    const workflowRunner = new WorkflowRunner({ runtime, logger });
    const context: CLICommandContext = {
      config,
      output,
      runtime,
      capabilityProbe,
      workflowRunner,
      ...(dependencies.nodeVersion === undefined ? {} : { nodeVersion: dependencies.nodeVersion }),
      env,
      signal: controller.signal,
      logger,
      ...(parsed.human ? { human: true } : {})
    };
    if (parsed.command === "call") return await executeCLICommand("call", context, parsed.call);
    return await executeCLICommand(parsed.command, {
      ...context,
      startMCP: () => startMCPStdioServer({ runtime, capabilityProbe, workflowRunner, logger })
    });
  } catch (error) {
    logger.emit("error", "cli.command.error", {
      command: knownCommand(argv),
      exitCode: EXIT_CODES.configError,
      errorType: error instanceof Error ? error.name : typeof error,
      phase: "startup"
    });
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

function parseArguments(argv: readonly string[]): ParsedArguments {
  const command = argv[0] as CLICommandName | undefined;
  if (command !== "init" && command !== "doctor" && command !== "call" && command !== "mcp") {
    throw new CLIConfigError(usage());
  }
  if (command === "mcp" && argv[1] === "setup") return parseMCPSetupArguments(argv);
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
    kind: "operational",
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

function parseMCPSetupArguments(argv: readonly string[]): MCPSetupArguments {
  const client = argv[2];
  if (client !== "codex" && client !== "claude" && client !== "trae") {
    throw new CLIConfigError("用法: iosdriver mcp setup <codex|claude|trae> [--scope user|project] [--project-dir path] [--dry-run] [--force] [--config path]");
  }
  let scope: MCPRegistrationScope | undefined;
  let configPath: string | undefined;
  let projectDir: string | undefined;
  let dryRun = false;
  let force = false;
  let index = 3;
  while (index < argv.length) {
    const flag = argv[index]!;
    if (flag === "--scope") {
      const value = requiredValue(argv, ++index, flag);
      if (value !== "user" && value !== "project") throw new CLIConfigError("--scope 必须是 user 或 project");
      scope = value;
    } else if (flag === "--config") {
      configPath = requiredValue(argv, ++index, flag);
    } else if (flag === "--project-dir") {
      projectDir = requiredValue(argv, ++index, flag);
    } else if (flag === "--dry-run") {
      dryRun = true;
    } else if (flag === "--force") {
      force = true;
    } else {
      throw new CLIConfigError(`未知参数: ${flag}`);
    }
    index += 1;
  }
  return {
    kind: "mcpSetup",
    client,
    ...(scope === undefined ? {} : { scope }),
    dryRun,
    force,
    ...(configPath === undefined ? {} : { configPath }),
    ...(projectDir === undefined ? {} : { projectDir })
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

function knownCommand(argv: readonly string[]): CLICommandName | "mcp.setup" | "unknown" {
  if (argv[0] === "mcp" && argv[1] === "setup") return "mcp.setup";
  const value = argv[0];
  return value === "init" || value === "doctor" || value === "call" || value === "mcp" ? value : "unknown";
}

function usage(): string {
  return "用法: iosdriver init|doctor|call <action> [--data JSON|@file] [--output path]|mcp|mcp setup <codex|claude|trae>";
}
