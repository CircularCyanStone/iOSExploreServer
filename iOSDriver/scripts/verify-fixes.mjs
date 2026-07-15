import { spawn } from "node:child_process";

const server = spawn("node", ["dist/index.js"], {
  cwd: process.cwd(),
  stdio: ["pipe", "pipe", "inherit"]
});

let buffer = "";
let nextId = 1;
const pending = new Map();

const send = (method, params) => {
  const id = nextId++;
  const msg = { jsonrpc: "2.0", id, method, params };
  pending.set(id, method);
  server.stdin.write(JSON.stringify(msg) + "\n");
  return id;
};

server.stdout.on("data", (chunk) => {
  buffer += chunk.toString();
  let idx;
  while ((idx = buffer.indexOf("\n")) >= 0) {
    const line = buffer.slice(0, idx).trim();
    buffer = buffer.slice(idx + 1);
    if (!line) continue;
    let msg;
    try { msg = JSON.parse(line); } catch { continue; }
    if (msg.id !== undefined && pending.has(msg.id)) {
      const method = pending.get(msg.id);
      pending.delete(msg.id);
      console.log(`\n=== ${method} (id=${msg.id}) ===`);
      console.log(JSON.stringify(msg.result ?? msg.error, null, 2));
      if (method === "initialize" && msg.result) {
        server.stdin.write(JSON.stringify({ jsonrpc: "2.0", method: "notifications/initialized" }) + "\n");
      }
    }
  }
});

send("initialize", {
  protocolVersion: "2024-11-05",
  capabilities: {},
  clientInfo: { name: "verify-stripping", version: "0.0.1" }
});

setTimeout(() => send("tools/list", {}), 300);
setTimeout(() => send("tools/call", {
  name: "wait_and_inspect",
  arguments: {
    conditions: [{ id: "idle", mode: "idle" }],
    timeoutMs: 1000,
    foo: "bar",
    extra: 42
  }
}), 600);
setTimeout(() => {
  console.log("\n=== done ===");
  server.kill("SIGTERM");
  process.exit(0);
}, 3000);
