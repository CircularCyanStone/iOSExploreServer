# Interaction Command Testing Report

Generated: 2026-07-13T14:30:25.622Z

## Summary

- **Total Scenarios**: 18
- **Commands Tested**: 14 / 32
- **Total Duration**: 29755ms
- **Coverage**: 44%

## Tested Commands

| Command | Success | Error | Total | Success Rate | Avg Duration |
|---------|---------|-------|-------|--------------|--------------|
| ui_inspect | 21 | 0 | 21 | 100% | 14ms |
| ui_swipe | 2 | 0 | 2 | 100% | 6ms |
| ui_tap | 3 | 1 | 4 | 75% | 5ms |
| ui_longPress | 1 | 0 | 1 | 100% | 5ms |
| ui_scroll | 1 | 0 | 1 | 100% | 5ms |
| ui_navigation_back | 1 | 0 | 1 | 100% | 4ms |
| ui_navigation_tapBarButton | 1 | 0 | 1 | 100% | 3ms |
| ui_wait | 1 | 0 | 1 | 100% | 549ms |
| ui_controllers | 1 | 0 | 1 | 100% | 4ms |
| call_action | 3 | 0 | 3 | 100% | 27ms |
| ui_keyboard_dismiss | 1 | 0 | 1 | 100% | 204ms |
| ui_scrollToElement | 0 | 1 | 1 | 0% | 4ms |
| wait_and_inspect | 1 | 0 | 1 | 100% | 344ms |
| ui_topViewHierarchy | 2 | 0 | 2 | 100% | 12ms |

## Test Scenarios

### 1. Scenario 1: Swipe on TableView Cell

在 UITableView cell 上执行 swipe action（左滑显示删除/收藏按钮）

**Steps**: 3

### 2. Scenario 2: Tap Element in Hierarchy

使用 ui.tap 点击列表中的元素

**Steps**: 3

### 3. Scenario 3: LongPress on Gesture View

在带手势识别器的 view 上执行长按

**Steps**: 3

### 4. Scenario 4: Scroll in TableView

在 UITableView 中滚动

**Steps**: 3

### 5. Scenario 5: Navigation Back

点击导航栏返回按钮

**Steps**: 5

### 6. Scenario 6: Navigation Bar Button

测试导航栏按钮点击（左/右按钮）

**Steps**: 2

### 7. Scenario 7: Wait for UI State

等待 UI 稳定后继续操作

**Steps**: 2

### 8. Scenario 8: Error Handling - Invalid Path

测试错误处理：无效的 path

**Steps**: 2

### 9. Scenario 9: Error Handling - Missing Snapshot ID

测试错误处理：缺少 viewSnapshotID

**Steps**: 1

### 10. Scenario 10: Swipe on Generic View

在普通 view 上执行 swipe（非 tableView cell）

**Steps**: 3

### 11. Scenario 11: Controllers Inspection

获取控制器层级信息

**Steps**: 1

### 12. Scenario 12: Screenshot Capture

截图并验证返回数据

**Steps**: 1

### 13. Scenario 13: Keyboard Dismiss

测试键盘收起功能（当前没有键盘，测试 no-op 场景）

**Steps**: 1

### 14. Scenario 14: ScrollToElement

滚动到指定元素

**Steps**: 3

### 15. Scenario 15: WaitAny Multi-Condition

等待多个条件之一满足

**Steps**: 1

### 16. Scenario 16: TopViewHierarchy with DetailLevel

获取完整视图层级（不同详情级别）

**Steps**: 2

### 17. Scenario 17: Device Info

获取设备信息

**Steps**: 2

### 18. Scenario 18: Performance - Rapid Inspect

性能测试：连续快速 inspect

**Steps**: 3


## Commands Still Untested

Based on the 32 total commands, the following are still not covered:

- ui.input
- ui.alert.respond
- ui.control.sendAction
- ui.waitAny
- debug.probe
- ui.screenshot
- app.logs.mark
- app.logs.read
- ping
- help
- app.info
- ui.alert.info
- ui.keyboard.info
- ui.navigation.info
- ui.tabBar.info
- ui.deepLink
- ui.shake
- system.memory
- system.orientation
- system.appearance

## Recommendations

1. **High Priority**: Add test coverage for `ui.alert.respond` by creating alert scenarios
2. **High Priority**: Add `ui.input` testing with text field interaction
3. **Medium Priority**: Test `ui.control.sendAction` for slider/switch controls
4. **Medium Priority**: Add `ui.scrollToElement` scenarios for large lists
5. **Low Priority**: Test auxiliary commands like `debug.probe`, `system.*` commands

## Next Steps

1. Create alert testing scenarios in SPMExample
2. Add text input page for `ui.input` testing
3. Add control testing page (slider, switch, stepper)
4. Expand error handling test cases
5. Add performance benchmarking for all commands
