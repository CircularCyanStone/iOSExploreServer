#!/usr/bin/env node
// Real-world scenario testing for skill development.
// Tests actual workflow patterns that skills will implement.
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

// Real-world workflow scenarios
const scenarios = [
  {
    name: "Scenario 1: Agent Startup Initialization",
    description: "Agent 启动时的标准初始化流程",
    steps: [
      { tool: "health_check", args: {}, delay: 300 },
      { tool: "ui_inspect", args: { maxDepth: 5, maxTargets: 20 }, delay: 300 },
      { tool: "call_action", args: { action: "app.logs.mark" }, delay: 300 },
    ]
  },
  {
    name: "Scenario 2: Find and Tap Element",
    description: "查找元素并点击的典型流程",
    steps: [
      { tool: "ui_inspect", args: { maxDepth: 8 }, delay: 300 },
      // 假设找到了 path，实际会基于上一步结果
      { tool: "call_action", args: { action: "ui.screenshot", data: { maxDimension: 800 } }, delay: 300 },
    ]
  },
  {
    name: "Scenario 3: Wait for UI Change",
    description: "等待 UI 变化后继续操作",
    steps: [
      { tool: "wait_and_inspect", args: {
        conditions: [{ id: "stable", mode: "idle" }],
        timeoutMs: 2000,
        inspectOptions: { maxDepth: 5 }
      }, delay: 2500 },
    ]
  },
  {
    name: "Scenario 4: Debug Operation with Logs",
    description: "调试操作时捕获日志",
    steps: [
      { tool: "call_action", args: { action: "app.logs.mark" }, delay: 300 },
      { tool: "ui_screenshot", args: { maxDimension: 400 }, delay: 300 },
      { tool: "call_action", args: { action: "app.logs.read", data: { limit: 30 } }, delay: 300 },
    ]
  },
  {
    name: "Scenario 5: Rapid Status Polling",
    description: "快速轮询状态（性能压测）",
    steps: [
      { tool: "call_action", args: { action: "ping" }, delay: 50 },
      { tool: "call_action", args: { action: "ping" }, delay: 50 },
      { tool: "call_action", args: { action: "ping" }, delay: 50 },
      { tool: "call_action", args: { action: "ping" }, delay: 50 },
      { tool: "call_action", args: { action: "ping" }, delay: 50 },
    ]
  },
  {
    name: "Scenario 6: Inspect with Different Detail Levels",
    description: "不同详细程度的 UI 检查对比",
    steps: [
      { tool: "ui_inspect", args: { maxDepth: 3, maxTargets: 10 }, delay: 300 },
      { tool: "ui_inspect", args: { maxDepth: 8, maxTargets: 50 }, delay: 300 },
      { tool: "ui_inspect", args: { includeHidden: true, maxDepth: 10 }, delay: 300 },
    ]
  },
  {
    name: "Scenario 7: Screenshot Quality Comparison",
    description: "不同尺寸截图的性能对比",
    steps: [
      { tool: "ui_screenshot", args: { maxDimension: 400 }, delay: 300 },
      { tool: "ui_screenshot", args: { maxDimension: 800 }, delay: 300 },
      { tool: "ui_screenshot", args: { maxDimension: 1280 }, delay: 300 },
    ]
  },
  {
    name: "Scenario 8: Log Source Filtering",
    description: "按日志来源过滤的实战用法",
    steps: [
      { tool: "call_action", args: { action: "app.logs.read", data: { sources: ["stdout"], limit: 10 } }, delay: 300 },
      { tool: "call_action", args: { action: "app.logs.read", data: { sources: ["bridge"], limit: 10 } }, delay: 300 },
      { tool: "call_action", args: { action: "app.logs.read", data: { sources: ["stdout", "stderr", "bridge"], limit: 20 } }, delay: 300 },
    ]
  },
  {
    name: "Scenario 9: Complete Page Navigation Flow",
    description: "完整的页面导航流程（模拟）",
    steps: [
      { tool: "ui_inspect", args: {}, delay: 300 },
      { tool: "ui_screenshot", args: { maxDimension: 800 }, delay: 300 },
      // 实际会有 ui.tap，这里用 inspect 代替演示流程
      { tool: "wait_and_inspect", args: {
        conditions: [{ id: "idle", mode: "idle" }],
        timeoutMs: 1000
      }, delay: 1500 },
      { tool: "ui_screenshot", args: { maxDimension: 800 }, delay: 300 },
    ]
  },
  {
    name: "Scenario 10: Error Recovery Pattern",
    description: "错误处理和恢复流程",
    steps: [
      { tool: "call_action", args: { action: "unknown.command" }, delay: 300 },
      { tool: "health_check", args: {}, delay: 300 },
      { tool: "call_action", args: { action: "ping" }, delay: 300 },
    ]
  }
];

async function runScenarios() {
  console.log("=== Real-World Scenario Testing ===\n");

  // Initialize
  send("initialize", {
    protocolVersion: "2024-11-05",
    capabilities: {},
    clientInfo: { name: "scenario-test", version: "1.0.0" }
  });
  await sleep(200);

  let scenarioId = 0;
  for (const scenario of scenarios) {
    scenarioId++;
    console.log(`\n[Scenario ${scenarioId}/${scenarios.length}] ${scenario.name}`);
    console.log(`  ${scenario.description}`);

    const scenarioStart = Date.now() - startTime;
    for (let i = 0; i < scenario.steps.length; i++) {
      const step = scenario.steps[i];
      console.log(`  Step ${i + 1}/${scenario.steps.length}: ${step.tool}`);

      send("tools/call", { name: step.tool, arguments: step.args });
      await sleep(step.delay);
    }
    const scenarioEnd = Date.now() - startTime;
    console.log(`  ✓ Completed in ${scenarioEnd - scenarioStart}ms`);

    await sleep(500); // Pause between scenarios
  }

  // Wait for final responses
  await sleep(2000);

  // Generate report
  generateReport();

  // Cleanup
  server.kill("SIGTERM");
  process.exit(0);
}

function generateReport() {
  console.log("\n\n=== Scenario Test Results ===\n");

  const scenarioResults = [];
  let currentScenarioIdx = 0;

  for (const scenario of scenarios) {
    const stepResults = [];
    for (let i = 0; i < scenario.steps.length; i++) {
      const step = scenario.steps[i];
      // Find matching result
      const result = results.find(r =>
        r.params?.name === step.tool &&
        r.method === "tools/call"
      );

      stepResults.push({
        step: i + 1,
        tool: step.tool,
        args: step.args,
        success: result && !result.isError,
        duration: result?.duration,
        result: result
      });
    }

    const totalDuration = stepResults.reduce((sum, r) => sum + (r.duration || 0), 0);
    const successSteps = stepResults.filter(r => r.success).length;

    scenarioResults.push({
      id: ++currentScenarioIdx,
      name: scenario.name,
      description: scenario.description,
      steps: stepResults,
      totalSteps: scenario.steps.length,
      successSteps,
      totalDuration,
      success: successSteps === scenario.steps.length
    });

    const status = successSteps === scenario.steps.length ? "✓" : "✗";
    console.log(`${status} Scenario ${currentScenarioIdx}: ${scenario.name}`);
    console.log(`  Steps: ${successSteps}/${scenario.steps.length} | Duration: ${totalDuration}ms`);

    if (successSteps < scenario.steps.length) {
      stepResults.filter(s => !s.success).forEach(s => {
        console.log(`  ✗ Step ${s.step} failed: ${s.tool}`);
      });
    }
  }

  // Statistics
  const totalScenarios = scenarioResults.length;
  const successScenarios = scenarioResults.filter(s => s.success).length;
  const totalSteps = scenarioResults.reduce((sum, s) => sum + s.totalSteps, 0);
  const successSteps = scenarioResults.reduce((sum, s) => sum + s.successSteps, 0);
  const avgDuration = scenarioResults.reduce((sum, s) => sum + s.totalDuration, 0) / totalScenarios;

  console.log(`\n=== Summary ===`);
  console.log(`Scenarios: ${successScenarios}/${totalScenarios} passed (${(successScenarios/totalScenarios*100).toFixed(1)}%)`);
  console.log(`Total Steps: ${successSteps}/${totalSteps} passed (${(successSteps/totalSteps*100).toFixed(1)}%)`);
  console.log(`Average Scenario Duration: ${avgDuration.toFixed(0)}ms`);

  // Save report
  const reportData = {
    summary: {
      totalScenarios,
      successScenarios,
      successRate: (successScenarios/totalScenarios*100).toFixed(2) + "%",
      totalSteps,
      successSteps,
      stepSuccessRate: (successSteps/totalSteps*100).toFixed(2) + "%",
      avgScenarioDuration: avgDuration.toFixed(2) + "ms",
      testDate: new Date().toISOString()
    },
    scenarios: scenarioResults
  };

  const jsonPath = "docs/scenario-test-report.json";
  writeFileSync(jsonPath, JSON.stringify(reportData, null, 2));
  console.log(`\n✓ Report saved to: ${jsonPath}`);

  generateMarkdown(reportData);
}

function generateMarkdown(data) {
  const md = [];
  md.push("# iOSDriver 真实场景测试报告");
  md.push("");
  md.push(`> 测试时间：${data.summary.testDate}`);
  md.push("");
  md.push("## 测试概览");
  md.push("");
  md.push(`- **场景数**：${data.summary.totalScenarios}`);
  md.push(`- **场景成功率**：${data.summary.successRate}`);
  md.push(`- **总步骤数**：${data.summary.totalSteps}`);
  md.push(`- **步骤成功率**：${data.summary.stepSuccessRate}`);
  md.push(`- **平均场景耗时**：${data.summary.avgScenarioDuration}`);
  md.push("");
  md.push("## 场景详情");
  md.push("");

  for (const scenario of data.scenarios) {
    const status = scenario.success ? "✓" : "✗";
    md.push(`### ${status} Scenario ${scenario.id}: ${scenario.name}`);
    md.push("");
    md.push(`**描述**：${scenario.description}`);
    md.push("");
    md.push(`**结果**：${scenario.successSteps}/${scenario.totalSteps} 步骤成功，总耗时 ${scenario.totalDuration}ms`);
    md.push("");
    md.push("| 步骤 | 工具 | 状态 | 耗时 |");
    md.push("|------|------|------|------|");

    scenario.steps.forEach(step => {
      const status = step.success ? "✓" : "✗";
      const duration = step.duration ? `${step.duration}ms` : "N/A";
      md.push(`| ${step.step} | ${step.tool} | ${status} | ${duration} |`);
    });
    md.push("");
  }

  md.push("## Skill 实现参考");
  md.push("");
  md.push("### 典型工作流耗时");
  md.push("");

  data.scenarios.forEach(s => {
    md.push(`- **${s.name}**：${s.totalDuration}ms (${s.totalSteps} 步骤)`);
  });

  md.push("");
  md.push("### 推荐步骤组合");
  md.push("");
  md.push("基于成功场景，推荐以下步骤组合：");
  md.push("");

  const successful = data.scenarios.filter(s => s.success);
  successful.forEach(s => {
    md.push(`**${s.name}**`);
    md.push("```");
    s.steps.forEach(step => {
      md.push(`${step.step}. ${step.tool} (${step.duration}ms)`);
    });
    md.push("```");
    md.push("");
  });

  const mdPath = "docs/scenario-test-report.md";
  writeFileSync(mdPath, md.join("\n"));
  console.log(`✓ Markdown report saved to: ${mdPath}`);
}

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

// Run scenarios
runScenarios().catch(err => {
  console.error("Scenario execution failed:", err);
  process.exit(1);
});
