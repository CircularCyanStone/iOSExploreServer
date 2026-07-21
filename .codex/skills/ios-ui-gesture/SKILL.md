---
name: ios-ui-gesture
description: iOS App 进阶手势(swipe 方向滑动 / long press 长按 / cell 滑动操作)(开发验证 + 自动化测试)/ swipe, scroll, long press, context menu, cell swipe action, delete, edit, ui_swipe, ui_longPress
---

# iOS 进阶手势:swipe 滑动与 long press 长按

基于 iOSDriver MCP Server(`mcp__iOSDriver__*`),覆盖 iOS App 基础点按之外的三类手势:容器内方向滑动(`ui_swipe`,可变方向 + 可变距离)、长按触发上下文菜单(`ui_longPress`,自定义时长)、列表 cell 横滑操作(`ui_swipe` 的 cell 模式,直接触发删除 / 归档 / 编辑)。合并自原 `ios-gestures`。**不含拖拽 drag**(iOSDriver 没有 drag action,旧 skill 的 drag 内容已删除)。

## 目标

解决"在滚动容器里按方向翻内容、长按某个元素弹上下文菜单、在列表 cell 上横滑触发滑动操作"这三类手势交互,并且每一步都能判断手势到底有没有生效。关键不是单条命令怎么调,而是:

- **滑动有两条独立路径,参数互斥**:容器滚动用 `accessibilityIdentifier` / `path` 定位 ScrollView;cell 滑动操作用 `cellAccessibilityIdentifier` / `cellPath` 切到 cell-action 模式。两套定位不能混用。
- **`duration` 单位是秒,不是毫秒**(旧 skill 写错成毫秒):`ui_longPress` 的 `duration` 默认 0.5 秒,传 `1000` 会变成 1000 秒的长按。
- **手势不会自动等动画**:iOSDriver 的 `ui_swipe` / `ui_longPress` 没有内置 postDelay,做完手势后内容还在滚、菜单还在弹,必须留动画时间(用 `ui_wait` 或重新 inspect)再读结果。
- **手势后必须重新 inspect 验证**:swipe 后看新内容是否出现、longPress 后看菜单项、cell 操作后看行是否删除;手势改变了 view 树,旧 `viewSnapshotID` 立即作废。

## 何时使用

- ✅ 用户要在列表 / ScrollView 里"向上 / 向下 / 向左 / 向右滑动"翻内容
- ✅ 用户要"长按某个元素"触发上下文菜单(复制 / 删除 / 分享 / 重命名)
- ✅ 用户要"在某个 cell 上横滑"露出或触发滑动操作(删除 / 归档 / 编辑)
- ✅ 用户要连续多方向滑动浏览内容
- ✅ 用户说 "滑动" / "swipe" / "长按" / "上下文菜单" / "滑动删除" / "cell 操作" / "左滑删除"
- ❌ 不要用于普通点按 / 双击(走 `ui_tap`,见 `ios-ui-list` / `ios-ui-form`)
- ❌ 不要用于"滚动到指定项"(走 `ios-ui-list` 的 `ui_scrollToElement`,按文本 / identifier 直接定位,比方向 swipe 更稳)
- ❌ 不要用于拖拽 drag(iOSDriver 无 drag action,无法实现)
- ❌ 不要用于"等异步加载 / loading 结束"本身(走 `ios-ui-wait`,本 skill 的 `ui_wait` 只做手势后的短动画稳定)

## 工作原理

核心时序:**inspect 取目标 → 手势(swipe / longPress)→ 留动画时间 → 重新 inspect 验证**。手势不会自动等动画,做完立即读会读到旧状态;验证必须基于手势之后的新 inspect。

### 1. 容器内方向滑动(`ui_swipe`)

- **定位**:用 `accessibilityIdentifier` 或 `path` 指向 `UIScrollView` / `UITableView` / `UICollectionView`;两者都不传时,默认作用于 keyWindow 最前面的 scrollView
- **`direction` 是手指滑动方向,不是内容滚动方向**:`up`(手指上滑)露出下方内容;`down` 露出上方内容;`left` 露出右侧内容;`right` 露出左侧内容
- **`distance`**:0–1 归一化比例(默认 0.8)。精调用小值(0.3–0.5),快翻用大值(0.8–0.9)
- **动画时序**:swipe 后滚动减速约 300ms;iOSDriver 的 `ui_swipe` 没有内置延迟,用 `ui_wait(mode:"idle", stableMs:300)` 或直接重新 inspect(首次读到旧状态就再 inspect 一次)

### 2. 长按(`ui_longPress`)

- **定位**:`accessibilityIdentifier` 或 `path`;两者都不传时,找 keyWindow 第一个可长按的 view
- **`duration` 单位是秒**(不是毫秒!),默认 0.5;典型上下文菜单用 0.5–1.0 秒。**传 1000 会变 1000 秒**,这是最常见的迁移错误
- **菜单转场动画**约 400–600ms;`ui_longPress` 没有 postDelay 参数,做完需 `ui_wait(mode:"idle", stableMs:500)` 或重新 inspect 留出时间,再读菜单项
- **验证**:longPress 后重新 `ui_inspect`,看是否新增了菜单项(Copy / Delete / Share 等)

### 3. cell 滑动操作(`ui_swipe` 的 cell 模式)

用 `cellAccessibilityIdentifier` 或 `cellPath` 定位 cell → `ui_swipe` 自动切到 cell-action 模式(不再当容器滚动处理):

- **`direction`**:`left`(左滑)露出右侧 trailing 操作(删除 / 归档,最常见);`right`(右滑)露出左侧 leading 操作
- **`actionTitle`**(关键):传指定标题(如 `"删除"` / `"归档"`)→ **直接触发该操作**(连点按钮都省了);不传 → 触发第一个操作
- 若只想"露出"按钮、由后续逻辑决定点哪个,不传 `actionTitle` 时会触发第一个;要精确控制就传 `actionTitle`
- 操作触发的后续(行删除、弹确认 alert)走对应的 `ios-ui-list` / `ios-ui-alert`

### 4. 手势后验证(必做,恢复 M1 要点)

每次手势后**重新 `ui_inspect`** 比对结果:swipe 后看 `targets` 是否出现新内容;longPress 后看菜单项;cell 操作后看行是否消失 / 操作 sheet 是否弹出。手势会让旧 `viewSnapshotID` 失效(view 树变化 + TTL),验证与后续操作都必须基于新 inspect 的 `viewSnapshotID`。**iOS 不向测试暴露"滚动结束"事件**,无法编程判断滚动何时停;只能用固定动画时间(~300ms)的 `ui_wait` 或 inspect 轮询直到 `targets` 稳定。

## 关键参数

### `ui_swipe`

| 参数 | 含义 | 注意 |
|---|---|---|
| `direction` | `"up"` / `"down"` / `"left"` / `"right"` | 必填;**手指方向**,不是内容方向 |
| `distance` | 0–1 归一化,默认 0.8 | 精调 0.3–0.5,快翻 0.8–0.9 |
| `accessibilityIdentifier` / `path` | 定位滚动容器 | 都不传默认最前 scrollView;与 cell 定位互斥 |
| `cellAccessibilityIdentifier` / `cellPath` | 定位 cell,切 cell-action 模式 | 与容器定位互斥 |
| `actionTitle` | 直接触发该标题的 cell 操作(如 `"删除"`) | 不传触发第一个操作 |

### `ui_longPress`

| 参数 | 含义 | 注意 |
|---|---|---|
| `accessibilityIdentifier` / `path` | 定位目标 | 都不传时找第一个可长按的 view |
| `duration` | **秒**(不是毫秒),默认 0.5 | 1 秒长按写 `0.8` 或 `1.0`,**不要写 `1000`** |

### `ui_wait`(手势后动画稳定)

| 参数 | 含义 | 注意 |
|---|---|---|
| `mode` | `"idle"`(连续稳定)/ `"snapshotChanged"` | 手势后稳定用 `idle`;等新内容用 `snapshotChanged` |
| `stableMs` | idle 模式连续稳定的毫秒数,默认 300 | swipe 后约 300;longPress 菜单约 500 |

## 常见错误与判别

### `duration` 传成毫秒(longPress 最常见迁移错误)

- **现象**:`ui_longPress` 看起来卡死、超时,或长按时间远超预期
- **原因**:`duration` 单位是**秒**,传 `1000`(意图 1 秒)实际是 1000 秒;旧 skill / 旧文档误标成毫秒
- **判别**:对照工具定义 `duration` 默认 0.5;任何 `≥10` 的值都疑似单位错
- **处理**:1 秒长按写 `duration:0.8` 或 `1.0`,不要写 `1000`

### 用 `withinElementRef` / `elementRef` 定位(参数不存在)

- **现象**:`ui_swipe` / `ui_longPress` 报 `invalid_data`,提示定位参数缺失
- **原因**:`withinElementRef` / `elementRef` 是 **XcodeBuildMCP** 的参数,iOSDriver 用 `accessibilityIdentifier` / `path`;旧 skill 抄串了
- **判别**:看响应 `message` 指向哪个参数;iOSDriver 不认 `*elementRef`
- **处理**:改用 `accessibilityIdentifier` 或 `path` 定位容器;cell 用 `cellAccessibilityIdentifier` / `cellPath`

### swipe 后读到旧内容(动画未结束)

- **现象**:swipe 后立即 inspect,`targets` 还是滑动前的列表
- **原因**:滚动减速动画约 300ms;**手势不会自动等动画**,读得太早
- **判别**:对比滑动前后 `targets` 列表,完全相同就是还没滚完
- **处理**:swipe 后 `ui_wait(mode:"idle", stableMs:300)` 再 inspect;或重新 inspect,首次读到旧状态就再 inspect 一次直到 `targets` 稳定

### longPress 后菜单没出现

- **现象**:`ui_longPress` 返回成功但 inspect 看不到菜单项
- **原因**:`duration` 太短(<0.5 秒系统不识别为长按);元素本身不支持长按;或菜单还在弹出动画(~500ms)
- **判别**:`duration` 是否 ≥0.5;inspect 是否在 longPress 后留了动画时间
- **处理**:`duration` 提到 0.8–1.0;longPress 后 `ui_wait(mode:"idle", stableMs:500)` 再 inspect

### 无法判断滚动何时结束(系统限制)

- **现象**:swipe 后想等滚动"完全停下"再操作,但没有"滚动结束"信号
- **原因**:iOS 不向测试暴露滚动结束回调,iOSDriver 也没有该事件;这是固有限制,不是 bug
- **判别**:确认是"等停"需求而非其他失败
- **处理**:用固定动画时间(~300ms)的 `ui_wait`,或重新 inspect 轮询直到 `targets` 连续两次一致

### `stale_locator`(snapshot 过期)

- **现象**:swipe / longPress 报 `stale_locator`
- **原因**:上一次 inspect 的 `viewSnapshotID` 已过期(手势改变了 view 树,或超过 120 秒 TTL)
- **判别**:响应 `code` = `stale_locator`
- **处理**:重新 `ui_inspect` 拿新 `viewSnapshotID`;手势后的验证本来就应基于新 inspect

### cell 模式没触发(定位参数混用)

- **现象**:本想触发 cell 滑动操作,结果只滚动了列表 / 报参数冲突
- **原因**:同时传了容器定位(`path` 指向 ScrollView)和 cell 定位,或没传 `cellAccessibilityIdentifier` / `cellPath`
- **判别**:看响应是否按容器滚动处理;cell-action 模式必须用 `cellAccessibilityIdentifier` / `cellPath`
- **处理**:cell 操作只传 `cellAccessibilityIdentifier`(或 `cellPath`)+ `direction` + 可选 `actionTitle`,不要混入容器 `path`

## 相关 skill

- `ios-ui-list` — 列表"滚动到指定项"走它的 `ui_scrollToElement`(按文本 / identifier 直接定位,比方向 swipe 更准);cell 选中、点按也归它。本 skill 只管手势滑动本身
- `ios-ui-wait` — 长时异步等待 / loading 归它;本 skill 的 `ui_wait` 只做手势后的短动画稳定(~300–500ms)
- `ios-ui-nav` — 长按菜单 / cell 操作触发的屏幕切换、modal dismiss 走它
- `ios-ui-alert` — cell 滑动操作(如删除)弹出的确认 `UIAlertController` 走 `ui_alert_respond`,不是本 skill
- `ios-ui-shot` — 手势前后的视觉对比取证归它,本 skill 不做截图
- `ios-automation` — L1 总入口;不确定走哪个子 skill 时先问它

**平台约束**:本套自动化能力是 Debug-only 开发工具,手势执行依赖私有 API 注入、被 `#if DEBUG` 隔离,Release 构建下不可用。命令在主线程执行,单次必须在 5 秒内完成。`viewSnapshotID` 默认 TTL 120 秒,但手势(改变 view 树)会提前作废。
