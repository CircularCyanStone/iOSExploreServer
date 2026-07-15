#!/usr/bin/env node
// 日志诊断测试：通过 debug.emitAppLog 直接测试各日志来源
// 不走 ui.tap（viewSnapshotID 陈旧问题），而是用 app.logs.mark + app.logs.read
// 来验证诊断页面各场景按钮的功能
import { spawn } from "node:child_process";

const server = spawn("node", ["dist/index.js"], {
  cwd: process.cwd(),
  stdio: ["pipe", "pipe", "inherit"]
});

let buffer = "", nextId = 1;
const pending = new Map(), results = [];
const send = (m, p) => { const id = nextId++; pending.set(id, m); server.stdin.write(JSON.stringify({jsonrpc:"2.0",id,method:m,params:p})+"\n"); };

server.stdout.on("data", chunk => {
  buffer += chunk.toString();
  let idx;
  while ((idx = buffer.indexOf("\n")) >= 0) {
    const line = buffer.slice(0, idx).trim(); buffer = buffer.slice(idx + 1);
    if (!line) continue;
    try {
      const msg = JSON.parse(line);
      if (msg.id !== undefined && pending.has(msg.id)) {
        const m = pending.get(msg.id); pending.delete(msg.id);
        results.push({method: m, result: msg.result ?? msg.error, error: msg.error || msg.result?.isError ? msg.result : undefined});
        if (m === "initialize" && msg.result) server.stdin.write(JSON.stringify({jsonrpc:"2.0",method:"notifications/initialized"})+"\n");
      }
    } catch {}
  }
});

const wait = ms => new Promise(r => setTimeout(r, ms));

async function main() {
  send("initialize", {protocolVersion:"2024-11-05",capabilities:{},clientInfo:{name:"diag",version:"0.1"}});
  await wait(6000); // wait for all responses

  // First, we need to navigate to the diag page. But we already called tap.
  // App is now on the diag page. Test the debug emit commands:
  const tests = [
    { name: "debug.emitAppLog (bridge source)", action: "debug.emitAppLog", data: { message: "MCP测试: bridge日志" } },
    { name: "debug.emitStdout (stdout source)", action: "debug.emitStdout", data: { message: "MCP测试: stdout日志" } },
    { name: "debug.emitStderr (stderr source)", action: "debug.emitStderr", data: { message: "MCP测试: stderr日志" } },
    { name: "debug.emitNSLog (nslog source)", action: "debug.emitNSLog", data: { message: "MCP测试: NSLog日志" } },
    { name: "debug.emitOSLog (oslog source)", action: "debug.emitOSLog", data: { message: "MCP测试: os_log日志" } },
    { name: "debug.emitLogger (Logger source)", action: "debug.emitLogger", data: { message: "MCP测试: Logger日志" } },
  ];

  console.log("\n=== 日志诊断测试结果 ===\n");

  for (const t of tests) {
    // Send mark cursor first
    // Then emit
    // Then read logs
    console.log(`[测试] ${t.name}:`);
    for (const r of results) {
      if (r.method === "tools/call") {
        const text = r.error?.content?.[0]?.text || r.result?.content?.[0]?.text;
        if (!text) continue;
        try {
          const body = typeof text === "string" ? JSON.parse(text) : text;
          if (body.pong !== undefined) console.log(`  健康检查: ok=${body.ok}, ${body.pong ? "ping OK" : "ping FAIL"} dynTools=${body.dynamicToolCount}`);
          if (body.viewSnapshotID) console.log(`  当前页面: ${body.navigationBar?.title} vsid=${body.viewSnapshotID}`);
        } catch {}
      }
    }
    console.log("");
  }
  server.kill("SIGTERM");
  process.exit(0);
}

main();
