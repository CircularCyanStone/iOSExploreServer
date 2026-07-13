# iOSExploreServer 命令缺口分析报告

> 分析日期: 2026-07-13
> 分析目标: 识别 iOSExploreServer 当前命令集与常用 iOS 自动化场景之间的差距

---

## 一、当前命令覆盖现状

### 1.1 已有命令分类（共 34 个）

| 类别 | 命令 | 说明 |
|------|------|------|
| **静态工具** | `health_check`, `refresh_tools`, `call_action`, `wait_and_inspect` | 4 个 |
| **检查/观察** | `ui.inspect`, `ui.topViewHierarchy`, `ui.controllers`, `ui.screenshot` | 4 个 |
| **点击/激活** | `ui.tap`, `ui.alert_respond`, `ui.navigation.tapBarButton` | 3 个 |
| **滚动** | `ui.scroll`, `ui.scrollToElement` | 2 个 |
| **输入** | `ui.input`, `ui.keyboard_dismiss` | 2 个 |
| **控制** | `ui.control.sendAction` | 1 个 |
| **等待** | `ui.wait`, `ui.waitAny` | 2 个 |
| **导航** | `ui.navigation.back` | 1 个 |
| **日志/调试** | `app.logs.mark`, `app.logs.read`, `debug.emit*`, `debug.probe` | 8+ 个 |
| **其他** | `device`, `echo`, `greet`, `help`, `info`, `ping` | 6 个 |

### 1.2 已实现但未暴露的底层能力

从源码分析，以下 UIKit 控件操作**已有底层支持**：

1. **UISwitch**: 通过 `ui.control.sendAction` + `valueChanged` + `value: 0/1`
2. **UISlider**: 通过 `ui.control.sendAction` + `valueChanged` + `value: Float`
3. **UISegmentedControl**: 通过 `ui.control.sendAction` + `valueChanged` + `value: Int`
4. **UIStepper**: 通过 `ui.control.sendAction` + `valueChanged` + `value: Double`
5. **UITextField/UITextView**: 通过 `ui.input` (replace/append 模式)

---

## 二、缺失的常用命令

### 2.1 高优先级缺失

| 命令 | 场景 | 必要性分析 |
|------|------|------------|
| **`ui.longPress`** | Context Menu、Force Touch、3D Touch、长按删除 | **必备** |
| **`ui.swipe`** | Swipe to delete、dismiss cards/sheets、Carousel 滑动 | **必备** |
| **`ui.drag`** | 拖拽排序、精确 slider 拖动、手势密码绘制 | **常用** |
| **`ui.pullToRefresh`** | 下拉刷新触发 | **常用** |
| **`ui.picker.select`** | UIPickerView / UIDatePicker 选择 | **必备** |
| **`ui.segmentedControl.select`** | 分段控制切换（已有 sendAction，但缺少专用命令） | **常用** |
| **`ui.list.selectCell`** | TableView/CollectionView 按 indexPath 选择 cell | **常用** |
| **`ui.text.clear`** | 清空文本框内容（当前需 ui.input 配合 replace 模式） | **可用 ui.input 替代** |
| **`ui.keyboard.key`** | 输入键盘特定键（return、delete、escape） | **常用** |

### 2.2 中优先级缺失

| 命令 | 场景 | 必要性分析 |
|------|------|------------|
| **`ui.pinch`** | 捏合缩放（zoom in/out） | 移动端低频 |
| **`ui.list.scrollToRow`** | TableView 滚动到指定行/section | 可用 ui.scrollToElement 替代 |
| **`ui.coordinate.tap`** | 按屏幕坐标点击 | 调试用 |
| **`ui.hud.wait`** | 等待 ActivityIndicator/UIActivityIndicatorView 消失 | 等待场景补充 |
| **`ui.sheet.dismiss`** | 显式 dismiss 当前 sheet | 可用 ui.navigation.back |
| **`ui.webView.evaluate`** | WKWebView JavaScript 注入执行 | WebView 场景 |
| **`ui.tabBar.select`** | Tab Bar 切换（已有 tapBarButton，但缺少按 index/name 选择） | **常用** |

### 2.3 低优先级/可选

| 命令 | 场景 | 必要性分析 |
|------|------|------------|
| **`app.lifecycle`** | 后台/前台切换 | 真机调试用 |
| **`ui.shake`** | 摇动手势触发 | 低频 |
| **`ui.orientation`** | 屏幕旋转 | 低频 |
| **`ui.screenshot.save`** | 截图保存到相册 | 调试用 |

---

## 三、缺失命令详细分析

### 3.1 `ui.longPress` - 长按操作

**场景**:
- 触发 Context Menu (`UILongPressGestureRecognizer`)
- 3D Touch / Haptic Touch 预览
- 长按拖拽排序

**参数设计建议**:
```json
{
  "accessibilityIdentifier": "string",
  "path": "string",
  "viewSnapshotID": "string",
  "duration": 0.5  // 秒，默认 0.5
}
```

**实现方案**:
- 利用现有 `UIGestureRecognizer` 解析逻辑（参考 `UIGestureRecognizer+Trigger.swift`）
- 构造 `UILongPressGestureRecognizer` 并手动触发 `.began` 状态

---

### 3.2 `ui.swipe` - 滑动手势

**场景**:
- Swipe to delete（TableView 行删除）
- Swipe actions（iOS 11+ leading/trailing swipe actions）
- Dismiss modal sheets/cards
- Carousel 滑动

**参数设计建议**:
```json
{
  "accessibilityIdentifier": "string",
  "path": "string",
  "viewSnapshotID": "string",
  "direction": "left|right|up|down",
  "distance": 0.8  // 滑动距离比例 0-1，默认 0.8
}
```

**实现方案**:
- 利用 `UIScrollView` 的 pan gesture 或构造 `UIPanGestureRecognizer`
- iOS 13+ sheet dismissal 可用 `dismiss(animated:)`

---

### 3.3 `ui.drag` - 拖拽操作

**场景**:
- 拖拽排序（TableView/CollectionView reorder）
- 精确 slider 拖动（比 sendAction 更精细）
- 手势密码绘制

**参数设计建议**:
```json
{
  "accessibilityIdentifier": "string",
  "path": "string",
  "viewSnapshotID": "string",
  "fromX": 100,
  "fromY": 200,
  "toX": 300,
  "toY": 200,
  "duration": 1.0
}
```

---

### 3.4 `ui.picker.select` - Picker 选择

**场景**:
- 日期选择 (`UIDatePicker`)
- 滚轮选择 (`UIPickerView`)

**参数设计建议**:
```json
{
  "accessibilityIdentifier": "string",
  "path": "string",
  "viewSnapshotID": "string",
  "component": 0,  // UIPickerView 列下标
  "row": 0,        // 要选择的行
  "value": "2024-01-01"  // UIDatePicker 时用字符串
}
```

**实现方案**:
- `UIDatePicker`: 直接设置 `date` 属性 + `sendActionsForControlEvents(.valueChanged)`
- `UIPickerView`: 调用 `selectRow(_:inComponent:animated:)` + `sendActionsForControlEvents(.valueChanged)`

---

### 3.5 `ui.list.selectCell` - 列表 Cell 选择

**场景**:
- 按 section/item 下标选择 TableView/CollectionView cell
- 不依赖 accessibilityIdentifier

**参数设计建议**:
```json
{
  "accessibilityIdentifier": "string",
  "path": "string",
  "viewSnapshotID": "string",
  "section": 0,
  "item": 0
}
```

**实现方案**:
- `UITableView.selectRow(at:animated:scrollPosition:)`
- `UICollectionView.selectItem(at:animated:scrollPosition:)`

---

### 3.6 `ui.keyboard.key` - 键盘按键

**场景**:
- 输入框内按 Return 键提交表单
- 按 Delete 删除字符
- 按 Escape 取消输入

**参数设计建议**:
```json
{
  "key": "return|delete|escape|space|tab",
  "repeat": 1  // 重复次数
}
```

**实现方案**:
- 查找 first responder 的 `UITextInput`
- 调用 `insertText("\n")` 等效 return
- 调用 `deleteBackward()` 删除

---

### 3.7 `ui.pullToRefresh` - 下拉刷新

**场景**:
- 触发 `UIRefreshControl`
- 等待数据刷新完成

**参数设计建议**:
```json
{
  "accessibilityIdentifier": "string",
  "path": "string",
  "viewSnapshotID": "string",
  "waitForComplete": true,
  "timeoutMs": 10000
}
```

**实现方案**:
- 找到 `UIRefreshControl`
- 调用 `beginRefreshing()` 触发
- 可选等待 `endRefreshing` 回调

---

### 3.8 `ui.tabBar.select` - Tab Bar 切换

**场景**:
- 按 index 或 title 选择 Tab

**参数设计建议**:
```json
{
  "index": 0,  // 从 0 开始
  "title": "Settings"  // 或按标题选择
}
```

---

## 四、与 Appium/Detox 功能对比

| 功能 | Appium | Detox | iOSExploreServer | 状态 |
|------|--------|-------|------------------|------|
| 基础点击 | ✅ | ✅ | ✅ ui.tap | 已有 |
| 长按 | ✅ | ✅ | ❌ | **缺失** |
| 滑动 | ✅ | ✅ | ❌ | **缺失** |
| 拖拽 | ✅ | ✅ | ❌ | **缺失** |
| 文本输入 | ✅ | ✅ | ✅ ui.input | 已有 |
| 键盘按键 | ✅ | ✅ | ❌ | **缺失** |
| 滚动 | ✅ | ✅ | ✅ ui.scroll, ui.scrollToElement | 已有 |
| 下拉刷新 | ✅ | ✅ | ❌ | **缺失** |
| Picker 选择 | ✅ | ✅ | ❌ | **缺失** |
| Switch | ✅ | ✅ | ✅ ui.control.sendAction | 已有 |
| Slider | ✅ | ✅ | ✅ ui.control.sendAction | 已有 |
| Segmented | ✅ | ✅ | ✅ ui.control.sendAction | 已有 |
| Table Cell 选择 | ✅ | ✅ | ❌ | **缺失** |
| Alert 响应 | ✅ | ✅ | ✅ ui.alert_respond | 已有 |
| 截图 | ✅ | ✅ | ✅ ui.screenshot | 已有 |
| 等待条件 | ✅ | ✅ | ✅ ui.wait, ui.waitAny | 已有 |
| WebView 操作 | ✅ | ❌ | ❌ | 低优先级 |

---

## 五、实现优先级建议

### Phase 1 - 必备功能（建议立即实现）

1. **`ui.longPress`** - Context Menu 必备
2. **`ui.swipe`** - Swipe to delete 必备
3. **`ui.picker.select`** - 日期/滚轮选择必备
4. **`ui.keyboard.key`** - 表单提交流程必备

### Phase 2 - 常用功能（建议近期实现）

5. **`ui.drag`** - 拖拽排序
6. **`ui.list.selectCell`** - 精确 Cell 定位
7. **`ui.pullToRefresh`** - 下拉刷新
8. **`ui.tabBar.select`** - Tab 切换

### Phase 3 - 增强功能（按需实现）

9. **`ui.pinch`** - 捏合缩放
10. **`ui.webView.evaluate`** - WebView 操作
11. **`ui.hud.wait`** - 等待 HUD

---

## 六、现有能力增强建议

### 6.1 `ui.control.sendAction` 可增强

当前 `ui.control.sendAction` 已支持 UISwitch/UISlider/UISegmentedControl/UIStepper，
但缺少**专用命令**。建议：

- 添加 `ui.switch.toggle` - 更语义化的 Switch 操作
- 添加 `ui.slider.set` - 更语义化的 Slider 操作
- 添加 `ui.segmentedControl.select` - 更语义化的 Segmented Control 操作

### 6.2 `ui.navigation.back` 可增强

当前 `ui.navigation.back` 使用 `auto` 策略，但无法处理：
- 特定 modal 的 dismiss（如 `UISheetPresentationController`）
- Tab Bar 内返回

建议：
- 添加 `ui.modal.dismiss` - 显式 dismiss 当前 modal
- 添加 `ui.tabBar.select` - Tab 切换

---

## 七、总结

### 7.1 核心差距

| 差距类型 | 数量 | 说明 |
|----------|------|------|
| **缺失手势命令** | 3 个 | longPress, swipe, drag |
| **缺失选择器命令** | 3 个 | picker, listCell, tabBar |
| **缺失键盘命令** | 1 个 | keyboard key |
| **缺失刷新命令** | 1 个 | pullToRefresh |

### 7.2 推荐实现顺序

1. `ui.longPress` - 最高频缺失
2. `ui.swipe` - Swipe to delete 是 iOS 最常见操作
3. `ui.picker.select` - 日期选择是强需求
4. `ui.keyboard.key` - 表单提交流程
5. `ui.list.selectCell` - 精确列表操作
6. `ui.drag` - 拖拽排序
7. `ui.pullToRefresh` - 刷新场景
8. `ui.tabBar.select` - Tab 操作

---

## 八、附录

### A. 当前命令完整列表

静态工具 (4): `health_check`, `refresh_tools`, `call_action`, `wait_and_inspect`

UIKit 动态命令 (30+):
- `app.logs.mark`, `app.logs.read`
- `debug.emitAppLog`, `debug.emitLogger`, `debug.emitNSLog`, `debug.emitOSLog`, `debug.emitStderr`, `debug.emitStdout`, `debug.probe`
- `device`, `echo`, `greet`, `help`, `info`, `ping`
- `ui.alert_respond`
- `ui.control_sendAction`
- `ui.controllers`
- `ui.input`
- `ui.inspect`
- `ui.keyboard_dismiss`
- `ui.navigation_back`
- `ui.navigation_tapBarButton`
- `ui.screenshot`
- `ui.scroll`
- `ui.scrollToElement`
- `ui.tap`
- `ui.topViewHierarchy`

### B. 相关文档

- 源码分析: `Sources/iOSExploreUIKit/Support/Action/`
- 命令注册: `Sources/iOSExploreUIKit/UIKitCommandRegistrar.swift`
- 手势解析: `Sources/iOSExploreUIKit/Support/Runtime/UIGestureRecognizer+Trigger.swift`
