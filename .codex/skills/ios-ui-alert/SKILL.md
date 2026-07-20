---
name: ios-ui-alert
description: iOS App 弹窗查询与交互(开发验证 + 自动化测试)/ alert, action sheet, dialog, confirm, button, role, text field, ui.alert.respond, ui_alert_respond
allowed-tools:
  - mcp__iOSDriver__ui_inspect
  - mcp__iOSDriver__ui_alert_respond
  - mcp__iOSDriver__ui_input
  - mcp__iOSDriver__ui_tap_and_inspect
  - mcp__iOSDriver__ui_wait
  - mcp__iOSDriver__ui_screenshot
---

# iOS 弹窗检测与响应

基于 iOSDriver MCP Server(`mcp__iOSDriver__*`),覆盖 `UIAlertController` 的全部自动化场景:检测弹窗是否存在、读取标题 / 消息 / 按钮 / 输入框、按 index / title / role 三种方式触发按钮、填写带文本框的弹窗(登录 / 输入对话框)、action sheet、嵌套与连续弹窗。合并自原 `ios-alert-handling`。

## 目标

解决"触发某个动作后弹出一个 alert,要能稳定检测到它、把信息读出来、再精确触发想要的那个按钮,并且每一步都能判断到底发生了什么"这一 iOS 自动化高频场景。关键不是单条命令怎么调,而是:

- **查询与触发分两条命令**:`ui_inspect` 读 alert 结构(标题 / 按钮 / 输入框 path),`ui_alert_respond` 只负责触发按钮 handler 并请求关闭。两者不混用 —— respond 不再回 alert 结构。
- **三种按钮选择器互斥**:buttonIndex / buttonTitle / role 至多传一个。单按钮 alert 可以不传选择器(默认点唯一按钮);多按钮 alert 必须显式指定,防止误点取消 / 删除等破坏性动作(否则返回 `alert_button_required`)。
- **role 查找无特殊失败模式**:`cancel` / `default` / `destructive` 三种角色在执行器里走完全相同的等值匹配,destructive 不存在"偶发失败",不需要为它加 retry / fallback。
- **每个失败有业务码可判**:`alert_unavailable` / `alert_button_not_found` / `alert_button_required` / `alert_button_trigger_failed` / `alert_release_unsupported` 各指向不同根因,本 skill 给出判别矩阵。

## 何时使用

- ✅ 用户要"点某按钮后预期会弹窗",需要检测并响应
- ✅ 用户要"读取弹窗的标题 / 消息 / 按钮文案"再决定点哪个
- ✅ 用户要"点确认 / 取消 / 删除按钮"(两按钮、三按钮、多按钮 alert)
- ✅ 用户要处理 action sheet(底部弹出式选择,如拍照 / 相册选择 / 分享)
- ✅ 用户要"填登录弹窗 / 输入对话框里的文本框再提交"
- ✅ 用户要处理"一个 alert 关掉后立刻又弹一个"(嵌套 / 连续 alert)
- ✅ 用户说 "弹窗" / "alert" / "对话框" / "确认框" / "action sheet" / "确认 / 取消 / 删除"
- ❌ 不要用于触发 alert 的那个按钮本身(点列表项 / 导航栏按钮 → `ios-ui-list` / `ios-ui-nav`,本 skill 只负责 alert 出现之后)
- ❌ 不要用于非 `UIAlertController` 的自定义模态视图(自定义弹层走 `ios-ui-nav` 的 dismiss 或 `ios-ui-gesture`)
- ❌ 不要用于系统级权限弹窗(位置 / 通知 / 相机等 `CLLocationManager` / `UNUserNotificationCenter` 触发的系统 alert 不在 App 进程内,本 skill 管不到)
- ❌ 不要用于"等异步加载结束"本身(走 `ios-ui-wait`,本 skill 内联用 `ui_wait` 只做 alert 出现 / 消失的短稳定等待)

## 工作原理

弹窗处理的核心时序:**触发动作 → 等 alert 出现 → inspect 读结构 → (可选)填文本框 → respond 触发按钮 → 等关闭 → 再 inspect 确认 / 检测后续 alert**。

### 1. 检测 alert 与读结构(`ui_inspect`)

`ui_inspect` 的顶层 `alert` 区块是唯一的结构查询入口:

```
alert: {
  available: true,            // 当前顶层 controller 是否为 UIAlertController
  title: "确认操作",
  message: "是否继续?",
  buttons: [
    { index: 0, title: "取消", role: "cancel" },
    { index: 1, title: "确认", role: "default" }
  ],
  textFields: [                // 仅输入型 alert 有
    { placeholder: "用户名", isSecure: false, path: "root/0/0/...",
      accessibilityIdentifier: "alert.input.username" }
  ]
}
```

`available == false` 表示当前没有 alert。多 alert 堆叠时只能看到最顶层那个,必须先关掉才能看到下一个。

### 2. 触发按钮(`ui_alert_respond`)

三种选择器**互斥**,只传一个:

- `{buttonIndex: 1}` —— 按下标(0 起),最快;知道按钮顺序时用
- `{buttonTitle: "确认"}` —— 按标题精确匹配(大小写敏感、语言相关),可读性最高
- `{role: "cancel"}` —— 按语义角色,跨语言最稳;role 取值 `cancel` / `default` / `destructive`

不传选择器时:单按钮 alert 默认点唯一按钮;多按钮 alert 返回 `alert_button_required`(防误点)。

响应字段:

| 字段 | 含义 |
|---|---|
| `performed` | 按钮 handler 是否已触发 |
| `dismissed` | 是否请求了系统关闭(presented 状态下为 true;已不在 presenting chain 时为 false,仅触发 handler) |
| `dismissWaitMs` | 异步等待关闭动画的耗时(上限 1500ms,典型 400–500ms) |
| `presentedAfterDismiss` | 被关闭的那个 alert **自身**是否仍滞留在 presenting chain(见"常见错误") |
| `button` | `{index, title, role}` —— 实际触发的按钮 |

> **role 选择顺序建议**:跨语言场景优先 `role`(语言无关);UI 文案稳定的中 / 英文场景用 `buttonTitle`(最直观);按钮顺序确定时用 `buttonIndex`(最快)。destructive 与 cancel / default 走同一套匹配,失败概率相同,不需要额外兜底。

### 3. 输入型 alert(登录 / 输入对话框)

带 `textFields` 的 alert(如登录对话框、重命名对话框):先 `ui_inspect` 拿每个文本框的 `path` / `accessibilityIdentifier`,再用 `ui_input` 逐个填写,最后 `ui_alert_respond` 触发提交按钮。

```
1. ui_inspect → 读 alert.textFields[].path / accessibilityIdentifier
2. ui_input({path/identifier, viewSnapshotID, text:"<value>", mode:"replace"})  // 逐字段
3. ui_alert_respond({buttonIndex:<login-btn-index>})                            // 提交
```

要点:

- **文本框 path 极深且脆弱**(如 `root/0/0/1/0/0/4/0/0/0/0/0/0/0/0`),不要硬编码、不要跨 alert 复用;每次都从当次 `ui_inspect` 重新读
- **安全字段(密码)**:`ui_input` 响应不回原文,只回 `length` + `masked`,用于核对位数;不会出现在日志里
- `ui_input` 的完整参数语义(replace / append、Unicode / emoji、submit 收键盘)同 `ios-ui-form`,本 skill 不重复

### 4. Action sheet

Action sheet(`UIAlertController.Style.actionSheet`)与普通 alert 走**完全相同**的 API —— `ui_inspect` 读 `alert.buttons`,`ui_alert_respond` 触发。区别仅在 UI 呈现(底部弹出、多按钮 + 取消)。典型场景:拍照 / 相册选择 / 分享渠道。处理流程与普通 alert 一致,无需特殊参数。

### 5. 嵌套与连续 alert

**嵌套 alert**(按钮 handler 里立即 present 一个新 alert):`ui_alert_respond` 用 `===` 身份比较判断"被关闭的那个 alert"是否离场,**新 alert 是不同对象,不会被误判为"关闭未完成"**。respond 返回后,要检测后续 alert,**必须重新 `ui_inspect` 看 `alert.available`**——`presentedAfterDismiss` 字段不负责报告"有没有新 alert 弹出"。

**连续 alert**(流水线式一个接一个):对每个 alert 重复"inspect → respond"循环,respond 的关闭等待(`dismissWaitMs`)已含动画,两个 alert 之间通常无需额外 sleep;若读到旧 alert,`ui_wait(mode:"idle", stableMs:300)` 等一拍再 inspect。

### 6. 触发 alert 的入口动作(`ui_tap_and_inspect`)

要点出一个会弹 alert 的按钮(如"删除"按钮),优先用 `ui_tap_and_inspect`:它合并 tap + 等稳定 + inspect,返回的 inspect 结果里直接带 `alert` 区块,省一轮推理。对异步 / 延迟弹出的 alert(点完后过一会才弹),`ui_tap_and_inspect` 的稳定窗口可能不够,用 `ui_wait(mode:"idle", stableMs:500)` 等一拍后再 `ui_inspect` 看 `alert.available`,必要时轮询 inspect 直到 alert 出现。

### 7. 截图取证(可选)

需要记录 alert 外观或失败证据时,`ui_screenshot` 返回 PNG base64。复杂的视觉对比归 `ios-ui-shot`。

## 关键参数

### `ui_alert_respond`

| 参数 | 含义 | 注意 |
|---|---|---|
| `buttonIndex` | 按钮下标(0 起) | 与 `buttonTitle` / `role` 三选一,至多传一个 |
| `buttonTitle` | 按钮标题,精确匹配 | 大小写敏感、语言相关;先 inspect 看真实标题 |
| `role` | `"cancel"` / `"default"` / `"destructive"` | 跨语言最稳;三种 role 走同一匹配,无特殊失败 |
| (都不传) | 默认点唯一按钮 | 仅单按钮 alert 合法;多按钮返回 `alert_button_required` |

### `ui_inspect` 的 `alert` 区块

| 字段 | 含义 |
|---|---|
| `available` | 是否当前顶层是 `UIAlertController` |
| `title` / `message` | 标题 / 消息(可能为 null) |
| `buttons[].index/title/role` | 按钮清单,选择前先看它 |
| `textFields[].path` / `accessibilityIdentifier` | 输入框定位(path 深且脆弱,每次重读) |
| `textFields[].isSecure` | 是否密码字段(响应不回原文) |

### `ui_input`(填 alert 文本框,完整语义见 `ios-ui-form`)

| 参数 | 含义 | 注意 |
|---|---|---|
| `text` | 要输入的文本 | 必填;空串 = 清空 |
| `path` / `accessibilityIdentifier` | 定位文本框(二选一) | 优先用 inspect 读到的 path 或 identifier |
| `viewSnapshotID` | 来自最近 `ui_inspect` | 必填 |
| `mode` | `"replace"`(默认)/ `"append"` | 弹窗填表用 replace |

## 常见错误与判别

### `alert_unavailable`

- **现象**:respond 失败,业务码 `alert_unavailable`
- **原因**:当前顶层 controller 不是 `UIAlertController`(alert 还没弹 / 已经关掉 / 触发动作没成功)
- **判别**:执行前 `ui_inspect` 看 `alert.available`,`false` 就是没有 alert
- **处理**:确认触发动作是否成功;alert 弹出有动画,触发后等 300–500ms 或 `ui_wait(mode:"idle")` 再 inspect;若本就不该弹 alert,这是正常结果不是错误

### `alert_button_not_found`

- **现象**:respond 失败,业务码 `alert_button_not_found`
- **原因**:选择器匹配不到 —— `buttonIndex` 越界、`buttonTitle` 拼写 / 大小写 / 空格不符、`role` 不是三种合法值之一或当前 alert 没有该角色的按钮
- **判别**:先 `ui_inspect` 读 `alert.buttons` 的真实 index / title / role 对照
- **处理**:按 inspect 结果修正选择器;跨语言 alert 别用 title,改用 role;destructive 按钮也是走 role,匹配失败就是 alert 里根本没有 destructive 按钮,不是"偶发失败"

### `alert_button_required`

- **现象**:respond 失败,业务码 `alert_button_required`
- **原因**:多按钮 alert 没传任何选择器(系统拒绝猜测默认按钮,防止误点取消 / 删除)
- **判别**:`ui_inspect` 看 `alert.buttons.length > 1` 且本次 respond 没传 index / title / role
- **处理**:显式传一个选择器(推荐 role 或 index)

### `alert_button_trigger_failed`

- **现象**:respond 失败,业务码 `alert_button_trigger_failed`
- **原因**:按钮选中成功,但触发其 `UIAlertAction` handler 时抛错(handler 内部业务异常)
- **判别**:走到了 trigger 阶段说明选择器对;失败在 handler 执行,看 message 里的 reason
- **处理**:检查 App 侧 handler 逻辑;这不是选择器问题,换 index / title / role 不会解决

### `alert_release_unsupported`

- **现象**:respond 失败,业务码 `alert_release_unsupported`
- **原因**:当前是 Release 构建 —— alert 触发依赖的私有 API 注入被 `#if DEBUG` 隔离,Release 下不可用
- **判别**:构建配置是 Release
- **处理**:切回 Debug 构建再跑;iOSExploreServer 是 Debug-only 开发工具,不支持 Release 触发 alert

### `presentedAfterDismiss: true`(关闭未完成)

- **现象**:respond 返回 `performed:true` 但 `presentedAfterDismiss:true`
- **原因**:被关闭的那个 alert **自身**等满 1500ms 仍滞留在 presenting chain(转场卡住 / 系统拒绝关闭)
- **判别**:注意这个字段**不是**"有新 alert 弹出"的信号 —— 执行器用 `===` 身份比较,handler 里 present 的新 alert 是不同对象,不会让这个字段变 true。要检测后续 alert,重新 `ui_inspect` 看 `alert.available` / `title`
- **处理**:重新 inspect 看顶层是什么;若还是同一个 alert,可能 App 侧拦截了关闭,检查 handler 逻辑

### 触发了动作但 inspect 读不到 alert

- **现象**:tap 后立即 inspect,`alert.available` 还是 `false`
- **原因**:alert 弹出有转场动画,读得太早;或 alert 是延迟 / 异步弹出
- **判别**:再等 300–500ms 重新 inspect;若一直不出现,确认触发动作是否真的绑定了 alert
- **处理**:用 `ui_tap_and_inspect(waitForStable:true, stableTimeMs:500)` 让 tap 后等稳定再 inspect;异步 alert 改 `ui_wait(mode:"idle")` 后轮询 inspect

### 文本框 path 失效(`stale_locator` / 填错框)

- **现象**:`ui_input` 报 `stale_locator`,或填到了错误的框
- **原因**:alert 文本框 path 极深(十几层),跨 alert / 跨次运行不稳定;硬编码的旧 path 对不上当次 view 树
- **判别**:响应 code 与 message 指向 path / snapshot 问题
- **处理**:每次都从当次 `ui_inspect` 的 `alert.textFields[]` 重新读 path / identifier,不复用历史值;优先用 `accessibilityIdentifier`(App 在 `addTextField` 时设置的,比 path 稳)

## 相关 skill

- `ios-ui-form` — `ui_input` 的完整语义(replace / append、Unicode / emoji、submit 收键盘、安全字段)归它;本 skill 只用到"填 alert 文本框"这一小段
- `ios-ui-nav` — 自定义模态视图(非 `UIAlertController`)的 dismiss 走它;alert 不走 navigation 命令
- `ios-ui-wait` — 异步 / 延迟弹出的 alert 的长时等待归它;本 skill 内联用 `ui_wait(mode:"idle")` 只做短稳定等待
- `ios-ui-shot` — 复杂的弹窗视觉对比归它,本 skill 只用 `ui_screenshot` 做单张取证
- `ios-automation` — L1 总入口;不确定走哪个子 skill 时先问它

**平台约束**:iOSExploreServer 是 Debug-only 开发工具,alert 触发依赖私有 API 注入、被 `#if DEBUG` 隔离,Release 构建下 `ui_alert_respond` 返回 `alert_release_unsupported`。`UIAlertController` 之外的系统权限弹窗(位置 / 通知 / 相机等由系统进程_present)不在本 skill 覆盖范围。命令在主线程执行,单次 respond 含关闭动画等待上限 1500ms。
