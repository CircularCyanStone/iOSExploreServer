#!/usr/bin/env node
// Minimal MCP stdio client.
//   node scripts/mcp-inspector.mjs                       -> runs a fixed smoke sequence
//   node scripts/mcp-inspector.mjs <tool> '<json>'       -> calls one tool with raw JSON args
//   node scripts/mcp-inspector.mjs <tool> '<json>' <tool2> '<json2>' ...
// Calls go through the Mac MCP server (dist/index.js) over stdio.
//
// 完整使用说明（前置条件、工具名映射、排障、边界）见：
//   docs/local-mcp-test.md
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

const calls = [];
if (process.argv.length > 2) {
  for (let i = 2; i < process.argv.length; i += 2) {
    const name = process.argv[i];
    const raw = process.argv[i + 1] ?? "{}";
    let args;
    try { args = JSON.parse(raw); }
    catch (e) { console.error(`bad JSON for ${name}: ${raw}`); process.exit(2); }
    calls.push({ name, arguments: args });
  }
} else {
  calls.push({ name: "health_check", arguments: {} });
  calls.push({ name: "ui_inspect", arguments: {} });
  calls.push({
    name: "call_action",
    arguments: { action: "ui.waitAny", data: { conditions: [{ id: "idle", mode: "idle" }], timeoutMs: 1000 } }
  });
  calls.push({
    name: "wait_and_inspect",
    arguments: { conditions: [{ id: "idle", mode: "idle" }], timeoutMs: 1000 }
  });
}

send("initialize", {
  protocolVersion: "2024-11-05",
  capabilities: {},
  clientInfo: { name: "mcp-inspector", version: "0.0.1" }
});

let t = 300;
send("tools/list", {});
for (const call of calls) {
  setTimeout(() => send("tools/call", call), (t += 300));
}

setTimeout(() => {
  console.log("\n=== done ===");
  server.kill("SIGTERM");
  process.exit(0);
}, t + 5000);
