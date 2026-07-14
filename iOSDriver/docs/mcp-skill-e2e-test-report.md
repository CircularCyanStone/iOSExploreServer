# iOSDriver 端到端测试报告

> 测试时间：2026-07-13T13:59:37.036Z

## 测试概览

- **总测试数**：43
- **成功**：38
- **失败**：5
- **成功率**：88.37%
- **平均响应时间**：31.09ms

## 分类测试结果

### connectivity (2/2)

| 测试名称 | 工具 | 状态 | 耗时 |
|---------|------|------|------|
| health_check | health_check | ✓ 通过 | 9ms |
| health_check_duplicate | health_check | ✓ 通过 | 9ms |

### basicCommands (6/6)

| 测试名称 | 工具 | 状态 | 耗时 |
|---------|------|------|------|
| ping | call_action | ✓ 通过 | 5ms |
| help | call_action | ✓ 通过 | 5ms |
| echo_simple | call_action | ✓ 通过 | 5ms |
| echo_complex | call_action | ✓ 通过 | 5ms |
| info | call_action | ✓ 通过 | 5ms |
| device | call_action | ✓ 通过 | 5ms |

### uiInspection (10/10)

| 测试名称 | 工具 | 状态 | 耗时 |
|---------|------|------|------|
| ui_inspect_default | ui_inspect | ✓ 通过 | 10ms |
| ui_inspect_with_hidden | ui_inspect | ✓ 通过 | 10ms |
| ui_inspect_max_depth | ui_inspect | ✓ 通过 | 10ms |
| ui_inspect_text_limit | ui_inspect | ✓ 通过 | 10ms |
| ui_inspect_max_targets | ui_inspect | ✓ 通过 | 10ms |
| ui_screenshot_small | ui_screenshot | ✓ 通过 | 35ms |
| ui_screenshot_medium | ui_screenshot | ✓ 通过 | 35ms |
| ui_screenshot_large | ui_screenshot | ✓ 通过 | 35ms |
| ui_topViewHierarchy_basic | ui_topViewHierarchy | ✓ 通过 | 14ms |
| ui_topViewHierarchy_full | ui_topViewHierarchy | ✓ 通过 | 14ms |

### uiWaiting (3/3)

| 测试名称 | 工具 | 状态 | 耗时 |
|---------|------|------|------|
| wait_idle_short | ui_waitAny | ✓ 通过 | 326ms |
| wait_idle_medium | ui_waitAny | ✓ 通过 | 326ms |
| wait_and_inspect_idle | wait_and_inspect | ✓ 通过 | 329ms |

### logging (6/6)

| 测试名称 | 工具 | 状态 | 耗时 |
|---------|------|------|------|
| logs_mark | call_action | ✓ 通过 | 5ms |
| logs_read_all | call_action | ✓ 通过 | 5ms |
| logs_read_stdout | call_action | ✓ 通过 | 5ms |
| logs_read_stderr | call_action | ✓ 通过 | 5ms |
| logs_read_oslog | call_action | ✓ 通过 | 5ms |
| logs_read_bridge | call_action | ✓ 通过 | 5ms |

### errorHandling (3/4)

| 测试名称 | 工具 | 状态 | 耗时 |
|---------|------|------|------|
| unknown_action | call_action | ✓ 通过 | 5ms |
| invalid_tool_name | invalid_tool_xyz | ✗ 失败 | 2ms |
| missing_required_param | call_action | ✓ 通过 | 5ms |
| invalid_json_structure | ui_inspect | ✓ 通过 | 10ms |

### toolRefresh (0/2)

| 测试名称 | 工具 | 状态 | 耗时 |
|---------|------|------|------|
| refresh_tools | refresh_tools | ✗ 失败 | 1ms |
| list_tools_after_refresh | tools/list | ✗ 失败 | 1ms |

### boundaryConditions (6/6)

| 测试名称 | 工具 | 状态 | 耗时 |
|---------|------|------|------|
| echo_empty | call_action | ✓ 通过 | 5ms |
| echo_large_payload | call_action | ✓ 通过 | 5ms |
| ui_inspect_zero_depth | ui_inspect | ✓ 通过 | 10ms |
| ui_inspect_large_depth | ui_inspect | ✓ 通过 | 10ms |
| logs_read_zero_limit | call_action | ✓ 通过 | 5ms |
| logs_read_large_limit | call_action | ✓ 通过 | 5ms |

### performance (5/5)

| 测试名称 | 工具 | 状态 | 耗时 |
|---------|------|------|------|
| rapid_ping_1 | call_action | ✓ 通过 | 5ms |
| rapid_ping_2 | call_action | ✓ 通过 | 5ms |
| rapid_ping_3 | call_action | ✓ 通过 | 5ms |
| rapid_inspect_1 | ui_inspect | ✓ 通过 | 10ms |
| rapid_inspect_2 | ui_inspect | ✓ 通过 | 10ms |

## 关键发现

### 性能数据

- **connectivity**：平均 9ms (最小 9ms, 最大 9ms, 2 次测试)
- **basicCommands**：平均 5ms (最小 5ms, 最大 5ms, 6 次测试)
- **uiInspection**：平均 18ms (最小 10ms, 最大 35ms, 10 次测试)
- **uiWaiting**：平均 327ms (最小 326ms, 最大 329ms, 3 次测试)
- **logging**：平均 5ms (最小 5ms, 最大 5ms, 6 次测试)
- **errorHandling**：平均 6ms (最小 2ms, 最大 10ms, 4 次测试)
- **toolRefresh**：平均 1ms (最小 1ms, 最大 1ms, 2 次测试)
- **boundaryConditions**：平均 7ms (最小 5ms, 最大 10ms, 6 次测试)
- **performance**：平均 7ms (最小 5ms, 最大 10ms, 5 次测试)

### 常见错误模式

- **errorHandling/invalid_tool_name**：`unknown` - {"content":[{"type":"text","text":"{\n  \"source\": \"mcp_server\",\n  \"code\": \"unknown_tool\",\n
- **toolRefresh/refresh_tools**：`unknown` - {"content":[{"type":"text","text":"{\n  \"source\": \"mcp_server\",\n  \"code\": \"missing_action\",
- **toolRefresh/list_tools_after_refresh**：`unknown` - {"content":[{"type":"text","text":"{\n  \"source\": \"mcp_server\",\n  \"code\": \"missing_action\",

## Skill 设计建议

### 基础命令 Skill
- 应包含：ping, help, echo, info, device
- 平均响应时间：5ms
- 推荐用于：快速健康检查、获取设备信息

### UI 检查 Skill
- 应包含：ui.inspect, ui.screenshot, ui.topViewHierarchy
- 平均响应时间：18ms
- 推荐参数组合：
  - 快速检查：`{ maxDepth: 5, maxTargets: 20 }`
  - 详细分析：`{ includeHidden: true, maxDepth: 10 }`
  - 截图：`{ maxDimension: 800 }` 平衡质量和传输速度

### 日志采集 Skill
- 应包含：app.logs.mark, app.logs.read
- 平均响应时间：5ms
- 推荐工作流：mark → 操作 → read (增量读取)
- 支持来源过滤：stdout, stderr, oslog, bridge

### UI 等待 Skill
- 应包含：ui.waitAny, wait_and_inspect
- 平均响应时间：327ms
- 推荐超时配置：
  - 快速轮询：500-1000ms
  - 标准等待：2000-5000ms
  - 长时等待：10000ms+
