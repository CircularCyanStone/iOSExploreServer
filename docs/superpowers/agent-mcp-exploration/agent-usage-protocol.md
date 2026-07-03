# Agent 使用协议

> 日期：2026-07-02
>
> 本文说明 Agent 应该如何使用 `iOSExploreServer` / `iOSExploreUIKit` 提供的 MCP 工具来探索和测试 App。它不是测试平台设计，也不是新命令实现方案；它先把“怎么正确使用现有工具”讲清楚。

## 1. 这份协议解决什么问题

当前项目已经有不少 UI 命令：

- 看页面：`ui.viewTargets`、`ui.topViewHierarchy`、`ui.screenshot`
- 做动作：`ui.tap`、`ui.control.sendAction`、`ui.input`、`ui.scroll`、`ui.scrollToElement`、`ui.keyboard.dismiss`、`ui.navigation.back`、`ui.navigation.tapBarButton`
- 等待：`ui.wait`
- 查询弹窗：`ui.alert.respond`

问题是：命令多，不等于 Agent 会正确使用。

这份协议要解决的是：

```text
Agent 每一步应该先做什么、再做什么；
什么结果能说明测试通过；
什么情况必须停下来重新观察；
哪些命令当前有边界，不能假装可用。
```

## 2. 基本闭环

Agent 每一步都应按这个顺序走：

```text
观察页面
→ 选择一个明确动作
→ 执行动作
→ 等待反馈或重新观察
→ 根据最新页面判断下一步
```

普通话解释：

- 先看当前页面，不要凭记忆操作；
- 每次只做一个动作；
- 动作成功不等于测试成功；
- 动作后必须等页面反馈，或者重新观察页面；
- 判断测试是否通过，必须看最终页面证据。

## 3. 观察页面规则

### 3.1 默认先用 `ui.viewTargets`

`ui.viewTargets` 是默认观察入口。

它适合回答：

```text
当前页面有哪些可能可操作的目标？
每个目标有没有 identifier？
它的 path 是什么？
它当前能不能点？
它支持哪些动作？
```

Agent 默认应该先调用它，而不是直接截图。**它也是 `viewSnapshotID` 的唯一签发者**——后续 `ui.tap` / `ui.control.sendAction` / `ui.wait(snapshotChanged)` 所需的 `viewSnapshotID` 必须来自最近一次 `ui.viewTargets`（`ui.screenshot` / `ui.topViewHierarchy` 不再签发）。

### 3.2 需要更详细信息时再用 `ui.topViewHierarchy`

`ui.topViewHierarchy` 返回完整 view 树，信息更多，也更重。

适合这些情况：

- `ui.viewTargets` 看不到足够信息；
- 需要排查页面结构；
- 需要看文本、颜色、控件状态、滚动信息；
- 需要确认某个 identifier 是否真的在树里。

### 3.3 截图不是默认观察方式

`ui.screenshot` 用于证据和排查，不是每一步默认动作。

使用场景：

- 失败时留现场；
- 结构化信息不够；
- 人工需要看页面；
- 未来 Mac 侧视觉模型需要辅助判断。

运行验证里，Example App 单张截图约 149 KB。这个体积可以接受，但不适合每一步都取。

## 4. 选择目标规则

### 4.1 优先使用 `accessibilityIdentifier`

如果目标有稳定的 `accessibilityIdentifier`，优先用它。

原因很简单：

```text
identifier 是业务给自动化留下的稳定名字；
页面层级变化时，它比 path 更稳。
```

业务 App 后续应该尽量给关键页面状态和关键控件设置稳定 identifier。

### 4.2 path 必须配合 viewSnapshotID 才适合安全复用

`path` 表示“当前这次页面快照里的位置”，例如：

```text
root/0/2/1
```

它不是永久地址。页面一变，旧 path 可能指向另一个控件。

所以如果 Agent 要用 path 做动作，应该使用：

```text
path + viewSnapshotID
```

`viewSnapshotID` 来自最近一次 `ui.viewTargets`。这样工具可以检查页面是否已经变化，避免旧 path 点错目标。

### 4.3 不存在“裸坐标点击”

`ui.tap` 不再接受坐标（`x`/`y`/`window`/`coordinateSpace` 已删除），也不做 hit-test。它只接受 `accessibilityIdentifier` 或 `path`（二选一）+ 必填 `viewSnapshotID`，并按 target 类型做“默认激活动作”。

所以协议要求：

```text
不要尝试用坐标点击绕过目标定位。
```

如果 `ui.viewTargets` 看不到能满足的目标，说明：

- 目标可能是普通 label / container / gesture-only view（不在 canonical targets 里），需要 `ui.topViewHierarchy` 排查；
- 目标可能是 navigationBar 按钮，走 `ui.navigation.tapBarButton`；
- 目标可能是弹窗按钮，走 `ui.alert.respond`；
- 目标真的不在当前页面，需要先滚动或返回。

没有“用坐标硬点”这条兜底路径。

## 5. 动作规则

### 5.1 `ui.tap` 是默认激活动作，不是触摸注入

`ui.tap` 现在按 target 类型路由“默认激活动作”：

```text
UIButton                → sendActions(.touchUpInside)
UISwitch                → setOn(!isOn) + .valueChanged
UITextField/UITextView  → becomeFirstResponder（聚焦）
UISlider/UISegmentedControl/普通 UIView → unsupported_target
```

它返回成功（`activated: true` + `activationRoute`），只能说明：

```text
目标找到了；
viewSnapshotID 通过了陈旧校验；
target 有默认激活路由，激活动作已经发出。
```

它不能说明：

- 页面已经跳转；
- 网络请求已经完成；
- 登录已经成功；
- 列表已经刷新；
- 测试步骤已经通过。

需要其他动作时走对应命令：

- 需要显式 control event（如 `.valueChanged` / `.touchDown` / `.editingDidEnd`）→ `ui.control.sendAction`（target 自身必须是 `UIControl`，需 `viewSnapshotID`）；
- navigationBar 按钮 → `ui.navigation.tapBarButton`（不并入 `ui.tap`）；
- 弹窗按钮 → `ui.alert.respond`（不并入 `ui.tap`）。

因此，`ui.tap` 后必须调用等待或重新观察。

### 5.2 输入后也要等待或重新观察

`ui.input` 会把文本写入控件，并校验最终文本。

但这只能说明“文本控件里写进去了”。它不能证明：

- 搜索结果出现；
- 表单校验完成；
- 下一页已经打开；
- 错误提示已经消失。

所以输入后仍要根据场景调用 `ui.wait` 或重新 `ui.viewTargets`。

### 5.3 滚动后必须重新观察

`ui.scroll` / `ui.scrollToElement` 会改变页面可见区域。

滚动后旧 viewSnapshotID 和旧 path 都可能不适合继续用。

因此滚动后默认应：

```text
重新 ui.viewTargets
或等待目标可见后再观察
```

### 5.4 返回和收起键盘后也要重新观察

`ui.navigation.back` 和 `ui.keyboard.dismiss` 会改变页面状态。

即使它们返回成功，也只能说明动作执行了。Agent 仍应重新观察，确认当前页面是否符合预期。

## 6. 等待规则

### 6.1 当前 `ui.wait` 是单条件等待

`ui.wait` 可以等：

- 页面稳定；
- 目标出现；
- 目标消失；
- 文本出现；
- snapshot 变化。

但它一次只等一个条件。

它不是完整的“测试步骤验证器”。例如登录后可能有多个结果：

```text
进入首页；
密码错误；
网络错误；
验证码弹窗；
仍在加载。
```

当前 `ui.wait` 不能一次表达这些分支。后续需要设计“多结果等待并返回最终页面”的能力。

### 6.2 `textExists` 只等当前可见文本

运行验证确认：`ui.wait mode=textExists` 检测的是当前可见文本。

它不能查到：

- 已经滚出屏幕的 cell；
- 被复用回收的列表内容；
- 数据源里的历史文本；
- 不在当前 view 树里的文本。

所以列表场景要按这个方式使用：

```text
scroll
→ observe
→ wait textExists
```

如果等不到，不要立刻认为业务失败。先判断目标是否可能还没滚到可见区域。

### 6.3 等待失败不是一定业务失败

`wait_timeout` 表示“在给定时间内没有等到这个条件”。

它可能意味着：

- 页面真的没变化；
- 条件写错；
- 目标文本不可见；
- 需要先滚动；
- 被弹窗挡住；
- 网络慢；
- 业务失败。

Agent 必须重新观察页面，再决定下一步。

## 7. 弹窗规则

当前 `ui.alert.respond` 名字像“响应弹窗”，但真实能力是查询弹窗。

当前它可以：

- 查询当前是否有 `UIAlertController`；
- 返回标题、消息、按钮、输入框；
- 当前无弹窗时返回 `alert_unavailable`。

当前它不能：

- 真正点击弹窗按钮；
- 自动关闭所有弹窗。

所以协议要求：

```text
遇到弹窗流程，不能假装已经能自动处理。
```

短期处理方式：

- 如果只是确认无弹窗，`alert_unavailable` 可以视为“没有弹窗要处理”；
- 如果发现有弹窗，需要人工、宿主自定义 action，或等待后续补齐真正的弹窗响应能力；
- 不能做“关闭所有弹窗”这种含糊动作。

未来补能力时，也必须按明确按钮操作：

- 按按钮 index；
- 按按钮 title；
- 按按钮 role；
- 或按业务提供的稳定 identifier。

## 8. NavigationBar 规则

`ui.viewTargets` 与 `ui.topViewHierarchy` 的响应里都带 `navigationBar` 区块，列出当前顶部控制器导航栏的 `leftItems` / `rightItems`，每个按钮含 `placement`、`index`、`title`、`accessibilityIdentifier`、`isEnabled` 与 `availableActions`。

导航栏按钮（`UIBarButtonItem`）**不走 `ui.tap`，也不要坐标硬点**。坐标点击会命中 `_UIModernBarButton` 这类 UIKit 私有 view，且 `ui.tap` 会因目标不是 `UIControl` 而拒绝；改用专门动作：

```text
ui.navigation.tapBarButton
```

调用规则：

1. 先观察 `navigationBar.rightItems` / `leftItems`，确认目标按钮的 `placement` 与 `index`；
2. 最好带上观察到的 `title` 或 `accessibilityIdentifier` 做二次确认，防止页面已变化点错按钮；
3. 按钮不存在、不匹配、disabled 或没有可触发动作时，命令返回明确错误码（`navigation_bar_unavailable` / `navigation_bar_item_not_found` / `navigation_bar_item_mismatch` / `navigation_bar_item_disabled` / `navigation_bar_item_unsupported`），不要重试旧输入，应重新观察；
4. 动作成功（`performed: true`）只表示按钮已触发，仍要 `ui.wait` 或重新 `ui.viewTargets` 确认页面反馈，再判断是否进入目标页。

旧版本（无 `navigationBar` 字段）的兼容策略：

```text
观察结果没有 navigationBar 字段时，记录为工具能力缺口，不要坐标硬点，
改走宿主自定义 action 或升级服务版本。
```

## 9. 错误处理规则

Agent 不应该把所有错误都当成“测试失败”。

常见错误应这样理解：

| code / 结果 | 普通解释 | Agent 应该怎么做 |
|---|---|---|
| `stale_locator` | 页面已经变了，旧 path / 旧 viewSnapshotID 不可靠（固定提示 "call ui.viewTargets first"） | 重新调用 `ui.viewTargets` 拿新 viewSnapshotID，不要重试旧输入 |
| `target_not_found` | 目标不存在或当前不可见 | 重新观察，必要时滚动或处理弹窗 |
| `ambiguous` / 歧义 | 找到多个候选 | 不要点，换更明确 identifier |
| `disabled` / unsupported | 目标当前不能操作或不支持动作 | 不要强点，观察状态或换动作 |
| `wait_timeout` | 等待条件没出现 | 重新观察，再判断是业务失败还是条件不对 |
| `alert_unavailable` | 当前没有 UIAlertController | 如果只是查弹窗，可继续下一步 |
| `navigation_back_unavailable` | 当前不能返回 | 如果已经在根页面，这不是业务失败 |
| `dismissed:false` | 当前没有键盘可收起 | 不是失败，可以继续 |

核心原则：

```text
能重新观察，就先重新观察；
目标不确定，就不要点；
错误分类清楚，才能决定下一步。
```

## 10. 测试是否通过的判断规则

测试是否通过，不能由动作命令直接决定。

正确判断方式是：

```text
动作执行后
→ 等待或重新观察
→ 找到明确页面证据
→ 再判断测试结果
```

明确证据可以是：

- 成功页面 root identifier 出现；
- 失败提示 identifier 出现；
- 空状态 identifier 出现；
- 重试按钮出现；
- 顶部控制器变成预期页面；
- 关键目标存在且状态正确；
- 必要时截图作为人工证据。

不应该用这些作为通过依据：

- `ui.tap` 返回 `activated: true`；
- `ui.input` 返回 finalText；
- 固定 sleep 后没有报错；
- 坐标点下去没有失败；
- 截图看起来“大概对”但没有结构化证据。

## 11. 推荐的单步模板

Agent 执行一个自然语言步骤时，推荐这样做：

```text
1. observe
   调 ui.viewTargets，看当前页面和可操作目标。

2. decide
   选择明确目标，优先 identifier，其次 path + viewSnapshotID（来自第 1 步的 ui.viewTargets）。

3. act
   按目标类型选命令：button/switch/可聚焦输入框用 `ui.tap`；特殊 control event 用 `ui.control.sendAction`；navigationBar 按钮用 `ui.navigation.tapBarButton`；其余用 `ui.input` / `ui.scroll` / `ui.navigation.back` 等。

4. wait
   根据测试目标调用 ui.wait，或直接重新 observe。

5. observe again
   重新看页面，拿最新 snapshot 和 targets。

6. judge
   用最终页面证据判断这一步是否通过。
```

如果第 2 步目标不明确，Agent 应停下来重新观察或请求人工确认，不应继续猜。

## 12. 推荐的完整测试案例模板

自然语言测试案例例子：

```text
输入错误密码登录，应出现密码错误提示。
```

Agent 应转换成类似流程：

```text
observe 当前登录页
→ 找到账号输入框，输入账号
→ 找到密码输入框，输入错误密码
→ 找到登录按钮，点击
→ wait 错误提示出现，或首页出现，或网络重试出现
→ observe again
→ 如果 login.error 出现，测试通过
→ 如果 home.root 出现，测试失败
→ 如果 network.retry 出现，测试环境/网络分支
→ 如果超时，截图并重新观察，不能直接判定
```

当前 `ui.wait` 还不能一次等待多个分支，所以短期 Agent 需要谨慎分步处理。后续应设计多结果等待能力来简化这一步。

## 13. 不应该做的事

Agent 默认不应该：

- 一上来截图让视觉模型猜；
- 不观察页面就直接点击；
- 坐标硬点；
- 旧 path 反复重试；
- 把 `ui.tap` 成功当测试成功；
- 把 `wait_timeout` 直接当业务失败；
- 自动关闭所有弹窗；
- 用 `ui.tap` 或坐标去点 navigationBar 按钮（应走 `ui.navigation.tapBarButton`）；
- 生成很多步骤后一次性执行到底。

## 14. 当前协议带来的后续任务

这份协议不是终点。它把下一步任务排清楚了：

1. ~~补 navigationBar / UIBarButtonItem 可达能力~~（已完成：`ui.navigation.tapBarButton`）；`ui.tap` 也已重构为"默认激活动作"（不再做坐标点击 / hit-test）。
2. 设计多结果等待并返回最终页面状态。
3. 补真正可用的弹窗响应能力。
4. 设计动作后轻量 final observation 是否由 iPhone 端返回，还是由 Mac MCP 层组合。
5. 后续再考虑视觉模型和测试平台化。

剩余优先项是多结果等待与弹窗响应能力。
