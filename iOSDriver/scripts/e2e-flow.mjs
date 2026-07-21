#!/usr/bin/env node
// Robust MCP E2E runner with proper JSON-RPC framing.
import { spawn } from "node:child_process";
import { writeFileSync } from "fs";

const server = spawn("node", ["dist/index.js"], {
  cwd: process.cwd(),
  stdio: ["pipe", "pipe", "inherit"]
});

let buffer = "";
let nextId = 1;
const pending = new Map();
const results = [];   // collected in send order

const send = (method, params) => {
  const id = nextId++;
  const msg = { jsonrpc: "2.0", id, method, params };
  pending.set(id, { method, ts: Date.now() });
  server.stdin.write(JSON.stringify(msg) + "\n");
  return id;
};

// Robust: handle multi-line JSON. Parse first complete {...} block from buffer.
function tryConsumeBuffer() {
  // Each JSON-RPC message is one or more lines. We need to find \n-delimited units,
  // but the message itself spans multiple lines. Strategy: accumulate buffer;
  // repeatedly try to parse balanced {...} from the start. If parse fails or is
  // incomplete, wait for more data.
  while (buffer.length > 0) {
    let depth = 0, inStr = false, esc = false, endIdx = -1;
    for (let i = 0; i < buffer.length; i++) {
      const c = buffer[i];
      if (esc) { esc = false; continue; }
      if (c === "\\" && inStr) { esc = true; continue; }
      if (c === "\"") inStr = !inStr;
      else if (!inStr) {
        if (c === "{") depth++;
        else if (c === "}") {
          depth--;
          if (depth === 0) { endIdx = i + 1; break; }
        }
      }
    }
    if (endIdx < 0) break;  // need more data
    let msg;
    try { msg = JSON.parse(buffer.slice(0, endIdx)); }
    catch { buffer = buffer.slice(endIdx).replace(/^\s+/, ""); continue; }

    if (msg.id !== undefined && pending.has(msg.id)) {
      const meta = pending.get(msg.id);
      pending.delete(msg.id);
      // For tools/call: isError is a field on result.content's sibling (i.e. result.isError)
      const isError = msg.error !== undefined || msg.result?.isError === true;
      results.push({ id: msg.id, method: meta.method, result: msg.result ?? msg.error, isError });
      if (meta.method === "initialize" && msg.result) {
        server.stdin.write(JSON.stringify({ jsonrpc: "2.0", method: "notifications/initialized" }) + "\n");
      }
    }
    buffer = buffer.slice(endIdx).replace(/^\s+/, "");
  }
}

server.stdout.on("data", (chunk) => {
  buffer += chunk.toString();
  tryConsumeBuffer();
});

server.on("close", () => { /* ok */ });

async function callTool(name, args) {
  return send("tools/call", { name, arguments: args });
}

async function waitForAll(count, timeoutMs = 30000) {
  const start = Date.now();
  while (pending.size > 0 && Date.now() - start < timeoutMs) {
    await new Promise(r => setTimeout(r, 100));
  }
}

function extractBody(raw) {
  if (!raw) return null;
  if (raw.content?.[0]?.type === "image") {
    return { __image: true, length: raw.content[0].data?.length, mimeType: raw.content[0].mimeType };
  }
  const text = raw.content?.[0]?.text;
  if (!text) return null;
  try { return JSON.parse(text); } catch { return { __raw: text }; }
}

// =====================================================
// THE TEST SEQUENCE
// =====================================================

// 0. init
send("initialize", { protocolVersion: "2024-11-05", capabilities: {}, clientInfo: { name: "e2e-flow", version: "0.1" } });
await new Promise(r => setTimeout(r, 100));
send("tools/list", {});
await new Promise(r => setTimeout(r, 100));

// 1. health_check
callTool("health_check", {});
// 2. refresh_tools
callTool("refresh_tools", {});
// 3. call_action help
callTool("call_action", { action: "help" });
// 4. inspect to find current state and snapshot identifier
const snapId1 = await callTool("ui_inspect", {});
await waitForAll(4);
await new Promise(r => setTimeout(r, 200));

// Get the snapshot ID from snapId1
const inspect1 = extractBody(results.find(r => r.id === snapId1).result);
const sid1 = inspect1?.viewSnapshotID;
console.log("Initial snapshot:", sid1, "screen:", inspect1?.screen);

// Find menu cells: paths root/5/0 (alert test), root/5/1, root/5/2, root/5/3
// Alert Test is item 0 in menuItems, so the corresponding cell is at root/5/0 (or similar)
// Let's look for cells with cells having disclosureIndicator (chevron) - cells are root/5/0 .. root/5/3
// But cell root/5/0 is just content + chevron imageView
// We need to tap the cell itself, which is root/5/0 (UITableViewCell)

// 5. Tap "弹窗测试" cell — first menu item. UITableViewCell should have availableActions=[ui.tap]
// But cells aren't "tappable" in the collector's view — they use didSelectRowAt, not UIButton.touchUpInside.
// Let's check if ui.tap supports UITableViewCell or if we have to use ui.scrollView/tap different mechanism.

// Try tapping the cell path root/5/0 with the snapshot ID
const tapCell1 = await callTool("ui_tap", { path: "root/5/0", viewSnapshotID: sid1 });
await waitForAll(1);
await new Promise(r => setTimeout(r, 800));

// 6. Inspect again after navigation
const snapId2 = await callTool("ui_inspect", {});
await waitForAll(1);
await new Promise(r => setTimeout(r, 200));
const inspect2 = extractBody(results.find(r => r.id === snapId2).result);
const sid2 = inspect2?.viewSnapshotID;
console.log("After tap on root/5/0: screen =", inspect2?.screen);
console.log("Available actions on AlertTestViewController targets:");
const identifierTargets2 = (inspect2?.targets || []).filter(t => t.accessibilityIdentifier);
for (const t of identifierTargets2) {
  console.log("  ", t.path, "|", t.accessibilityIdentifier, "|", t.type, "|", (t.availableActions || []).join(","));
}

// 7. Tap alert.trigger.simple (if present)
let alertButtonTap;
let sidForAlertTap = sid2;
if (identifierTargets2.some(t => t.accessibilityIdentifier === "alert.trigger.simple")) {
  alertButtonTap = await callTool("ui_tap", { accessibilityIdentifier: "alert.trigger.simple", viewSnapshotID: sid2 });
  await waitForAll(1);
  await new Promise(r => setTimeout(r, 1000));
  // Inspect during alert
  const snapId3 = await callTool("ui_inspect", {});
  await waitForAll(1);
  await new Promise(r => setTimeout(r, 200));
  const inspect3 = extractBody(results.find(r => r.id === snapId3).result);
  console.log("\nDuring alert: available=", inspect3?.alert?.available);
  console.log("alert buttons:", JSON.stringify(inspect3?.alert?.buttons?.[0]));
  console.log("alert textFields:", JSON.stringify(inspect3?.alert?.textFields?.[0]));
  const sid3 = inspect3?.viewSnapshotID;

  // 8. Tap on close button (single button default)
  // ui_alert_respond with no args uses default behavior: dismiss if single button
  const alertClose = await callTool("ui_alert_respond", {});
  await waitForAll(1);
  await new Promise(r => setTimeout(r, 1000));
  // Re-inspect to verify alert is gone
  const snapId4 = await callTool("ui_inspect", {});
  await waitForAll(1);
  const inspect4 = extractBody(results.find(r => r.id === snapId4).result);
  console.log("After alert.respond: alert.available =", inspect4?.alert?.available);
}

// 9. Now test loginInput alert workflow (the more complex one with textFields)
// Need to also test ui.input on the alert textFields
const loginButtonTargets = (inspect2?.targets || []).filter(t => t.accessibilityIdentifier === "alert.trigger.loginInput");
if (loginButtonTargets.length > 0) {
  const tapLogin = await callTool("ui_tap", { accessibilityIdentifier: "alert.trigger.loginInput", viewSnapshotID: sid2 });
  await waitForAll(1);
  await new Promise(r => setTimeout(r, 1000));
  // Inspect during alert
  const snapLoginAlert = await callTool("ui_inspect", {});
  await waitForAll(1);
  const loginAlertInspect = extractBody(results.find(r => r.id === snapLoginAlert).result);
  console.log("\nLogin alert: available=", loginAlertInspect?.alert?.available);
  console.log("Login alert buttons:", JSON.stringify(loginAlertInspect?.alert?.buttons));
  console.log("Login alert textFields:", JSON.stringify(loginAlertInspect?.alert?.textFields));
  const loginSid = loginAlertInspect?.viewSnapshotID;

  // 10. Use ui.input to write into the alert textFields (N3 fix path)
  if (loginAlertInspect?.alert?.textFields?.length > 0) {
    const usernameTf = loginAlertInspect.alert.textFields[0];
    const ui_input_test = await callTool("ui_input", {
      viewSnapshotID: loginSid,
      fields: [
        {
          path: usernameTf.path,
          text: "E2EAgentName42"
        }
      ]
    });
    await waitForAll(1);
    await new Promise(r => setTimeout(r, 500));
    // Re-inspect to verify text written
    const afterInputSid = await callTool("ui_inspect", {});
    await waitForAll(1);
    const afterInputInspect = extractBody(results.find(r => r.id === afterInputSid).result);
    const afterInputTfs = afterInputInspect?.targets?.filter(t => t.type?.includes("Field")) || [];
    console.log("After ui.input: alert textFields:", JSON.stringify(afterInputInspect?.alert?.textFields?.[0]));
    // Find the textfield text directly
    for (const t of (afterInputInspect?.targets || [])) {
      if (t.type === "_UIAlertControllerTextField" || (t.accessibilityIdentifier && t.text !== null && t.text !== undefined)) {
        if (t.text === "E2EAgentName42") {
          console.log("✅ TextField text readback via inspect:", t.path, "text=", t.text);
        }
      }
    }

    // 11. ui.alert.respond to close login alert — must specify button (multiple buttons)
    // Login alert has OK and Cancel — must specify
    const alertResp = await callTool("ui_alert_respond", { buttonIndex: 1 });
    await waitForAll(1);
    await new Promise(r => setTimeout(r, 1000));
    console.log("alert.respond result:", JSON.stringify(extractBody(results.find(r => r.id === alertResp)?.result)));
  }
}

// 12. Error scenarios
const errTests = [
  ["err: ui_tap empty", "ui_tap", {}],
  ["err: ui_tap stale snap", "ui_tap", { path: "root/0", viewSnapshotID: "snap-fake-stale" }],
  ["err: unknown tool name", "ui_unknown_xyz", {}],
  ["err: call_action missing", "call_action", {}],
  ["err: call_action unknown", "call_action", { action: "this.does.not.exist" }],
  ["err: ui_inspect garbage", "ui_inspect", { nonexistentField: "x" }],
  ["err: ui_alert_respond no alert", "ui_alert_respond", {}],
];
for (const [name, tool, args] of errTests) {
  await callTool(tool, args);
  await waitForAll(1);
}

// 13. Screenshot
await callTool("ui_screenshot", {});
await waitForAll(1);

// 14. Logs test
await callTool("app_logs_mark", {});
await waitForAll(1);
await callTool("app_logs_read", { sources: ["explore"], limit: 3 });
await waitForAll(1);
await callTool("app_logs_read", { limit: 2, sources: ["stdout"] });
await waitForAll(1);

// 15. wait idle / waitAny / wait_and_inspect
await callTool("ui_wait", { mode: "idle", timeoutMs: 800 });
await waitForAll(1);
await callTool("ui_waitAny", { conditions: [{ id: "idle", mode: "idle" }], timeoutMs: 800 });
await waitForAll(1);
await callTool("wait_and_inspect", { conditions: [{ id: "idle", mode: "idle" }], timeoutMs: 800 });
await waitForAll(1);

// 16. ui_topViewHierarchy variants
await callTool("ui_topViewHierarchy", { detailLevel: "basic" });
await waitForAll(1);
await callTool("ui_topViewHierarchy", { detailLevel: "full", includeHidden: true });
await waitForAll(1);

// Wait for all to complete
await waitForAll(0);
await new Promise(r => setTimeout(r, 1000));
server.kill("SIGTERM");
await new Promise(r => server.on("close", r));

// =====================================================
// ANALYSIS
// =====================================================

// Map results to test names — easier: just analyze each in order
console.log("\n\n========================================");
console.log("     E2E FLOW ANALYSIS REPORT");
console.log("========================================\n");

// First, exclude init/list
const toolCalls = results.filter(r => r.method === "tools/call");

let passCount = 0, failCount = 0, warnCount = 0;
const findings = [];

function check(name, cond, detail) {
  if (cond) { passCount++; console.log(`✅ [${name}] ${detail}`); }
  else { failCount++; console.log(`❌ [${name}] ${detail}`); findings.push({ name, severity: "FAIL", detail }); }
}
function warn(name, detail) {
  warnCount++; console.log(`⚠️  [${name}] ${detail}`); findings.push({ name, severity: "WARN", detail });
}

// Walk through toolCalls in order, classify by response content
for (let i = 0; i < toolCalls.length; i++) {
  const r = toolCalls[i];
  const raw = r.result;
  const isError = r.isError;
  const body = extractBody(raw);

  // Try to identify the call based on content shape
  const name = `[call#${i}] tool=${raw?.content?.[0]?.type === "image" ? "(image)" : "?"}`;
  let label;
  if (body?.pong !== undefined) label = "health_check";
  else if (body?.commands) label = "call_action(help)";
  else if (body?.dynamicToolCount !== undefined && !body?.cursor) label = i === 1 ? "refresh_tools" : "static";
  else if (body?.__image) label = "ui_screenshot";
  else if (body?.targets && body?.viewSnapshotID) label = "ui_inspect";
  else if (body?.root && body?.detailLevel) label = "ui_topViewHierarchy";
  else if (body?.satisfied !== undefined) label = "ui_waitAny";
  else if (body?.wait && body?.observation) label = "wait_and_inspect";
  else if (body?.entries) label = "app.logs.read";
  else if (body?.cursor && body?.latestAvailableID) label = "app.logs.mark";
  else if (body?.code === "performed" || body?.code === "dismissed" || body?.code === "button") label = "ui.tap/alert.respond";
  else if (body?.code === "target_not_found" || body?.code === "not_actionable") label = "ui.tap(fail)";
  else if (body?.code === "invalid_data" || body?.code === "unknown_tool" || body?.code === "missing_action" || body?.code === "unknown_action") label = "error-path";
  else label = body?.code || "unknown";

  console.log(`#${i} [${label}] isError=${isError}${body?.code ? " code=" + body.code : ""}${body?.message ? " msg=" + String(body.message).slice(0,100) : ""}`);
}

writeFileSync("/tmp/e2e-results.json", JSON.stringify({ results, findings }, null, 2));
console.log(`\nRaw results saved to /tmp/e2e-results.json (${toolCalls.length} tool calls)`);
console.log(`Summary: ${passCount} pass / ${failCount} fail / ${warnCount} warn`);

process.exit(0);
