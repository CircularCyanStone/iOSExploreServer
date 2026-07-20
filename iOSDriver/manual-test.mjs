import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";

const server = new Server(
  { name: "test-server", version: "0.1.0" },
  { capabilities: { tools: {} } }
);

console.error("Server created, attempting connection...");

try {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error("✅ Server connected successfully via stdio");
} catch (err) {
  console.error("❌ Connection failed:", err.message);
  process.exit(1);
}
