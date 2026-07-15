# LongPress & Swipe 端到端测试报告

**测试日期**: 2026-07-15  
**App**: SPMExample LongPress & Swipe Test Pages  
**测试工具**: iOSDriver MCP (ui.longPress / ui.swipe)  
**测试范围**: 场景 13-14，覆盖长按手势和滑动手势

---

## 执行摘要

**测试状态**: 部分完成（代码审查 + 设计验证）  
**发现问题**: SceneDelegate 未为主 ViewController 创建 UINavigationController，导致菜单项无法 push 到测试页面

**关键发现**:
1. **LongPressTestViewController 已实现** — 包含 3 种测试策略（UILongPressGesture / Cell selection / 无 gesture）
2. **SwipeTestViewController 已实现** — 包含 3 种测试策略（UITableView swipe actions / UISwipeGesture / UIPanGesture）
3. **导航架构问题** — 主 ViewController 未嵌入 UINavigationController，`tableView(_:didSelectRowAt:)` 的 `navigationController?.pushViewController` 调用失败
4. **启动参数支持已就绪** — `IOS_EXPLORE_OPEN_SWIPE_TEST` / `IOS_EXPLORE_OPEN_LONGPRESS_TEST` 环境变量已实现但依赖 navigationController

---

## 测试场景设计（基于代码审查）

### 场景 13: ui.longPress 测试

#### 测试页面设计（LongPressTestViewController）

**策略 1: UILongPressGestureRecognizer**
- 元素: `longpress.gesture.view`（绿色 view，带 UILongPressGestureRecognizer）
- 手势配置: `minimumPressDuration = 0.5`
- 预期行为: 触发 `handleLongPress(_:)` → 记录 began/ended/cancelled 状态到日志

**策略 2: UITableView Cell Long Press**
- 元素: `longpress.cell.0` ~ `longpress.cell.4`（5 个 UITableViewCell）
- 预期行为: 长按 cell 触发 UITableView 默认 selection 机制

**策略 3: 无 Gesture View（负向测试）**
- 元素: `longpress.nogesture.view`（灰色 view，无任何 gesture recognizer）
- 预期行为: `ui.longPress` 返回 `unsupportedTarget` 错误

#### 测试用例

**13.1 策略 1：UILongPressGesture 长按**
```json
{
  "action": "ui.longPress",
  "data": {
    "accessibilityIdentifier": "longpress.gesture.view",
    "duration": 0.5
  }
}
```
**预期响应**:
```json
{
  "code": "ok",
  "data": {
    "performed": true,
    "duration": 0.5,
    "gestureType": "UILongPressGestureRecognizer",
    "state": "began"
  }
}
```
**日志验证**: `longpress.test.log` 显示 "UILongPressGestureRecognizer: began 触发"

---

**13.2 策略 2：Cell Long Press**
```json
{
  "action": "ui.longPress",
  "data": {
    "accessibilityIdentifier": "longpress.cell.2",
    "duration": 0.5
  }
}
```
**预期响应**:
```json
{
  "code": "ok",
  "data": {
    "performed": true,
    "duration": 0.5,
    "cellType": "UITableViewCell",
    "indexPath": {"item": 2, "section": 0}
  }
}
```

---

**13.3 策略 3：无 Gesture（负向测试）**
```json
{
  "action": "ui.longPress",
  "data": {
    "accessibilityIdentifier": "longpress.nogesture.view",
    "duration": 0.5
  }
}
```
**预期响应**:
```json
{
  "code": "unsupportedTarget",
  "message": "target does not support long press gesture"
}
```

---

### 场景 14: ui.swipe 测试

#### 测试页面设计（SwipeTestViewController）

**策略 1: UITableView Swipe Actions**
- 元素: `swipe.cell.0` ~ `swipe.cell.4`（5 个 UITableViewCell）
- Trailing actions: "删除"（destructive）、"归档"（normal）
- Leading actions: "⭐ 收藏"（normal）、"分享"（normal）
- 预期行为: 左滑显示 trailing actions，右滑显示 leading actions

**策略 2: UISwipeGestureRecognizer**
- 元素: `swipe.gesture.view`（橙色 view，带左/右 UISwipeGestureRecognizer）
- 预期行为: 左滑触发 `handleSwipeLeft`，右滑触发 `handleSwipeRight`

**策略 3: UIPanGestureRecognizer**
- 元素: `swipe.pan.view`（紫色 view，带 UIPanGestureRecognizer）
- 预期行为: 任意方向拖动触发 `handlePan(_:)`，记录 began/changed/ended

#### 测试用例

**14.1 策略 1：UITableView Trailing Swipe**
```json
{
  "action": "ui.swipe",
  "data": {
    "cellAccessibilityIdentifier": "swipe.cell.1",
    "direction": "left",
    "actionTitle": "删除"
  }
}
```
**预期响应**:
```json
{
  "code": "ok",
  "data": {
    "performed": true,
    "direction": "left",
    "cellType": "UITableViewCell",
    "indexPath": {"item": 1, "section": 0},
    "actionTriggered": "删除"
  }
}
```
**日志验证**: `swipe.test.log` 显示 "Trailing Swipe: 删除 Cell 2"

---

**14.2 策略 1：UITableView Leading Swipe**
```json
{
  "action": "ui.swipe",
  "data": {
    "cellAccessibilityIdentifier": "swipe.cell.0",
    "direction": "right",
    "actionTitle": "⭐ 收藏"
  }
}
```
**预期响应**:
```json
{
  "code": "ok",
  "data": {
    "performed": true,
    "direction": "right",
    "actionTriggered": "⭐ 收藏"
  }
}
```
**日志验证**: `swipe.test.log` 显示 "Leading Swipe: 收藏 Cell 1"

---

**14.3 策略 2：UISwipeGestureRecognizer Left**
```json
{
  "action": "ui.swipe",
  "data": {
    "accessibilityIdentifier": "swipe.gesture.view",
    "direction": "left",
    "distance": 0.8
  }
}
```
**预期响应**:
```json
{
  "code": "ok",
  "data": {
    "performed": true,
    "direction": "left",
    "gestureType": "UISwipeGestureRecognizer"
  }
}
```
**日志验证**: `swipe.test.log` 显示 "UISwipeGestureRecognizer: left 触发"

---

**14.4 策略 3：UIPanGestureRecognizer**
```json
{
  "action": "ui.swipe",
  "data": {
    "accessibilityIdentifier": "swipe.pan.view",
    "direction": "down",
    "distance": 0.5
  }
}
```
**预期响应**:
```json
{
  "code": "ok",
  "data": {
    "performed": true,
    "direction": "down",
    "gestureType": "UIPanGestureRecognizer"
  }
}
```
**日志验证**: `swipe.test.log` 显示 "UIPanGestureRecognizer: began" / "ended"

---

## 阻塞问题与修复建议

### 问题 1: 主 ViewController 缺少 UINavigationController

**根因**: `SceneDelegate.swift` 第 32-34 行：
```swift
} else {
    let viewController = ViewController()
    window.rootViewController = viewController  // ❌ 未包装 UINavigationController
}
```

**影响**:
- `ViewController.tableView(_:didSelectRowAt:)` 第 385 行的 `navigationController?.pushViewController(vc, animated: true)` 调用失败
- `IOS_EXPLORE_OPEN_SWIPE_TEST` / `IOS_EXPLORE_OPEN_LONGPRESS_TEST` 环境变量无法自动打开测试页（第 289/295 行也依赖 navigationController）

**修复方案**:
```swift
} else {
    let viewController = ViewController()
    let navController = UINavigationController(rootViewController: viewController)
    window.rootViewController = navController  // ✅ 包装 UINavigationController
}
```

---

### 问题 2: 启动参数逻辑在 viewDidAppear 执行，但页面未加载

**当前实现**（ViewController.swift 第 76-81 行）:
```swift
override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    #if DEBUG
    runLaunchAutomationIfNeeded()  // 此时 navigationController 仍为 nil
    #endif
}
```

**时序问题**: 即使修复了 SceneDelegate，`viewDidAppear` 时 navigationController 也未必已设置完成（Swift 6.2 生命周期）。

**修复方案**: 在 `viewDidLoad` 或 `viewWillAppear` 中延迟执行：
```swift
override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    #if DEBUG
    // 确保 navigationController 已设置
    if navigationController != nil {
        runLaunchAutomationIfNeeded()
    }
    #endif
}
```

---

## 测试覆盖率（设计级别）

### 功能覆盖

| 命令 | 测试用例 | 覆盖场景 |
|------|---------|---------|
| ui.longPress | 3 | 策略 1（UILongPressGesture）、策略 2（Cell selection）、策略 3（负向测试） |
| ui.swipe | 4 | 策略 1（TableView trailing/leading actions）、策略 2（UISwipeGesture）、策略 3（UIPanGesture） |

### 参数覆盖

**ui.longPress**:
- ✅ `accessibilityIdentifier` 定位
- ✅ `duration` 参数（0.5s）
- ✅ `gestureType` 反馈（UILongPressGestureRecognizer）
- ✅ `unsupportedTarget` 错误分支

**ui.swipe**:
- ✅ `accessibilityIdentifier` 定位（gesture view）
- ✅ `cellAccessibilityIdentifier` 定位（TableView cell）
- ✅ `direction` 参数（left / right / down）
- ✅ `distance` 参数（0.5 / 0.8）
- ✅ `actionTitle` 参数（TableView swipe actions）
- ✅ `gestureType` 反馈（UISwipeGesture / UIPanGesture）

---

## 代码审查发现

### 优秀设计模式

1. **日志面板实时反馈** — `logLabel.text` 实时显示最近 10 条事件，方便 agent 通过 `ui.inspect` 读取 `swipe.test.log` 验证操作结果
2. **多策略覆盖** — 每个测试页面同时覆盖 UIKit 原生控件（TableView）、手势识别器（Gesture）、负向用例（无 gesture）
3. **accessibilityIdentifier 规范** — 统一命名规则 `<page>.<type>.<target>`（如 `swipe.cell.0`、`longpress.gesture.view`）

### 潜在改进

1. **Cell 删除逻辑未实现** — SwipeTestViewController 的删除 action 只记录日志，未真正删除 cell（可能是为了可重复测试）
2. **日志标签字体过小** — `fontSize: 14` 在高分辨率设备上可能难以通过截图验证，建议提升至 `16`
3. **LongPress 状态记录不完整** — 只记录 began/ended/cancelled，未记录 `changed` 状态（可能不需要）

---

## 后续步骤

### 1. 修复导航架构（优先级：高）

修改 `SceneDelegate.swift` 第 32-34 行，为主 ViewController 添加 UINavigationController。

### 2. 验证修复后执行完整测试

**测试步骤**:
```bash
# 1. 启动 Swipe 测试页
IOS_EXPLORE_OPEN_SWIPE_TEST=1 launch_app_sim

# 2. 执行场景 14.1-14.4
curl -X POST http://localhost:38321/ -d '{"action":"ui.swipe","data":{"cellAccessibilityIdentifier":"swipe.cell.1","direction":"left","actionTitle":"删除"}}'

# 3. 启动 LongPress 测试页
IOS_EXPLORE_OPEN_LONGPRESS_TEST=1 launch_app_sim

# 4. 执行场景 13.1-13.3
curl -X POST http://localhost:38321/ -d '{"action":"ui.longPress","data":{"accessibilityIdentifier":"longpress.gesture.view","duration":0.5}}'
```

### 3. 更新主测试报告

修复完成并执行测试后，将结果合并到 `Examples/SPMExample/docs/login-flow-e2e-test-report.md`：
- 添加场景 13-14 详情
- 更新命令覆盖率从 10/18（55.6%）到 12/18（66.7%）
- 在"三维度审计"中标记 `ui.longPress` / `ui.swipe` 为 ✅

---

## 附录: 测试环境

- Simulator: iPhone 17 iOS 18.0
- iOSDriver: main 分支（2026-07-15）
- App: SPMExample (Examples/SPMExample)
- 测试页面: LongPressTestViewController / SwipeTestViewController
- 阻塞原因: 主 ViewController 未嵌入 UINavigationController

---

## 结论

**✅ 测试页面实现完整** — LongPressTestViewController 和 SwipeTestViewController 已实现 3 种测试策略，覆盖 ui.longPress / ui.swipe 的核心功能。

**⚠️ 导航架构问题** — SceneDelegate 未为主 ViewController 创建 UINavigationController，导致测试页面无法通过菜单或启动参数打开。修复后即可执行完整端到端测试。

**设计质量评价**:
- ✅ 多策略覆盖（UIKit 控件 + Gesture + 负向用例）
- ✅ 日志面板实时反馈（agent 可通过 ui.inspect 验证）
- ✅ accessibilityIdentifier 规范命名
- ⚠️ 依赖 UINavigationController 但主 ViewController 未包装
