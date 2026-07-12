# iOSExploreServer 命令扩展优先级分析

**日期**: 2026-07-13
**目的**: 分析现有命令体系，识别缺失的高价值命令

---

## 现有命令总览（22 个）

### Core 命令（6 个）
| Action | 用途 |
|--------|------|
| `ping` | 健康检查 |
| `echo` | JSON 解析验证 |
| `info` | 系统/Bundle 信息 |
| `help` | 命令列表 |
| `app.logs.mark` | 日志检查点 |
| `app.logs.read` | 读取捕获的日志 |

### UIKit 命令（16 个）
| 分类 | 命令 |
|------|------|
| 查询 | `ui.inspect`, `ui.topViewHierarchy`, `ui.screenshot`, `ui.controllers.list` |
| 操作 | `ui.tap`, `ui.control.sendAction` |
| 输入 | `ui.input`, `ui.keyboard.dismiss` |
| 滚动 | `ui.scroll`, `ui.scrollToElement` |
| 导航 | `ui.navigation.back`, `ui.navigation.tapBarButton` |
| 等待 | `ui.wait`, `ui.waitAny` |
| 弹窗 | `ui.alert.respond` |

---

## 推荐实现优先级

### P0 - 强烈推荐（高价值、低复杂度）

| 优先级 | 命令 | 复杂度 | 理由 |
|--------|------|--------|------|
| 1 | **ui.swipe** | 低 | 高频手势，UISwipeGestureRecognizer 语义无法被 ui.scroll 替代 |
| 1 | **ui.cell.select** | 低 | 高频操作，现有 executor 已实现 selection 逻辑，独立命令更直接可靠 |
| 1 | **ui.tab.select** | 中 | TabBar 切换高频操作，当前完全无等价替代 |

### P1 - 建议实现（中等价值）

| 优先级 | 命令 | 复杂度 | 理由 |
|--------|------|--------|------|
| 2 | **ui.longPress** | 低 | 手势语义独特，复用 UIGestureTargetExecutor |
| 2 | **ui.refreshControl.trigger** | 低 | pullToRefresh 语义与 scroll 不同，部分 App 自定义刷新逻辑 |

### P2 - 可延后（有价值但非必须）

| 优先级 | 命令 | 复杂度 | 理由 |
|--------|------|--------|------|
| 3 | **ui.picker.select** | 高 | UIPickerView 非 UIControl，唯一真正缺少新命令的场景 |
| 3 | **ui.swift/slider get/set** | 低 | inspect/sendAction 响应已覆盖，语义更清晰但非必须 |

### P3 - 不建议实现

| 优先级 | 命令 | 理由 |
|--------|------|------|
| 4 | **ui.property.get/set** | inspect full 档已输出所有属性，冗余 |
| 4 | **ui.stepper.set** | sendAction+value 已覆盖 |
| 5 | **ui.progress.set** | 无实际自动化场景 |
| 5 | **ui.view.create/delete** | 纯测试用途 |
| 5 | **ui.contextMenu** | iOS 版本兼容复杂，低频 |

---

## 已设计但未实现

| 设计文档 | 状态 | 说明 |
|----------|------|------|
| `2026-06-30-action-commands-design.md` | 部分实现 | input text/dismiss、scrollIntoView 未完成；keyboard dismiss 已实现 |
| `2026-07-05-uitableviewcell-tap-selection-design.md` | 未实现 | 等价于 ui.cell.select |
| `2026-06-25-typed-command-input-schema-design.md` | 待评估 | typed command input schema |

---

## 关键发现

1. **sendAction + inspect 组合覆盖了大部分场景**：9 个属性命令中 7 个已被覆盖
2. **唯一真正需要新命令的场景是 UIPickerView**（非 UIControl，sendAction 无效）
3. **sheet/modal dismiss 已被 `navigation.back(strategy:dismiss)` 覆盖**，无需独立命令
4. **已设计但未实现的功能**：`scrollIntoView`、`cell tap selection`

---

## 实施建议

### 第一阶段：P0 命令（预计 2-3 天）

1. **ui.cell.select** - 复用现有 selection 逻辑，独立命令
2. **ui.swipe** - UISwipeGestureRecognizer 触发
3. **ui.tab.select** - UITabBarController selectedIndex 控制

### 第二阶段：P1 命令（预计 1-2 天）

4. **ui.longPress** - 复用 UIGestureTargetExecutor
5. **ui.refreshControl.trigger** - UIRefreshControl 触发

### 第三阶段：P2 命令（按需）

6. **ui.picker.select** - UIDatePicker 先做，UIPickerView 后做

---

## 架构参考

所有新命令遵循现有架构模式：

```
Commands/<Feature>/
├── <Feature>Command.swift      # Command struct (adapter)
├── <Feature>Input.swift       # Input model (Foundation-only)
└── <Feature>Executor.swift    # @MainActor enum executor
```

- **Adapter**: 实现 `Command` 协议，MainActor.run 调用 executor，catch UIKitCommandError 转 envelope
- **Input**: Foundation-only，字段走 CommandFields.* 声明，解析走 CommandInputDecoder
- **Executor**: @MainActor enum，抛出 UIKitCommandError，private 辅助方法返回 JSON
