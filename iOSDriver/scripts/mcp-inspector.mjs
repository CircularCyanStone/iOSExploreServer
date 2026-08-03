#!/usr/bin/env node
// 轻量 MCP stdio smoke client：它刻意通过构建后的 CLI 入口启动 server，以同时验证
// CLI 分流、stdio framing、工具目录和 runtime 调用，而不是直接 import MCP handlers。
//   node scripts/mcp-inspector.mjs                       -> 执行固定 smoke 序列
//   node scripts/mcp-inspector.mjs <tool> '<json>'       -> 用原始 JSON 参数调用一个工具
//   node scripts/mcp-inspector.mjs <tool> '<json>' <tool2> '<json2>' ...
// 所有调用都通过 iosdriver CLI 的 MCP stdio 入口。
//
// 完整使用说明（前置条件、工具名映射、排障、边界）见：
//   docs/local-mcp-test.md
import { spawn } from "node:child_process";

// 以子进程方式启动 iosdriver CLI 的 mcp 命令：stdin/stdout 接协议帧（pipe），
// stderr 直接继承到终端（inherit）——这样 server 的日志可见且不会混入协议流。
const server = spawn("node", ["dist/adapters/cli/main.js", "mcp"], {
  cwd: process.cwd(),
  stdio: ["pipe", "pipe", "inherit"]
});

let buffer = "";
let nextId = 1;
// 只追踪由本脚本发出的 request（按 id）；server 主动 notification 或未知响应不混入输出。
const pending = new Map();

/**
 * 发送一条 JSON-RPC request（每帧一行 JSON + 换行，写进 server 的 stdin）。
 *
 * @param method 方法名（"initialize"/"tools/list"/"tools/call"）。
 * @param params 方法参数对象。
 * @returns 本次 request 的 id（用于匹配响应）。
 */
const send = (method, params) => {
  const id = nextId++;
  const msg = { jsonrpc: "2.0", id, method, params };
  pending.set(id, method);
  server.stdin.write(JSON.stringify(msg) + "\n");
  return id;
};

server.stdout.on("data", (chunk) => {
  // stdio chunk 不保证按 JSON-RPC 行切分，因此先累积到换行，再逐帧 JSON.parse。
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
  // 自定义模式按 <tool> <json> 成对读取，便于一次进程内串行 smoke 多个工具。
  for (let i = 2; i < process.argv.length; i += 2) {
    const name = process.argv[i];
    const raw = process.argv[i + 1] ?? "{}";
    let args;
    try { args = JSON.parse(raw); }
    catch (e) { console.error(`bad JSON for ${name}: ${raw}`); process.exit(2); }
    calls.push({ name, arguments: args });
  }
} else {
  // 默认序列覆盖能力探测、直接 action、动态 action 和 host workflow 四条路由。
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

// 错峰发送：initialize 之后 300ms 发 tools/list，再每隔 300ms 发一个 tools/call，
// 避免在握手完成前同时灌入全部请求（server 按顺序处理帧）。
let t = 300;
send("tools/list", {});
for (const call of calls) {
  setTimeout(() => send("tools/call", call), (t += 300));
}

// 全部调用预期完成后收尾：打印结束标记、SIGTERM 关闭 server、退出。
setTimeout(() => {
  console.log("\n=== done ===");
  server.kill("SIGTERM");
  process.exit(0);
}, t + 5000);
