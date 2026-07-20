import { loadConfig } from "./dist/config.js";
import { IOSExploreClient } from "./dist/iosExploreClient.js";

console.error("=== iOSDriver startup test ===");
const config = loadConfig();
console.error("Config:", config);

const client = new IOSExploreClient(config);
console.error("Client created");

try {
  const result = await client.call("ping", {});
  console.error("Ping result:", result);
} catch (err) {
  console.error("Ping error:", err.message);
}
