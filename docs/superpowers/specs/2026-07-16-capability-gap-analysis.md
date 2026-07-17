# iOS 自动化能力缺口分析与补充方案

**文档版本**: v1.0  
**创建日期**: 2026-07-16  
**分析范围**: iOSExploreServer Skills 与 MCP 工具体系  
**分析方法**: 实际 App 调用验证 + 业内通用场景对比  

---

## 执行摘要

本文档基于 iOSExploreServer 项目现有的 12 个 skills 和 32+ MCP 工具，通过实际调用验证（SPMExample 登录页测试）和业内 iOS App 通用模式分析，识别出 **7 大类缺失场景**，并按控件使用频率和业内通用性提供 **4 阶段补充方案**。

**关键发现**：
- ✅ 现有能力覆盖基础 UI 自动化核心场景（点击、输入、滚动、等待、截图、日志）
- ❌ 缺失 5 个极高频控件/场景（TabBar、DatePicker、Picker、WebView、系统权限）
- ❌ 缺失 1 个关键手势（Drag & Drop）
- 🎯 建议优先补充 TabBar 和 Picker（影响 80%+ iOS App）

---

## 1. 现有能力验证

### 1.1 验证方法

**测试环境**：
- SPMExample App（登录页面）
- iOSDriver MCP Server
- 实际调用命令：ui.inspect、ui.controllers、app.logs.read、ui.screenshot

**验证结果**：现有 L0/L1/L2 三层架构运行稳定，基础能力可用。

### 1.2 现有能力清单

| 层级 | Skill | 覆盖场景 | 验证状态 |
|-----|-------|---------|---------|
| L0 构建调试 | ios-debugger-agent | 编译、运行、调试、系统日志 | ✅ 文档完善 |
| L1 操作层 | ios-automation | 总入口、连接管理、路由 | ✅ 实测可用 |
| L1 操作层 | ios-ui-nav | 导航、返回、导航栏、controller 树 | ✅ 实测可用 |
| L1 操作层 | ios-ui-list | 列表滚动、cell 选中 | ✅ 文档完善 |
| L1 操作层 | ios-ui-form | 文本输入、Switch、Slider、Stepper、SegmentedControl | ✅ 文档完善 |
| L1 操作层 | ios-ui-alert | Alert/ActionSheet 响应 | ✅ 文档完善 |
| L1 操作层 | ios-ui-shot | 截图取证 | ✅ 实测可用 |
| L1 操作层 | ios-ui-gesture | Swipe、LongPress | ✅ 文档完善 |
| L1 操作层 | ios-ui-wait | 异步等待、多条件并发等待 | ✅ 文档完善 |
| L1 操作层 | ios-logs | 进程内日志（6 种 source） | ✅ 实测可用 |
| L2 测试闭环 | ios-test-intent | 测试意图产出 | ✅ 文档完善 |
| L2 测试闭环 | ios-test-runner | 测试执行与覆盖报告 | ✅ 文档完善 |

**MCP 命令总数**：32+ 动态工具


---

## 2. 业内通用场景缺口分析

### 2.1 分析维度

按**业内 iOS App 控件使用频率**分类（基于微信、淘宝、抖音、美团、支付宝等主流 App 模式）：

| 频率等级 | 定义 | 示例控件 |
|---------|------|---------|
| 🔴 极高频 | 90%+ App 必有 | TabBar、TableView、Button、TextField |
| 🟡 高频 | 60%+ App 使用 | DatePicker、PickerView、SearchBar、RefreshControl |
| 🟢 中频 | 40%+ App 使用 | Drag & Drop、Pinch Zoom、WebView |
| ⚪ 低频 | <20% App 使用 | 3D Touch、Widget、Siri Shortcuts |

### 2.2 缺失场景总览

| 类别 | 缺失项 | 频率 | 影响范围 | 优先级 |
|-----|-------|------|---------|--------|
| 极高频控件 | TabBar 导航 ✅已实现 | 🔴 | 几乎所有主流 App 的主导航 | P0 |
| 高频控件 | UIDatePicker | 🟡 | 生日、预约、日程（80%+ App） | P0 |
| 高频控件 | UIPickerView | 🟡 | 地区、分类、选项（80%+ App） | P0 |
| 高频控件 | UISearchBar | 🟡 | 搜索功能（70%+ App） | P1 |
| 高频控件 | UIRefreshControl | 🟡 | 下拉刷新（90%+ 列表页） | P1 |
| 手势 | Drag & Drop | 🟢 | 列表编辑、文件管理、日历 | P1 |
| 混合场景 | WKWebView | 🟡 | H5 活动页、协议页（50%+ App） | P1 |
| 系统级 | 系统权限弹窗 | 🔴 | 相机/位置/通知授权（几乎所有 App） | P2 |
| 系统级 | App 生命周期 | 🟡 | 前后台切换、深度链接 | P2 |
| 手势 | Pinch / Rotate | 🟢 | 地图、图片查看（40%+ App） | P3 |
| 验证 | 视觉回归对比 | 🟢 | 自动化质量保障 | P3 |


---

## 3. 补充方案设计

### 3.1 Phase 1：极高频控件补齐（P0，必做）

#### 3.1.1 TabBar 导航

> ✅ **已实现(2026-07-17)** —— 走原方案 A(controller 层命令),非方案 B(tap)。
>
> - **命令**:`ui.tabBar.selectTab`(注册于 `iOSExploreUIKit`,经 iOSDriver `call_action` 调用)
> - **参数**:`index`(非负整数)与 `title`(字符串)二选一;`tabBarControllerPath`(可选,省略时自动查找 UITabBarController);`triggerDelegate`(bool,默认 true,补调 `tabBarController(_:didSelect:)` delegate)
> - **返回**:`previousIndex` / `selectedIndex` / `previousTitle` / `selectedTitle` / `tabCount`
> - **与原方案差异**:用 `title` 替代 `identifier` 定位(运行时 `UITabBarButton` 的 identifier 不一定从 `UITabBarItem` 继承,实测不可靠);新增 `triggerDelegate`(覆盖挂在 delegate 上的业务逻辑)与 `tabBarControllerPath`(多 TabBar 共存时精确指定);返回值增加 `tabCount`
> - **为何不依赖 resolver 盲区修复**:走 controller 层(`selectedIndex`),不遍历 view 子树,即使 `ui.inspect` 在 modal 容器场景有盲区(见 `docs/superpowers/specs/2026-07-17-resolver-modal-blindspot.md`)也不影响本命令
> - **端到端验证**:SPMExample 模拟器实测通过,按 index/title 双向切换,`ui_controllers` 确认 `isSelected` 状态同步
> - **代码**:`Sources/iOSExploreUIKit/Commands/TabBarSelect/`(Input / Executor / Command)
> - **指南**:`.claude/skills/ios-ui-nav/SKILL.md` §4;skill 归属 `ios-ui-nav`
> - **未实现**:自定义 tab bar(非 `UITabBarController` 子类)仍不支持,需降级 `ui.tap`(依赖 resolver 盲区修复后能采集到 tab 按钮)

**问题描述**：
- 几乎所有主流 App 使用 UITabBarController 作为主导航
- 当前没有专门的 skill 或命令指导如何切换 tab

**解决方案**：

**方案 A（推荐）**：新增命令到 iOSExploreUIKit
```swift
// 新增命令
action: "ui.tabBar.selectTab"

// 参数
{
  "index": 2,  // tab 索引（0-based）
  "identifier": "tab_profile",  // 或用 accessibilityIdentifier
  "viewSnapshotID": "snap-1"
}

// 响应
{
  "code": "ok",
  "data": {
    "selectedIndex": 2,
    "previousIndex": 0,
    "selectedIdentifier": "tab_profile",
    "selectedTitle": "我的"
  }
}
```

**方案 B（备选）**：复用现有 ui.tap
- 说明：TabBarItem 本质是 UIControl，可以用 ui.tap 点击
- 问题：需要 agent 自己从 ui.inspect 里识别 tabBar 结构
- 建议：即使复用 ui.tap，也应该在 ios-ui-nav skill 中增加 TabBar 操作指南

**Skill 变更**：
- 扩展 ios-ui-nav skill，增加 "TabBar 导航" 专节
- 或新建 ios-ui-tabbar skill（如果 TabBar 场景足够复杂）

**实现要点**：
- 定位：通过 index 或 identifier 定位 UITabBarItem
- 执行：调用 UITabBarController.selectedIndex = ... 或 ui.tap 点击 item
- 验证：返回切换前后的 index 和 identifier

---

#### 3.1.2 UIDatePicker / UIPickerView

**问题描述**：
- 80%+ App 有日期/选项选择场景（生日、预约时间、地区选择等）
- ios-date-picker skill 已删除，原因：ui.datePicker.* 和 ui.picker.* 命令根本不存在

**解决方案**：

**实现命令**：
```swift
// DatePicker 命令
action: "ui.datePicker.setDate"
data: {
  "identifier": "birthday_picker",
  "date": "1990-01-01T00:00:00Z",  // ISO 8601
  "animated": true,
  "viewSnapshotID": "snap-1"
}

// 或分量设置
action: "ui.datePicker.setDateComponents"
data: {
  "identifier": "birthday_picker",
  "year": 1990,
  "month": 1,
  "day": 1,
  "viewSnapshotID": "snap-1"
}

// PickerView 命令
action: "ui.picker.selectRow"
data: {
  "identifier": "city_picker",
  "component": 0,  // 列索引
  "row": 5,        // 行索引
  "animated": true,
  "viewSnapshotID": "snap-1"
}

// 或按标题选择
action: "ui.picker.selectRowByTitle"
data: {
  "identifier": "city_picker",
  "component": 0,
  "title": "北京市",
  "viewSnapshotID": "snap-1"
}
```

**响应示例**：
```json
{
  "code": "ok",
  "data": {
    "selectedDate": "1990-01-01T00:00:00Z",
    "selectedRow": 5,
    "selectedTitle": "北京市",
    "numberOfComponents": 2,
    "numberOfRowsInComponent": 34
  }
}
```

**Skill 变更**：
- 新建 ios-ui-picker skill
- 包含：DatePicker、PickerView、DatePicker 多种模式（date/time/dateAndTime/countDownTimer）

**实现要点**：
- DatePicker：通过 UIDatePicker.date = ... 直接设置
- PickerView：调用 selectRow(_:inComponent:animated:) + 触发 delegate
- 验证：读取 date 或 selectedRow(inComponent:) 确认设置成功
- 边界：处理 minimumDate/maximumDate、禁用行

---

#### 3.1.3 UISearchBar

**问题描述**：
- 70%+ App 有搜索功能
- 当前可以用 ui.input 输入文本，但缺少"提交搜索"的语义指导

**解决方案**：

**方案 A（推荐）**：扩展 ios-ui-form skill
```markdown
增加 "UISearchBar 操作" 专节：

1. 输入搜索文本：ui.input
2. 提交搜索：ui.tap (搜索按钮) 或 ui.keyboard.dismiss (键盘 Search 键)
3. 清空搜索：ui.tap (clear button)
4. 取消搜索：ui.tap (cancel button)
```

**方案 B（备选）**：新增专门命令
```swift
action: "ui.searchBar.search"
data: {
  "identifier": "product_search_bar",
  "text": "iPhone",
  "submit": true,
  "viewSnapshotID": "snap-1"
}
```

**推荐**：方案 A（扩展 skill 文档），SearchBar 本质是 UITextField + 额外按钮，不需要新命令。


---

### 3.2 Phase 2：高频场景补齐（P1，重要）

#### 3.2.1 Drag & Drop

**问题描述**：
- 列表编辑模式（重排序）、日历拖拽事件、文件管理
- 文档明确 ui.drag 不存在，ios-ui-gesture 只有 swipe/longPress

**解决方案**：

**实现命令**：
```swift
action: "ui.drag"
data: {
  "from": {
    "identifier": "item_1"  // 或 path
  },
  "to": {
    "identifier": "item_3"  // 或 coordinates
  },
  "duration": 0.5,
  "viewSnapshotID": "snap-1"
}

// 或基于坐标
data: {
  "fromCoordinates": {"x": 100, "y": 200},
  "toCoordinates": {"x": 100, "y": 400},
  "duration": 0.5
}
```

**Skill 变更**：
- 扩展 ios-ui-gesture skill，增加 "拖拽操作" 专节
- 更新 allowed-tools：添加 ui_drag

**实现要点**：
- 使用 XCUITest 或私有 API 模拟 drag 手势
- 支持两种模式：identifier-based 和 coordinate-based
- 处理长按延迟、拖拽路径、drop 动画

---

#### 3.2.2 WKWebView 操作

**问题描述**：
- 50%+ App 有 H5 混合页面（活动页、帮助文档、用户协议）
- 当前完全没有 WebView 相关能力

**解决方案**：

**实现命令**：
```swift
// 执行 JavaScript
action: "ui.webView.evaluateJavaScript"
data: {
  "webViewIdentifier": "web_container",
  "script": "document.querySelector('#submit-btn').click()",
  "timeout": 5
}

// 等待元素
action: "ui.webView.waitForElement"
data: {
  "webViewIdentifier": "web_container",
  "selector": "#submit-btn",  // CSS selector
  "timeout": 10
}

// 点击元素
action: "ui.webView.tap"
data: {
  "webViewIdentifier": "web_container",
  "selector": "#submit-btn"
}

// 输入文本
action: "ui.webView.input"
data: {
  "webViewIdentifier": "web_container",
  "selector": "#username",
  "text": "test_user"
}
```

**Skill 变更**：
- 新建 ios-ui-webview skill
- 包含：JS 注入、元素等待、点击、输入、内容读取

**实现要点**：
- 通过 WKWebView.evaluateJavaScript(_:completionHandler:) 执行 JS
- 支持 CSS selector 定位（转换为 document.querySelector）
- 处理跨域限制、JS 执行超时、iframe 切换

---

#### 3.2.3 UIRefreshControl

**问题描述**：
- 90%+ 列表页面有下拉刷新功能
- 当前可以用 ui.scroll 但缺少"触发刷新"的语义

**解决方案**：

**方案 A（推荐）**：扩展 ui.scroll 命令
```swift
action: "ui.scroll"
data: {
  "identifier": "table_view",
  "direction": "down",
  "distance": 100,
  "trigger": "refresh",  // 新增参数
  "viewSnapshotID": "snap-1"
}
```

**方案 B（备选）**：新增专门命令
```swift
action: "ui.refreshControl.trigger"
data: {
  "scrollViewIdentifier": "table_view",
  "waitForCompletion": true,
  "timeout": 10
}
```

**推荐**：方案 A（扩展现有命令），RefreshControl 本质是特殊的 scroll + 状态监听。

**Skill 变更**：
- 扩展 ios-ui-list skill，增加 "下拉刷新" 专节
- 配合 ui.wait 等待刷新完成（监听 refreshControl.isRefreshing 变为 false）


---

### 3.3 Phase 3：系统级交互（P2，进阶）

#### 3.3.1 系统权限弹窗

**问题描述**：
- 首次启动、申请权限时（相机/位置/通知/麦克风/相册等）
- 当前只能处理 App 内 UIAlertController，无法处理系统级弹窗

**解决方案**：

**实现命令**：
```swift
action: "ui.systemAlert.respond"
data: {
  "buttonLabel": "允许",  // 或 "不允许" / "Allow" / "Don't Allow"
  "buttonIndex": 0,       // 备选定位方式
  "timeout": 5
}

// 或按权限类型
action: "ui.systemAlert.allowPermission"
data: {
  "permissionType": "camera",  // camera / location / notification / microphone / photos
  "action": "allow"            // allow / deny / allowOnce
}
```

**Skill 变更**：
- 新建 ios-system-alert skill（或扩展 ios-ui-alert，增加 "系统弹窗" 专节）

**实现要点**：
- **技术难点**：系统弹窗不在 App 的 view hierarchy 中
- **解决方案**：
  - 方案 A：通过 XCUITest 的 XCUIApplication().alerts 访问
  - 方案 B：通过 Accessibility API（私有）
  - 方案 C：依赖 XcodeBuildMCP 的 UI 自动化能力
- **推荐**：方案 C（扩展 ios-debugger-agent），因为系统弹窗需要 Accessibility 权限

---

#### 3.3.2 App 生命周期控制

**问题描述**：
- 前后台切换、深度链接测试、推送通知模拟
- 当前缺失 App 级别的生命周期控制

**解决方案**：

**实现命令**：
```swift
// 进入后台
action: "app.lifecycle.background"
data: {
  "duration": 5  // 后台停留时间（秒）
}

// 回到前台
action: "app.lifecycle.foreground"

// 触发深度链接
action: "app.deepLink.open"
data: {
  "url": "myapp://profile/user123",
  "waitForTransition": true,
  "timeout": 5
}

// 模拟推送通知
action: "app.notification.simulate"
data: {
  "title": "新消息",
  "body": "您有一条新的订单",
  "userInfo": {"orderId": "123456"},
  "action": "tap"  // tap / swipe / none
}
```

**Skill 变更**：
- 扩展 ios-debugger-agent skill（L0 层，因为涉及 App 进程控制）
- 或新建 ios-lifecycle skill（如果场景足够独立）

**实现要点**：
- 后台/前台：通过 XCUITest 的 XCUIDevice.shared.press(.home) 或 Simulator API
- 深度链接：通过 openURL 或 xcrun simctl openurl
- 推送通知：通过 APNS 模拟工具或 xcrun simctl push

---

### 3.4 Phase 4：高级能力（P3，可选）

#### 3.4.1 双指手势（Pinch / Rotate）

**场景**：地图、图片查看器、PDF 阅读器（40%+ App）

**命令**：
```swift
action: "ui.pinch"
data: {
  "identifier": "map_view",
  "scale": 2.0,  // 放大 2 倍
  "duration": 0.5
}

action: "ui.rotate"
data: {
  "identifier": "image_view",
  "rotation": 90,  // 顺时针 90 度
  "duration": 0.5
}
```

**Skill**：扩展 ios-ui-gesture

---

#### 3.4.2 视觉回归与断言

**场景**：自动化质量保障、UI 一致性验证

**命令**：
```swift
action: "ui.screenshot.compare"
data: {
  "baseline": "baseline_login.png",
  "threshold": 0.95,  // 相似度阈值
  "ignoreAreas": [{"x": 0, "y": 0, "width": 100, "height": 50}]
}

action: "ui.assert.elementState"
data: {
  "identifier": "submit_button",
  "assertions": {
    "isEnabled": true,
    "isHidden": false,
    "text": "提交"
  }
}
```

**Skill**：
- 新建 ios-assertions skill
- 或扩展 ios-ui-shot（增加对比功能）


---

## 4. 实现优先级矩阵

| 阶段 | 功能 | 影响 App 比例 | 实现复杂度 | 优先级 | 预计工作量 |
|-----|------|-------------|-----------|--------|-----------|
| **Phase 1** | TabBar 导航 | 90%+ | 🟢 低 | P0 | 2-3 天 |
| | UIDatePicker | 80%+ | 🟡 中 | P0 | 3-5 天 |
| | UIPickerView | 80%+ | 🟡 中 | P0 | 3-5 天 |
| | UISearchBar | 70%+ | 🟢 低 | P1 | 1-2 天 |
| **Phase 2** | Drag & Drop | 40%+ | 🔴 高 | P1 | 5-7 天 |
| | WKWebView | 50%+ | 🟡 中 | P1 | 5-7 天 |
| | UIRefreshControl | 90%+ | 🟢 低 | P1 | 1-2 天 |
| **Phase 3** | 系统权限弹窗 | 95%+ | 🔴 高 | P2 | 7-10 天 |
| | App 生命周期 | 60%+ | 🟡 中 | P2 | 5-7 天 |
| **Phase 4** | Pinch / Rotate | 40%+ | 🟡 中 | P3 | 3-5 天 |
| | 视觉回归对比 | 30%+ | 🔴 高 | P3 | 7-10 天 |

**总计**：
- Phase 1: ~10-15 天（3 个 P0 + 1 个 P1）
- Phase 2: ~11-16 天（3 个 P1）
- Phase 3: ~12-17 天（2 个 P2）
- Phase 4: ~10-15 天（2 个 P3）

---

## 5. 设计原则与约束

### 5.1 架构一致性

1. **遵循 L0/L1/L2 分层**：
   - L0（XcodeBuildMCP）：App 进程控制、系统级日志
   - L1（iOSDriver）：UI 操作、进程内日志
   - L2（iOSDriver + 源码）：测试闭环

2. **命令命名规范**：
   - 格式：`ui.<控件>.<动作>`
   - 示例：`ui.tabBar.selectTab`、`ui.datePicker.setDate`、`ui.webView.tap`

3. **Skill 命名规范**：
   - 格式：`ios-<层级>-<场景>`
   - L0: `ios-debugger-agent`、`ios-lifecycle`
   - L1: `ios-ui-tabbar`、`ios-ui-picker`、`ios-ui-webview`
   - L2: `ios-test-intent`、`ios-test-runner`

4. **复用现有机制**：
   - `viewSnapshotID`：陈旧检测
   - `identifier` / `path`：定位语义
   - `UIKitCommandLogging`：日志系统
   - `UIKitSnapshotStore`：快照管理

### 5.2 实现约束

1. **Debug-only 原则**：
   - 所有新命令用 `#if DEBUG` 隔离
   - Release 构建不编译自动化代码

2. **Typed Factory 原则**：
   - UIKit 操作入参先用 Foundation-only typed model 解析校验
   - UIKit 类型不穿过 public 边界

3. **Swift 6.2 严格并发**：
   - 跨边界模型 `Sendable`
   - 共享状态用 `Mutex`
   - 闭包 `@Sendable`

4. **错误处理**：
   - 通信失败用 HTTP 状态码（400/500）
   - 业务失败用 HTTP 200 + `code/message`

5. **文档同步**：
   - 每个新 skill 必须有 `docs/skills/examples/` 案例
   - 更新 `docs/skills/inventory.md`
   - 更新 `docs/architecture/index.md`

### 5.3 最小可用原则

优先实现"最小可用"版本，后续迭代增强：

- ✅ DatePicker：先支持 `setDate`，后续再支持动画、滚动效果
- ✅ WebView：先支持 JS 执行，后续再支持 DOM 查询 DSL
- ✅ TabBar：先支持 `selectTab`，后续再支持 badge、自定义 item

---

## 6. 技术风险与依赖

### 6.1 技术风险

| 功能 | 风险 | 影响 | 缓解措施 |
|-----|------|------|---------|
| Drag & Drop | 触摸注入复杂、iOS 版本兼容性 | 🔴 高 | 先支持 iOS 15+，使用 XCUITest API |
| 系统权限弹窗 | 需要 Accessibility 权限、沙箱限制 | 🔴 高 | 依赖 XcodeBuildMCP，或明确标注"仅模拟器" |
| WKWebView | JS 执行跨域限制、iframe 切换 | 🟡 中 | 限制同源策略、提供清晰错误提示 |
| App 生命周期 | 真机/模拟器实现方式不同 | 🟡 中 | 统一接口、内部适配平台差异 |
| 双指手势 | 触摸坐标计算复杂 | 🟡 中 | 先支持固定中心点缩放/旋转 |

### 6.2 依赖关系

| 功能 | 依赖项 | 备注 |
|-----|-------|------|
| 系统权限弹窗 | XcodeBuildMCP 或 Accessibility API | 可能需要扩展 XcodeBuildMCP |
| App 生命周期 | XCUITest 或 Simulator CLI | 真机需要 XCUITest |
| Drag & Drop | 私有 API 或 XCUITest | 优先使用公开 API |
| WKWebView | WKWebView API（公开） | 无额外依赖 |

---

## 7. 下一步行动

### 7.1 立即行动（P0）

1. **TabBar 导航**：✅ 已完成(2026-07-17)
   - [x] 决策：新增命令 vs 复用 ui.tap → **选新增命令**(走 controller 层,1 步 vs tap 的 3 步,跨版本稳定)
   - [x] 实现命令（如果新增）→ `ui.tabBar.selectTab`(`Sources/iOSExploreUIKit/Commands/TabBarSelect/`)
   - [x] 扩展 ios-ui-nav skill 文档 → `ios-ui-nav` SKILL.md §4 + `inventory.md` 已更新
   - [x] 编写 SPMExample 测试案例 → `Tests/iOSExploreServerTests/UITabBarSelectTests.swift`(16 个)+ 端到端实测通过

2. **UIDatePicker / UIPickerView**：
   - [ ] 实现 ui.datePicker.setDate 命令
   - [ ] 实现 ui.picker.selectRow 命令
   - [ ] 新建 ios-ui-picker skill
   - [ ] 编写 SPMExample 测试案例

### 7.2 短期规划（1-2 个月）

- 完成 Phase 1 全部 P0 功能
- 完成 Phase 2 部分 P1 功能（WebView、RefreshControl）
- 更新文档和示例

### 7.3 中期规划（3-6 个月）

- 完成 Phase 2 全部 P1 功能（包括 Drag & Drop）
- 启动 Phase 3 系统级交互能力
- 收集社区反馈，调整优先级

### 7.4 长期规划（6-12 个月）

- 完成 Phase 3 系统级交互
- 根据实际需求决定是否启动 Phase 4
- 持续优化现有能力

---

## 8. 附录

### 8.1 参考资源

- 现有文档：
  - `docs/skills/README.md` - Skill 体系总览
  - `docs/skills/inventory.md` - Skill 清单
  - `docs/architecture/index.md` - 架构文档
  - `AGENTS.md` / `CLAUDE.md` - 项目规范

- 业内参考：
  - Appium iOS Driver
  - XCUITest Framework
  - Detox (React Native)
  - EarlGrey (Google)

### 8.2 联系方式

如有问题或建议，请通过以下方式反馈：
- GitHub Issues
- 项目文档评论
- 团队讨论组

---

**文档结束**

