---
name: ios-ui-gesture
description: iOS App 中显式手势识别器与 UITableView cell swipe action 的自动化。用于触发 UISwipeGestureRecognizer、非系统 ScrollView 的 UIPanGestureRecognizer、UILongPressGestureRecognizer，以及 UITableView cell 的 leading/trailing action；普通列表滚动、UICollectionView swipe action、拖拽不适用。触发词包括 swipe gesture、long press、上下文手势、左滑删除、ui_swipe、ui_longPress。
---

# iOS 手势与 cell swipe action

本 skill 处理 `ui_swipe` 和 `ui_longPress` 能真实触发的路径。不要把 `ui_swipe` 当作系统 ScrollView 的滚动命令；列表和滚动容器移动内容应使用 `ui_scroll` 或 `ui_scrollToElement`，由 `ios-ui-list` 负责。

## 先选执行路径

| 需求 | 命令 | 前提 |
|---|---|---|
| 滚动 UITableView/UICollectionView/UIScrollView | `ui_scroll` / `ui_scrollToElement` | 转到 `ios-ui-list` |
| 触发 UITableView cell 的 leading/trailing action | `ui_swipe` cell 模式 | cell 当前可见，table delegate 提供标准 swipe actions |
| 触发业务显式添加的 swipe/pan recognizer | `ui_swipe` | 目标挂有匹配 recognizer；系统 ScrollView pan 会被跳过 |
| 触发业务显式添加的 long-press recognizer | `ui_longPress` | 目标挂有 `UILongPressGestureRecognizer` |

`ui_swipe` 不合成 UIKit 触摸序列。对系统 ScrollView 只传容器定位时通常返回 `unsupported_target`，不会产生滚动。

## 通用时序

1. 用 `ui_inspect` 取得当前目标与可选 `viewSnapshotID`。
2. 调用手势命令。
3. 读取响应的 `triggered` 与 `route`，确认走到预期路由。
4. 手势可能改变 UI；等待短动画后重新 inspect，用业务终态验证，而不是只凭命令成功判定任务完成。

## UITableView cell swipe action

使用 `cellAccessibilityIdentifier` 或 `cellPath` 定位可见 cell，并使用 `direction:left` 取 trailing actions、`direction:right` 取 leading actions。建议显式传 `actionTitle`，避免省略时触发该方向的第一个 action。

```text
ui_swipe(
  direction:"left",
  cellAccessibilityIdentifier:"<cell-id>",
  actionTitle:"<现场 action 标题>"
)
```

若同屏有多个滚动容器，再传 `accessibilityIdentifier` 或 `path` 指定所属 `UITableView`。cell 定位与容器定位服务于不同层级，可以同时使用；cell 必须位于所选 table 子树内。

当前 `UICollectionView` 没有标准 delegate swipe-action API，cell 模式会返回 `unsupported_target`，不要把 UITableView 路径套用过去。

## 自定义 swipe / pan recognizer

- `direction` 是 recognizer 的手势方向：`up/down/left/right`。
- `distance` 范围 `(0,1]`，默认 `0.8`；仅 pan 路由使用距离。
- 目标上必须存在方向匹配的 `UISwipeGestureRecognizer`，或业务显式添加的 `UIPanGestureRecognizer`。
- `UIScrollView` 的系统 pan 会被跳过；滚动内容使用 `ui_scroll`。

## Long press

- `duration` 单位是秒，范围 `(0,10]`，默认 `0.5`。
- 命令只派发目标上已有 `UILongPressGestureRecognizer` 的 `.began -> .ended`，不保证所有系统 `UIContextMenuInteraction` 都可触发。
- 无定位时会寻找第一个可长按 view；存在多个候选时应显式传 identifier/path，避免误触发。

## 失败分诊

| 现象或 code | 原因 | 动作 |
|---|---|---|
| `invalid_data` 且 duration 越界 | 把秒误写成毫秒，或超出 `(0,10]` | 例如 1 秒写 `1.0` |
| `unsupported_target` on swipe | 系统 ScrollView 无自定义 recognizer、方向不匹配，或 UICollectionView cell action | 改用 `ui_scroll`，或确认目标 recognizer/受支持 cell 类型 |
| `unsupported_target` on longPress | 目标没有 `UILongPressGestureRecognizer` | 不盲目加时；确认 App 实际交互实现 |
| `target_not_found` | 目标/cell 不在当前树或 cell 不可见 | 重新 inspect；先滚动到 cell 可见 |
| `stale_locator` | 携带的快照与当前 view 不一致 | 重新 inspect 后重试 |
| action title 未命中 | 标题与 table delegate 返回值不一致 | 使用现场精确标题，不自动触发第一个 |

cell action 若弹出确认框，交给 `ios-ui-alert`；若导致页面切换，交给 `ios-ui-nav`；长时异步结果交给 `ios-ui-wait`。

手势 runtime 派发仅 Debug 可用。
