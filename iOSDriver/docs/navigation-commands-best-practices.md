# iOSExplore Navigation 命令使用注意事项

本文档记录 `ui.navigation.*` 命令在使用时需要注意的边界情况和最佳实践。

---

## ui.navigation.back - 返回上一页

### 基本用法

```json
{
  "action": "ui.navigation.back",
  "data": {
    "strategy": "auto",      // auto | dismiss | navigationController
    "animated": false,
    "waitAfterMs": 300
  }
}
```

### Strategy 说明

- **auto** (默认): 先尝试 dismiss 模态，失败后尝试 navigation pop
- **dismiss**: 只尝试 dismiss 当前 presented view controller
- **navigationController**: 只尝试 pop navigation stack

### ⚠️ 已知问题：dismiss 后的 `topAfter` 字段可能不准确

#### 问题描述

当使用 `strategy: "dismiss"` 或 `strategy: "auto"` 关闭模态窗口时，返回结果中的 `topAfter` 字段可能显示为 root view controller（如 `UITabBarController`）而不是实际的顶部 view controller。

#### 重现场景

```javascript
// 1. Present 一个全屏模态
await tap({ path: "root/0/1/5", viewSnapshotID: "snap-9" });

// 2. Dismiss 模态
const result = await navigationBack({ strategy: "dismiss" });
console.log(result.topAfter);  
// 可能返回 "UITabBarController" 而不是实际的 "NavigationTestViewController"

// 3. 后续 inspect 显示真实状态
const inspect = await uiInspect({});
console.log(inspect.screen.topViewController);  
// 正确显示 "NavigationTestViewController"
```

#### 原因分析

在 dismiss 动画完成前采集了 `topAfter`，此时：
1. `presentedViewController` 已被清空
2. 系统正在重新计算 window 的 topViewController
3. 临时返回了 root 的 view controller

#### 影响范围

- ✅ `performed: true` 是准确的（dismiss 操作确实成功）
- ✅ `strategy: "navigationController"` 的 `topAfter` 是准确的（pop 没有动画延迟问题）
- ⚠️ `strategy: "dismiss"` 的 `topAfter` 可能不准确
- ⚠️ `strategy: "auto"` 命中 dismiss 路径时的 `topAfter` 可能不准确
- ✅ `topBefore` 始终准确

#### 最佳实践

**推荐做法**: 在关键导航操作后，额外调用 `ui.inspect` 确认最终状态。

```javascript
// ❌ 不推荐：依赖 topAfter
const backResult = await navigationBack({ strategy: "dismiss" });
if (backResult.topAfter === "NavigationTestViewController") {
  // 可能误判
}

// ✅ 推荐：额外调用 ui.inspect 确认
const backResult = await navigationBack({ strategy: "dismiss" });
if (backResult.performed) {
  await sleep(100);  // 可选：等待动画完成
  const inspect = await uiInspect({});
  const actualTop = inspect.screen.topViewController;
  // 使用 actualTop 判断
}
```

**适用场景**:
- 需要根据返回后的页面类型执行不同逻辑
- 多级导航返回，需要确认返回到了哪一层
- 自动化测试，需要验证导航流程

**不需要担心的场景**:
- 只关心 dismiss 是否成功（检查 `performed: true` 即可）
- 返回后立即进行其他 UI 操作（下一个命令会等待页面稳定）
- 单向导航流程，不需要根据目标页面分支

---

## ui.navigation.tapBarButton - 点击导航栏按钮

### 基本用法

支持三种定位方式：

#### 1. placement + index (传统方式)

```json
{
  "action": "ui.navigation.tapBarButton",
  "data": {
    "placement": "right",
    "index": 0
  }
}
```

适用场景：已知按钮的准确位置

---

#### 2. 仅 accessibilityIdentifier (全局搜索) ⭐️ 推荐

```json
{
  "action": "ui.navigation.tapBarButton",
  "data": {
    "accessibilityIdentifier": "nav.right.share"
  }
}
```

**优点**:
- 无需提前调用 `ui.inspect` 查询 placement
- 减少一次 MCP 调用
- 代码更简洁

**适用场景**: 
- 按钮有唯一的 `accessibilityIdentifier`
- 不关心按钮在左侧还是右侧

**返回结果**: 包含实际找到的 `placement` 和 `index`

```json
{
  "performed": true,
  "placement": "right",
  "index": 0,
  "accessibilityIdentifier": "nav.right.share",
  "title": "分享"
}
```

---

#### 3. placement + accessibilityIdentifier (指定侧搜索)

```json
{
  "action": "ui.navigation.tapBarButton",
  "data": {
    "placement": "right",
    "accessibilityIdentifier": "nav.action.done"
  }
}
```

**适用场景**: 
- 左右侧可能有同名 identifier（防止误点）
- 已知按钮在哪一侧，但不知道具体 index

---

### 参数说明

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `placement` | string | 否 | 按钮位置：`left` 或 `right` |
| `index` | integer | 否 | 按钮在当前侧的下标（从 0 开始） |
| `accessibilityIdentifier` | string | 否 | 按钮的唯一标识符 |
| `title` | string | 否 | 按钮标题（用于二次确认） |
| `waitAfterMs` | integer | 否 | 执行后等待毫秒数，默认 300 |

**定位规则**:
- 必须提供 `(placement + index)` 或 `accessibilityIdentifier` 之一
- 只提供 `placement` 不提供 `index` 会报错（无法确定具体按钮）
- 提供 `title` 时会进行二次确认，不匹配则报错

---

### 错误处理

#### `navigation_bar_unavailable`

当前顶部 view controller 不在 navigation controller 中。

**解决方案**: 检查当前页面是否真的有导航栏

```javascript
const inspect = await uiInspect({});
if (!inspect.navigationBar.available) {
  console.log("当前页面没有导航栏");
}
```

---

#### `navigation_bar_item_not_found`

指定的按钮不存在。

**可能原因**:
1. `index` 越界（如 `rightItems` 只有 2 个，传了 `index: 2`）
2. `accessibilityIdentifier` 拼写错误或不存在
3. 页面变化，按钮已被移除

**解决方案**: 先调用 `ui.inspect` 查看当前可用的按钮

```javascript
const inspect = await uiInspect({});
console.log("Left items:", inspect.navigationBar.leftItems);
console.log("Right items:", inspect.navigationBar.rightItems);
```

---

#### `navigation_bar_item_mismatch`

按钮存在，但 `title` 或 `accessibilityIdentifier` 与观察时不一致。

**原因**: 页面在观察后发生了变化（如动态改标题）

**解决方案**: 重新 `ui.inspect` 获取最新状态

---

#### `navigation_bar_item_disabled`

按钮存在但当前不可用（`isEnabled: false`）。

**解决方案**: 等待按钮变为可用状态，或检查是否满足了启用条件

---

#### `invalid_navigation_bar_selector`

参数组合无效。

**示例**: 只提供 `placement` 不提供 `index` 也不提供 `accessibilityIdentifier`

```json
// ❌ 错误：无法确定具体按钮
{
  "placement": "right"
}

// ✅ 正确：提供 index
{
  "placement": "right",
  "index": 0
}

// ✅ 正确：提供 accessibilityIdentifier
{
  "placement": "right",
  "accessibilityIdentifier": "nav.right.share"
}
```

---

### 最佳实践

#### 1. 优先使用 `accessibilityIdentifier`

```javascript
// ✅ 推荐：简洁，无需提前查询
await tapBarButton({ 
  accessibilityIdentifier: "nav.right.share" 
});

// ❌ 不推荐：需要额外调用
const inspect = await uiInspect({});
const shareButton = inspect.navigationBar.rightItems.find(
  item => item.accessibilityIdentifier === "nav.right.share"
);
await tapBarButton({ 
  placement: shareButton.placement, 
  index: shareButton.index 
});
```

---

#### 2. 使用 `title` 做二次确认

当页面可能动态变化时，加上 `title` 确保点击的是预期按钮：

```javascript
await tapBarButton({ 
  accessibilityIdentifier: "nav.right.action",
  title: "完成"  // 如果标题变了会报错，避免误点
});
```

---

#### 3. 处理按钮不存在的情况

```javascript
try {
  await tapBarButton({ 
    accessibilityIdentifier: "nav.right.share" 
  });
} catch (error) {
  if (error.code === "navigation_bar_item_not_found") {
    console.log("分享按钮不存在，可能页面已变化");
    // 重新 inspect 或采取其他策略
  }
}
```

---

## 通用建议

### 1. 关键导航后调用 `ui.inspect`

在以下场景建议额外调用 `ui.inspect` 确认状态：

- ✅ Present/Dismiss 模态后
- ✅ 多级 Push/Pop 导航后
- ✅ 需要根据目标页面类型分支逻辑时
- ✅ 自动化测试验证导航流程时

### 2. 合理使用 `waitAfterMs`

默认 300ms 适合大多数场景，但某些复杂动画可能需要更长时间：

```javascript
// 简单页面跳转
await navigationBack({ waitAfterMs: 300 });

// 复杂动画或慢设备
await navigationBack({ waitAfterMs: 500 });

// 无动画立即返回
await navigationBack({ animated: false, waitAfterMs: 100 });
```

### 3. 优先使用稳定的定位方式

定位优先级（从高到低）：

1. **accessibilityIdentifier** - 最稳定，不受布局变化影响
2. **placement + index** - 较稳定，但按钮顺序变化会失效
3. **title** - 仅作为二次确认，不要单独使用

---

## 变更历史

| 日期 | 版本 | 变更内容 |
|------|------|----------|
| 2026-07-12 | 1.0 | 初始版本，记录 dismiss topAfter 不准确问题和 tapBarButton 全局搜索功能 |

---

## 相关文档

- [问题修复记录](./fix-navigation-issues-2026-07-12.md)
