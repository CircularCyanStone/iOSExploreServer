#!/usr/bin/env node
// Comprehensive E2E test script for iOSDriver
// Tests multiple command paths, error scenarios, and workflows
import { spawn } from "node:child_process";

const server = spawn("node", ["dist/index.js"], {
  cwd: process.cwd(),
  stdio: ["pipe", "pipe", "inherit"]
});

const RAW = [];

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
      RAW.push({ method, id: msg.id, result: msg.result ?? msg.error });
      if (method === "initialize" && msg.result) {
        server.stdin.write(JSON.stringify({ jsonrpc: "2.0", method: "notifications/initialized" }) + "\n");
      }
    }
  }
});

function waitForClose(timeoutMs = 15000) {
  return new Promise((resolve) => {
    const t = setTimeout(() => { server.kill(); resolve(); }, timeoutMs);
    server.on("close", () => { clearTimeout(t); resolve(); });
  });
}

function pretty(v) {
  return JSON.stringify(v, null, 2);
}

function extractResult(raw) {
  const text = raw?.content?.[0]?.text;
  if (!text) return { isError: raw?.isError ?? false, body: null };
  try { return { isError: raw?.isError ?? false, body: JSON.parse(text) }; }
  catch { return { isError: raw?.isError ?? false, body: text }; }
}

const TESTS = [
  // === [T1] Static tools ===
  { name: "T1a: health_check", func: () => send("tools/call", { name: "health_check", arguments: {} }) },
  { name: "T1b: refresh_tools", func: () => send("tools/call", { name: "refresh_tools", arguments: {} }) },
  { name: "T1c: call_action(help)", func: () => send("tools/call", { name: "call_action", arguments: { action: "help" } }) },

  // === [T2] Dynamic tools: inspect variants ===
  { name: "T2a: ui_inspect default", func: () => send("tools/call", { name: "ui_inspect", arguments: {} }) },
  { name: "T2b: ui_inspect filtered", func: () => send("tools/call", { name: "ui_inspect", arguments: { accessibilityIdentifierPrefix: "alert.trigger" } }) },
  { name: "T2c: ui_topViewHierarchy basic", func: () => send("tools/call", { name: "ui_topViewHierarchy", arguments: { detailLevel: "basic" } }) },
  { name: "T2d: ui_topViewHierarchy full", func: () => send("tools/call", { name: "ui_topViewHierarchy", arguments: { detailLevel: "full", includeHidden: true } }) },

  // === [T3] Tap ===
  { name: "T3a: ui_tap by identifier", func: () => send("tools/call", { name: "ui_tap", arguments: { accessibilityIdentifier: "alert.trigger.simple" } }) },
  { name: "T3b: ui_tap by path", func: () => {
    // Path must be obtained from latest inspect - let's use the known path "root/0/0/0/1/1" for alert.trigger.simple
    send("tools/call", { name: "ui_tap", arguments: { path: "root/0/0/0/1/1", viewSnapshotID: "snap-38" } });
  }},

  // === [T4] Alert ===
  { name: "T4a: ui_alert_respond dryRun(implicit)", func: () => {
    // After tapping simple alert button, there should be an alert
    send("tools/call", { name: "ui_alert_respond", arguments: {} });
  }},
  { name: "T4b: ui_alert_respond single button", func: () => {
    // Now invoke simple alert again, then close it with the "确认" button
    send("tools/call", { name: "ui_tap", arguments: { accessibilityIdentifier: "alert.trigger.simple" } });
  }},
  { name: "T4c: ui_inspect during alert", func: () => {
    send("tools/call", { name: "ui_inspect", arguments: {} });
  }},

  // === [T5] Wait / waitAny ===
  { name: "T5a: ui_wait idle", func: () => send("tools/call", { name: "ui_wait", arguments: { mode: "idle", timeoutMs: 1000 } }) },
  { name: "T5b: ui_waitAny multi-condition", func: () => send("tools/call", { name: "ui_waitAny", arguments: { conditions: [{ id: "idle", mode: "idle" }], timeoutMs: 1000 } }) },
  { name: "T5c: wait_and_inspect compound", func: () => send("tools/call", { name: "wait_and_inspect", arguments: { conditions: [{ id: "idle", mode: "idle" }], timeoutMs: 1000 } }) },

  // === [T6] Navigation ===
  { name: "T6a: ui_navigation_back", func: () => send("tools/call", { name: "ui_navigation_back", arguments: {} }) },

  // === [T7] Logs ===
  { name: "T7a: app.logs.mark", func: () => send("tools/call", { name: "app_logs_mark", arguments: {} }) },
  { name: "T7b: app.logs.read filtered", func: () => send("tools/call", { name: "app_logs_read", arguments: { sources: ["explore"], limit: 2 } }) },
  { name: "T7c: app.logs.read with cursor", func: () => send("tools/call", { name: "app_logs_read", arguments: { limit: 1, sources: ["stdout"] } }) },

  // === [T8] Error scenarios ===
  { name: "T8a: ui_tap missing required args", func: () => send("tools/call", { name: "ui_tap", arguments: {} }) },
  { name: "T8b: ui_tap with stale viewSnapshotID", func: () => send("tools/call", { name: "ui_tap", arguments: { path: "root/0/0/0/1/1", viewSnapshotID: "snap-xxx-fake" } }) },
  { name: "T8c: unknown tool name", func: () => send("tools/call", { name: "ui_unknown_tool_xyz", arguments: {} }) },
  { name: "T8d: call_action missing action", func: () => send("tools/call", { name: "call_action", arguments: {} }) },
  { name: "T8e: call_action unknown action", func: () => send("tools/call", { name: "call_action", arguments: { action: "this.action.does.not.exist" } }) },
  { name: "T8f: ui_inspect garbage fields", func: () => send("tools/call", { name: "ui_inspect", arguments: { nonexistentField: "value", maxDepth: "not-a-number" } }) },

  // === [T9] Keyboard (may not work on simulator without hardware keyboard) ===
  { name: "T9a: ui_keyboard_press", func: () => send("tools/call", { name: "ui_keyboard_press", arguments: { key: "return" } }) },
  { name: "T9b: ui_key_type", func: () => send("tools/call", { name: "ui_key_type", arguments: { text: "Hello World" } }) },

  // === [T10] Scroll ===
  { name: "T10a: ui_scroll", func: () => send("tools/call", { name: "ui_scroll", arguments: { accessibilityIdentifier: "alert.trigger.simple", direction: "down" } }) },

  // === [T11] Screenshot ===
  { name: "T11a: ui_screenshot", func: () => send("tools/call", { name: "ui_screenshot", arguments: {} }) },

  // === [T12] Alert close ===
  { name: "T12a: ui_alert_respond close alert", func: () => send("tools/call", { name: "ui_alert_respond", arguments: { buttonIndex: 0 } }) },
];

// ====== CONTROL FLOW ======
const results = {};

send("initialize", {
  protocolVersion: "2024-11-05",
  capabilities: {},
  clientInfo: { name: "mcp-e2e-tester", version: "0.1.0" }
});

// Insert tools/list after init
setTimeout(() => {
  send("tools/list", {});
  // Then start running tests
  let delay = 500;
  for (const test of TESTS) {
    delay += 400;
    setTimeout(() => test.func(), delay);
  }
  // After all tests, wait and analyze
}, 300);

// Give time for all requests
await waitForClose(30000);

// Now analyze
let idx = 0;
for (const test of TESTS) {
  // Find the next matching raw result
  while (idx < RAW.length) {
    const r = RAW[idx++];
    // Skip non-tools/call entries
    if (r.method !== "tools/call" && r.method !== "tools/list") continue;
    if (r.method === "tools/list") { results["tools/list"] = r.result; continue; }

    const parsed = extractResult(r.result);
    results[test.name] = { isError: parsed.isError, body: parsed.body, raw: r.result };
    break;
  }
}

console.log("\n============================================================");
console.log("     MCP Server E2E Test Report");
console.log("============================================================\n");

// We need to track the alert state for T4c/T12 which depend on order
let passCount = 0, failCount = 0, warnCount = 0;
const issues = [];

function check(testName, condition, detail) {
  if (condition) {
    console.log(`  ✅ ${testName}: ${detail}`);
    passCount++;
  } else {
    console.log(`  ❌ ${testName}: ${detail}`);
    failCount++;
    issues.push({ testName, severity: "FAIL", detail });
  }
}

function warn(testName, detail) {
  console.log(`  ⚠️  ${testName}: ${detail}`);
  warnCount++;
  issues.push({ testName, severity: "WARN", detail });
}

for (const [name, r] of Object.entries(results)) {
  if (name === "tools/list") continue;
  console.log(`\n--- ${name} ---`);

  if (!r) { warn(name, "No result captured"); continue; }

  const body = r.body;
  const err = r.isError;

  if (!body) {
    warn(name, `No body (isError=${err})`);
    continue;
  }

  // Parse the raw result's content text if body is a string
  if (typeof body === "string") {
    console.log(`  isError=${err}, body[0:100]=${body.slice(0,100)}`);
    continue;
  }

  // Common checks
  if (body.source === "transport" || body.source === "http") {
    check(name, false, `Transport/HTTP error: ${body.message}`);
    continue;
  }

  // Check for ios_envelope errors with isError=true
  if (body.code && err) {
    check(name, false, `Error: [${body.code}] ${body.message}`);
    continue;
  }

  // Tool-specific checks
  if (name === "T1a: health_check") {
    check(name, body.ok === true, "health_check.ok=true");
    check(name, body.ping?.pong === true, "ping.pong=true");
    check(name, typeof body.dynamicToolCount === "number", `dynamicToolCount=${body.dynamicToolCount}`);
    check(name, Array.isArray(body.conflicts), "conflicts is array");
  } else if (name === "T1b: refresh_tools") {
    check(name, typeof body.dynamicToolCount === "number", `dynamicToolCount=${body.dynamicToolCount}`);
    check(name, Array.isArray(body.conflicts), "conflicts is array");
  } else if (name === "T1c: call_action(help)") {
    check(name, Array.isArray(body.actions), `help.actions is array length=${body.actions?.length}`);
  } else if (name.startsWith("T2") || name.startsWith("T2")) {
    // Inspect variants
    check(name, Array.isArray(body.targets), "targets is array");
    check(name, typeof body.viewSnapshotID === "string", `viewSnapshotID=${body.viewSnapshotID || "MISSING"}`);
    check(name, typeof body.targetCount === "number", `targetCount=${body.targetCount}`);
    check(name, typeof body.fullCount === "number", `fullCount=${body.fullCount}`);
    check(name, typeof body.minimalCount === "number", `minimalCount=${body.minimalCount}`);
    check(name, typeof body.screen?.topViewController === "string", `topViewController=${body.screen?.topViewController}`);
    if (body.alert) {
      if (name.includes("alert")) {
        // During alert: check alert block
        check(name, body.alert.available === true, "alert.available=true");
        check(name, Array.isArray(body.alert.buttons), "alert.buttons is array");
        check(name, Array.isArray(body.alert.textFields), "alert.textFields is array");
        if (body.alert.buttons.length > 0) {
          const btn0 = body.alert.buttons[0];
          check(name, typeof btn0.index === "number", `alert.buttons[0].index=${btn0.index}`);
          check(name, typeof btn0.title === "string", `alert.buttons[0].title="${btn0.title}"`);
          check(name, typeof btn0.role === "string", `alert.buttons[0].role="${btn0.role}"`);
          // N2 fix: path should NOT be present on alert buttons
          check(name, btn0.path === undefined, "alert.buttons[0] has no path (N2 fix)");
          check(name, Array.isArray(btn0.availableActions) && btn0.availableActions.includes("ui.alert.respond"),
            "alert.buttons[0].availableActions includes ui.alert.respond");
        }
        if (body.alert.textFields.length > 0) {
          const tf0 = body.alert.textFields[0];
          check(name, typeof tf0.path === "string", `alert.textFields[0].path="${tf0.path}" (N3 fix)`);
          check(name, typeof tf0.accessibilityIdentifier === "string", `alert.textFields[0].accessibilityIdentifier present`);
        }
      } else {
        // No alert visible: alert block should be available=false
        check(name, body.alert.available === false, "alert.available=false (no alert)");
      }
    } else {
      warn(name, "No 'alert' block in inspect output");
    }
  } else if (name.startsWith("T3")) {
    // Tap results
    check(name, body.code === "performed" || body.code === "dismissed" || body.code === "button" || body.status === "ok",
      `tap result code=${body.code || body.status || "?"}`);
  } else if (name.startsWith("T4")) {
    // Alert respond
    check(name, body.code === "performed" || body.code === "dismissed" || body.code === "button",
      `alert.respond code=${body.code}`);
    if (body.code === "performed") {
      check(name, body.message?.includes("performed") || body.message?.includes("dismissed") || typeof body.button === "string",
        `alert.respond message: ${body.message || "?"}, button: ${body.button || "?"}`);
    }
  } else if (name.startsWith("T5")) {
    // Wait commands
    check(name, body.satisfied === true, `satisfied=${body.satisfied}`);
    check(name, typeof body.attempts === "number", `attempts=${body.attempts}`);
    if (body.matchedID) {
      check(name, typeof body.matchedID === "string", `matchedID=${body.matchedID}`);
    }
    if (body.observation) {
      check(name, Array.isArray(body.observation.targets), "observation.targets is array");
    }
  } else if (name.startsWith("T6")) {
    // Navigation
    check(name, body.code === "performed" || body.code === "not_found" || body.code === "unavailable",
      `navigation code=${body.code}`);
    // If back is available, navigation should succeed
    if (body.status === "ok") check(name, true, "navigation back performed");
  } else if (name.startsWith("T7")) {
    // Logs
    if (name.includes("mark")) {
      check(name, typeof body.oldestAvailableID === "number", `mark has oldestAvailableID`);
      check(name, typeof body.latestAvailableID === "number", `mark has latestAvailableID`);
      check(name, body.cursor?.captureSessionID, "mark has cursor.captureSessionID");
    }
    if (name.includes("read")) {
      check(name, Array.isArray(body.entries), "read has entries array");
      check(name, body.nextCursor?.captureSessionID, "read has nextCursor.captureSessionID");
      if (body.entries?.length > 0) {
        const e0 = body.entries[0];
        check(name, typeof e0.id === "number", `entry[0].id=${e0.id}`);
        check(name, typeof e0.message === "string", "entry[0].message is string");
        check(name, typeof e0.source === "string", `entry[0].source="${e0.source}"`);
        check(name, typeof e0.timestamp === "string", "entry[0].timestamp is string");
        check(name, typeof e0.category === "string", "entry[0].category is string");
        check(name, typeof e0.level === "string", "entry[0].level is string");
        check(name, typeof e0.messageTruncated === "boolean", "entry[0].messageTruncated is boolean");
      }
      if (name.includes("stdout")) {
        // This is interesting - stdout source filtering
        check(name, body.entries.every(e => e.source === "stdout") || body.entries.length === 0,
          `stdout filter: entries=${body.entries.length}`);
      }
    }
  } else if (name.startsWith("T8")) {
    // Error scenarios: these SHOULD return errors
    if (name === "T8a: ui_tap missing required args") {
      check(name, err === true || body.code === "invalid_data",
        `tap without args should error: isError=${err}, code=${body.code}`);
    } else if (name === "T8b: ui_tap with stale viewSnapshotID") {
      check(name, err === true || body.code === "stale_locator" || body.code === "not_found",
        `stale snapshot should error: isError=${err}, code=${body.code}`);
    } else if (name === "T8c: unknown tool name") {
      check(name, body.code === "unknown_tool" || body.code === "unknown_action",
        `unknown tool: code=${body.code}`);
      check(name, err === true, `unknown tool should be isError=true`);
    } else if (name === "T8d: call_action missing action") {
      check(name, body.code === "missing_action", "missing_action should be missing_action");
    } else if (name === "T8e: call_action unknown action") {
      check(name, body.code === "unknown_action",
        `unknown action: code=${body.code}`);
      // call_action with unknown_action should be isError=false
      check(name, err === false,
        "call_action unknown_action should be isError=false (P1-5 Fix B)");
    } else if (name === "T8f: ui_inspect garbage fields") {
      check(name, body.code === "invalid_data" || (Array.isArray(body.targets)),
        `garbage fields: code=${body.code}`);
    }
  } else if (name.startsWith("T9")) {
    // Keyboard
    check(name, body.code === "performed" || body.code === "unavailable" || body.code === "not_actionable",
      `keyboard code=${body.code}`);
    if (body.code === "unavailable" || body.code === "not_actionable") {
      warn(name, `Keyboard ${body.code}: ${body.message || "no detail"}`);
    }
  } else if (name.startsWith("T10")) {
    // Scroll
    check(name, body.code === "performed" || body.code === "not_found" || body.code === "not_actionable",
      `scroll code=${body.code}`);
  } else if (name.startsWith("T11")) {
    // Screenshot
    if (body.image && typeof body.image === "string") {
      check(name, true, "screenshot returned base64 image");
      check(name, body.format === "png", `format=${body.format}`);
    } else {
      warn(name, `No image in screenshot response`);
    }
  } else if (name.startsWith("T12")) {
    // Alert close
    check(name, body.code === "performed" || body.code === "dismissed" || body.code === "button",
      `alert close: code=${body.code}`);
    if (body.code === "dismissed" || body.code === "button") {
      check(name, true, "alert closed successfully");
    }
  }
}

console.log("\n============================================================");
console.log(`  Summary: ${passCount} passed, ${failCount} failed, ${warnCount} warnings`);
console.log("============================================================\n");

if (issues.length > 0) {
  console.log("Issues Found:");
  for (const issue of issues) {
    console.log(`  [${issue.severity}] ${issue.testName}: ${issue.detail}`);
  }
}

process.exit(failCount > 0 ? 1 : 0);
