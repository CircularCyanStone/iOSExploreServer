#!/usr/bin/env node
// 端到端测试辅助：读取 mcp-inspector.mjs 的 stdout（含多个 JSON-RPC 响应块），
// 把每个 tools/call 的 envelope data 解析出来并按需摘要。
// 用法: node scripts/e2e-parse.mjs <raw-output-file> [--summary]
import fs from "node:fs";

const file = process.argv[2];
const summary = process.argv.includes("--summary");
const raw = fs.readFileSync(file, "utf8");

// 按 "=== <label> (id=N) ===" 分块
const parts = raw.split(/=== (.+?) \(id=(\d+)\) ===/);
// parts[0] 前导；之后每 3 个一组: label, id, body
const calls = [];
for (let i = 1; i < parts.length; i += 3) {
  const label = parts[i];
  const id = parts[i + 1];
  const body = parts[i + 2] || "";
  const jsonStart = body.indexOf("{");
  if (jsonStart < 0) { calls.push({ id, label, obj: null }); continue; }
  let objText = body.slice(jsonStart).trim();
  // 去掉结尾 "=== done ===" 之类
  const doneIdx = objText.indexOf("=== ");
  if (doneIdx >= 0) objText = objText.slice(0, doneIdx).trim();
  let rpc;
  try { rpc = JSON.parse(objText); } catch { calls.push({ id, label, obj: null, rawBody: objText.slice(0, 200) }); continue; }
  // tools/call 结果在 content[0].text 里是 envelope data 的 JSON 字符串
  if (rpc.content && Array.isArray(rpc.content)) {
    const textNode = rpc.content.find((c) => c.type === "text");
    let inner = null;
    if (textNode) { try { inner = JSON.parse(textNode.text); } catch { inner = textNode.text; } }
    calls.push({ id, label, isError: rpc.isError, obj: inner, hasImage: rpc.content.some((c) => c.type === "image") });
  } else {
    calls.push({ id, label, obj: rpc });
  }
}

for (const c of calls) {
  console.log(`\n===== id=${c.id} ${c.label} isError=${c.isError ?? "-"} image=${c.hasImage ? "yes" : ""}`);
  if (c.obj == null) { console.log("  <no parseable body>", c.rawBody ?? ""); continue; }
  if (typeof c.obj !== "object") { console.log("  ", String(c.obj).slice(0, 300)); continue; }
  if (!summary) { console.log(JSON.stringify(c.obj, null, 2)); continue; }
  // summary 模式
  const o = c.obj;
  if (o.code && o.code !== "ok") console.log("  BIZ-CODE:", o.code, "|", o.message);
  if (o.viewSnapshotID) console.log("  snapshotID:", o.viewSnapshotID);
  const targets = o.targets || o.nodes;
  if (Array.isArray(targets)) {
    console.log("  count:", targets.length);
    for (const t of targets) {
      const txt = t.title ?? t.text ?? t.label ?? t.accessibilityLabel ?? "";
      console.log(`   ${t.path} | ${t.type} | id=${t.accessibilityIdentifier ?? ""} | full=${t.isFull ?? ""} | "${String(txt).slice(0, 30)}" | acts=${JSON.stringify(t.availableActions ?? "")} | ip=${t.indexPath ? JSON.stringify(t.indexPath) : ""}`);
    }
  }
  if (o.controllers || o.tree) {
    console.log("  controllerTree:", JSON.stringify(o.controllers ?? o.tree).slice(0, 600));
  }
  // 其余顶层字段
  const skip = new Set(["targets", "nodes", "controllers", "tree", "viewSnapshotID"]);
  const rest = {};
  for (const k of Object.keys(o)) if (!skip.has(k)) rest[k] = o[k];
  if (Object.keys(rest).length) console.log("  fields:", JSON.stringify(rest).slice(0, 500));
}
