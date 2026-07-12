# Screenshot & Navigation 命令端到端测试报告

**测试日期**: 2026-07-12  
**测试人**: AI Agent (Claude)  
**测试环境**: 模拟器 (iPhone 17, iOS 26.5)  
**测试工具**: `scripts/mcp-inspector.mjs`  
**测试页面**: `NavigationTestViewController` (新建)

## 测试概要

本次测试针对 `ui.screenshot` 和 `ui.navigation.*` 命令进行了全面的端到端验证，覆盖：
- 截图功能（全尺寸 + 降采样）
- 导航栏按钮点击（左/右，通过 index 和 accessibilityIdentifier）
- 多级 Push 导航与返回
- Present/Dismiss 模态场景
- 不同的 navigation.back strategy

## 测试结果汇总

### 通过的测试场景 (9/10)

1. ✅ `ui.screenshot` 默认参数 - 成功截图，返回约 295KB PNG (base64)
2. ✅ `ui.screenshot` 降采样 - `maxDimension=400` 成功将图像减小到 55KB
3. ✅ `ui.navigation.tapBarButton` 左侧按钮 - `placement=left, index=0` 成功点击
4. ✅ `ui.navigation.tapBarButton` 右侧按钮 - `placement=right, index=0` 成功点击，带 `accessibilityIdentifier` 验证
5. ✅ `ui.navigation.back` 多级 Push 返回 - 从 Level 3 → Level 2 → NavigationTest → Main 全程成功
6. ✅ `ui.navigation.back` dismiss strategy - 成功关闭全屏模态
7. ✅ `ui.navigation.tapBarButton` 模态导航栏按钮 - 点击 Done 按钮成功关闭带导航栏的模态
8. ✅ MCP Screenshot 转换 - base64 PNG 正确转换为 MCP `type: "image"` content
9. ✅ NavigationBar 信息完整性 - leftItems/rightItems 包含所有必要字段（index, placement, title, accessibilityIdentifier, availableActions）

### 发现的问题

#### 问题 1: `ui.navigation.tapBarButton` 必须提供 `placement` 参数（设计问题）

**严重性**: 中等  
**问题描述**: 即使提供了 `accessibilityIdentifier` 来唯一定位按钮，`placement` 参数仍然是必填的。

**重现步骤**:
```bash
node scripts/mcp-inspector.mjs ui_navigation_tapBarButton '{"accessibilityIdentifier":"nav.right.share"}'
```

**实际结果**:
```json
{
  "source": "ios_envelope",
  "message": "missing required parameter 'placement'",
  "code": "invalid_data",
  "action": "ui.navigation.tapBarButton"
}
```

**期望行为**: 当 `accessibilityIdentifier` 唯一确定按钮时，应该允许省略 `placement`（自动从 leftItems/rightItems 中查找）。

**影响**: Agent 必须先调用 `ui.inspect` 获取 navigationBar 信息，再根据 `accessibilityIdentifier` 所在的 leftItems/rightItems 数组来决定传 `placement: "left"` 还是 `"right"`，增加了一次额外调用。

**建议修复**: 
1. 将 `placement` 改为可选参数
2. 当只提供 `accessibilityIdentifier` 时，在 `leftItems` 和 `rightItems` 中全局搜索
3. 如果 `placement` + `accessibilityIdentifier` 都提供，优先在指定 placement 的数组中查找（防误点）

---

#### 问题 2: `ui.navigation.back` 的 `topAfter` 字段不准确（观察到的异常）

**严重性**: 低  
**问题描述**: 使用 `strategy: "dismiss"` 关闭全屏模态时，返回的 `topAfter` 显示为 `UITabBarController` 而不是实际的顶部 ViewController `NavigationTestViewController`。

**重现步骤**:
1. 从 NavigationTestViewController present 一个全屏模态
2. 调用 `ui.navigation.back({"strategy":"dismiss"})`

**实际结果**:
```json
{
  "performed": true,
  "strategy": "dismiss",
  "topAfter": "UITabBarController",
  "topBefore": "NavigationModalViewController"
}
```

**后续 `ui.inspect` 显示**:
```json
{
  "screen": {
    "topViewController": "NavigationTestViewController"
  }
}
```

**分析**: `topAfter` 可能在 dismiss 动画完成前就被采集，此时 `presentedViewController` 刚被清空，系统还在重新计算 topViewController，临时返回了 root 的 `UITabBarController`。

**影响**: 轻微。`performed: true` 是准确的，只是 `topAfter` 字段在 dismiss 场景下可能不可靠。Agent 应该在关键导航操作后额外调用 `ui.inspect` 确认最终状态。

**建议修复**: 
1. 在 `UINavigationBackExecutor.execute` 的 dismiss 路径中，`waitAfterMs` 默认值从当前值增加 50-100ms，确保动画完成后再采集 `topAfter`
2. 或者在文档中明确说明 dismiss/present 场景下 `topAfter` 可能不准确，推荐额外调用 `ui.inspect`

---

## 详细测试流程

### 1. ui.screenshot 基础功能

```bash
# 全尺寸截图
node scripts/mcp-inspector.mjs ui_screenshot '{}'
```

**结果**: 
- ✅ 成功返回 PNG base64
- ✅ 图像大小: 295.27 KB
- ✅ MCP 正确转换为 `type: "image"` content

```bash
# 降采样截图
node scripts/mcp-inspector.mjs ui_screenshot '{"maxDimension":400}'
```

**结果**:
- ✅ 成功返回降采样 PNG
- ✅ 图像大小: 55.20 KB (减少 81%)
- ✅ 降采样算法工作正常

---

### 2. ui.navigation.tapBarButton 导航栏按钮

**测试页面导航栏配置**:
- Left buttons: "编辑" (nav.left.edit), "添加" (nav.left.add)
- Right buttons: "分享" (nav.right.share), "搜索" (nav.right.search), "设置" (nav.right.settings)

**测试用例 2.1**: 点击左侧第一个按钮
```bash
node scripts/mcp-inspector.mjs ui_navigation_tapBarButton '{"placement":"left","index":0}'
```

**结果**:
```json
{
  "accessibilityIdentifier": "nav.left.edit",
  "index": 0,
  "performed": true,
  "placement": "left",
  "title": "编辑",
  "topAfter": "NavigationTestViewController",
  "topBefore": "NavigationTestViewController"
}
```
✅ 成功，返回了完整的按钮信息

---

**测试用例 2.2**: 通过 accessibilityIdentifier + placement 点击右侧按钮
```bash
node scripts/mcp-inspector.mjs ui_navigation_tapBarButton '{"placement":"right","index":0,"accessibilityIdentifier":"nav.right.share"}'
```

**结果**:
```json
{
  "accessibilityIdentifier": "nav.right.share",
  "index": 0,
  "performed": true,
  "placement": "right",
  "title": "分享",
  "topAfter": "NavigationTestViewController",
  "topBefore": "NavigationTestViewController"
}
```
✅ 成功，accessibilityIdentifier 验证生效

---

**测试用例 2.3**: 只提供 accessibilityIdentifier（预期失败）
```bash
node scripts/mcp-inspector.mjs ui_navigation_tapBarButton '{"accessibilityIdentifier":"nav.right.share"}'
```

**结果**:
```json
{
  "source": "ios_envelope",
  "message": "missing required parameter 'placement'",
  "code": "invalid_data",
  "action": "ui.navigation.tapBarButton"
}
```
❌ 失败（设计问题，见问题 1）

---

### 3. 多级 Push 导航与 ui.navigation.back

**测试用例 3.1**: Push 三级页面
```bash
# Main → NavigationTest
node scripts/mcp-inspector.mjs ui_tap '{"path":"root/5/5/1","viewSnapshotID":"snap-3"}'

# NavigationTest → Level 2
node scripts/mcp-inspector.mjs ui_tap '{"path":"root/0/1/1","viewSnapshotID":"snap-4"}'

# Level 2 → Level 3
node scripts/mcp-inspector.mjs ui_tap '{"path":"root/1","viewSnapshotID":"snap-5"}'
```

**结果**: ✅ 全部成功，页面栈: Main → NavigationTest → Level 2 → Level 3

---

**测试用例 3.2**: 多次 back 返回
```bash
# Level 3 → Level 2
node scripts/mcp-inspector.mjs ui_navigation_back '{"strategy":"navigationController"}'

# Level 2 → NavigationTest
node scripts/mcp-inspector.mjs ui_navigation_back '{}'

# NavigationTest → Main
node scripts/mcp-inspector.mjs ui_navigation_back '{}'
```

**结果**: 
```json
// 最后一次 back
{
  "performed": true,
  "strategy": "navigationController",
  "topAfter": "ViewController",
  "topBefore": "NavigationTestViewController"
}
```
✅ 全部成功，完全返回到主页

---

### 4. Present/Dismiss 模态场景

**测试用例 4.1**: Present 全屏模态 + dismiss strategy
```bash
# Present 全屏模态
node scripts/mcp-inspector.mjs ui_tap '{"path":"root/0/1/5","viewSnapshotID":"snap-9"}'

# Dismiss
node scripts/mcp-inspector.mjs ui_navigation_back '{"strategy":"dismiss"}'
```

**结果**:
```json
{
  "performed": true,
  "strategy": "dismiss",
  "topAfter": "UITabBarController",  // ⚠️ 不准确，实际是 NavigationTestViewController
  "topBefore": "NavigationModalViewController"
}
```
✅ 模态成功关闭，但 `topAfter` 字段不准确（见问题 2）

---

**测试用例 4.2**: Present 带导航栏的模态 + 点击 Done 按钮关闭
```bash
# Present 带导航栏的模态
node scripts/mcp-inspector.mjs ui_tap '{"path":"root/0/1/7","viewSnapshotID":"snap-12"}'

# 点击导航栏的 Done 按钮
node scripts/mcp-inspector.mjs ui_navigation_tapBarButton '{"placement":"right","index":0,"accessibilityIdentifier":"modal.done"}'
```

**结果**:
```json
// tapBarButton 结果
{
  "accessibilityIdentifier": "modal.done",
  "index": 0,
  "performed": true,
  "placement": "right",
  "title": null,
  "topAfter": "NavigationModalViewController",  // ⚠️ 按钮触发后页面还未切换
  "topBefore": "NavigationModalViewController"
}

// 后续 ui.inspect 确认
{
  "screen": {
    "topViewController": "NavigationTestViewController"  // ✅ 已成功关闭模态
  }
}
```
✅ 成功通过导航栏按钮关闭模态（业务逻辑在按钮 action 中执行 dismiss）

---

## 设计验证

### NavigationBar 信息完整性

`ui.inspect` 返回的 `navigationBar` 包含所有必要信息：

```json
{
  "available": true,
  "backAvailable": true,
  "leftItems": [
    {
      "accessibilityIdentifier": "nav.left.edit",
      "availableActions": ["ui.navigation.tapBarButton"],
      "index": 0,
      "isEnabled": true,
      "placement": "left",
      "title": "编辑"
    },
    {
      "accessibilityIdentifier": "nav.left.add",
      "availableActions": ["ui.navigation.tapBarButton"],
      "index": 1,
      "isEnabled": true,
      "placement": "left",
      "title": null
    }
  ],
  "rightItems": [
    {
      "accessibilityIdentifier": "nav.right.share",
      "availableActions": ["ui.navigation.tapBarButton"],
      "index": 0,
      "isEnabled": true,
      "placement": "right",
      "title": "分享"
    },
    {
      "accessibilityIdentifier": "nav.right.search",
      "availableActions": ["ui.navigation.tapBarButton"],
      "index": 1,
      "isEnabled": true,
      "placement": "right",
      "title": null
    },
    {
      "accessibilityIdentifier": "nav.right.settings",
      "availableActions": ["ui.navigation.tapBarButton"],
      "index": 2,
      "isEnabled": true,
      "placement": "right",
      "title": null
    }
  ],
  "title": "导航与截图测试",
  "topViewController": "NavigationTestViewController"
}
```

✅ 字段完整，index 顺序正确，availableActions 提示正确的命令

---

### MCP Screenshot 图像转换

**验证点**: MCPServer 正确将 iOSExplore 返回的 base64 PNG 转换为 MCP `image` content type

**iOSExplore 响应** (简化):
```json
{
  "code": "ok",
  "data": {
    "image": "iVBORw0KGgoAAAANSUhEUgAAAk0AAAUAEAYAAAK...",  // base64 PNG
    "width": 1179,
    "height": 2556,
    "scale": 3
  }
}
```

**MCP 响应**:
```json
{
  "content": [
    {
      "type": "image",
      "data": "iVBORw0KGgoAAAANSUhEUgAAAk0AAAUAEAYAAAK..."
    }
  ],
  "isError": false
}
```

✅ 转换正确，Claude 可以直接显示图像

---

## 问题优先级与建议

### 优先级 1: 必须修复

无

### 优先级 2: 应该修复

- **问题 1**: `ui.navigation.tapBarButton` 的 `placement` 参数应该可选

### 优先级 3: 考虑修复

- **问题 2**: `ui.navigation.back` dismiss 后的 `topAfter` 不准确（文档说明或增加 waitAfterMs）

---

## 测试环境信息

- **MCPServer 版本**: 0.1.0
- **iOSExploreServer**: commit f7d09b0
- **测试设备**: iPhone 17 模拟器 (065CC8DB-8978-46C5-82D6-C96625B608D8)
- **iOS 版本**: 26.5
- **Xcode**: 当前版本
- **测试时间**: 约 15 分钟
- **测试命令数**: 23 次 MCP 调用

---

## 结论

Screenshot 和 Navigation 命令的核心功能全部正常工作：
- ✅ 截图功能完整（全尺寸 + 降采样）
- ✅ 导航栏按钮点击可靠
- ✅ Push/Pop 导航流畅
- ✅ Present/Dismiss 模态正常
- ✅ 不同 strategy 的 navigation.back 工作正常
- ✅ MCP 转换正确

发现的 2 个问题均为非阻塞性问题：
1. `placement` 必填参数可以通过先调用 `ui.inspect` 规避
2. `topAfter` 不准确可以通过后续 `ui.inspect` 确认

**建议**: 优先修复问题 1，提升 Agent 调用效率。
