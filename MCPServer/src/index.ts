import { loadConfig } from "./config.js";
import { IOSExploreClient } from "./iosExploreClient.js";
import { startStdioServer } from "./server.js";
import { createStaticTools } from "./staticTools.js";
import { ToolRegistry } from "./toolRegistry.js";

const config = loadConfig();
const client = new IOSExploreClient(config);
const fixedToolNames = new Set(["health_check", "refresh_tools", "call_action", "observe", "wait_and_observe"]);
const registry = new ToolRegistry({ fixedToolNames, client });
const staticTools = createStaticTools({ client, registry });

await registry.refresh();
await startStdioServer({ staticTools, registry, client });
