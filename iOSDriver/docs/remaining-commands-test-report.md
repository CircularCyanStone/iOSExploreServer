# 剩余命令端到端测试报告

**生成时间**: 2026/7/13 23:18:10

## 📊 测试摘要

| 指标 | 数值 |
|------|------|
| 总测试数 | 21 |
| 通过 | 15 |
| 失败 | 6 |
| 成功率 | 71.43% |
| 新增命令覆盖 | 12 / 32 (37.50%) |

## 📋 命令测试结果

| 命令 | 总数 | 通过 | 失败 | 成功率 |
|------|------|------|------|--------|
| `greet` | 2 | 2 | 0 | 100.0% |
| `debug.probe` | 2 | 2 | 0 | 100.0% |
| `debug.emitStdout` | 1 | 1 | 0 | 100.0% |
| `debug.emitStderr` | 1 | 1 | 0 | 100.0% |
| `debug.emitNSLog` | 1 | 1 | 0 | 100.0% |
| `debug.emitOSLog` | 1 | 1 | 0 | 100.0% |
| `debug.emit+logs.read` | 1 | 0 | 1 | 0.0% |
| `ui.controllers` | 3 | 1 | 2 | 33.3% |
| `ui.navigation.tapBarButton` | 3 | 2 | 1 | 66.7% |
| `ui.scrollToElement` | 4 | 2 | 2 | 50.0% |
| `debug.emitLogger` | 1 | 1 | 0 | 100.0% |
| `debug.emitAppLog` | 1 | 1 | 0 | 100.0% |

## ⚡ 性能统计

| 命令 | 平均 (ms) | 最小 (ms) | 最大 (ms) | 调用次数 |
|------|-----------|-----------|-----------|----------|
| `ping` | 22.0 | 22 | 22 | 1 |
| `greet` | 3.0 | 2 | 4 | 2 |
| `debug.probe` | 3.5 | 3 | 4 | 2 |
| `debug.emitStdout` | 4.0 | 4 | 4 | 1 |
| `debug.emitStderr` | 7.0 | 7 | 7 | 1 |
| `debug.emitNSLog` | 3.0 | 3 | 3 | 1 |
| `debug.emitOSLog` | 2.0 | 2 | 2 | 1 |
| `app.logs.read` | 9.0 | 9 | 9 | 1 |
| `ui.navigation.back` | 2.5 | 2 | 3 | 6 |
| `ui.controllers` | 3.3 | 3 | 4 | 3 |
| `ui.wait` | 323.8 | 321 | 326 | 4 |
| `ui.tap` | 3.5 | 2 | 6 | 4 |
| `ui.navigation.tapBarButton` | 5.0 | 3 | 7 | 3 |
| `ui.scrollToElement` | 3.3 | 2 | 5 | 4 |
| `debug.emitLogger` | 2.0 | 2 | 2 | 1 |
| `debug.emitAppLog` | 3.0 | 3 | 3 | 1 |

## 📝 详细测试场景

### `greet`

✅ **基础调用** (2ms)

✅ **带参数调用** (4ms)

### `debug.probe`

✅ **基础探测** (3ms)

✅ **验证返回调试信息** (4ms)

### `debug.emitStdout`

✅ **输出到 stdout** (4ms)

### `debug.emitStderr`

✅ **输出到 stderr** (7ms)

### `debug.emitNSLog`

✅ **输出到 NSLog** (3ms)

### `debug.emitOSLog`

✅ **输出到 OSLog** (2ms)

### `debug.emit+logs.read`

❌ **验证日志已写入** (9ms)
   - 预期: 成功
   - 实际: 失败

### `ui.controllers`

✅ **主页控制器层级** (3ms)

❌ **验证返回数据结构** (4ms)
   - 预期: 成功
   - 实际: 失败

❌ **按钮页面控制器** (3ms)
   - 预期: 成功
   - 实际: 失败

### `ui.navigation.tapBarButton`

❌ **点击左侧导航按钮** (7ms)
   - 预期: 成功
   - 实际: 失败
   - 错误: invalid navigation bar button selector: 必须提供 (placement + index) 或 accessibilityIdentifier

✅ **点击不存在的右侧按钮** (3ms)

✅ **无效位置参数** (5ms)

### `ui.scrollToElement`

❌ **滚动到文本元素（Item 50）** (3ms)
   - 预期: 成功
   - 实际: 失败
   - 错误: missing required parameter 'value'

❌ **带动画滚动到 Item 10** (5ms)
   - 预期: 成功
   - 实际: 失败
   - 错误: missing required parameter 'value'

✅ **滚动到不存在的元素** (2ms)

✅ **缺少 value 参数** (3ms)

### `debug.emitLogger`

✅ **使用 Swift Logger 输出** (2ms)

### `debug.emitAppLog`

✅ **输出应用日志** (3ms)

## 🎯 测试的命令列表

本次测试覆盖了以下命令：

- `debug.emit+logs.read`
- `debug.emitAppLog`
- `debug.emitLogger`
- `debug.emitNSLog`
- `debug.emitOSLog`
- `debug.emitStderr`
- `debug.emitStdout`
- `debug.probe`
- `greet`
- `ui.controllers`
- `ui.navigation.tapBarButton`
- `ui.scrollToElement`

## 📌 注意事项

1. 所有测试在 SPMExample App (模拟器) 上运行
2. 测试环境: localhost:38321
3. 每个命令至少测试 2 个场景（正常 + 错误处理）
4. 性能数据基于单次运行，实际性能可能因设备和负载而异
