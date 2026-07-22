---
name: ios-ui-list
description: iOS App 的 UITableView、UICollectionView 与 UIScrollView 查找、滚动定位和可见项选择。用于按文本片段或 accessibilityIdentifier 定位屏幕外元素、按方向滚动容器、滚动后刷新快照并选择 cell；手势 recognizer 和 cell swipe action 交给 ios-ui-gesture。触发词包括 list、table、collection、scroll、scrollToElement、find item、select cell、ui_scroll、ui_scrollToElement。
---

# iOS 列表查找、滚动与选择

优先按目标滚动，找不到明确目标时才按方向滚动。所有滚动都会改变可见树；滚动后必须重新 `ui_inspect`，不要复用旧 `viewSnapshotID`。

## 决策流程

1. 已知目标文本或 identifier：先用 `ui_scrollToElement`。
2. 只知道方向、需要触发分页，或需要微调位置：使用 `ui_scroll`。
3. 滚动完成后重新 `ui_inspect`，读取新的 `viewSnapshotID` 和目标 path。
4. 使用 `ui_tap_and_inspect` 选择项并立即验证新页面；无需组合观察时才用 `ui_tap`。
5. 需要 UITableView cell leading/trailing action 时转到 `ios-ui-gesture`。

## 按目标滚动

`ui_scrollToElement` 的 `value` 必填，`match` 默认为 `text`：

- `match:"text"`：匹配 `UILabel.text` 是否包含 `value`，区分大小写。
- `match:"accessibilityIdentifier"`：精确匹配 identifier。
- `accessibilityIdentifier` / `path`：可选，定位滚动容器本身；多容器同屏时必须显式指定。
- `animated`：默认 `false`，确定性测试保留默认值。

命令会在可见 cell 中查找，并在需要时渐进滚动搜索；横向 `UICollectionViewFlowLayout` 也按横向搜索。成功返回 `found/targetPath/targetType/container`，但不签发新快照。

不要假设 `targetPath` 可直接与旧快照配套点击。统一重新 inspect，再取当前目标。

## 按方向滚动

`ui_scroll` 的方向是 content offset 的目标方向，不是手指方向：

| direction | offset 变化 | 用途 |
|---|---|---|
| `down` | y 增大 | 朝列表底部，看到后续内容 |
| `up` | y 减小 | 朝列表顶部，看到前序内容 |
| `right` | x 增大 | 朝右侧内容 |
| `left` | x 减小 | 朝左侧内容 |

`amount` 单位是 point 且必须大于 0；省略时使用可视区约一半。`animated` 默认 `false`。定位字段都省略时选择 key window 最前的 scroll view，因此多容器页面应显式给 identifier/path。

成功响应中的 `offsetBefore/offsetAfter` 可确认是否发生移动，`reachedExtent` 可为 `top/bottom/left/right/null`。到达边界且 offset 不变不是命令失败。

## 选择可见项

滚动后重新 inspect，优先选择 `availableActions` 包含点击动作的 full 节点。cell 内标签通常会因 cell ancestor 被纳入 full；若现场节点 `availableActions=[]`，不要猜测它可点击，改用同一 cell 中的可操作节点或 cell 本体。

`ui_tap_and_inspect` 返回 `{tap, stateAfter, timing}`。从 `stateAfter` 判断导航、弹窗或选中态，不要把 tap 成功等同于业务成功。

## 失败分诊

| code/现象 | 原因 | 动作 |
|---|---|---|
| `target_not_found` from scrollToElement | 文本片段/identifier 未命中，异步数据尚未加载，或搜索超过当前内容 | 核对现场文本；异步加载用 `ios-ui-wait`；分页后重试 |
| `container_not_scrollable` | 容器 disabled 或未挂到 window | 重新 inspect，确认页面和容器 |
| `target_not_found` from scroll | 指定容器不存在 | 更新 identifier/path；多容器不要省略定位 |
| `stale_locator` on 后续点击 | 复用了滚动前快照 | 重新 inspect 后点击 |
| offset 不变且到达 extent | 已在边界 | 结束该方向搜索或换方向 |
| offset 不变且未到 extent | 选错容器或布局尚未稳定 | 检查 `container`，显式定位并等待布局 |

列表加载、搜索结果或分页的长时等待归 `ios-ui-wait`；页面切换归 `ios-ui-nav`；视觉证据归 `ios-ui-shot`。
