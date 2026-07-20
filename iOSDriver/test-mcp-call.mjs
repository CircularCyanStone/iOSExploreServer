import { loadConfig } from "./dist/config.js";
import { IOSExploreClient } from "./dist/iosExploreClient.js";
import { createStaticTools } from "./dist/staticTools.js";
import { ToolRegistry } from "./dist/toolRegistry.js";

const config = loadConfig();
const client = new IOSExploreClient(config);
const fixedToolNames = new Set(["health_check", "refresh_tools", "call_action"]);
const registry = new ToolRegistry({ fixedToolNames, client });
const staticTools = createStaticTools({ client, registry });

console.error("=== Testing health_check tool ===");
await registry.refresh();

const result = await staticTools.health_check.handler({});
console.log(JSON.stringify(result, null, 2));
