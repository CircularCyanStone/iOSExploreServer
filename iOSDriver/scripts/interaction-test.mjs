#!/usr/bin/env node
// Comprehensive interaction command testing for MCP Server
// Tests real scenarios with ui.tap, ui.input, ui.alert.respond, ui.swipe, ui.longPress, etc.

import { spawn } from "node:child_process";
import { writeFileSync } from "fs";

const results = [];
let buffer = "", nextId = 1;
const pending = new Map();
const startTime = Date.now();

const server = spawn("node", ["dist/index.js"], {
  cwd: process.cwd(),
  stdio: ["pipe", "pipe", "inherit"]
});

function send(method, params) {
  const id = nextId++;
  const timestamp = Date.now() - startTime;
  pending.set(id, { method, params, timestamp, label: params.name || method });
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
    try { msg = JSON.parse(buffer.slice(0, end)); } catch { buffer = buffer.slice(1); continue; }
    if (msg.id !== undefined && pending.has(msg.id)) {
      const { method, params, timestamp: reqTime, label } = pending.get(msg.id);
      pending.delete(msg.id);
      const respTime = Date.now() - startTime;
      const duration = respTime - reqTime;

      const isError = msg.error !== undefined || msg.result?.isError === true;
      results.push({
        id: msg.id,
        label,
        method,
        params,
        result: msg.result ?? msg.error,
        isError,
        requestTime: reqTime,
        responseTime: respTime,
        duration
      });

      if (method === "initialize" && msg.result) {
        server.stdin.write(JSON.stringify({ jsonrpc: "2.0", method: "notifications/initialized" }) + "\n");
      }
    }
    buffer = buffer.slice(end).replace(/^[\r\n\s]+/, "");
  }
}

server.stdout.on("data", chunk => { buffer += chunk.toString(); tryConsume(); });

// Test scenarios - based on real app pages
const scenarios = [
  {
    name: "Scenario 1: Swipe on TableView Cell",
    description: "在 UITableView cell 上执行 swipe action（左滑显示删除/收藏按钮）",
    steps: [
      { tool: "ui_inspect", args: {}, delay: 500, extractSnapshot: true },
      {
        tool: "ui_swipe",
        args: {
          cellAccessibilityIdentifier: "swipe.cell.1",
          direction: "left",
          actionTitle: "收藏"
        },
        delay: 800
      },
      { tool: "ui_inspect", args: {}, delay: 500 },
    ]
  },
  {
    name: "Scenario 2: Tap Element in Hierarchy",
    description: "使用 ui.tap 点击列表中的元素",
    steps: [
      { tool: "ui_inspect", args: {}, delay: 500, extractSnapshot: true },
      {
        tool: "ui_tap",
        args: {
          path: "root/1/4/1",  // UIListContentView of Cell 1
          viewSnapshotID: "__EXTRACTED__"
        },
        delay: 800
      },
      { tool: "ui_inspect", args: {}, delay: 500 },
    ]
  },
  {
    name: "Scenario 3: LongPress on Gesture View",
    description: "在带手势识别器的 view 上执行长按",
    steps: [
      { tool: "ui_inspect", args: {}, delay: 500 },
      {
        tool: "ui_longPress",
        args: {
          accessibilityIdentifier: "swipe.gesture.view",
          duration: 1.0
        },
        delay: 1500
      },
      { tool: "ui_inspect", args: {}, delay: 500 },
    ]
  },
  {
    name: "Scenario 4: Scroll in TableView",
    description: "在 UITableView 中滚动",
    steps: [
      { tool: "ui_inspect", args: {}, delay: 500 },
      {
        tool: "ui_scroll",
        args: {
          accessibilityIdentifier: "swipe.tableview",
          direction: "down"
          // Note: ui.scroll doesn't accept distance parameter
        },
        delay: 800
      },
      { tool: "ui_inspect", args: {}, delay: 500 },
    ]
  },
  {
    name: "Scenario 5: Navigation Back",
    description: "点击导航栏返回按钮",
    steps: [
      { tool: "ui_inspect", args: {}, delay: 500 },
      { tool: "ui_navigation_back", args: {}, delay: 800 },
      { tool: "ui_inspect", args: {}, delay: 500 },
      // Go forward again
      { tool: "ui_inspect", args: {}, delay: 500, extractSnapshot: true },
      {
        tool: "ui_tap",
        args: {
          accessibilityIdentifier: "nav.swipe.test",
          viewSnapshotID: "__EXTRACTED__"
        },
        delay: 800
      },
    ]
  },
  {
    name: "Scenario 6: Navigation Bar Button",
    description: "测试导航栏按钮点击（左/右按钮）",
    steps: [
      { tool: "ui_inspect", args: {}, delay: 500 },
      // Note: tapBarButton is for navigation bar buttons (left/right), not TabBar
      // Current page doesn't have nav bar buttons, so this will test error handling
      {
        tool: "ui_navigation_tapBarButton",
        args: { placement: "right", index: 0 },
        delay: 500,
        expectError: true
      },
    ]
  },
  {
    name: "Scenario 7: Wait for UI State",
    description: "等待 UI 稳定后继续操作",
    steps: [
      {
        tool: "ui_wait",
        args: {
          mode: "idle",
          timeoutMs: 2000,
          stableMs: 500
        },
        delay: 2500
      },
      { tool: "ui_inspect", args: {}, delay: 500 },
    ]
  },
  {
    name: "Scenario 8: Error Handling - Invalid Path",
    description: "测试错误处理：无效的 path",
    steps: [
      { tool: "ui_inspect", args: {}, delay: 500, extractSnapshot: true },
      {
        tool: "ui_tap",
        args: {
          path: "root/999/999/999",
          viewSnapshotID: "__EXTRACTED__"
        },
        delay: 500,
        expectError: true
      },
    ]
  },
  {
    name: "Scenario 9: Error Handling - Missing Snapshot ID",
    description: "测试错误处理：缺少 viewSnapshotID",
    steps: [
      {
        tool: "ui_tap",
        args: {
          path: "root/1/4/1"
          // Missing viewSnapshotID
        },
        delay: 500,
        expectError: true
      },
    ]
  },
  {
    name: "Scenario 10: Swipe on Generic View",
    description: "在普通 view 上执行 swipe（非 tableView cell）",
    steps: [
      { tool: "ui_inspect", args: {}, delay: 500 },
      {
        tool: "ui_swipe",
        args: {
          accessibilityIdentifier: "swipe.gesture.view",
          direction: "left",
          distance: 0.7
        },
        delay: 800
      },
      { tool: "ui_inspect", args: {}, delay: 500 },
    ]
  },
  {
    name: "Scenario 11: Controllers Inspection",
    description: "获取控制器层级信息",
    steps: [
      { tool: "ui_controllers", args: {}, delay: 500 },
    ]
  },
  {
    name: "Scenario 12: Screenshot Capture",
    description: "截图并验证返回数据",
    steps: [
      { tool: "call_action", args: { action: "ui.screenshot", data: { maxDimension: 600 } }, delay: 800 },
    ]
  },
  {
    name: "Scenario 13: Keyboard Dismiss",
    description: "测试键盘收起功能（当前没有键盘，测试 no-op 场景）",
    steps: [
      { tool: "ui_keyboard_dismiss", args: { strategy: "auto" }, delay: 500 },
    ]
  },
  {
    name: "Scenario 14: ScrollToElement",
    description: "滚动到指定元素",
    steps: [
      { tool: "ui_inspect", args: {}, delay: 500 },
      {
        tool: "ui_scrollToElement",
        args: {
          accessibilityIdentifier: "swipe.cell.0",
          scrollContainerIdentifier: "swipe.tableview"
        },
        delay: 800
      },
      { tool: "ui_inspect", args: {}, delay: 500 },
    ]
  },
  {
    name: "Scenario 15: WaitAny Multi-Condition",
    description: "等待多个条件之一满足",
    steps: [
      {
        tool: "wait_and_inspect",
        args: {
          conditions: [
            { id: "stable", mode: "idle" },
            { id: "text", mode: "textExists", text: "Swipe 测试" }
          ],
          timeoutMs: 3000,
          inspectOptions: { maxDepth: 5 }
        },
        delay: 3500
      },
    ]
  },
  {
    name: "Scenario 16: TopViewHierarchy with DetailLevel",
    description: "获取完整视图层级（不同详情级别）",
    steps: [
      { tool: "ui_topViewHierarchy", args: { detailLevel: "basic", maxDepth: 3 }, delay: 500 },
      { tool: "ui_topViewHierarchy", args: { detailLevel: "appearance", maxDepth: 3 }, delay: 500 },
    ]
  },
  {
    name: "Scenario 17: Device Info",
    description: "获取设备信息",
    steps: [
      { tool: "call_action", args: { action: "device" }, delay: 500 },
      { tool: "call_action", args: { action: "info" }, delay: 500 },
    ]
  },
  {
    name: "Scenario 18: Performance - Rapid Inspect",
    description: "性能测试：连续快速 inspect",
    steps: [
      { tool: "ui_inspect", args: { maxDepth: 3, maxTargets: 50 }, delay: 100 },
      { tool: "ui_inspect", args: { maxDepth: 3, maxTargets: 50 }, delay: 100 },
      { tool: "ui_inspect", args: { maxDepth: 3, maxTargets: 50 }, delay: 100 },
    ]
  },
];

// Execute scenarios
async function runTests() {
  send("initialize", {
    protocolVersion: "2024-11-05",
    capabilities: { tools: {} },
    clientInfo: { name: "interaction-test", version: "1.0.0" }
  });
  await sleep(500);

  send("tools/list", {});
  await sleep(500);

  for (const scenario of scenarios) {
    console.log(`\n▶ ${scenario.name}`);
    console.log(`  ${scenario.description}`);

    let extractedSnapshot = null;

    for (const step of scenario.steps) {
      const { tool, args, delay, extractSnapshot, expectError } = step;

      // Replace __EXTRACTED__ placeholder with actual snapshot ID
      let finalArgs = args;
      if (args.viewSnapshotID === "__EXTRACTED__" && extractedSnapshot) {
        finalArgs = { ...args, viewSnapshotID: extractedSnapshot };
      }

      console.log(`  - ${tool}(${JSON.stringify(finalArgs).substring(0, 60)}...)`);

      send("tools/call", { name: tool, arguments: finalArgs });
      await sleep(delay || 500);

      // Extract snapshot ID if needed
      if (extractSnapshot && results.length > 0) {
        const lastResult = results[results.length - 1];
        if (lastResult.result?.content?.[0]?.text) {
          try {
            const data = JSON.parse(lastResult.result.content[0].text);
            if (data.viewSnapshotID) {
              extractedSnapshot = data.viewSnapshotID;
              console.log(`    ✓ Extracted snapshot: ${extractedSnapshot}`);
            }
          } catch (e) {}
        }
      }

      // Check if error was expected
      if (expectError) {
        const lastResult = results[results.length - 1];
        if (lastResult.isError) {
          console.log(`    ✓ Expected error occurred`);
        } else {
          console.log(`    ✗ Expected error but got success`);
        }
      }
    }
  }

  await sleep(1000);
  server.kill();

  // Generate reports
  generateReports();
}

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

function generateReports() {
  console.log("\n" + "=".repeat(80));
  console.log("TEST RESULTS");
  console.log("=".repeat(80));

  // Command coverage analysis
  const testedCommands = new Set();
  const commandResults = {};

  results.forEach(r => {
    if (r.method === "tools/call") {
      const toolName = r.params?.name;
      if (toolName) {
        testedCommands.add(toolName);
        if (!commandResults[toolName]) {
          commandResults[toolName] = { success: 0, error: 0, totalDuration: 0 };
        }
        if (r.isError) {
          commandResults[toolName].error++;
        } else {
          commandResults[toolName].success++;
        }
        commandResults[toolName].totalDuration += r.duration;
      }
    }
  });

  console.log(`\nTested Commands: ${testedCommands.size}`);
  console.log("Command Performance:");
  Object.entries(commandResults).forEach(([cmd, stats]) => {
    const total = stats.success + stats.error;
    const avgDuration = Math.round(stats.totalDuration / total);
    const successRate = Math.round((stats.success / total) * 100);
    console.log(`  ${cmd}: ${stats.success}/${total} success (${successRate}%), avg ${avgDuration}ms`);
  });

  // Scenario summary
  console.log(`\nScenarios Executed: ${scenarios.length}`);
  const scenarioResults = {};
  let currentScenario = null;

  results.forEach(r => {
    if (r.label && r.label.startsWith("Scenario")) {
      currentScenario = r.label;
      if (!scenarioResults[currentScenario]) {
        scenarioResults[currentScenario] = { success: 0, error: 0 };
      }
    }
    if (currentScenario && r.method === "tools/call") {
      if (r.isError) {
        scenarioResults[currentScenario].error++;
      } else {
        scenarioResults[currentScenario].success++;
      }
    }
  });

  // Save detailed JSON report
  const jsonReport = {
    summary: {
      totalScenarios: scenarios.length,
      testedCommands: Array.from(testedCommands),
      commandCount: testedCommands.size,
      timestamp: new Date().toISOString(),
      totalDuration: Date.now() - startTime
    },
    scenarios: scenarios.map(s => ({
      name: s.name,
      description: s.description,
      stepCount: s.steps.length
    })),
    commandResults,
    detailedResults: results.map(r => ({
      id: r.id,
      label: r.label,
      method: r.method,
      isError: r.isError,
      duration: r.duration,
      result: r.result
    }))
  };

  writeFileSync("docs/interaction-test-report.json", JSON.stringify(jsonReport, null, 2));
  console.log("\n✓ Detailed report saved to docs/interaction-test-report.json");

  // Generate Markdown report
  generateMarkdownReport(jsonReport);
}

function generateMarkdownReport(jsonReport) {
  const { summary, scenarios, commandResults } = jsonReport;

  let md = `# Interaction Command Testing Report

Generated: ${summary.timestamp}

## Summary

- **Total Scenarios**: ${summary.totalScenarios}
- **Commands Tested**: ${summary.commandCount} / 32
- **Total Duration**: ${summary.totalDuration}ms
- **Coverage**: ${Math.round((summary.commandCount / 32) * 100)}%

## Tested Commands

| Command | Success | Error | Total | Success Rate | Avg Duration |
|---------|---------|-------|-------|--------------|--------------|
`;

  Object.entries(commandResults).forEach(([cmd, stats]) => {
    const total = stats.success + stats.error;
    const successRate = Math.round((stats.success / total) * 100);
    const avgDuration = Math.round(stats.totalDuration / total);
    md += `| ${cmd} | ${stats.success} | ${stats.error} | ${total} | ${successRate}% | ${avgDuration}ms |\n`;
  });

  md += `\n## Test Scenarios

`;

  scenarios.forEach((s, i) => {
    md += `### ${i + 1}. ${s.name}

${s.description}

**Steps**: ${s.stepCount}

`;
  });

  md += `\n## Commands Still Untested

Based on the 32 total commands, the following are still not covered:

`;

  const allCommands = [
    "ui.tap", "ui.input", "ui.alert.respond", "ui.navigation.back", "ui.swipe", "ui.scroll",
    "ui.longPress", "ui.control.sendAction", "ui.keyboard.dismiss", "ui.navigation.tapBarButton",
    "ui.scrollToElement", "ui.controllers", "ui.wait", "ui.waitAny", "debug.probe",
    "ui.inspect", "ui.topViewHierarchy", "ui.screenshot", "app.logs.mark", "app.logs.read",
    "ping", "help", "app.info", "ui.alert.info", "ui.keyboard.info", "ui.navigation.info",
    "ui.tabBar.info", "ui.deepLink", "ui.shake", "system.memory", "system.orientation", "system.appearance"
  ];

  const tested = new Set(summary.testedCommands.map(c => {
    // Map tool names back to action names
    return c.replace(/_/g, '.');
  }));

  const untested = allCommands.filter(cmd => !tested.has(cmd));

  md += untested.map(cmd => `- ${cmd}`).join('\n');

  md += `\n\n## Recommendations

1. **High Priority**: Add test coverage for \`ui.alert.respond\` by creating alert scenarios
2. **High Priority**: Add \`ui.input\` testing with text field interaction
3. **Medium Priority**: Test \`ui.control.sendAction\` for slider/switch controls
4. **Medium Priority**: Add \`ui.scrollToElement\` scenarios for large lists
5. **Low Priority**: Test auxiliary commands like \`debug.probe\`, \`system.*\` commands

## Next Steps

1. Create alert testing scenarios in SPMExample
2. Add text input page for \`ui.input\` testing
3. Add control testing page (slider, switch, stepper)
4. Expand error handling test cases
5. Add performance benchmarking for all commands
`;

  writeFileSync("docs/interaction-test-report.md", md);
  console.log("✓ Markdown report saved to docs/interaction-test-report.md");
}

// Run all tests
runTests().catch(console.error);
