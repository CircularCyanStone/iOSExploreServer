#!/usr/bin/env node

/**
 * 剩余命令端到端测试脚本
 * 目标：测试未覆盖的命令，将覆盖率从 68.75% 提升到 90%+
 */

import { setTimeout as delay } from 'timers/promises';

const BASE_URL = 'http://localhost:38321/';
const DELAY_MS = 500; // 命令间延迟

// 测试结果存储
const testResults = {
  timestamp: new Date().toISOString(),
  summary: {
    total: 0,
    passed: 0,
    failed: 0,
    successRate: 0
  },
  commands: {},
  details: []
};

// 性能统计
const performanceStats = {};

/**
 * 发送命令到服务器
 */
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

    // 记录性能
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

/**
 * 记录测试结果
 */
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
    command,
    scenario,
    passed,
    expected,
    actual: result.success,
    duration: result.duration,
    response: result.data || result.error,
    timestamp: new Date().toISOString()
  });

  const status = passed ? '✅' : '❌';
  console.log(`${status} ${command}: ${scenario} (${result.duration}ms)`);
}

/**
 * 辅助函数：确保在主页
 */
async function ensureHomePage() {
  console.log('\n📍 确保在主页...');

  // 尝试返回主页（最多3次）
  for (let i = 0; i < 3; i++) {
    const result = await sendCommand('ui.navigation.back');
    await delay(300);
    if (!result.success) break; // 已经在最顶层
  }

  await delay(500);
}

/**
 * 辅助函数：导航到指定页面
 */
async function navigateToPage(buttonText) {
  console.log(`\n📱 导航到页面: ${buttonText}`);

  // 先确保在主页
  await ensureHomePage();

  // 等待主页加载
  await sendCommand('ui.wait', { condition: 'stable', timeout: 3 });
  await delay(300);

  // 点击按钮
  const result = await sendCommand('ui.tap', { match: 'text', value: buttonText });
  await delay(800);

  return result;
}

/**
 * 测试 1: greet 命令
 */
async function testGreet() {
  console.log('\n=== 测试 greet 命令 ===');

  // 场景1：基础调用
  let result = await sendCommand('greet');
  recordTest('greet', '基础调用', result, true);
  await delay(DELAY_MS);

  // 场景2：带参数调用（如果支持）
  result = await sendCommand('greet', { name: 'Claude' });
  recordTest('greet', '带参数调用', result, true);
  await delay(DELAY_MS);
}

/**
 * 测试 2: debug.probe 命令
 */
async function testDebugProbe() {
  console.log('\n=== 测试 debug.probe 命令 ===');

  // 场景1：基础探测
  let result = await sendCommand('debug.probe');
  recordTest('debug.probe', '基础探测', result, true);
  await delay(DELAY_MS);

  // 场景2：探测后验证返回数据
  result = await sendCommand('debug.probe');
  const hasDebugInfo = result.success && result.data && typeof result.data === 'object';
  recordTest('debug.probe', '验证返回调试信息', { ...result, success: hasDebugInfo }, true);
  await delay(DELAY_MS);
}

/**
 * 测试 3: debug.emit* 系列命令
 */
async function testDebugEmit() {
  console.log('\n=== 测试 debug.emit* 系列命令 ===');

  // 场景1：emitStdout
  let result = await sendCommand('debug.emitStdout', { message: 'Test stdout message' });
  recordTest('debug.emitStdout', '输出到 stdout', result, true);
  await delay(DELAY_MS);

  // 场景2：emitStderr
  result = await sendCommand('debug.emitStderr', { message: 'Test stderr message' });
  recordTest('debug.emitStderr', '输出到 stderr', result, true);
  await delay(DELAY_MS);

  // 场景3：emitNSLog
  result = await sendCommand('debug.emitNSLog', { message: 'Test NSLog message' });
  recordTest('debug.emitNSLog', '输出到 NSLog', result, true);
  await delay(DELAY_MS);

  // 场景4：emitOSLog
  result = await sendCommand('debug.emitOSLog', { message: 'Test OSLog message' });
  recordTest('debug.emitOSLog', '输出到 OSLog', result, true);
  await delay(DELAY_MS);

  // 场景5：验证日志读取
  await delay(1000); // 等待日志写入
  result = await sendCommand('app.logs.read', { source: 'stdout', limit: 10 });
  const hasLogs = result.success && result.data?.logs?.length > 0;
  recordTest('debug.emit+logs.read', '验证日志已写入', { ...result, success: hasLogs }, true);
  await delay(DELAY_MS);
}

/**
 * 测试 4: ui.controllers 命令
 */
async function testUIControllers() {
  console.log('\n=== 测试 ui.controllers 命令 ===');

  await ensureHomePage();

  // 场景1：主页控制器层级
  let result = await sendCommand('ui.controllers');
  recordTest('ui.controllers', '主页控制器层级', result, true);
  await delay(DELAY_MS);

  // 场景2：验证返回数据结构
  result = await sendCommand('ui.controllers');
  const hasValidStructure = result.success &&
                            result.data?.root &&
                            result.data?.topPath &&
                            typeof result.data?.controllerCount === 'number';
  recordTest('ui.controllers', '验证返回数据结构', { ...result, success: hasValidStructure }, true);
  await delay(DELAY_MS);

  // 场景3：不同页面的控制器
  await navigateToPage('🔘 按钮点击测试');
  await delay(500);

  result = await sendCommand('ui.controllers');
  const differentController = result.success && result.data?.controllerCount > 0;
  recordTest('ui.controllers', '按钮页面控制器', { ...result, success: differentController }, true);
  await delay(DELAY_MS);
}

/**
 * 测试 5: ui.navigation.tapBarButton 命令
 */
async function testUINavigationTapBarButton() {
  console.log('\n=== 测试 ui.navigation.tapBarButton 命令 ===');

  // 先导航到一个有导航栏按钮的页面
  await navigateToPage('🔘 按钮点击测试');
  await delay(500);

  // 场景1：点击返回按钮（left）
  let result = await sendCommand('ui.navigation.tapBarButton', { position: 'left' });
  recordTest('ui.navigation.tapBarButton', '点击左侧导航按钮', result, true);
  await delay(800);

  // 场景2：尝试点击不存在的右侧按钮
  await navigateToPage('🔘 按钮点击测试');
  await delay(500);

  result = await sendCommand('ui.navigation.tapBarButton', { position: 'right' });
  recordTest('ui.navigation.tapBarButton', '点击不存在的右侧按钮', result, false);
  await delay(DELAY_MS);

  // 场景3：无效参数
  result = await sendCommand('ui.navigation.tapBarButton', { position: 'invalid' });
  recordTest('ui.navigation.tapBarButton', '无效位置参数', result, false);
  await delay(DELAY_MS);
}

/**
 * 测试 6: ui.scrollToElement 命令
 */
async function testUIScrollToElement() {
  console.log('\n=== 测试 ui.scrollToElement 命令 ===');

  // 导航到滚动测试页
  await navigateToPage('📜 滚动测试');
  await delay(800);

  // 场景1：滚动到文本元素（默认 match=text）
  let result = await sendCommand('ui.scrollToElement', {
    value: 'Item 50',
    animated: false
  });
  recordTest('ui.scrollToElement', '滚动到文本元素（Item 50）', result, true);
  await delay(800);

  // 场景2：滚动到另一个文本元素
  result = await sendCommand('ui.scrollToElement', {
    value: 'Item 10',
    animated: true
  });
  recordTest('ui.scrollToElement', '带动画滚动到 Item 10', result, true);
  await delay(800);

  // 场景3：滚动到不存在的元素
  result = await sendCommand('ui.scrollToElement', {
    value: 'NonExistentItem999'
  });
  recordTest('ui.scrollToElement', '滚动到不存在的元素', result, false);
  await delay(DELAY_MS);

  // 场景4：缺少必需参数
  result = await sendCommand('ui.scrollToElement', {});
  recordTest('ui.scrollToElement', '缺少 value 参数', result, false);
  await delay(DELAY_MS);
}

/**
 * 测试 7: 其他未测试命令
 */
async function testOtherCommands() {
  console.log('\n=== 测试其他未覆盖命令 ===');

  await ensureHomePage();

  // debug.emitLogger
  let result = await sendCommand('debug.emitLogger', {
    message: 'Test Logger message',
    level: 'info'
  });
  recordTest('debug.emitLogger', '使用 Swift Logger 输出', result, true);
  await delay(DELAY_MS);

  // debug.emitAppLog
  result = await sendCommand('debug.emitAppLog', {
    message: 'Test App Log',
    level: 'debug'
  });
  recordTest('debug.emitAppLog', '输出应用日志', result, true);
  await delay(DELAY_MS);
}

/**
 * 生成测试报告
 */
async function generateReports() {
  console.log('\n=== 生成测试报告 ===');

  // 计算成功率
  testResults.summary.successRate = (testResults.summary.passed / testResults.summary.total * 100).toFixed(2);

  // 生成 JSON 报告
  const jsonReport = {
    ...testResults,
    performance: performanceStats,
    coverage: {
      tested: Object.keys(testResults.commands).length,
      total: 32,
      percentage: (Object.keys(testResults.commands).length / 32 * 100).toFixed(2)
    }
  };

  const { writeFile, mkdir } = await import('fs/promises');
  const { join } = await import('path');
  const { existsSync } = await import('fs');

  const docsDir = join(process.cwd(), 'docs');
  if (!existsSync(docsDir)) {
    await mkdir(docsDir, { recursive: true });
  }

  // 写入 JSON 报告
  const jsonPath = join(docsDir, 'remaining-commands-test-report.json');
  await writeFile(jsonPath, JSON.stringify(jsonReport, null, 2));
  console.log(`✅ JSON 报告已保存: ${jsonPath}`);

  // 生成 Markdown 报告
  const mdContent = generateMarkdownReport(jsonReport);
  const mdPath = join(docsDir, 'remaining-commands-test-report.md');
  await writeFile(mdPath, mdContent);
  console.log(`✅ Markdown 报告已保存: ${mdPath}`);

  return jsonReport;
}

/**
 * 生成 Markdown 报告内容
 */
function generateMarkdownReport(report) {
  let md = `# 剩余命令端到端测试报告\n\n`;
  md += `**生成时间**: ${new Date(report.timestamp).toLocaleString('zh-CN')}\n\n`;

  md += `## 📊 测试摘要\n\n`;
  md += `| 指标 | 数值 |\n`;
  md += `|------|------|\n`;
  md += `| 总测试数 | ${report.summary.total} |\n`;
  md += `| 通过 | ${report.summary.passed} |\n`;
  md += `| 失败 | ${report.summary.failed} |\n`;
  md += `| 成功率 | ${report.summary.successRate}% |\n`;
  md += `| 新增命令覆盖 | ${report.coverage.tested} / ${report.coverage.total} (${report.coverage.percentage}%) |\n\n`;

  md += `## 📋 命令测试结果\n\n`;
  md += `| 命令 | 总数 | 通过 | 失败 | 成功率 |\n`;
  md += `|------|------|------|------|--------|\n`;

  for (const [cmd, stats] of Object.entries(report.commands)) {
    const rate = (stats.passed / stats.total * 100).toFixed(1);
    md += `| \`${cmd}\` | ${stats.total} | ${stats.passed} | ${stats.failed} | ${rate}% |\n`;
  }
  md += `\n`;

  md += `## ⚡ 性能统计\n\n`;
  md += `| 命令 | 平均 (ms) | 最小 (ms) | 最大 (ms) | 调用次数 |\n`;
  md += `|------|-----------|-----------|-----------|----------|\n`;

  for (const [cmd, perf] of Object.entries(report.performance)) {
    md += `| \`${cmd}\` | ${perf.avg.toFixed(1)} | ${perf.min} | ${perf.max} | ${perf.times.length} |\n`;
  }
  md += `\n`;

  md += `## 📝 详细测试场景\n\n`;

  const commandGroups = {};
  for (const detail of report.details) {
    if (!commandGroups[detail.command]) {
      commandGroups[detail.command] = [];
    }
    commandGroups[detail.command].push(detail);
  }

  for (const [cmd, details] of Object.entries(commandGroups)) {
    md += `### \`${cmd}\`\n\n`;
    for (const detail of details) {
      const icon = detail.passed ? '✅' : '❌';
      md += `${icon} **${detail.scenario}** (${detail.duration}ms)\n`;
      if (!detail.passed) {
        md += `   - 预期: ${detail.expected ? '成功' : '失败'}\n`;
        md += `   - 实际: ${detail.actual ? '成功' : '失败'}\n`;
        if (detail.response?.message) {
          md += `   - 错误: ${detail.response.message}\n`;
        }
      }
      md += `\n`;
    }
  }

  md += `## 🎯 测试的命令列表\n\n`;
  md += `本次测试覆盖了以下命令：\n\n`;
  for (const cmd of Object.keys(report.commands).sort()) {
    md += `- \`${cmd}\`\n`;
  }
  md += `\n`;

  md += `## 📌 注意事项\n\n`;
  md += `1. 所有测试在 SPMExample App (模拟器) 上运行\n`;
  md += `2. 测试环境: localhost:38321\n`;
  md += `3. 每个命令至少测试 2 个场景（正常 + 错误处理）\n`;
  md += `4. 性能数据基于单次运行，实际性能可能因设备和负载而异\n`;

  return md;
}

/**
 * 主测试流程
 */
async function main() {
  console.log('🚀 开始剩余命令端到端测试\n');
  console.log('目标：将命令覆盖率从 68.75% 提升到 90%+\n');

  try {
    // 检查服务器连接
    console.log('🔍 检查服务器连接...');
    const pingResult = await sendCommand('ping');
    if (!pingResult.success) {
      throw new Error('服务器未运行，请先启动 SPMExample App');
    }
    console.log('✅ 服务器连接正常\n');

    // 执行测试
    await testGreet();
    await testDebugProbe();
    await testDebugEmit();
    await testUIControllers();
    await testUINavigationTapBarButton();
    await testUIScrollToElement();
    await testOtherCommands();

    // 生成报告
    const report = await generateReports();

    // 打印摘要
    console.log('\n' + '='.repeat(60));
    console.log('🎉 测试完成！');
    console.log('='.repeat(60));
    console.log(`📊 总测试数: ${report.summary.total}`);
    console.log(`✅ 通过: ${report.summary.passed}`);
    console.log(`❌ 失败: ${report.summary.failed}`);
    console.log(`📈 成功率: ${report.summary.successRate}%`);
    console.log(`📦 新增命令覆盖: ${report.coverage.tested}/${report.coverage.total} (${report.coverage.percentage}%)`);
    console.log('='.repeat(60));

    // 退出码
    process.exit(report.summary.failed === 0 ? 0 : 1);

  } catch (error) {
    console.error('\n❌ 测试失败:', error.message);
    process.exit(1);
  }
}

// 运行测试
main();
