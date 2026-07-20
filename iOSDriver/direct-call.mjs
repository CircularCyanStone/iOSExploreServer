import { loadConfig } from "./dist/config.js";
import { IOSExploreClient } from "./dist/iosExploreClient.js";
import { ToolRegistry } from "./dist/toolRegistry.js";

const config = loadConfig();
const client = new IOSExploreClient(config);
const fixedToolNames = new Set(["health_check", "refresh_tools", "call_action"]);
const registry = new ToolRegistry({ fixedToolNames, client });

console.error("=== Refreshing tool registry ===");
try {
  await registry.refresh();
  console.error("✅ Registry refreshed successfully");
  
  const tools = registry.tools();
  console.error(`Found ${tools.length} dynamic tools:`);
  tools.slice(0, 5).forEach(t => console.error(`  - ${t.name}: ${t.description.substring(0, 60)}...`));
} catch (err) {
  console.error("❌ Registry refresh failed:", err.message);
  process.exit(1);
}
