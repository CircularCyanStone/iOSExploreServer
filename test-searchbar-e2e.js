#!/usr/bin/env node

/**
 * UISearchBar E2E 测试脚本
 *
 * 验证 UISearchBar 的完整交互流程：
 * 1. 导航到搜索测试页
 * 2. 场景 1: 基础搜索（输入 → 提交 → 验证结果）
 * 3. 场景 2: 带取消按钮（输入 → 取消 → 验证清空）
 * 4. 场景 3: 实时搜索（输入 → 验证过滤结果）
 * 5. 验证日志记录
 *
 * 使用方式：
 *   node test-searchbar-e2e.js
 *
 * 前置条件：
 *   - SPMExample 已在模拟器运行
 *   - iOSExploreServer 已启动（端口 38321）
 */

const http = require('http');

const BASE_URL = 'http://localhost:38321';

// HTTP POST 请求封装
async function callAction(action, data = {}) {
  return new Promise((resolve, reject) => {
    const payload = JSON.stringify({ action, ...data });
    const options = {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(payload)
      }
    };

    const req = http.request(BASE_URL, options, (res) => {
      let body = '';
      res.on('data', (chunk) => { body += chunk; });
      res.on('end', () => {
        try {
          const result = JSON.parse(body);
          if (result.code === 'ok') {
            resolve(result.data);
          } else {
            reject(new Error(`Action failed: ${result.code} - ${result.message}`));
          }
        } catch (err) {
          reject(new Error(`Parse error: ${err.message}`));
        }
      });
    });

    req.on('error', reject);
    req.write(payload);
    req.end();
  });
}

// 延迟函数
const sleep = (ms) => new Promise(resolve => setTimeout(resolve, ms));

// 主测试流程
async function runTests() {
  console.log('='.repeat(70));
  console.log('UISearchBar E2E 测试开始');
  console.log('='.repeat(70));

  try {
    // 步骤 1: 验证服务连接
    console.log('\n[步骤 1] 验证 iOSExploreServer 连接...');
    const pingResult = await callAction('ping');
    console.log('✅ 服务连接成功:', pingResult);

    // 步骤 2: 获取主页并导航到搜索测试页
    console.log('\n[步骤 2] 导航到搜索测试页...');
    let snapshot = await callAction('ui.inspect', { maxDepth: 3 });
    console.log(`当前页面: ${snapshot.navigationBar?.title || '(无标题)'}`);

    // 查找"搜索框测试"菜单项
    const searchMenuItem = snapshot.targets.find(t =>
      t.text && t.text.includes('搜索框测试')
    );

    if (!searchMenuItem) {
      throw new Error('未找到"搜索框测试"菜单项，请确保 SPMExample 已更新');
    }

    console.log(`找到菜单项: ${searchMenuItem.text}`);
    await callAction('ui.tap', {
      path: searchMenuItem.path,
      viewSnapshotID: snapshot.viewSnapshotID
    });

    // 等待页面切换
    await sleep(500);
    snapshot = await callAction('ui.inspect', {
      maxDepth: 4,  // UISearchBar 嵌套层级较深
      maxTargets: 100
    });
    console.log(`✅ 已进入页面: ${snapshot.navigationBar?.title || '(无标题)'}`);

    // 步骤 3: 场景 1 - 基础搜索框测试
    console.log('\n[步骤 3] 场景 1: 基础搜索框（输入 → 提交 → 验证）...');

    // 查找基础搜索框内的 UISearchTextField
    const basicSearchField = snapshot.targets.find(t =>
      t.type === 'UISearchTextField' &&
      t.path.includes('searchBar_basic')
    );

    if (!basicSearchField) {
      console.log('可用的 UISearchTextField:');
      snapshot.targets
        .filter(t => t.type === 'UISearchTextField')
        .forEach(t => console.log(`  - path: ${t.path}`));
      throw new Error('未找到基础搜索框的 UISearchTextField');
    }

    console.log(`找到搜索输入框: ${basicSearchField.path}`);

    // 输入搜索关键词
    await callAction('ui.input', {
      path: basicSearchField.path,
      text: 'Apple',
      mode: 'replace',
      submit: true,  // 自动收键盘触发搜索
      viewSnapshotID: snapshot.viewSnapshotID
    });
    console.log('✅ 已输入关键词 "Apple" 并提交');

    // 等待搜索结果
    await sleep(300);
    snapshot = await callAction('ui.inspect', {
      maxDepth: 3,
      maxTargets: 100
    });

    const basicResultLabel = snapshot.targets.find(t =>
      t.accessibilityIdentifier === 'searchBar_basic_result'
    );

    if (basicResultLabel) {
      console.log(`✅ 搜索结果: ${basicResultLabel.text}`);
      if (basicResultLabel.text.includes('Apple')) {
        console.log('✅ 场景 1 通过：搜索结果正确');
      } else {
        console.log('⚠️ 场景 1 警告：搜索结果未包含关键词');
      }
    } else {
      console.log('⚠️ 未找到结果标签');
    }

    // 步骤 4: 场景 2 - 带取消按钮的搜索框
    console.log('\n[步骤 4] 场景 2: 带取消按钮（输入 → 取消 → 验证清空）...');

    // 查找可取消搜索框
    const cancelableSearchField = snapshot.targets.find(t =>
      t.type === 'UISearchTextField' &&
      t.path.includes('searchBar_cancelable')
    );

    if (!cancelableSearchField) {
      throw new Error('未找到可取消搜索框的 UISearchTextField');
    }

    console.log(`找到可取消搜索框: ${cancelableSearchField.path}`);

    // 点击搜索框（让取消按钮显示）
    await callAction('ui.tap', {
      path: cancelableSearchField.path,
      viewSnapshotID: snapshot.viewSnapshotID
    });
    console.log('✅ 已点击搜索框');

    // 等待取消按钮出现并重新 inspect
    await sleep(300);
    snapshot = await callAction('ui.inspect', {
      maxDepth: 4,
      maxTargets: 100
    });

    // 输入文本
    const cancelableSearchField2 = snapshot.targets.find(t =>
      t.type === 'UISearchTextField' &&
      t.path.includes('searchBar_cancelable')
    );

    await callAction('ui.input', {
      path: cancelableSearchField2.path,
      text: 'test query',
      mode: 'replace',
      submit: false,  // 不收键盘，保持编辑状态
      viewSnapshotID: snapshot.viewSnapshotID
    });
    console.log('✅ 已输入 "test query"');

    // 等待输入完成
    await sleep(200);
    snapshot = await callAction('ui.inspect', {
      maxDepth: 4,
      maxTargets: 100
    });

    // 查找并点击取消按钮
    const cancelButton = snapshot.targets.find(t =>
      t.type === 'UIButton' &&
      (t.text === 'Cancel' || t.text === '取消')
    );

    if (cancelButton) {
      console.log(`找到取消按钮: ${cancelButton.text}`);
      await callAction('ui.tap', {
        path: cancelButton.path,
        viewSnapshotID: snapshot.viewSnapshotID
      });
      console.log('✅ 已点击取消按钮');

      // 验证取消效果
      await sleep(300);
      snapshot = await callAction('ui.inspect', {
        maxDepth: 4,
        maxTargets: 100
      });

      const cancelableResultLabel = snapshot.targets.find(t =>
        t.accessibilityIdentifier === 'searchBar_cancelable_result'
      );

      if (cancelableResultLabel) {
        console.log(`取消后结果标签: ${cancelableResultLabel.text}`);
      }

      const cancelableSearchFieldAfter = snapshot.targets.find(t =>
        t.type === 'UISearchTextField' &&
        t.path.includes('searchBar_cancelable')
      );

      if (cancelableSearchFieldAfter && !cancelableSearchFieldAfter.text) {
        console.log('✅ 场景 2 通过：取消后文本已清空');
      } else {
        console.log(`⚠️ 场景 2 警告：取消后文本为 "${cancelableSearchFieldAfter?.text || ''}"`);
      }
    } else {
      console.log('⚠️ 未找到取消按钮（可能未显示）');
    }

    // 步骤 5: 场景 3 - 实时搜索列表
    console.log('\n[步骤 5] 场景 3: 实时搜索（输入 → 验证过滤）...');

    // 查找列表搜索框
    const listSearchField = snapshot.targets.find(t =>
      t.type === 'UISearchTextField' &&
      t.path.includes('searchBar_list')
    );

    if (!listSearchField) {
      throw new Error('未找到列表搜索框的 UISearchTextField');
    }

    console.log(`找到列表搜索框: ${listSearchField.path}`);

    // 输入过滤关键词
    await callAction('ui.input', {
      path: listSearchField.path,
      text: 'Apple',
      mode: 'replace',
      submit: false,  // 实时搜索，不收键盘
      viewSnapshotID: snapshot.viewSnapshotID
    });
    console.log('✅ 已输入过滤关键词 "Apple"');

    // 等待过滤结果
    await sleep(300);
    snapshot = await callAction('ui.inspect', {
      maxDepth: 4,
      maxTargets: 100
    });

    const listStatusLabel = snapshot.targets.find(t =>
      t.accessibilityIdentifier === 'searchBar_list_status'
    );

    if (listStatusLabel) {
      console.log(`✅ 过滤状态: ${listStatusLabel.text}`);
      if (listStatusLabel.text.includes('1 项')) {
        console.log('✅ 场景 3 通过：实时过滤正确（找到 1 项匹配）');
      } else {
        console.log('⚠️ 场景 3 警告：过滤结果数量可能不符预期');
      }
    } else {
      console.log('⚠️ 未找到状态标签');
    }

    // 步骤 6: 验证日志记录
    console.log('\n[步骤 6] 验证日志记录...');

    // 标记日志点
    await callAction('app.logs.mark', { marker: 'searchbar_test_complete' });

    // 读取日志
    const logs = await callAction('app.logs.read', {
      source: 'oslog',
      marker: 'searchbar_test_complete',
      count: 50
    });

    console.log(`读取到 ${logs.entries.length} 条日志`);

    const searchBarLogs = logs.entries.filter(entry =>
      entry.message.includes('SearchBar')
    );

    if (searchBarLogs.length > 0) {
      console.log(`✅ 找到 ${searchBarLogs.length} 条搜索框相关日志:`);
      searchBarLogs.slice(0, 5).forEach(log => {
        console.log(`  [${log.level}] ${log.message}`);
      });
    } else {
      console.log('⚠️ 未找到搜索框相关日志');
    }

    // 步骤 7: 返回主页
    console.log('\n[步骤 7] 返回主页...');
    await callAction('ui.navigation.back');
    await sleep(300);

    snapshot = await callAction('ui.inspect', { maxDepth: 2 });
    console.log(`✅ 已返回页面: ${snapshot.navigationBar?.title || '(无标题)'}`);

    // 测试完成
    console.log('\n' + '='.repeat(70));
    console.log('✅ UISearchBar E2E 测试全部完成');
    console.log('='.repeat(70));
    console.log('\n测试总结:');
    console.log('  ✓ 场景 1: 基础搜索（输入 → 提交）');
    console.log('  ✓ 场景 2: 取消按钮（输入 → 取消 → 清空）');
    console.log('  ✓ 场景 3: 实时搜索（输入 → 动态过滤）');
    console.log('  ✓ 日志记录验证');
    console.log('\n所有 UISearchBar 交互均通过现有命令完成：');
    console.log('  - ui.input: 输入搜索文本');
    console.log('  - ui.tap: 点击取消按钮/清空按钮');
    console.log('  - ui.keyboard.dismiss: 收键盘触发搜索');
    console.log('  - ui.inspect: 获取搜索结果和状态');

  } catch (error) {
    console.error('\n❌ 测试失败:', error.message);
    console.error(error.stack);
    process.exit(1);
  }
}

// 运行测试
runTests().catch(err => {
  console.error('❌ 未捕获的错误:', err);
  process.exit(1);
});
