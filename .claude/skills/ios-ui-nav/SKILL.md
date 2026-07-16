---
name: ios-ui-nav
description: iOS App 屏幕导航、返回、导航栏按钮与 controller 层级检查(原 ios-navigation、原 ios-controller-navigation)/ navigation, back, dismiss, modal, nav bar button, controller hierarchy, ui.controllers, ui_navigation_back, ui_navigation_tapBarButton
allowed-tools:
  - mcp__iOSDriver__ui_inspect
  - mcp__iOSDriver__ui_tap
  - mcp__iOSDriver__ui_tap_and_inspect
  - mcp__iOSDriver__ui_navigation_back
  - mcp__iOSDriver__ui_navigation_tapBarButton
  - mcp__iOSDriver__ui_controllers
  - mcp__iOSDriver__ui_screenshot
  - mcp__iOSDriver__ui_wait
---

# iOS 屏幕导航与 controller 层级检查

基于 iOSDriver MCP Server(`mcp__iOSDriver__*`),覆盖 iOS App 的屏幕导航(push / pop / modal dismiss)、导航栏按钮(left / right)点按,以及 view controller 层级树读取(`ui.controllers`)。合并自原 `ios-navigation` 与原 `ios-controller-navigation`,前者管屏幕切换操作,后者管只读的 controller 层级检查。

## 目标

解决"从一个屏幕走到另一个屏幕、再原路返回、并在过程中确认当前位置"这一 iOS 自动化测试基础问题。覆盖基于 `UINavigationController` 的 push/pop,也覆盖 modal present/dismiss。对于"想确认现在到底在哪一屏 / 当前导航栈有几层 / 顶层是不是某个 controller 类"这类调试需求,本 skill 同时给两条路径:

- **轻量间接探测**:`ui_inspect` 的 `navigationBar` 字段(title / backAvailable / leftButtons / rightButtons),日常导航定位优先用它
- **完整层级树**:`ui_controllers` 读出根到叶的 controller 结构(navigation stack / presented 链 / tab / split / child),用于排查嵌套容器或确认顶层类名

## 何时使用

- ✅ 用户要在同一 App 内"点某个按钮 / 列表项进入下一屏"
- ✅ 用户要"返回上一屏"或"关闭模态弹窗"
- ✅ 用户要"点导航栏左 / 右按钮"(返回、编辑、分享、取消、保存等)
- ✅ 用户要"确认现在在哪个屏幕"(读 `navigationBar.title` 或 `ui_controllers` 顶层)
- ✅ 用户要"读出整个 controller 层级树"(排查 tab / split / modal 嵌套)
- ✅ 用户说 "导航" / "返回" / "上一页" / "关闭弹窗(模态)" / "导航栏按钮" / "controller 树" / "navigation stack"
- ❌ 不要用于点击列表项以外的列表交互(滚动、查找项目 → `ios-ui-list`)
- ❌ 不要用于"等屏幕加载完再继续"(动态等待 → `ios-ui-wait`)
- ❌ 不要用于 `UIAlertController` 弹窗的按钮响应(走 `ui_alert_respond`,即 `ios-ui-alert`)
- ❌ 不要用于 tab bar 切换 —— tab bar 不是 navigation stack,需用 `ui_tap` 直接点 tab(见 `工作原理 §4`)

## 工作原理

导航操作的关键时序:**tap → 等动画 → inspect 验证**。iOS 屏幕切换动画 200–500ms,不等就读 `ui_inspect` 会读到旧状态。

### 1. 屏幕导航(push)

1. 用 `ui_inspect` 取当前快照,记下 `viewSnapshotID`、`navigationBar.title`、目标元素的 `path`
2. 用 `ui_tap_and_inspect`(推荐,合并 tap + 等待 + inspect,省一轮推理)或 `ui_tap` 点目标元素
3. 读返回的 `topAfter` / `navigationBar.title`,确认切换到了预期屏幕
4. 若一次没切换成功,可能是动画还没结束,`ui_wait(mode:"idle")` 等 300–500ms 再 inspect

### 2. 返回与模态 dismiss(`ui_navigation_back`)

- **默认 auto 策略**:不传 `strategy`,先试 `dismiss`,失败再试 `popViewController`,两种返回方式都覆盖
- **只要 pop**:`{strategy:"navigationController"}` —— 仅 navigation stack 返回,无 nav stack 时失败
- **只要 dismiss**:`{strategy:"dismiss"}` —— 关闭模态,无 presented controller 时失败
- 响应里的 `strategy` 字段是**实际生效的策略**(`auto` 下反映 dismiss 还是 pop 生效),`topBefore` / `topAfter` 是切换前后顶层 controller 类名

返回前建议用 `ui_inspect` 看 `navigationBar.backAvailable`,为 `true` 才有意义 pop;为 `false` 且无模态时,再调 back 必然失败。

### 3. 导航栏按钮(`ui_navigation_tapBarButton`)

三种定位方式(任选其一):

- `{placement:"left"|"right", index:0}` —— 按位置下标
- `{placement, accessibilityIdentifier:"<your.button.id>"}` —— 按 a11y 标识符(最稳,推荐)
- `{placement, index, title:"<button-title>"}` —— 点之前额外校验按钮标题与现场一致,防误点

响应给 `performed:true` + 按钮描述 + `topBefore` / `topAfter`。若 `topBefore == topAfter` 不代表失败 —— 编辑 / 分享按钮可能只切换 mode,不 push 新屏。

### 4. Tab bar 切换(走 `ui_tap`,不用 navigation 命令)

Tab bar 是平级切换,不是 navigation stack。用 `ui_inspect` 找到 tab 的 `path`(通常 type 为 `UITabBarButton` 或类似),用 `ui_tap` 点,然后 inspect 验证。

### 5. controller 层级树(`ui_controllers`,整合自原 ios-controller-navigation)

读取从 `window.rootViewController` 出发的完整 controller 结构树,含 navigation stack / presented 链 / tab / split / child。每个节点有唯一定位 `path` 与 `topPath` 摘要。典型用途:

- 看当前顶层 controller 类名(比 `navigationBar.title` 更准)
- 看 navigation stack 深度 / modal presented 链长度
- 排查 tab + nav + modal 嵌套结构

用法:`ui_controllers(maxDepth:0)` 看根节点概览,需要深入子树再加大 `maxDepth`。该命令适合先看结构、再用 `ui_inspect` 看具体节点的 view 层细节。

注:`ui_controllers` 继承自原 ios-controller-navigation,实测覆盖弱于本 skill 其他 navigation 命令;遇到非标准容器(如自定义 container VC)返回异常时,退回 `ui_inspect` + navigationBar 间接推断。

### 6. 截图取证(`ui_screenshot`)

返回 PNG base64。导航前后各截一张,对比切换效果,或作为失败证据。

## 关键参数

### `ui_navigation_back`

| 参数 | 含义 | 注意 |
|---|---|---|
| `strategy` | `"auto"`(默认)/ `"navigationController"` / `"dismiss"` | `auto` 依次尝试 dismiss → pop;响应里 `strategy` 是实际生效的策略 |
| `animated` | bool,默认 false | 默认关闭动画以减少等待 |
| `waitAfterMs` | 0...3000,默认 300 | 读 UI 前的稳定等待 |

### `ui_navigation_tapBarButton`

| 参数 | 含义 | 注意 |
|---|---|---|
| `placement` | `"left"` / `"right"` | 必填 |
| `index` | 按钮在该侧的下标,从 0 起 | 与 `accessibilityIdentifier` 二选一 |
| `accessibilityIdentifier` | 按钮的 a11y 标识符(全局可搜) | 与 `index` 二选一;单独使用时可配合 `placement` 二次确认 |
| `title` | 校验用,执行时必须与现场按钮标题一致 | 防误点;不作为定位主键 |
| `waitAfterMs` | 0...3000,默认 300 | 读 UI 前的稳定等待 |

### `ui_controllers`

| 参数 | 含义 | 注意 |
|---|---|---|
| `maxDepth` | 最大递归深度,0 表示仅根节点 | 默认会展开整棵树;排深栈时调小,逐步加大 |

### `ui_tap_and_inspect`

| 参数 | 含义 | 注意 |
|---|---|---|
| `viewSnapshotID` | 来自最近一次 `ui_inspect` 的目标指纹 | 必填 |
| `path` / `accessibilityIdentifier` | 定位目标 view(二选一) | 与 `viewSnapshotID` 配套 |
| `waitForStable` | 是否等 UI 稳定再 inspect,默认 true | 处理动画 / 异步加载 |
| `stableTimeMs` | 0...3000,默认 300 | 稳定窗口 |
| `inspectDepth` / `inspectMaxTargets` | inspect 的深度与目标数上限 | 复杂屏调大 |

## 常见错误与判别

### `back_button_unavailable`(`ui_navigation_back`)

- **现象**:调 back 返回失败,业务码 `back_button_unavailable`
- **原因**:已在 navigation stack 根节点且无 modal presented,auto 策略两路都失败
- **判别**:执行前 `ui_inspect` 看 `navigationBar.backAvailable`,`false` 就是根节点;或 `ui_controllers` 看 root 是否就是 topmost
- **处理**:不要调 back,改走具体按钮 / tab / 退出登录等其他路径

### `invalid_data`(`ui_navigation_tapBarButton`)

- **现象**:业务码 `invalid_data`,提示 placement / index / 标识符不对
- **原因**:`placement` 不是 left/right、`index` 越界、`accessibilityIdentifier` 不匹配、`title` 与现场不一致
- **判别**:先 `ui_inspect` 读 `navigationBar.leftButtons` / `rightButtons`,确认按钮数量与标识符
- **处理**:优先用 `accessibilityIdentifier` 替代 `index`(最稳);`title` 字段留空除非确实现场校验

### `target_not_found` / `not_actionable`(`ui_tap_and_inspect` / `ui_tap`)

- **现象**:tap 失败,提示目标找不到或不可操作
- **原因**:`viewSnapshotID` 已过期(屏幕变了)或 `path` 指向 minimal 节点(只给 path+type,不可点击)
- **判别**:响应 `code` = `not_actionable` 指向 minimal 节点;`target_not_found` 多半是 snapshot 过期
- **处理**:重新 `ui_inspect` 拿新 `viewSnapshotID`;若是 minimal 节点,改点其 full 父节点(cell 内子 label 通常要点 cell 本体)

### 切换后 title 没变 / 读到旧状态

- **现象**:tap 后立即 inspect,title 还是上一屏
- **原因**:iOS 屏幕切换动画 200–500ms,读得太早
- **判别**:对比 `topAfter` 与 `topBefore`,相同时不一定失败(编辑按钮),但若新屏 title 应改变却没变,多半是动画未完
- **处理**:`ui_tap_and_inspect(waitForStable:true, stableTimeMs:500)` 或 tap 后 `ui_wait(mode:"idle", stableMs:300)` 再 inspect

### `ui_controllers` 返回为空 / 结构与预期不符

- **现象**:root 为空、stack 深度不对、tab 子树没展开
- **原因**:`maxDepth` 太小;或 App 使用非标准 controller 容器(自定义 present 转场),系统未识别
- **判别**:`maxDepth:0` 先看根节点类名,逐级加大;若根节点就为空,是 App 未正确挂 `rootViewController`
- **处理**:调大 `maxDepth`;`ui_controllers` 不准时退回 `ui_inspect` + `navigationBar` 间接推断(title / backAvailable)

## 相关 skill

- `ios-ui-list` — 点列表项进入详情是常见导航入口;但滚动 / 查找项本身归它
- `ios-ui-wait` — 轻量 idle 等待(导航动画后 300ms)本 skill 内联用 `ui_wait`;长时等待 / 异步加载归它
- `ios-ui-shot` — 复杂的截图对比 / 视觉验证归它,本 skill 只用 `ui_screenshot` 做单张取证
- `ios-ui-alert` — 导航过程中弹出的 `UIAlertController` 不走 navigation 命令,走 `ui_alert_respond`
- `ios-automation` — L1 总入口;不确定走哪个子 skill 时先问它
