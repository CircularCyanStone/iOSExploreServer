#!/usr/bin/env node

import { loadConfig } from "./config.js";
import { IOSExploreClient } from "./iosExploreClient.js";
import { startStdioServer } from "./server.js";
import { createStaticTools, STATIC_TOOL_NAMES } from "./staticTools.js";
import { ToolRegistry } from "./toolRegistry.js";

const config = loadConfig();
const client = new IOSExploreClient(config);
const fixedToolNames = new Set<string>(STATIC_TOOL_NAMES);
const registry = new ToolRegistry({ fixedToolNames, client });
const staticTools = createStaticTools({ client, registry });

await startStdioServer({ staticTools, registry, client });
