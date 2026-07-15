#!/usr/bin/env node
// E2E test runner: inline script that captures real results and reports findings.
import { spawn } from "node:child_process";
import { writeFileSync } from "fs";

const RAW = [];
let buffer = "", nextId = 1;
const pending = new Map();

const server = spawn("node", ["dist/index.js"], { cwd: process.cwd(), stdio: ["pipe", "pipe", "inherit"] });

function send(method, params) {
  const id = nextId++;
  pending.set(id, method);
  server.stdin.write(JSON.stringify({ jsonrpc: "2.0", id, method, params }) + "\n");
  return id;
}

function tryConsume() {
  while (buffer.length > 0) {
    let depth = 0, inStr = false, esc = false, end = -1;
    for (let i = 0; i < buffer.length; i++) {
      const c = buffer[i];
      if (esc) { esc = false; continue; }
      if (c === "\\" && inStr) { esc = true; continue; }
      if (c === "\"") inStr = !inStr;
      else if (!inStr) {
        if (c === "{") depth++;
        else if (c === "}") { depth--; if (depth === 0) { end = i + 1; break; } }
      }
    }
    if (end < 0) break;
    let msg;
    try { msg = JSON.parse(buffer.slice(0, end)); } catch { continue; }
    if (msg.id !== undefined && pending.has(msg.id)) {
      const m = pending.get(msg.id);
      pending.delete(msg.id);
      const isError = msg.error !== undefined || msg.result?.isError === true;
      RAW.push({ id: msg.id, method: m, result: msg.result ?? msg.error, isError });
      if (m === "initialize" && msg.result) {
        server.stdin.write(JSON.stringify({ jsonrpc: "2.0", method: "notifications/initialized" }) + "\n");
      }
    }
    buffer = buffer.slice(end).replace(/^[\r\n\s]+/, "");
  }
}
server.stdout.on("data", chunk => { buffer += chunk.toString(); tryConsume(); });

const T = {}; // track call IDs by label

async function callTool(label, name, args, waitMs = 300) {
  const id = send("tools/call", { name, arguments: args });
  T[label] = id;
  await new Promise(r => setTimeout(r, waitMs));
  return id;
}

// Phase 1: Initialize + get baseline state
send("initialize", { protocolVersion: "2024-11-05", capabilities: {}, clientInfo: { name: "e2e", version: "1" } });
await new Promise(r => setTimeout(r, 100));
send("tools/list", {});

// Call a fresh inspect
await callTool("init-inspect", "ui_inspect", {}, 500);

// Wait for inspect result
await new Promise(r => setTimeout(r, 1500));

// Find the initial snapshot ID
const initInspectRaw = RAW.find(r => r.method === "tools/call" && r.id === T["init-inspect"]);
const initBody = initInspectRaw?.result?.content?.[0]?.text ? JSON.parse(initInspectRaw.result.content[0].text) : {};
const initSid = initBody.viewSnapshotID;
const initTargets = initBody.targets || [];
console.log("INITIAL SNAPSHOT:", initSid);
console.log("SCREEN:", JSON.stringify(initBody.screen));
console.log("NAVBAR:", JSON.stringify(initBody.navigationBar));

// Find menu table cells with tap capability
// The 4 menu items are in a UITableView. Cells at paths like root/5/*.
// We need cells with availableActions (not just UIImageViews inside them)
const menuCells = initTargets.filter(t => t.path && t.path.startsWith("root/5/") && t.path.split("/").length === 3);
const tappableMenu = initTargets.filter(t => t.path && t.path.startsWith("root/5/") && (t.availableActions || []).length > 0);
console.log("Menu cells:", menuCells.length, "Tappable:", tappableMenu.length);
if (menuCells.length > 0) {
  menuCells.slice(0, 6).forEach(t => {
    console.log("  ", t.path, t.type, t.isEnabled, "actions:", (t.availableActions || []).join(","));
  });
}
// Check if there's a UITapGestureRecognizer or similar
const allInspectResult = initTargets.map(t => ({
  path: t.path, type: t.type, actions: (t.availableActions || []).join(","),
  isEnabled: t.isEnabled, hidden: t.isHidden
}));
const tapTargets = allInspectResult.filter(t => t.actions.length > 0);
console.log("All tappable targets in initial inspect:");
tapTargets.slice(0, 10).forEach(t => console.log("  ", t.path, t.type, "actions:", t.actions));

// Try navigating to alert test via tapping the cell
// Since table cells may not be directly tappable with ui.tap,
// we use a multi-step approach: tap via scrollView then wait

const gestureLabel = initTargets.find(t => t.accessibilityIdentifier === "example.gestureTap");
const menuListContentViews = initTargets.filter(t => t.path && /^root\/5\/\d+\/1$/.test(t.path) && (t.availableActions || []).length > 0);
console.log("Menu UIListContentViews (tappable):", menuListContentViews.length);

// T2: Tap on UIListContentView for first menu cell (弹窗测试)
let navCellPath = null;
if (menuListContentViews.length > 0) {
  navCellPath = menuListContentViews[0].path;
  await callTool("nav-tap-cell", "ui_tap", { path: navCellPath, viewSnapshotID: initSid }, 600);
  await new Promise(r => setTimeout(r, 1500));

  // Inspect after navigation
  await callTool("after-nav", "ui_inspect", { maxDepth: 6 }, 600);
  await new Promise(r => setTimeout(r, 1000));

  const afterNavRaw = RAW.find(r => r.method === "tools/call" && r.id === T["after-nav"]);
  const afterNavBody = afterNavRaw?.result?.content?.[0]?.text ? JSON.parse(afterNavRaw.result.content[0].text) : {};
  console.log("\n=== NAVIGATION RESULTS ===");
  console.log("After tapping menu cell:", afterNavBody.screen);
  const navTargets = afterNavBody.targets || [];
  const alertTriggers = navTargets.filter(t => t.accessibilityIdentifier && t.accessibilityIdentifier.startsWith("alert.trigger."));
  console.log("Alert trigger buttons:", alertTriggers.length);
  for (const at of alertTriggers.slice(0, 6)) {
    console.log("  ", at.path, "|", at.accessibilityIdentifier, "|", at.type, "actions:", (at.availableActions || []).join(","));
  }
  const afterNavSid = afterNavBody.viewSnapshotID;
  console.log("After nav snapshot:", afterNavSid);

  // T3: Test alert trigger flow with the simple alert (single button)
  if (alertTriggers.length > 0) {
    const simpleTrigger = navTargets.find(t => t.accessibilityIdentifier === "alert.trigger.simple");
    if (simpleTrigger) {
      console.log("\n=== ALERT TRIGGER: alert.trigger.simple ===");
      await callTool("alert-tap-simple", "ui_tap", { accessibilityIdentifier: "alert.trigger.simple", viewSnapshotID: afterNavSid }, 600);
      await new Promise(r => setTimeout(r, 1500));

      // Inspect during alert
      await callTool("alert-during-simple", "ui_inspect", {}, 600);
      await new Promise(r => setTimeout(r, 1000));

      const duringAlertRaw = RAW.find(r => r.method === "tools/call" && r.id === T["alert-during-simple"]);
      const duringAlertBody = duringAlertRaw?.result?.content?.[0]?.text ? JSON.parse(duringAlertRaw.result.content[0].text) : {};
      console.log("During alert: available=", duringAlertBody.alert?.available, "buttons=", duringAlertBody.alert?.buttons?.length, "textFields=", duringAlertBody.alert?.textFields?.length);
      console.log("alert.buttons:", JSON.stringify(duringAlertBody.alert?.buttons));
      const duringAlertSid = duringAlertBody.viewSnapshotID;

      // Dismiss alert
      await callTool("alert-respond-simple", "ui_alert_respond", {}, 600);
      await new Promise(r => setTimeout(r, 1200));

      // Inspect after dismiss
      await callTool("alert-after-simple", "ui_inspect", {}, 600);
      await new Promise(r => setTimeout(r, 800));

      const afterAlertRaw = RAW.find(r => r.method === "tools/call" && r.id === T["alert-after-simple"]);
      const afterAlertBody = afterAlertRaw?.result?.content?.[0]?.text ? JSON.parse(afterAlertRaw.result.content[0].text) : {};
      console.log("After alert.respond: alert.available =", afterAlertBody.alert?.available);
    }

    // T4: Test loginInput alert flow (with textFields) - tests ui.input on alert
    // Need fresh snapshot since prior alert has been dismissed
    const loginTrigger = navTargets.find(t => t.accessibilityIdentifier === "alert.trigger.loginInput");
    if (loginTrigger && simpleTrigger) {
      console.log("\n=== ALERT TRIGGER: alert.trigger.loginInput ===");
      // Need fresh inspect because we tapped/dismissed previously
      const freshInspectRaw = RAW.find(r => r.method === "tools/call" && r.id === T["alert-after-simple"]);
      const freshInspectBody = freshInspectRaw?.result?.content?.[0]?.text ? JSON.parse(freshInspectRaw.result.content[0].text) : {};
      const freshSid = freshInspectBody.viewSnapshotID;
      await callTool("alert-tap-login", "ui_tap", { accessibilityIdentifier: "alert.trigger.loginInput", viewSnapshotID: freshSid }, 600);
      await new Promise(r => setTimeout(r, 1500));
      await callTool("alert-during-login", "ui_inspect", {}, 600);
      await new Promise(r => setTimeout(r, 1000));

      const duringLoginRaw = RAW.find(r => r.method === "tools/call" && r.id === T["alert-during-login"]);
      const duringLoginBody = duringLoginRaw?.result?.content?.[0]?.text ? JSON.parse(duringLoginRaw.result.content[0].text) : {};
      console.log("Login alert: available=", duringLoginBody.alert?.available);
      console.log("Login alert buttons:", JSON.stringify(duringLoginBody.alert?.buttons));
      console.log("Login alert textFields:", JSON.stringify(duringLoginBody.alert?.textFields));
      const duringLoginSid = duringLoginBody.viewSnapshotID;

      // Use ui.input to write into username textfield (first)
      const usernameTf = duringLoginBody.alert?.textFields?.[0];
      if (usernameTf) {
        console.log("Username textfield path:", usernameTf.path, "placeholder:", usernameTf.placeholder);
        await callTool("alert-input-username", "ui_input", {
          path: usernameTf.path,
          viewSnapshotID: duringLoginSid,
          text: "E2EAgentName42"
        }, 600);
        await new Promise(r => setTimeout(r, 800));
        // Re-inspect to verify text was written
        await callTool("alert-after-input", "ui_inspect", {}, 600);
        await new Promise(r => setTimeout(r, 800));

        const afterInputRaw = RAW.find(r => r.method === "tools/call" && r.id === T["alert-after-input"]);
        const afterInputBody = afterInputRaw?.result?.content?.[0]?.text ? JSON.parse(afterInputRaw.result.content[0].text) : {};
        console.log("After ui.input: alert textFields text =", JSON.stringify(afterInputBody.alert?.textFields?.[0]));

        // Dismiss login alert with OK (buttonIndex 1 typically for OK after Cancel)
        // Check button titles to find OK
        const buttons = duringLoginBody.alert?.buttons;
        const okIdx = buttons.findIndex(b => /OK|确定|登录|Login|确认|Confirm/i.test(b.title || ""));
        const chosenIdx = okIdx >= 0 ? okIdx : 0;
        console.log("Buttons:", buttons.map(b=>b.title), "chosenIdx =", chosenIdx);
        await callTool("alert-respond-login", "ui_alert_respond", { buttonIndex: chosenIdx }, 600);
        await new Promise(r => setTimeout(r, 1200));
        // Verify alert is gone
        await callTool("alert-after-login", "ui_inspect", { maxDepth: 4 }, 600);
        await new Promise(r => setTimeout(r, 800));
        const verifyLoginRaw = RAW.find(r => r.method === "tools/call" && r.id === T["alert-after-login"]);
        const verifyLoginBody = verifyLoginRaw?.result?.content?.[0]?.text ? JSON.parse(verifyLoginRaw.result.content[0].text) : {};
        console.log("After login alert.respond: alert.available =", verifyLoginBody.alert?.available);
      }
    }
  }
}

// Phase 3: Test more error scenarios
await callTool("err-tap-empty", "ui_tap", {}, 300);
await callTool("err-tap-stale", "ui_tap", { path: "root/0", viewSnapshotID: "snap-fake" }, 300);
await callTool("err-unknown-tool", "ui_unknown_xyz", {}, 300);
await callTool("err-missing-action", "call_action", {}, 300);
await callTool("err-unknown-action", "call_action", { action: "this.does.not.exist" }, 300);
await callTool("err-garbage-fields", "ui_inspect", { nonexistentField: "x" }, 300);
await callTool("err-no-alert", "ui_alert_respond", {}, 300);

// Phase 4: Wait commands (use longer timeout to ensure satisfied=true)
await callTool("wait-idle", "ui_wait", { mode: "idle", timeoutMs: 3000 }, 3500);
await callTool("wait-multi", "ui_waitAny", { conditions: [{ id: "a", mode: "idle" }], timeoutMs: 3000 }, 3500);
await callTool("wait-inspect", "wait_and_inspect", { conditions: [{ id: "a", mode: "idle" }], timeoutMs: 3000 }, 3500);

// Phase 5: Top view hierarchy
await callTool("hierarchy-basic", "ui_topViewHierarchy", { detailLevel: "basic" }, 300);
await callTool("hierarchy-full", "ui_topViewHierarchy", { detailLevel: "full", includeHidden: false }, 300);

// Phase 6: Logs + Screenshot
await callTool("logs-mark", "call_action", { action: "app.logs.mark" }, 300);
await callTool("logs-read", "call_action", { action: "app.logs.read", data: { sources: ["explore"], limit: 2 } }, 300);
await callTool("stdout-read", "call_action", { action: "app.logs.read", data: { limit: 2, sources: ["stdout"] } }, 300);
await callTool("screenshot", "ui_screenshot", { }, 500);

// Wait for all recent calls to complete
await new Promise(r => setTimeout(r, 2000));
server.kill("SIGTERM");
await new Promise(r => server.on("close", r));

// ========================================
// ANALYSIS
// ========================================
const callResults = rawToResultMap(RAW);
const FINDINGS = [];

function PASS(name, detail) { console.log(` ✅ ${name}: ${detail}`); }
function FAIL(name, detail) { console.log(` ❌ ${name}: ${detail}`); FINDINGS.push({ name, severity: "FAIL", detail }); }
function WARN(name, detail) { console.log(` ⚠️  ${name}: ${detail}`); FINDINGS.push({ name, severity: "WARN", detail }); }

function safe(body, keys) {
  if (!body) return null;
  let cur = body;
  for (const k of keys) {
    if (cur == null) return null;
    cur = ((k.startsWith("[") && k.endsWith("]"))) ? cur[parseInt(k.slice(1,-1), 10)] : cur[k];
  }
  return cur;
}

function findTarget(body, pred) {
  return (body?.targets || []).find(pred) || null;
}

console.log("\n======================================");
console.log("     MCP SERVER E2E REPORT");
console.log("======================================\n");

// === T1: Initialize ===
const initRaw = RAW.find(r => r.method === "initialize");
PASS("T0-init", `server init ${initRaw?.result?.serverInfo?.name || "N/A"}`);
const toolList = RAW.find(r => r.method === "tools/list");
const tools = toolList?.result?.tools || [];
PASS("T0-tools", `${tools.length} tools available`);

// === T2: Fresh inspect baseline ===
const inspectRaw = callResults[T["init-inspect"]];
const inspectBody = inspectRaw?.body;
if (inspectBody && inspectBody.targets) {
  PASS("T2a-inspect", `targets=${inspectBody.targetCount} full=${inspectBody.fullCount} minimal=${inspectBody.minimalCount} viewSnapshotID=${inspectBody.viewSnapshotID}`);
  PASS("T2b-screen", `topVC=${safe(inspectBody,["screen","topViewController"])} rootVC=${safe(inspectBody,["screen","rootViewController"])}`);

  // Check for alert block
  if (inspectBody.alert) {
    PASS("T2c-alert", `available=${inspectBody.alert.available} buttons=${inspectBody.alert.buttons.length} textFields=${inspectBody.alert.textFields.length}`);
  } else {
    WARN("T2c-alert", "No alert block in inspect output (P0-4 regression?)");
  }

  // Check for navigationBar block
  if (inspectBody.navigationBar) {
    PASS("T2d-navbar", `title=${inspectBody.navigationBar.title} backAvailable=${inspectBody.navigationBar.backAvailable} topVC=${inspectBody.navigationBar.topViewController}`);
  } else {
    WARN("T2d-navbar", "No navigationBar block in inspect output");
  }

  // Check gesture label tappability
  const gesLabel = findTarget(inspectBody, t => t.accessibilityIdentifier === "example.gestureTap");
  if (gesLabel) {
    if (gesLabel.availableActions && gesLabel.availableActions.length > 0) {
      PASS("T2e-gesture", `availableActions=${gesLabel.availableActions.join(",")}`);
    } else {
      WARN("T2e-gesture", "gesture label has no availableActions despite having UITapGestureRecognizer");
    }
  }
} else {
  FAIL("T2-inspect", "ui.inspect returned no targets");
}

// === T3: Navigation to AlertTestViewController ===
const navTapRaw = callResults[T["nav-tap-cell"]];
if (navTapRaw) {
  if (navTapRaw.isError) {
    WARN("T3-nav-tap", `tapping menu cell failed: code=${navTapRaw.body?.code} msg=${navTapRaw.body?.message}`);
  } else {
    PASS("T3-nav-tap", `code=${navTapRaw.body?.code || "performed"}`);
  }
}

const afterNavRaw = callResults[T["after-nav"]];
if (afterNavRaw?.body) {
  const afterTop = afterNavRaw.body.screen?.topViewController;
  if (afterTop && afterTop !== "ViewController" && /AlertTest/.test(afterTop)) {
    PASS("T3-after-nav", `navigated to ${afterTop}`);
  } else if (afterTop && /AlertTest/.test(afterTop)) {
    PASS("T3-after-nav", `navigated to ${afterTop}`);
  } else {
    WARN("T3-after-nav", `expected AlertTestViewController, got ${afterTop}`);
  }

  // Check for alert trigger buttons
  const triggers = (afterNavRaw.body.targets || []).filter(t => t.accessibilityIdentifier && t.accessibilityIdentifier.startsWith("alert.trigger."));
  if (triggers.length > 0) {
    PASS("T3-triggers", `${triggers.length} alert.trigger.* buttons found`);
    // Verify all trigger identifiers we expect
    const expectedTriggers = ["alert.trigger.simple", "alert.trigger.okCancel", "alert.trigger.destructive", "alert.trigger.loginInput", "alert.trigger.inputFields"];
    const foundIds = triggers.map(t => t.accessibilityIdentifier);
    for (const e of expectedTriggers) {
      if (foundIds.includes(e)) PASS(`T3-trigger-${e}`, "found");
      else WARN(`T3-trigger-${e}`, `not found in triggers: ${foundIds.join(",")}`);
    }
  } else {
    WARN("T3-triggers", "No alert.trigger.* buttons after navigation");
  }
}

// === T4: alert.trigger.simple flow ===
const alertSimpleTapRaw = callResults[T["alert-tap-simple"]];
if (alertSimpleTapRaw) {
  if (alertSimpleTapRaw.isError) {
    FAIL("T4-alert-tap-simple", `tap failed: code=${alertSimpleTapRaw.body?.code}`);
  } else {
    PASS("T4-alert-tap-simple", `code=${alertSimpleTapRaw.body?.code || "performed"}`);
  }
}
const duringSimpleRaw = callResults[T["alert-during-simple"]];
if (duringSimpleRaw) {
  const a = duringSimpleRaw.body?.alert;
  if (a?.available === true) {
    PASS("T4-alert-present", `available=true buttons=${a.buttons?.length} title="${a.title}"`);
    if (a.buttons?.length === 1) {
      PASS("T4-alert-single-button", `button[0].title="${a.buttons[0].title}"`);
    } else {
      WARN("T4-alert-single-button", `expected 1 button, got ${a.buttons?.length}`);
    }
  } else {
    WARN("T4-alert-present", `alert.available=${a?.available}`);
  }
}
const respondSimpleRaw = callResults[T["alert-respond-simple"]];
if (respondSimpleRaw) {
  if (respondSimpleRaw.isError) {
    FAIL("T4-respond-simple", `code=${respondSimpleRaw.body?.code}`);
  } else {
    PASS("T4-respond-simple", `code=${respondSimpleRaw.body?.code || "ok"}`);
  }
}
const afterSimpleRaw = callResults[T["alert-after-simple"]];
if (afterSimpleRaw) {
  const a = afterSimpleRaw.body?.alert;
  if (a?.available === false) {
    PASS("T4-alert-dismissed", `alert.available=false after respond`);
  } else {
    WARN("T4-alert-dismissed", `alert.available=${a?.available}`);
  }
}

// === T5: alert.trigger.loginInput flow with ui.input ===
const loginTapRaw = callResults[T["alert-tap-login"]];
if (loginTapRaw) {
  if (loginTapRaw.isError) {
    FAIL("T5-alert-tap-login", `tap failed: code=${loginTapRaw.body?.code}`);
  } else {
    PASS("T5-alert-tap-login", `code=${loginTapRaw.body?.code || "performed"}`);
  }
}
const duringLoginRaw = callResults[T["alert-during-login"]];
if (duringLoginRaw) {
  const a = duringLoginRaw.body?.alert;
  if (a?.available === true && a.textFields?.length > 0) {
    PASS("T5-alert-textFields", `textFields=${a.textFields.length} buttons=${a.buttons.length}`);
    // List textfield specs
    a.textFields.forEach((tf, i) => {
      console.log(`  textField[${i}]: placeholder="${tf.placeholder}" text="${tf.text||''}"`);
    });
  } else {
    WARN("T5-alert-textFields", `alert.available=${a?.available} textFields=${a?.textFields?.length}`);
  }
}
const inputRaw = callResults[T["alert-input-username"]];
if (inputRaw) {
  if (inputRaw.isError) {
    FAIL("T5-input-username", `ui.input failed: code=${inputRaw.body?.code} msg=${inputRaw.body?.message?.slice(0,100)}`);
  } else {
    PASS("T5-input-username", `code=${inputRaw.body?.code || "ok"}`);
  }
}
const afterInputRaw = callResults[T["alert-after-input"]];
if (afterInputRaw) {
  // Verify the text was actually written to textfield
  const a = afterInputRaw.body?.alert;
  if (a?.textFields?.[0]?.text === "E2EAgentName42") {
    PASS("T5-input-readback", `textField[0].text="${a.textFields[0].text}"`);
  } else {
    WARN("T5-input-readback", `textField[0].text = "${a?.textFields?.[0]?.text}" (expected E2EAgentName42)`);
  }
}
const respondLoginRaw = callResults[T["alert-respond-login"]];
if (respondLoginRaw) {
  if (respondLoginRaw.isError) {
    FAIL("T5-respond-login", `code=${respondLoginRaw.body?.code}`);
  } else {
    PASS("T5-respond-login", `code=${respondLoginRaw.body?.code || "ok"}`);
  }
}
const verifyLoginRaw = callResults[T["alert-after-login"]];
if (verifyLoginRaw) {
  const a = verifyLoginRaw.body?.alert;
  if (a?.available === false) {
    PASS("T5-login-dismissed", `alert.available=false after OK respond`);
  } else {
    WARN("T5-login-dismissed", `alert.available=${a?.available}`);
  }
}

// === T4: Error scenarios ===
const errCallIds = ["err-tap-empty", "err-tap-stale", "err-unknown-tool", "err-missing-action", "err-unknown-action", "err-garbage-fields", "err-no-alert"];
const errExpectations = {
  "err-tap-empty": { isError: true, code: "invalid_data" },
  "err-tap-stale": { isError: true, code: "stale_locator" },
  "err-unknown-tool": { isError: true, code: "unknown_tool" },
  "err-missing-action": { isError: true, code: "missing_action" },
  "err-unknown-action": { isError: false, code: "unknown_action" },  // P1-5 Fix B: call_action stays isError=false
  "err-garbage-fields": { isError: true, code: "invalid_data" },
  "err-no-alert": { isError: false, code: "alert_unavailable" },    // runtime state, not error
};

for (const [label, exp] of Object.entries(errExpectations)) {
  const raw = callResults[T[label]];
  if (!raw) { FAIL(`T4-${label}`, `no result`); continue; }
  const codeMatch = raw.body?.code === exp.code;
  const errorMatch = raw.isError === exp.isError;
  if (codeMatch && errorMatch) {
    PASS(`T4-${label}`, `code=${exp.code} isError=${exp.isError}`);
  } else {
    WARN(`T4-${label}`, `expected code=${exp.code} isError=${exp.isError}, got code=${raw.body?.code} isError=${raw.isError}`);
  }
}

// === T5: Wait commands ===
const waitLabels = ["wait-idle", "wait-multi", "wait-inspect"];
for (const label of waitLabels) {
  const raw = callResults[T[label]];
  if (!raw) { FAIL(`T5-${label}`, `no result`); continue; }
  const body = raw.body;
  if (label === "wait-inspect") {
    if (body?.wait?.satisfied === true && body?.observation?.targetCount > 0) {
      PASS(`T5-${label}`, `wait.satisfied=true observation.targetCount=${body.observation.targetCount}`);
    } else {
      WARN(`T5-${label}`, `wait=${JSON.stringify(body?.wait)}, observation=${body?.observation?.targetCount || "N/A"}`);
    }
  } else {
    if (body?.satisfied === true) {
      const labelSuffix = body.matchedID ? ` matchedID=${body.matchedID}` : "";
      PASS(`T5-${label}`, `satisfied=true attempts=${body.attempts}${labelSuffix}`);
    } else {
      WARN(`T5-${label}`, `satisfied=${body?.satisfied} attempts=${body?.attempts}`);
    }
  }
}

// === T6: Hierarchy ===
for (const label of ["hierarchy-basic", "hierarchy-full"]) {
  const raw = callResults[T[label]];
  if (!raw) { FAIL(`T6-${label}`, `no result`); continue; }
  const body = raw.body;
  const isBasic = label.includes("basic");
  if (body?.root && body?.detailLevel) {
    PASS(`T6-${label}`, `detailLevel=${body.detailLevel} nodeCount=${body.nodeCount} root.type=${body.root.type}`);
  } else {
    WARN(`T6-${label}`, `root=${!!body?.root}, detailLevel=${body?.detailLevel}`);
  }
  // Check alert/nav blocks
  if (body?.alert) {
    PASS(`T6-${label}-alert`, `alert block present: available=${body.alert.available}`);
  } else {
    WARN(`T6-${label}-alert`, "No alert block - hierarchy injection missing?");
  }
  if (body?.navigationBar) {
    PASS(`T6-${label}-nav`, `navBar block present: title=${body.navigationBar.title}`);
  } else {
    WARN(`T6-${label}-nav`, "No navigationBar block in hierarchy");
  }
}

// === T7: Logs ===
const markRaw = callResults[T["logs-mark"]];
if (markRaw?.body?.cursor?.captureSessionID) {
  PASS("T7a-mark", `cursor.sessionID=${markRaw.body.cursor.captureSessionID} latestID=${markRaw.body.latestAvailableID}`);
} else {
  WARN("T7a-mark", `mark result missing cursor: ${JSON.stringify(markRaw?.body).slice(0, 80)}`);
}

const readRaw = callResults[T["logs-read"]];
if (readRaw?.body?.entries) {
  PASS("T7b-read-explore", `entries=${readRaw.body.entries.length} hasMore=${readRaw.body.hasMore} gap=${readRaw.body.gap}`);
  if (readRaw.body.entries.length > 0) {
    const e0 = readRaw.body.entries[0];
    if (e0.id && e0.message && e0.source && e0.timestamp && e0.category && e0.level) {
      PASS("T7b-entry", `id=${e0.id} source=${e0.source} category=${e0.category} level=${e0.level}`);
    } else {
      WARN("T7b-entry-keys", `entry[0] keys: ${Object.keys(e0).join(",")}`);
    }
    if (e0.messageTruncated !== undefined && typeof e0.messageTruncated === "boolean") {
      PASS("T7b-truncated", `messageTruncated is boolean`);
    } else {
      WARN("T7b-truncated", `messageTruncated field missing or not boolean: ${typeof e0.messageTruncated}`);
    }
  }
} else {
  WARN("T7b-read-explore", `read result: ${JSON.stringify(readRaw?.body).slice(0, 120)}`);
}

const stdoutRaw = callResults[T["stdout-read"]];
if (stdoutRaw?.body?.entries !== undefined) {
  const allStdout = stdoutRaw.body.entries.every(e => e.source === "stdout");
  PASS("T7c-stdout", `entries=${stdoutRaw.body.entries.length} allStdout=${allStdout}`);
} else {
  WARN("T7c-stdout", `stdout read: ${JSON.stringify(stdoutRaw?.body).slice(0, 120)}`);
}

// === T8: Screenshot ===
const ssRaw = callResults[T["screenshot"]];
if (ssRaw?.raw?.content?.[0]?.type === "image") {
  const imgContent = ssRaw.raw.content[0];
  PASS("T8a-screenshot", `type=image mimeType=${imgContent.mimeType} dataLength=${imgContent.data?.length || "N/A"}`);
  const textContent = ssRaw.raw.content?.find(c => c.type === "text");
  if (textContent) {
    PASS("T8b-screenshot-text", `text content present`);
  }
} else {
  WARN("T8a-screenshot", `No image content: ${JSON.stringify(ssRaw?.raw?.content).slice(0, 200)}`);
}

// === T9: isError=stale_locator was properly elevated ===
// This was P1-5 Fix B: stale_locator should be isError=true
const staleRaw = callResults[T["err-tap-stale"]];
if (staleRaw && staleRaw.body?.code === "stale_locator" && staleRaw.isError === true) {
  PASS("T9-stale-isError", `stale_locator isError=true (P1-5 Fix B)`);
} else if (staleRaw) {
  WARN("T9-stale-isError", `Expected isError=true, got ${staleRaw.isError} (P1-5 Fix B regression?)`);
}

// === T10: app.logs.mark/read lifecycle ===
// Check that entries exist and are well-formed
const readRaw2 = callResults[T["logs-read"]];
if (readRaw2?.body?.capturedThrough) {
  PASS("T10-capturedThrough", `id=${readRaw2.body.capturedThrough.id} sessionID=${readRaw2.body.capturedThrough.captureSessionID}`);
}
if (readRaw2?.body?.nextCursor) {
  PASS("T10-nextCursor", `id=${readRaw2.body.nextCursor.id}`);
}

// === T11: wait_and_inspect returned observation ===
const wiRaw = callResults[T["wait-inspect"]];
if (wiRaw?.body?.observation) {
  const obs = wiRaw.body.observation;
  if (obs.targetCount !== undefined && obs.viewSnapshotID) {
    PASS("T11-wait-inspect-obs", `targetCount=${obs.targetCount} viewSnapshotID=${obs.viewSnapshotID}`);
  } else {
    WARN("T11-wait-inspect-obs", `observation missing key fields: ${JSON.stringify(obs).slice(0, 200)}`);
  }
}

// Summary
console.log(`\n======================================`);
console.log(`  E2E COMPLETE`);
const total = FINDINGS.length;
const failCount = FINDINGS.filter(f => f.severity === "FAIL").length;
const warnCount = FINDINGS.filter(f => f.severity === "WARN").length;
console.log(`  ${total} findings (${failCount} FAIL, ${warnCount} WARN)`);

// Save raw results
writeFileSync("/tmp/e2e-complete.json", JSON.stringify(RAW, null, 2));
console.log("Raw results saved to /tmp/e2e-complete.json");

// =========================================
function rawToResultMap(raws) {
  const map = {};
  const toolCalls = raws.filter(r => r.method === "tools/call");
  for (const r of toolCalls) {
    const text = r.result?.content?.[0]?.text;
    let body = null;
    if (text) { try { body = JSON.parse(text); } catch { body = { __raw: text }; } }
    else if (r.result?.content?.[0]?.type === "image") { body = { __image: true }; }
    map[r.id] = { raw: r.result, body, isError: r.isError };
  }
  return map;
}
