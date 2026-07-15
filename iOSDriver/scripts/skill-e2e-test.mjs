#!/usr/bin/env node
// Comprehensive E2E test for skill development data collection.
// Tests all major command categories with various scenarios.
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
  pending.set(id, { method, params, timestamp });
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
      const { method, params, timestamp: reqTime } = pending.get(msg.id);
      pending.delete(msg.id);
      const respTime = Date.now() - startTime;
      const duration = respTime - reqTime;

      const isError = msg.error !== undefined || msg.result?.isError === true;
      results.push({
        id: msg.id,
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

// Test scenarios organized by category
const scenarios = {
  // 1. 基础连通性测试
  connectivity: [
    { name: "health_check", tool: "health_check", args: {} },
    { name: "health_check_duplicate", tool: "health_check", args: {} }, // 测试重复调用
  ],

  // 2. 基础命令测试
  basicCommands: [
    { name: "ping", tool: "call_action", args: { action: "ping" } },
    { name: "help", tool: "call_action", args: { action: "help" } },
    { name: "echo_simple", tool: "call_action", args: { action: "echo", data: { test: true } } },
    { name: "echo_complex", tool: "call_action", args: { action: "echo", data: { nested: { deep: { value: 123 } }, array: [1, 2, 3] } } },
    { name: "info", tool: "call_action", args: { action: "info" } },
    { name: "device", tool: "call_action", args: { action: "device" } },
  ],

  // 3. UI 检查命令
  uiInspection: [
    { name: "ui_inspect_default", tool: "ui_inspect", args: {} },
    { name: "ui_inspect_with_hidden", tool: "ui_inspect", args: { includeHidden: true } },
    { name: "ui_inspect_max_depth", tool: "ui_inspect", args: { maxDepth: 10 } },
    { name: "ui_inspect_text_limit", tool: "ui_inspect", args: { textLimit: 50 } },
    { name: "ui_inspect_max_targets", tool: "ui_inspect", args: { maxTargets: 20 } },
    { name: "ui_screenshot_small", tool: "ui_screenshot", args: { maxDimension: 400 } },
    { name: "ui_screenshot_medium", tool: "ui_screenshot", args: { maxDimension: 800 } },
    { name: "ui_screenshot_large", tool: "ui_screenshot", args: { maxDimension: 1280 } },
    { name: "ui_topViewHierarchy_basic", tool: "ui_topViewHierarchy", args: { detailLevel: "basic" } },
    { name: "ui_topViewHierarchy_full", tool: "ui_topViewHierarchy", args: { detailLevel: "full" } },
  ],

  // 4. UI 等待命令
  uiWaiting: [
    { name: "wait_idle_short", tool: "ui_waitAny", args: { conditions: [{ id: "idle1", mode: "idle" }], timeoutMs: 500 } },
    { name: "wait_idle_medium", tool: "ui_waitAny", args: { conditions: [{ id: "idle2", mode: "idle" }], timeoutMs: 1000 } },
    { name: "wait_and_inspect_idle", tool: "wait_and_inspect", args: {
      conditions: [{ id: "idle3", mode: "idle" }],
      timeoutMs: 1000,
      inspectOptions: { maxDepth: 5 }
    }},
  ],

  // 5. 日志命令测试
  logging: [
    { name: "logs_mark", tool: "call_action", args: { action: "app.logs.mark" } },
    { name: "logs_read_all", tool: "call_action", args: { action: "app.logs.read", data: { limit: 20 } } },
    { name: "logs_read_stdout", tool: "call_action", args: { action: "app.logs.read", data: { sources: ["stdout"], limit: 10 } } },
    { name: "logs_read_stderr", tool: "call_action", args: { action: "app.logs.read", data: { sources: ["stderr"], limit: 10 } } },
    { name: "logs_read_oslog", tool: "call_action", args: { action: "app.logs.read", data: { sources: ["oslog"], limit: 10 } } },
    { name: "logs_read_bridge", tool: "call_action", args: { action: "app.logs.read", data: { sources: ["bridge"], limit: 10 } } },
  ],

  // 6. 错误处理测试
  errorHandling: [
    { name: "unknown_action", tool: "call_action", args: { action: "nonexistent.command" } },
    { name: "invalid_tool_name", tool: "invalid_tool_xyz", args: {} },
    { name: "missing_required_param", tool: "call_action", args: {} }, // 缺少 action
    { name: "invalid_json_structure", tool: "ui_inspect", args: { maxDepth: "not_a_number" } },
  ],

  // 7. 工具刷新测试
  toolRefresh: [
    { name: "refresh_tools", tool: "refresh_tools", args: {} },
    { name: "list_tools_after_refresh", tool: "tools/list", args: {} },
  ],

  // 8. 边界条件测试
  boundaryConditions: [
    { name: "echo_empty", tool: "call_action", args: { action: "echo", data: {} } },
    { name: "echo_large_payload", tool: "call_action", args: {
      action: "echo",
      data: {
        longText: "x".repeat(1000),
        array: Array(100).fill(0).map((_, i) => ({ id: i, value: `item_${i}` }))
      }
    }},
    { name: "ui_inspect_zero_depth", tool: "ui_inspect", args: { maxDepth: 0 } },
    { name: "ui_inspect_large_depth", tool: "ui_inspect", args: { maxDepth: 99 } },
    { name: "logs_read_zero_limit", tool: "call_action", args: { action: "app.logs.read", data: { limit: 0 } } },
    { name: "logs_read_large_limit", tool: "call_action", args: { action: "app.logs.read", data: { limit: 1000 } } },
  ],

  // 9. 性能基准测试（快速连续调用）
  performance: [
    { name: "rapid_ping_1", tool: "call_action", args: { action: "ping" }, delay: 0 },
    { name: "rapid_ping_2", tool: "call_action", args: { action: "ping" }, delay: 0 },
    { name: "rapid_ping_3", tool: "call_action", args: { action: "ping" }, delay: 0 },
    { name: "rapid_inspect_1", tool: "ui_inspect", args: {}, delay: 0 },
    { name: "rapid_inspect_2", tool: "ui_inspect", args: {}, delay: 0 },
  ]
};

// Execute test scenarios
async function runTests() {
  console.log("=== Starting Comprehensive E2E Test ===\n");

  // Initialize
  send("initialize", {
    protocolVersion: "2024-11-05",
    capabilities: {},
    clientInfo: { name: "skill-e2e-test", version: "1.0.0" }
  });
  await sleep(200);

  // List tools first
  send("tools/list", {});
  await sleep(300);

  // Run each category
  for (const [category, tests] of Object.entries(scenarios)) {
    console.log(`\n--- Category: ${category} ---`);
    for (const test of tests) {
      const delay = test.delay !== undefined ? test.delay : 300;
      console.log(`  Running: ${test.name}`);

      if (test.tool === "tools/list") {
        send("tools/list", {});
      } else {
        send("tools/call", { name: test.tool, arguments: test.args });
      }

      await sleep(delay);
    }
    await sleep(500); // Category separator
  }

  // Wait for all responses
  await sleep(3000);

  // Generate report
  generateReport();

  // Cleanup
  server.kill("SIGTERM");
  process.exit(0);
}

function generateReport() {
  console.log("\n\n=== Test Results Summary ===\n");

  const categorized = {};
  for (const [category, tests] of Object.entries(scenarios)) {
    categorized[category] = tests.map(t => {
      const result = results.find(r =>
        r.params?.name === t.tool ||
        (r.params?.name === "call_action" && r.params?.arguments?.action === t.args?.action)
      );
      return {
        name: t.name,
        tool: t.tool,
        args: t.args,
        success: result && !result.isError,
        duration: result?.duration,
        error: result?.isError ? result.result : null,
        result: result
      };
    });
  }

  // Statistics
  const totalTests = results.filter(r => r.method === "tools/call").length;
  const successTests = results.filter(r => r.method === "tools/call" && !r.isError).length;
  const failedTests = totalTests - successTests;
  const avgDuration = results.filter(r => r.method === "tools/call")
    .reduce((sum, r) => sum + r.duration, 0) / totalTests;

  console.log(`Total Tests: ${totalTests}`);
  console.log(`Successful: ${successTests} (${(successTests/totalTests*100).toFixed(1)}%)`);
  console.log(`Failed: ${failedTests} (${(failedTests/totalTests*100).toFixed(1)}%)`);
  console.log(`Average Duration: ${avgDuration.toFixed(0)}ms\n`);

  // Per-category breakdown
  for (const [category, tests] of Object.entries(categorized)) {
    const catSuccess = tests.filter(t => t.success).length;
    const catTotal = tests.length;
    console.log(`\n${category}: ${catSuccess}/${catTotal} passed`);

    tests.forEach(t => {
      const status = t.success ? "✓" : "✗";
      const duration = t.duration ? `${t.duration}ms` : "N/A";
      console.log(`  ${status} ${t.name} (${duration})`);
      if (!t.success && t.error) {
        const errMsg = typeof t.error === 'object' ? JSON.stringify(t.error).slice(0, 100) : String(t.error).slice(0, 100);
        console.log(`    Error: ${errMsg}`);
      }
    });
  }

  // Save detailed results
  const reportData = {
    summary: {
      totalTests,
      successTests,
      failedTests,
      successRate: (successTests/totalTests*100).toFixed(2) + "%",
      avgDuration: avgDuration.toFixed(2) + "ms",
      testDate: new Date().toISOString()
    },
    categories: categorized,
    rawResults: results.map(r => ({
      ...r,
      // Truncate large content for readability
      result: truncateContent(r.result, 500)
    }))
  };

  const reportPath = "docs/mcp-skill-e2e-test-report.json";
  writeFileSync(reportPath, JSON.stringify(reportData, null, 2));
  console.log(`\n✓ Detailed report saved to: ${reportPath}`);

  // Generate markdown summary
  generateMarkdownReport(reportData);
}

function generateMarkdownReport(data) {
  const md = [];
  md.push("# iOSDriver 端到端测试报告");
  md.push("");
  md.push(`> 测试时间：${data.summary.testDate}`);
  md.push("");
  md.push("## 测试概览");
  md.push("");
  md.push(`- **总测试数**：${data.summary.totalTests}`);
  md.push(`- **成功**：${data.summary.successTests}`);
  md.push(`- **失败**：${data.summary.failedTests}`);
  md.push(`- **成功率**：${data.summary.successRate}`);
  md.push(`- **平均响应时间**：${data.summary.avgDuration}`);
  md.push("");
  md.push("## 分类测试结果");
  md.push("");

  for (const [category, tests] of Object.entries(data.categories)) {
    const passed = tests.filter(t => t.success).length;
    const total = tests.length;
    md.push(`### ${category} (${passed}/${total})`);
    md.push("");
    md.push("| 测试名称 | 工具 | 状态 | 耗时 |");
    md.push("|---------|------|------|------|");

    tests.forEach(t => {
      const status = t.success ? "✓ 通过" : "✗ 失败";
      const duration = t.duration ? `${t.duration}ms` : "N/A";
      md.push(`| ${t.name} | ${t.tool} | ${status} | ${duration} |`);
    });
    md.push("");
  }

  md.push("## 关键发现");
  md.push("");
  md.push("### 性能数据");
  md.push("");

  const durations = Object.entries(data.categories).map(([cat, tests]) => {
    const validTests = tests.filter(t => t.duration);
    if (validTests.length === 0) return null;
    const avg = validTests.reduce((sum, t) => sum + t.duration, 0) / validTests.length;
    const min = Math.min(...validTests.map(t => t.duration));
    const max = Math.max(...validTests.map(t => t.duration));
    return { category: cat, avg, min, max, count: validTests.length };
  }).filter(Boolean);

  durations.forEach(d => {
    md.push(`- **${d.category}**：平均 ${d.avg.toFixed(0)}ms (最小 ${d.min}ms, 最大 ${d.max}ms, ${d.count} 次测试)`);
  });

  md.push("");
  md.push("### 常见错误模式");
  md.push("");

  const errors = [];
  for (const [category, tests] of Object.entries(data.categories)) {
    tests.filter(t => !t.success && t.error).forEach(t => {
      errors.push({ category, name: t.name, error: t.error });
    });
  }

  if (errors.length > 0) {
    errors.forEach(e => {
      const errCode = e.error?.code || "unknown";
      const errMsg = e.error?.message || JSON.stringify(e.error).slice(0, 100);
      md.push(`- **${e.category}/${e.name}**：\`${errCode}\` - ${errMsg}`);
    });
  } else {
    md.push("无错误");
  }

  md.push("");
  md.push("## Skill 设计建议");
  md.push("");
  md.push("### 基础命令 Skill");
  md.push("- 应包含：ping, help, echo, info, device");
  md.push(`- 平均响应时间：${durations.find(d => d.category === 'basicCommands')?.avg.toFixed(0) || 'N/A'}ms`);
  md.push("- 推荐用于：快速健康检查、获取设备信息");
  md.push("");
  md.push("### UI 检查 Skill");
  md.push("- 应包含：ui.inspect, ui.screenshot, ui.topViewHierarchy");
  md.push(`- 平均响应时间：${durations.find(d => d.category === 'uiInspection')?.avg.toFixed(0) || 'N/A'}ms`);
  md.push("- 推荐参数组合：");
  md.push("  - 快速检查：`{ maxDepth: 5, maxTargets: 20 }`");
  md.push("  - 详细分析：`{ includeHidden: true, maxDepth: 10 }`");
  md.push("  - 截图：`{ maxDimension: 800 }` 平衡质量和传输速度");
  md.push("");
  md.push("### 日志采集 Skill");
  md.push("- 应包含：app.logs.mark, app.logs.read");
  md.push(`- 平均响应时间：${durations.find(d => d.category === 'logging')?.avg.toFixed(0) || 'N/A'}ms`);
  md.push("- 推荐工作流：mark → 操作 → read (增量读取)");
  md.push("- 支持来源过滤：stdout, stderr, oslog, bridge");
  md.push("");
  md.push("### UI 等待 Skill");
  md.push("- 应包含：ui.waitAny, wait_and_inspect");
  md.push(`- 平均响应时间：${durations.find(d => d.category === 'uiWaiting')?.avg.toFixed(0) || 'N/A'}ms`);
  md.push("- 推荐超时配置：");
  md.push("  - 快速轮询：500-1000ms");
  md.push("  - 标准等待：2000-5000ms");
  md.push("  - 长时等待：10000ms+");
  md.push("");

  const mdPath = "docs/mcp-skill-e2e-test-report.md";
  writeFileSync(mdPath, md.join("\n"));
  console.log(`✓ Markdown report saved to: ${mdPath}`);
}

function truncateContent(obj, maxLen) {
  if (typeof obj === 'string') {
    return obj.length > maxLen ? obj.slice(0, maxLen) + "..." : obj;
  }
  if (Array.isArray(obj)) {
    return obj.length > 10 ? obj.slice(0, 10).concat(['...']) : obj;
  }
  if (typeof obj === 'object' && obj !== null) {
    const str = JSON.stringify(obj);
    if (str.length > maxLen) {
      return { _truncated: true, _preview: str.slice(0, maxLen) + "..." };
    }
  }
  return obj;
}

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

// Run tests
runTests().catch(err => {
  console.error("Test execution failed:", err);
  process.exit(1);
});
