#!/usr/bin/env node

import { pathToFileURL } from "node:url";
import { loadConfig } from "./config.js";
import { CapabilityProbe } from "./runtime/capabilityProbe.js";
import { DriverRuntime } from "./runtime/driverRuntime.js";
import { HttpActionTransport } from "./runtime/httpActionTransport.js";
import { startStdioServer } from "./server.js";
import { WorkflowRunner } from "./workflows/workflowRunner.js";

/** 兼容入口：没有参数时保持原有 MCP stdio 行为。 */
export async function startLegacyMCP(): Promise<void> {
  const config = loadConfig();
  const transport = new HttpActionTransport(config.baseURL);
  const runtime = new DriverRuntime({
    transport,
    configuredRequestTimeoutMs: config.requestTimeoutMs
  });
  const capabilityProbe = new CapabilityProbe(runtime);
  const workflowRunner = new WorkflowRunner({ runtime });
  await startStdioServer({ runtime, capabilityProbe, workflowRunner });
}

if (process.argv[1] !== undefined && pathToFileURL(process.argv[1]).href === import.meta.url && process.argv.length <= 2) {
  await startLegacyMCP();
} else if (process.argv[1] !== undefined && pathToFileURL(process.argv[1]).href === import.meta.url) {
  const { main } = await import("./adapters/cli/main.js");
  process.exitCode = await main(process.argv.slice(2));
}
