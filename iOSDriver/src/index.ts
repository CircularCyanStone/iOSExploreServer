#!/usr/bin/env node

import { loadConfig } from "./config.js";
import { CapabilityProbe } from "./runtime/capabilityProbe.js";
import { DriverRuntime } from "./runtime/driverRuntime.js";
import { HttpActionTransport } from "./runtime/httpActionTransport.js";
import { startStdioServer } from "./server.js";
import { WorkflowRunner } from "./workflows/workflowRunner.js";

const config = loadConfig();
const transport = new HttpActionTransport(config.baseURL);
const runtime = new DriverRuntime({
  transport,
  configuredRequestTimeoutMs: config.requestTimeoutMs
});
const capabilityProbe = new CapabilityProbe(runtime);
const workflowRunner = new WorkflowRunner({ runtime });

await startStdioServer({ runtime, capabilityProbe, workflowRunner });
