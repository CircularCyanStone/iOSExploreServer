# Navigation 命令问题修复报告

**修复日期**: 2026-07-12  
**修复人**: AI Agent (Claude)  
**关联测试**: `iOSDriver/docs/e2e-test-screenshot-navigation-2026-07-12.md`

## 修复概要

根据端到端测试发现的 2 个问题，已完成以下修复：

1. ✅ **问题 1 修复**: `ui.navigation.tapBarButton` 的 `placement` 和 `index` 参数现在是可选的，支持只传 `accessibilityIdentifier` 全局搜索
2. ⏸️ **问题 2 待定**: `ui.navigation.back` dismiss 后的 `topAfter` 不准确（已记录，暂不修复）

---

## 问题 1: `placement` 参数应该可选

### 修复前的问题

即使提供了 `accessibilityIdentifier` 唯一定位按钮，`placement` 和 `index` 仍然是必填参数。

**重现**:
```bash
node scripts/mcp-inspector.mjs ui_navigation_tapBarButton '{"accessibilityIdentifier":"nav.right.share"}'
# 返回错误: "missing required parameter 'placement'"
```

**影响**: Agent 必须先调用 `ui.inspect` 获取 navigationBar 信息，判断该 `accessibilityIdentifier` 在 leftItems 还是 rightItems 中，才能传正确的 `placement`。这增加了一次额外的 MCP 调用。

---

### 修复方案

#### 1. 修改输入模型 - 支持三种定位方式

**文件**: `Sources/iOSExploreUIKit/Commands/Navigation/UINavigationBarButtonModels.swift`

**改动**:
- 将 `placement` 从 `requiredEnum` 改为 `optionalString`（手动解析为 enum）
- 将 `index` 从 `requiredInt` 改为 `optionalFiniteNumber`（手动转换为 Int）
- 更新 `parse` 方法，手动验证和转换这两个字段

**新的定位方式**:
1. `placement` + `index`: 精确定位指定侧的第 N 个按钮
2. 仅 `accessibilityIdentifier`: 在 leftItems 和 rightItems 中全局搜索
3. `placement` + `accessibilityIdentifier`: 只在指定侧搜索（防误点）

**代码示例**:
```swift
public static func parse(decoding decoder: inout CommandInputDecoder) throws -> UINavigationBarButtonInput {
    let placementString: String? = try decoder.read(Fields.placement)
    let indexNumber: Double? = try decoder.read(Fields.index)

    // 解析 placement string 为 enum
    let placement: NavigationBarPlacement?
    if let placementString = placementString {
        guard let parsed = NavigationBarPlacement(rawValue: placementString) else {
            throw CommandInputParseError("placement must be 'left' or 'right'")
        }
        placement = parsed
    } else {
        placement = nil
    }

    // 解析 index number 为 Int
    let index: Int?
    if let indexNumber = indexNumber {
        guard indexNumber.isFinite, indexNumber >= 0, indexNumber <= 20,
              indexNumber == floor(indexNumber) else {
            throw CommandInputParseError("index must be an integer between 0 and 20")
        }
        index = Int(indexNumber)
    } else {
        index = nil
    }

    return UINavigationBarButtonInput(
        placement: placement,
        index: index,
        title: try decoder.read(Fields.title),
        accessibilityIdentifier: try decoder.read(Fields.accessibilityIdentifier),
        waitAfterMs: try decoder.read(Fields.waitAfterMs)
    )
}
```

---

#### 2. 修改 Inspector - 实现全局搜索逻辑

**文件**: `Sources/iOSExploreUIKit/Support/Navigation/UINavigationBarInspector.swift`

**改动**:
- `item(for:topViewController:)` 方法返回类型从 `UIBarButtonItem` 改为 `(item: UIBarButtonItem, placement: NavigationBarPlacement, index: Int)`
- 实现三种定位逻辑：
  - 情况 1: `placement` + `index` → 精确定位
  - 情况 2 & 3: 通过 `accessibilityIdentifier` 搜索（全局或指定侧）
  - 情况 4: 参数不足 → 抛出 `invalidNavigationBarSelector` 错误
- 新增 `verifyItem(_:input:)` 方法，统一验证 title 和 identifier

**关键代码**:
```swift
static func item(for input: UINavigationBarButtonInput,
                 topViewController: UIViewController) throws -> (item: UIBarButtonItem, placement: NavigationBarPlacement, index: Int) {
    guard topViewController.navigationController != nil else {
        throw UIKitCommandError.navigationBarUnavailable(...)
    }

    let navigationItem = topViewController.navigationItem

    // 情况 1: placement + index 精确定位
    if let placement = input.placement, let index = input.index {
        let items = barButtonItems(placement: placement, from: navigationItem)
        guard index < items.count else {
            throw UIKitCommandError.navigationBarItemNotFound(...)
        }
        let item = items[index]
        try verifyItem(item, input: input)
        return (item, placement, index)
    }

    // 情况 2 & 3: 通过 accessibilityIdentifier 搜索
    if let identifier = input.accessibilityIdentifier {
        let searchPlacements: [NavigationBarPlacement] = input.placement.map { [$0] } ?? [.left, .right]

        for placement in searchPlacements {
            let items = barButtonItems(placement: placement, from: navigationItem)
            if let foundIndex = items.firstIndex(where: { $0.accessibilityIdentifier == identifier }) {
                let item = items[foundIndex]
                try verifyItem(item, input: input)
                return (item, placement, foundIndex)
            }
        }

        throw UIKitCommandError.navigationBarItemNotFound(...)
    }

    // 情况 4: 参数不足
    throw UIKitCommandError.invalidNavigationBarSelector(
        action: NavigationBarButtonCommand.actionName,
        reason: "必须提供 (placement + index) 或 accessibilityIdentifier"
    )
}
```

---

#### 3. 修改 Executor - 使用新返回值

**文件**: `Sources/iOSExploreUIKit/Support/Action/UINavigationBarButtonExecutor.swift`

**改动**:
- 更新 `execute` 方法，解构 Inspector 返回的元组 `(item, placement, index)`
- 使用实际找到的 `placement` 和 `index`（而不是 `input.placement` 和 `input.index`）

**代码示例**:
```swift
static func execute(input: UINavigationBarButtonInput,
                    context: UIKitContextProvider.Context) throws -> JSON {
    let topBefore = describe(context.topViewController)
    let (item, placement, index) = try UINavigationBarInspector.item(for: input, topViewController: context.topViewController)
    
    guard item.isEnabled else {
        throw UIKitCommandError.navigationBarItemDisabled(...)
    }

    guard trigger(item: item) else {
        throw UIKitCommandError.navigationBarItemUnsupported(...)
    }

    settle(milliseconds: input.waitAfterMs)
    let topAfter = describe(context.topViewController.navigationController?.topViewController ?? context.topViewController)
    
    return [
        "performed": .bool(true),
        "placement": .string(placement.rawValue),  // 使用实际找到的 placement
        "index": .double(Double(index)),            // 使用实际找到的 index
        "title": item.title.map(JSONValue.string) ?? .null,
        "accessibilityIdentifier": item.accessibilityIdentifier.map(JSONValue.string) ?? .null,
        "topBefore": .string(topBefore),
        "topAfter": .string(topAfter),
    ]
}
```

---

#### 4. 添加新错误类型

**文件**: `Sources/iOSExploreUIKit/UIKitCommandError.swift`

**改动**:
- 新增 `invalidNavigationBarSelector` 工厂方法

**代码示例**:
```swift
static func invalidNavigationBarSelector(action: String, reason: String) -> UIKitCommandError {
    UIKitCommandError(code: .invalidData,
                      message: "invalid navigation bar button selector: \(reason)",
                      logMessage: "ui navigation bar invalid selector action=\(action) reason=\(reason)")
}
```

---

#### 5. 更新单元测试

**文件**: `Tests/iOSExploreServerTests/UINavigationBarButtonInputTests.swift`

**改动**:
- 删除测试 `navigation bar button 要求 index 必填`（因为 index 现在可选）
- 新增测试 `navigation bar button 允许只提供 accessibilityIdentifier 全局搜索`
- 新增测试 `navigation bar button 允许 placement + accessibilityIdentifier 组合`
- 新增测试 `navigation bar button 允许只提供 placement + index`

**测试代码**:
```swift
@Test("navigation bar button 允许只提供 accessibilityIdentifier 全局搜索")
func navigationBarButtonAllowsAccessibilityIdentifierOnly() throws {
    let input = try UINavigationBarButtonInput.parse(from: [
        "accessibilityIdentifier": "example.controlTest",
    ])

    #expect(input.placement == nil)
    #expect(input.index == nil)
    #expect(input.accessibilityIdentifier == "example.controlTest")
    #expect(input.waitAfterMs == 300)
}

@Test("navigation bar button 允许 placement + accessibilityIdentifier 组合")
func navigationBarButtonAllowsPlacementWithAccessibilityIdentifier() throws {
    let input = try UINavigationBarButtonInput.parse(from: [
        "placement": "right",
        "accessibilityIdentifier": "example.controlTest",
    ])

    #expect(input.placement == .right)
    #expect(input.index == nil)
    #expect(input.accessibilityIdentifier == "example.controlTest")
}
```

---

### 修复后的测试结果

#### 单元测试

```bash
swift test --filter UINavigationBarButtonInputTests
```

**结果**: ✅ 全部通过（7 个测试）
- navigation bar button 解析 right index title identifier waitAfterMs
- navigation bar button 默认 waitAfterMs 300
- navigation bar button 拒绝非法 placement
- navigation bar button 拒绝非法 index
- navigation bar button 允许只提供 accessibilityIdentifier 全局搜索
- navigation bar button 允许 placement + accessibilityIdentifier 组合
- navigation bar button 允许只提供 placement + index

#### 完整测试套件

```bash
swift test
```

**结果**: ✅ 281 个测试全部通过

---

### 端到端测试

**测试环境**: iPhone 17 模拟器，NavigationTestViewController 页面

**导航栏配置**:
- Left buttons: "编辑" (nav.left.edit), "添加" (nav.left.add)
- Right buttons: "分享" (nav.right.share), "搜索" (nav.right.search), "设置" (nav.right.settings)

#### 测试用例 1: 只传 `accessibilityIdentifier`（全局搜索）

```bash
node scripts/mcp-inspector.mjs ui_navigation_tapBarButton '{"accessibilityIdentifier":"nav.right.share"}'
```

**结果**: ✅ 成功
```json
{
  "performed": true,
  "placement": "right",
  "index": 0,
  "accessibilityIdentifier": "nav.right.share",
  "title": "分享",
  "topBefore": "NavigationTestViewController",
  "topAfter": "NavigationTestViewController"
}
```

**验证**: 
- ✅ 成功找到右侧第 0 个按钮
- ✅ 返回了实际的 placement 和 index
- ✅ 无需提前调用 `ui.inspect`

---

#### 测试用例 2: `placement` + `accessibilityIdentifier`（指定侧搜索）

```bash
node scripts/mcp-inspector.mjs ui_navigation_tapBarButton '{"placement":"right","accessibilityIdentifier":"nav.right.settings"}'
```

**结果**: ✅ 成功
```json
{
  "performed": true,
  "placement": "right",
  "index": 2,
  "accessibilityIdentifier": "nav.right.settings",
  "title": null,
  "topBefore": "NavigationTestViewController",
  "topAfter": "NavigationTestViewController"
}
```

**验证**:
- ✅ 只在右侧搜索，找到了第 2 个按钮
- ✅ 防止误点左侧同名按钮（如果存在）

---

#### 测试用例 3: `placement` + `index`（传统方式，向后兼容）

```bash
node scripts/mcp-inspector.mjs ui_navigation_tapBarButton '{"placement":"left","index":0}'
```

**结果**: ✅ 成功
```json
{
  "performed": true,
  "placement": "left",
  "index": 0,
  "accessibilityIdentifier": "nav.left.edit",
  "title": "编辑",
  "topBefore": "NavigationTestViewController",
  "topAfter": "NavigationTestViewController"
}
```

**验证**:
- ✅ 传统方式依然工作
- ✅ 向后兼容，不影响现有 Agent 代码

---

## 问题 2: `ui.navigation.back` dismiss 后的 `topAfter` 不准确

### 问题描述

使用 `strategy: "dismiss"` 关闭全屏模态时，返回的 `topAfter` 显示为 `UITabBarController` 而不是实际的顶部 `NavigationTestViewController`。

**重现**:
1. Present 一个全屏模态
2. 调用 `ui.navigation.back({"strategy":"dismiss"})`
3. 返回的 `topAfter` 是 `UITabBarController`，但后续 `ui.inspect` 显示实际 topViewController 是 `NavigationTestViewController`

**分析**: 可能是在 dismiss 动画完成前就采集了 `topAfter`，此时 `presentedViewController` 刚被清空，系统还在重新计算 topViewController。

### 修复方案（待定）

**方案 1**: 在 `UINavigationBackExecutor.execute` 的 dismiss 路径中，增加 `waitAfterMs` 默认值 50-100ms

**方案 2**: 在文档/description 中说明 dismiss 场景下 `topAfter` 可能不准确，推荐额外调用 `ui.inspect`

### 当前状态

⏸️ **暂不修复**

**理由**:
1. `performed: true` 是准确的，dismiss 操作确实成功了
2. Agent 可以通过后续 `ui.inspect` 确认最终状态（这是推荐的做法）
3. 影响轻微，不是阻塞性问题
4. 修改 `waitAfterMs` 可能影响性能，需要更多测试验证合适的延迟值

**建议**: 在未来的文档更新中明确说明 dismiss/present 场景下 `topAfter` 可能不准确。

---

## 总结

### 修复成果

1. ✅ **问题 1 已完全修复**
   - `ui.navigation.tapBarButton` 现在支持只传 `accessibilityIdentifier`
   - 减少了 Agent 的调用次数（无需提前 `ui.inspect` 查 placement）
   - 向后兼容，不影响现有代码
   - 281 个单元测试全部通过
   - 3 个端到端测试场景全部通过

2. ⏸️ **问题 2 暂不修复**
   - 已记录问题和分析
   - 提供了两种修复方案
   - 暂时通过文档说明即可

### 修改文件列表

1. `Sources/iOSExploreUIKit/Commands/Navigation/UINavigationBarButtonModels.swift`
2. `Sources/iOSExploreUIKit/Support/Navigation/UINavigationBarInspector.swift`
3. `Sources/iOSExploreUIKit/Support/Action/UINavigationBarButtonExecutor.swift`
4. `Sources/iOSExploreUIKit/UIKitCommandError.swift`
5. `Tests/iOSExploreServerTests/UINavigationBarButtonInputTests.swift`

### 测试覆盖

- ✅ 单元测试: 7 个 NavigationBarButton 测试
- ✅ 完整测试套件: 281 个测试
- ✅ 端到端测试: 3 个场景（全局搜索、指定侧搜索、传统方式）

### 下一步

1. 可选：修复问题 2（增加 dismiss 后的 `waitAfterMs` 或更新文档）
2. 可选：为 Navigation 命令添加更多单元测试（测试 Inspector 的全局搜索逻辑）
3. 建议：更新 iOSDriver 的 MCP tools description，说明新的定位方式

---

## 参考

- 原始测试报告: `iOSDriver/docs/e2e-test-screenshot-navigation-2026-07-12.md`
- 相关 commit: f7d09b0, a82275c, e31ac8b
