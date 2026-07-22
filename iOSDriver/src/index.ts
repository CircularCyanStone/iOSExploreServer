#!/usr/bin/env node

import { loadConfig } from "./config.js";
import { IOSExploreClient } from "./iosExploreClient.js";
import { startStdioServer } from "./server.js";
import { createStaticTools } from "./staticTools.js";

const config = loadConfig();
const client = new IOSExploreClient(config);
const staticTools = createStaticTools({ client });

await startStdioServer({ staticTools });
