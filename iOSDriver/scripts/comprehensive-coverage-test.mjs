#!/usr/bin/env node

/**
 * 综合命令覆盖率测试 - 目标 90%+
 * 整合之前所有成功的测试
 */

import { setTimeout as delay } from 'timers/promises';
import { writeFile, mkdir } from 'fs/promises';
import { existsSync } from 'fs';
import { join } from 'path';

const BASE_URL = 'http://localhost:38321/';
const DELAY_MS = 300;

const testResults = {
  timestamp: new Date().toISOString(),
  summary: { total: 0, passed: 0, failed: 0, successRate: 0 },
  commands: {},
  details: []
};

const performanceStats = {};

async function sendCommand(action, payload = {}) {
  const startTime = Date.now();
  try {
    const response = await fetch(BASE_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ action, ...payload })
    });

    const duration = Date.now() - startTime;
    const data = await response.json();

    if (!performanceStats[action]) {
      performanceStats[action] = { times: [], min: Infinity, max: 0, avg: 0 };
    }
    performanceStats[action].times.push(duration);
    performanceStats[action].min = Math.min(performanceStats[action].min, duration);
    performanceStats[action].max = Math.max(performanceStats[action].max, duration);
    performanceStats[action].avg = performanceStats[action].times.reduce((a, b) => a + b, 0) / performanceStats[action].times.length;

    return { success: data.code === 'ok', data, duration, status: response.status };
  } catch (error) {
    const duration = Date.now() - startTime;
    return { success: false, error: error.message, duration };
  }
}

function recordTest(command, scenario, result, expected = true) {
  testResults.summary.total++;
  const passed = result.success === expected;
  if (passed) testResults.summary.passed++;
  else testResults.summary.failed++;

  if (!testResults.commands[command]) {
    testResults.commands[command] = { total: 0, passed: 0, failed: 0 };
  }
  testResults.commands[command].total++;
  if (passed) testResults.commands[command].passed++;
  else testResults.commands[command].failed++;

  testResults.details.push({
    command, scenario, passed, expected,
    actual: result.success,
    duration: result.duration,
    response: result.data || result.error,
    timestamp: new Date().toISOString()
  });

  const status = passed ? '✅' : '❌';
  console.log(`${status} ${command}: ${scenario} (${result.duration}ms)`);
}

async function ensureHomePage() {
  for (let i = 0; i < 3; i++) {
    const result = await sendCommand('ui.navigation.back');
    await delay(200);
    if (!result.success) break;
  }
  await delay(300);
}

async function navigateToPage(buttonText) {
  await ensureHomePage();
  await sendCommand('ui.wait', { condition: 'stable', timeout: 2 });
  await delay(300);
  const result = await sendCommand('ui.tap', { match: 'text', value: buttonText });
  await delay(600);
  return result;
}

/**
 * 测试所有基础命令
 */
async function testAllBasicCommands() {
  console.log('\n=== 测试基础命令 (6 个) ===');

  const commands = [
    { action: 'ping', scenario: '心跳检测', args: {} },
    { action: 'echo', scenario: '回显消息', args: { message: 'test' } },
    { action: 'greet', scenario: '问候', args: {} },
    { action: 'info', scenario: '服务器信息', args: {} },
    { action: 'device', scenario: '设备信息', args: {} },
    { action: 'help', scenario: '帮助信息', args: {} }
  ];

  for (const cmd of commands) {
    const result = await sendCommand(cmd.action, cmd.args);
    recordTest(cmd.action, cmd.scenario, result, true);
    await delay(DELAY_MS);
  }
}

/**
 * 测试所有 debug 命令
 */
async function testAllDebugCommands() {
  console.log('\n=== 测试 Debug 命令 (7 个) ===');

  const commands = [
    { action: 'debug.probe', scenario: '调试探测', args: {} },
    { action: 'debug.emitStdout', scenario: 'stdout 输出', args: { message: 'test' } },
    { action: 'debug.emitStderr', scenario: 'stderr 输出', args: { message: 'test' } },
    { action: 'debug.emitNSLog', scenario: 'NSLog 输出', args: { message: 'test' } },
    { action: 'debug.emitOSLog', scenario: 'OSLog 输出', args: { message: 'test' } },
    { action: 'debug.emitLogger', scenario: 'Logger 输出', args: { message: 'test', level: 'info' } },
    { action: 'debug.emitAppLog', scenario: 'AppLog 输出', args: { message: 'test', level: 'debug' } }
  ];

  for (const cmd of commands) {
    const result = await sendCommand(cmd.action, cmd.args);
    recordTest(cmd.action, cmd.scenario, result, true);
    await delay(DELAY_MS);
  }
}

/**
 * 测试日志命令
 */
async function testAllLogCommands() {
  console.log('\n=== 测试日志命令 (2 个) ===');

  let result = await sendCommand('app.logs.mark', { label: 'test' });
  recordTest('app.logs.mark', '日志标记', result, true);
  await delay(DELAY_MS);

  result = await sendCommand('app.logs.read', { source: 'oslog', limit: 10 });
  recordTest('app.logs.read', '读取日志', result, true);
  await delay(DELAY_MS);
}

/**
 * 测试所有 UI 基础命令
 */
async function testAllUICommands() {
  console.log('\n=== 测试 UI 命令 (13+ 个) ===');

  await ensureHomePage();

  // 1. ui.topViewHierarchy
  let result = await sendCommand('ui.topViewHierarchy');
  recordTest('ui.topViewHierarchy', '顶层视图', result, true);
  await delay(DELAY_MS);

  // 2. ui.controllers
  result = await sendCommand('ui.controllers');
  recordTest('ui.controllers', '控制器层级', result, true);
  await delay(DELAY_MS);

  // 3. ui.inspect
  result = await sendCommand('ui.inspect', { mode: 'minimal' });
  recordTest('ui.inspect', 'UI 检查', result, true);
  await delay(DELAY_MS);

  // 4. ui.screenshot
  result = await sendCommand('ui.screenshot', { format: 'png', scale: 0.5 });
  recordTest('ui.screenshot', '截图', result, true);
  await delay(DELAY_MS);

  // 5. ui.wait
  result = await sendCommand('ui.wait', { condition: 'stable', timeout: 2 });
  recordTest('ui.wait', '等待稳定', result, true);
  await delay(DELAY_MS);

  // 6. ui.waitAny
  result = await sendCommand('ui.waitAny', {
    conditions: [
      { condition: 'visible', match: 'text', value: 'iOSExploreServer' }
    ],
    timeout: 2
  });
  recordTest('ui.waitAny', '等待任一条件', result, true);
  await delay(DELAY_MS);

  // 导航到按钮测试页
  await navigateToPage('🔘 按钮点击测试');
  await delay(500);

  // 7. ui.tap
  result = await sendCommand('ui.tap', { match: 'text', value: 'Tap Me' });
  recordTest('ui.tap', '点击按钮', result, true);
  await delay(DELAY_MS);

  // 8. ui.navigation.back
  result = await sendCommand('ui.navigation.back');
  recordTest('ui.navigation.back', '返回导航', result, true);
  await delay(DELAY_MS);

  // 导航到输入测试页
  await navigateToPage('⌨️ 文本输入测试');
  await delay(500);

  // 9. ui.input
  result = await sendCommand('ui.input', {
    match: 'accessibilityIdentifier',
    value: 'text.field.main',
    text: 'Hello Test'
  });
  recordTest('ui.input', '文本输入', result, true);
  await delay(DELAY_MS);

  // 10. ui.keyboard.dismiss
  result = await sendCommand('ui.keyboard.dismiss');
  recordTest('ui.keyboard.dismiss', '关闭键盘', result, true);
  await delay(DELAY_MS);

  // 返回主页
  await ensureHomePage();

  // 导航到滚动测试页
  await navigateToPage('📜 滚动测试');
  await delay(500);

  // 11. ui.scroll
  result = await sendCommand('ui.scroll', {
    match: 'accessibilityIdentifier',
    value: 'scroll.tableview',
    direction: 'down',
    distance: 0.3
  });
  recordTest('ui.scroll', '滚动操作', result, true);
  await delay(DELAY_MS);

  // 12. ui.swipe
  result = await sendCommand('ui.swipe', {
    match: 'accessibilityIdentifier',
    value: 'swipe.tableview',
    direction: 'up',
    distance: 0.5
  });
  recordTest('ui.swipe', '滑动操作', result, true);
  await delay(DELAY_MS);

  // 13. ui.longPress
  result = await sendCommand('ui.longPress', {
    match: 'text',
    value: 'Item 10',
    duration: 500
  });
  recordTest('ui.longPress', '长按操作', result, true);
  await delay(DELAY_MS);

  // 返回主页
  await ensureHomePage();

  // 导航到 Alert 测试页
  await navigateToPage('🚨 Alert 测试');
  await delay(500);

  // 点击触发 alert
  result = await sendCommand('ui.tap', { match: 'text', value: 'Show Alert' });
  await delay(500);

  // 14. ui.alert.respond
  result = await sendCommand('ui.alert.respond', { button: 'OK' });
  recordTest('ui.alert.respond', 'Alert 响应', result, true);
  await delay(DELAY_MS);

  // 返回主页
  await ensureHomePage();

  // 导航到 Segmented Control 测试页
  await navigateToPage('🎛 Segmented Control');
  await delay(500);

  // 15. ui.control.sendAction
  result = await sendCommand('ui.control.sendAction', {
    match: 'accessibilityIdentifier',
    value: 'segmented.control',
    action: 'primaryActionTriggered'
  });
  recordTest('ui.control.sendAction', '控件动作', result, true);
  await delay(DELAY_MS);

  await ensureHomePage();
}

/**
 * 生成报告
 */
async function generateReports() {
  console.log('\n=== 生成测试报告 ===');

  testResults.summary.successRate = (testResults.summary.passed / testResults.summary.total * 100).toFixed(2);

  const jsonReport = {
    ...testResults,
    performance: performanceStats,
    coverage: {
      tested: Object.keys(testResults.commands).length,
      total: 32,
      percentage: (Object.keys(testResults.commands).length / 32 * 100).toFixed(2)
    }
  };

  const docsDir = join(process.cwd(), 'docs');
  if (!existsSync(docsDir)) {
    await mkdir(docsDir, { recursive: true });
  }

  // JSON 报告
  const jsonPath = join(docsDir, 'comprehensive-coverage-report.json');
  await writeFile(jsonPath, JSON.stringify(jsonReport, null, 2));
  console.log(`✅ JSON: ${jsonPath}`);

  // Markdown 报告
  const mdContent = generateMarkdownReport(jsonReport);
  const mdPath = join(docsDir, 'comprehensive-coverage-report.md');
  await writeFile(mdPath, mdContent);
  console.log(`✅ MD: ${mdPath}`);

  // 覆盖率总结
  const coverageContent = generateCoverageSummary(jsonReport);
  const coveragePath = join(docsDir, 'FINAL-COMMAND-COVERAGE-90PERCENT.md');
  await writeFile(coveragePath, coverageContent);
  console.log(`✅ 覆盖率: ${coveragePath}`);

  return jsonReport;
}

function generateMarkdownReport(report) {
  let md = `# 综合命令覆盖率测试报告\n\n`;
  md += `**测试时间**: ${new Date(report.timestamp).toLocaleString('zh-CN')}\n\n`;

  md += `## 📊 总体情况\n\n`;
  md += `| 指标 | 数值 |\n|------|------|\n`;
  md += `| 命令覆盖率 | **${report.coverage.tested}/${report.coverage.total} (${report.coverage.percentage}%)** |\n`;
  md += `| 目标 | 90% (29/32) |\n`;
  md += `| 状态 | ${parseFloat(report.coverage.percentage) >= 90 ? '✅ 已达成' : '⚠️ 进行中'} |\n`;
  md += `| 总测试数 | ${report.summary.total} |\n`;
  md += `| 成功率 | ${report.summary.successRate}% |\n\n`;

  md += `## ✅ 已测试命令 (${report.coverage.tested})\n\n`;
  Object.keys(report.commands).sort().forEach((cmd, i) => {
    const stats = report.commands[cmd];
    md += `${i + 1}. \`${cmd}\` - ${stats.passed}/${stats.total} 通过\n`;
  });
  md += `\n`;

  md += `## ⚡ 性能数据（前 10 最快）\n\n`;
  md += `| 命令 | 平均 (ms) |\n|------|----------|\n`;
  const topPerf = Object.entries(performanceStats)
    .sort((a, b) => a[1].avg - b[1].avg)
    .slice(0, 10);
  topPerf.forEach(([cmd, perf]) => {
    md += `| \`${cmd}\` | ${perf.avg.toFixed(1)} |\n`;
  });
  md += `\n`;

  return md;
}

function generateCoverageSummary(report) {
  const allCommands = [
    'ping', 'echo', 'greet', 'info', 'device', 'help',
    'debug.probe', 'debug.emitStdout', 'debug.emitStderr', 'debug.emitNSLog',
    'debug.emitOSLog', 'debug.emitLogger', 'debug.emitAppLog',
    'app.logs.mark', 'app.logs.read',
    'ui.topViewHierarchy', 'ui.inspect', 'ui.tap', 'ui.input', 'ui.screenshot',
    'ui.keyboard.dismiss', 'ui.scroll', 'ui.swipe', 'ui.longPress',
    'ui.navigation.back', 'ui.navigation.tapBarButton', 'ui.scrollToElement',
    'ui.wait', 'ui.waitAny', 'ui.controllers', 'ui.control.sendAction', 'ui.alert.respond'
  ];

  const tested = Object.keys(report.commands);
  const untested = allCommands.filter(cmd => !tested.includes(cmd));

  let md = `# 最终命令覆盖率报告\n\n`;
  md += `**生成时间**: ${new Date().toLocaleString('zh-CN')}\n\n`;

  md += `## 🎯 覆盖率目标\n\n`;
  md += `- **目标**: 90% (29/32 命令)\n`;
  md += `- **实际**: ${report.coverage.percentage}% (${report.coverage.tested}/32 命令)\n`;
  md += `- **状态**: ${parseFloat(report.coverage.percentage) >= 90 ? '✅ **已达成**' : '⚠️ 进行中'}\n\n`;

  md += `## ✅ 已测试 (${tested.length})\n\n`;
  tested.sort().forEach((cmd, i) => md += `${i + 1}. \`${cmd}\`\n`);
  md += `\n`;

  md += `## ❌ 未测试 (${untested.length})\n\n`;
  if (untested.length > 0) {
    untested.forEach((cmd, i) => md += `${i + 1}. \`${cmd}\`\n`);
  } else {
    md += `*无*\n`;
  }
  md += `\n`;

  md += `## 📈 测试质量\n\n`;
  md += `- 总测试场景: ${report.summary.total}\n`;
  md += `- 通过: ${report.summary.passed}\n`;
  md += `- 失败: ${report.summary.failed}\n`;
  md += `- 成功率: ${report.summary.successRate}%\n`;

  return md;
}

/**
 * 主流程
 */
async function main() {
  console.log('🚀 综合命令覆盖率测试');
  console.log('目标: 90%+ (29/32 命令)\n');

  try {
    const pingResult = await sendCommand('ping');
    if (!pingResult.success) throw new Error('服务器未运行');
    console.log('✅ 服务器正常\n');

    await testAllBasicCommands();
    await testAllDebugCommands();
    await testAllLogCommands();
    await testAllUICommands();

    const report = await generateReports();

    console.log('\n' + '='.repeat(70));
    console.log('🎉 测试完成');
    console.log('='.repeat(70));
    console.log(`📦 命令覆盖: ${report.coverage.tested}/${report.coverage.total} (${report.coverage.percentage}%)`);
    console.log(`📊 测试场景: ${report.summary.total} (${report.summary.passed} 通过)`);
    console.log(`📈 成功率: ${report.summary.successRate}%`);
    console.log(`🎯 目标: ${parseFloat(report.coverage.percentage) >= 90 ? '✅ 已达成 90%+' : `⚠️ 还需 ${Math.ceil(29 - report.coverage.tested)} 个命令`}`);
    console.log('='.repeat(70));

    process.exit(0);

  } catch (error) {
    console.error('\n❌ 错误:', error.message);
    process.exit(1);
  }
}

main();
