---
name: ios-ui-list
description: iOS App 列表/集合视图查找、滚动定位与 cell 选中(原 ios-list-interaction)/ list, table view, collection view, scroll, scrollToElement, find item, select cell, swipe action, ui_scroll, ui_scrollToElement, ui_swipe
allowed-tools:
  - mcp__iOSDriver__ui_inspect
  - mcp__iOSDriver__ui_scroll
  - mcp__iOSDriver__ui_scrollToElement
  - mcp__iOSDriver__ui_swipe
  - mcp__iOSDriver__ui_tap
  - mcp__iOSDriver__ui_tap_and_inspect
  - mcp__iOSDriver__ui_wait
---

# iOS 列表与集合视图查找、滚动、选中

基于 iOSDriver MCP Server(`mcp__iOSDriver__*`),覆盖 iOS App 中 `UITableView` / `UICollectionView` 的常见自动化场景:按文本或 accessibilityIdentifier 滚动定位、按方向滚动容器、查找可见 / 不可见项、选中 cell,以及 cell 的滑动操作(swipe action)。合并自原 `ios-list-interaction`。

## 目标

解决"列表里找到某个具体项(可能在屏幕外)、把它滚到可见、再选中它"这一 iOS 自动化最高频的场景。同时覆盖当 `scrollToElement` 失效(如无限滚动未加载、section header 遮挡、横向 collection view)时的手动滚动兜底路径。对常见失败模式(滚动后 snapshot 过期、cell 内子 label 点击不到、多 scroll view 选错容器)给出明确的业务码判别与处理方法。

## 何时使用

- ✅ 用户要"找到列表里某个具体项"(按文本 / identifier)
- ✅ 用户要"把某项滚动到可见"(`ui_scrollToElement`)
- ✅ 用户要"按方向滚动列表"(上滑 / 下滑 / 翻页,`ui_scroll`)
- ✅ 用户要"选中某个 cell 进入详情"或"勾选某项"
- ✅ 用户要"触发 cell 的滑动操作"(左滑删除 / 右滑归档,`ui_swipe`)
- ✅ 用户说 "列表" / "table" / "collection" / "滚动" / "翻页" / "滑到某项" / "左滑删除"
- ❌ 不要用于纯手势(任意方向的 swipe,不针对列表容器 → `ios-ui-gesture`)
- ❌ 不要用于点列表项后的屏幕切换(走 `ios-ui-nav`,本 skill 只负责"找到并选中"这一步)
- ❌ 不要用于"等列表加载完"(异步等待 → `ios-ui-wait`,但本 skill 内联用 `ui_wait` 做 scroll 后的短稳定等待)
- ❌ 不要用于弹窗响应(走 `ios-ui-alert`)

## 工作原理

列表操作的核心时序:**scroll → 等布局稳定 → 重新 inspect → tap**。`ui_scrollToElement` 只负责"把目标项滚进可视区",不返回可点的 `viewSnapshotID`;要 tap 必须重新 `ui_inspect` 拿新快照。

### 1. 首选:`ui_scrollToElement`(按文本 / identifier)

最快路径(实测 2–7ms),走 iOSDriver 内置的 scroll-to-item 逻辑,不需要知道 scroll view 的 path。

1. `ui_scrollToElement({match:"text", value:"<item-text>"})` 或 `{match:"accessibilityIdentifier", value:"<item-id>"}`
2. 读响应:`found:true` + `targetPath` + `targetType` + `container`(确认是 UITableView 还是 UICollectionView)
3. `found:false` 时返回业务码 `target_not_found`(见"常见错误")

`animated:true` 让滚动带动画(适合取证;默认 `false` 用于确定性测试)。

### 2. 兜底:`ui_scroll`(按方向 + pt 距离滚 UIScrollView)

`scrollToElement` 失效时(无限滚动尚未加载该项、section header 遮挡定位、横向 collection view)用手动滚动。`ui_scroll` 只作用于 `UIScrollView` 系(不含 `UITextView`),传 `direction` + `amount`(单位 pt,不是比例):

1. 定位 scroll view:用 `accessibilityIdentifier`(最稳)、`path` 或 `viewSnapshotID`(来自最近 `ui_inspect`)
2. 三者全缺省时,iOSDriver 自动选 keyWindow 最前的 scrollView
3. `direction:"up"`(内容上移 = 看到下方)、`"down"`、`"left"`、`"right"`;`amount` 缺省时按可视区 × 0.5 滚
4. 滚动后 `ui_wait(mode:"idle", stableMs:300)` 等布局稳定,再 `ui_inspect`

### 3. 查找:可见项直接 inspect,不可见项先 scroll

- **可见项**:`ui_inspect` 读 targets,按 `text` / `accessibilityIdentifier` / `type`(`UILabel` / `UITableViewCell` / `UICollectionViewCell`)筛选
- **不可见项**:先 `ui_scrollToElement`,再 `ui_inspect` 读最新 targets
- cell 内子 view(label / button)会通过 `cellAncestor` 自动进 full(见 `ui_inspect` 设计要点),可直接按 cell 标题文本定位再 tap 子元素 path

### 4. 选中 cell(`ui_tap_and_inspect` / `ui_tap`)

1. **先确保目标可见**(走 §1 或 §2)
2. 重新 `ui_inspect` 拿**新** `viewSnapshotID` + 目标 `path`(scroll 后旧 snapshot 立即作废)
3. `ui_tap_and_inspect`(推荐,合并 tap + 等动画 + inspect,自带 `waitForStable:true`)或 `ui_tap` 点 cell / cell 内子 view
4. 若 cell 内子 label 返回 `not_actionable`(指向 minimal 节点),改点其 full 父 cell

### 5. cell 滑动操作(`ui_swipe` 的 cell 模式)

`ui_swipe` 有两种模式,容器模式见 §6,这里是用 `cellAccessibilityIdentifier`(或 `cellPath`)定位 cell,触发其挂载的 `UISwipeActionsConfiguration`:

- `{cellAccessibilityIdentifier:"<cell-id>", direction:"left", actionTitle:"删除"}` —— `direction:"left"` 触发 trailing actions(删除 / 归档常用),`"right"` 触发 leading actions
- `actionTitle` 选具体某个操作;省略时触发第一个
- 该路径**不滚容器**,仅对 cell 做 swipe 手势

### 6. 容器兜底滚动(`ui_swipe` 的容器模式)

当 `ui_scroll` 找不到 UIScrollView 或要模拟真实手指滑动时用 `ui_swipe`:

- `{accessibilityIdentifier:"<scrollview-id>", direction:"up", distance:0.8}` —— `distance` 是 0–1 比例(不是 pt),`direction:"up"` 内容上移 = 看到下方
- `accessibilityIdentifier` / `path` / `viewSnapshotID` 三者全缺省时,swipe keyWindow 最前的 scrollView
- 与 §5 共用 `ui_swipe`,区分依据是**有没有传 `cellAccessibilityIdentifier` / `cellPath`**

## 关键参数

### `ui_scrollToElement`

| 参数 | 含义 | 注意 |
|---|---|---|
| `match` | `"text"` / `"accessibilityIdentifier"` | 必填;text 区分大小写 |
| `value` | 文本片段 或 a11y 标识符 | 必填;建议用从 inspect 看到的完整原样字符串,避免匹配歧义 |
| `animated` | bool,默认 false | false 用于确定性测试;true 用于取证 |
| `accessibilityIdentifier` / `path` | 可选,定位 scroll 容器 | 多 scroll view 同屏时必填,否则可能滚错容器 |

### `ui_scroll`

| 参数 | 含义 | 注意 |
|---|---|---|
| `direction` | `"up"` / `"down"` / `"left"` / `"right"` | 必填;`"up"` = 内容上移 = 看到下方 |
| `amount` | 滚动距离(pt,>0) | 缺省按可视区 × 0.5;与 `ui_swipe.distance`(比例)单位不同,别混用 |
| `accessibilityIdentifier` / `path` / `viewSnapshotID` | 定位 UIScrollView | 三者全缺省时滚 keyWindow 最前 scrollView;`ui_scroll` 不作用于 `UITextView` |
| `animated` | bool,默认 false | 默认关动画以求确定性 |

### `ui_swipe`(双模式共用)

| 参数 | 含义 | 注意 |
|---|---|---|
| `direction` | `"up"` / `"down"` / `"left"` / `"right"` | 必填 |
| `distance` | 比例 (0,1],默认 0.8 | 容器模式用;cell 模式可省 |
| `accessibilityIdentifier` / `path` / `viewSnapshotID` | 容器模式定位 scrollView | 三者全缺省时 swipe 最前 scrollView |
| `cellAccessibilityIdentifier` / `cellPath` | cell 模式定位 cell | 传其中之一即切到 cell 模式 |
| `actionTitle` | 要触发的 swipe action 标题 | 省略时触发第一个;仅 cell 模式用 |

### `ui_tap_and_inspect`(选中 cell)

| 参数 | 含义 | 注意 |
|---|---|---|
| `viewSnapshotID` | 来自最近 `ui_inspect` 的目标指纹 | 必填;scroll 后必须重新 inspect 拿新 ID |
| `path` / `accessibilityIdentifier` | 定位目标 view(二选一) | 与 `viewSnapshotID` 配套 |
| `waitForStable` / `stableTimeMs` | 等 UI 稳定再 inspect,默认开 | push 新屏前的动画等待靠它 |

## 常见错误与判别

### `target_not_found`(`ui_scrollToElement`)

- **现象**:业务码 `target_not_found`,message `scroll target not found`
- **原因**:text 大小写不一致、identifier 拼错、项不在数据源(无限滚动还没加载该 index)、目标在横向 collection view 但 `scrollToElement` 只滚了纵向
- **判别**:先 `ui_inspect` 看可见项文本大小写;`scrollToElement` 响应的 `container` 字段告诉你滚的是哪个类
- **处理**:`text` 用从 inspect 看到的完整原样字符串;无限滚动先连续 `ui_scroll` 触发分页加载,再重试 `scrollToElement`;横向 collection view 改用 `ui_swipe(direction:"left")`

### `stale_locator`(滚动后用旧 snapshot)

- **现象**:tap 或 sendAction 失败,业务码 `stale_locator`
- **原因**:`scrollToElement` / `ui_scroll` 后 `viewSnapshotID` 立即作废(屏幕变了),但用例复用了旧 ID
- **判别**:看响应 code 与 message;snapshot TTL 默认 120 秒,但任何 scroll / 动画都会提前作废
- **处理**:**每次 scroll 后必重新 `ui_inspect`**,不要跨 scroll 复用 `viewSnapshotID`

### `not_actionable`(点 cell 内子 label)

- **现象**:tap 业务码 `not_actionable`,提示 minimal 节点不可操作
- **原因**:点中的 label / button 是 `ui_inspect` 的 minimal 节点(只给 path+type,不签发指纹),`availableActions=[]`
- **判别**:响应 code 区分 —— `not_actionable` = minimal 节点;`target_not_found` = snapshot 过期或 path 不存在
- **处理**:改点其 full 父 cell(cell 本体通常进 full);`ui_inspect` 设计保证 cell 内子 view 会通过 `cellAncestor` 自动进 full,直接用 cell 的 path

### 滚错容器(多 scroll view 同屏)

- **现象**:`scrollToElement` 或 `ui_scroll` 执行了,但滚的是错的那个 scroll view(例如顶部 banner 横滚滚了,主列表没动)
- **原因**:同屏有多个 `UIScrollView`(横幅 + 列表 + 内嵌卡片),三者全缺省时 iOSDriver 选 keyWindow 最前的,可能不是预期那个
- **判别**:`scrollToElement` 响应的 `container` 字段告诉你是哪个类;`ui_inspect` 看 targets 里多个 scroll view 的 path 与 accessibilityIdentifier 区分
- **处理**:`scrollToElement` / `ui_scroll` / `ui_swipe` 传 `accessibilityIdentifier` 或 `path` 显式定位正确的 scroll view

### 滚到了但 inspect 读不到

- **现象**:`scrollToElement` 返回 `found:true`,但 `ui_inspect` targets 里没看到目标项
- **原因**:scroll 动画还没结束 / section header 遮挡 / cell 异步加载未渲染
- **判别**:对比响应时间;`animated:true` 必等 ~300ms 再 inspect
- **处理**:`ui_wait(mode:"idle", stableMs:300)` 再 inspect;若仍读不到,改用 `ui_scroll` 手动微调 amount 让目标项移到屏幕中部

## 相关 skill

- `ios-ui-nav` — 点列表项进入详情后的屏幕切换 / 返回走它;本 skill 只负责"找到并选中"
- `ios-ui-wait` — 长异步加载(分页、搜索结果、骨架屏退场)归它;本 skill 内联用 `ui_wait(mode:"idle")` 仅做 scroll 后的短稳定等待
- `ios-ui-gesture` — 不针对列表容器的纯手势(边缘 swipe、自由拖拽、长按)归它;本 skill 的 `ui_swipe` 限定在列表容器与 cell 场景
- `ios-ui-shot` — 滚动前后的视觉验证归它
- `ios-automation` — L1 总入口;不确定走哪个子 skill 时先问它
