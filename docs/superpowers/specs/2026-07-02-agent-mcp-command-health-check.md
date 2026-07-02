# Agent MCP 现有命令体检

> 日期：2026-07-02
>
> 本文基于当前代码，对 `iOSExploreUIKit` 已有命令做一次体检。目标不是复述每个命令做什么，而是判断它们能不能组成这条闭环：
>
> ```text
> 自然语言测试目标
> → Agent 观察 App
> → Agent 执行动作
> → Agent 等待反馈
> → Agent 判断测试是否通过
> ```

## 1. 总体结论

当前库已经不是空白探索状态。它已经有比较完整的“看页面、找目标、点目标、输入、滚动、返回、截图、等待”的基础能力。

但它还没有真正形成 Agent 连续使用时最舒服的闭环。

最主要的问题不是“命令数量不够”，而是：

```text
动作命令只证明动作发出去了；
等待命令只等一个条件；
动作后的最终页面状态没有统一返回；
弹窗只能查询，不能真正处理；
Agent 应该按什么顺序使用这些命令，还没有被写成明确协议。
```

所以当前方向不是推翻全部实现，而是保留底层安全能力，补齐 Agent 连续操作时缺的“等待结果”和“重新观察”。

## 2. 当前命令清单按闭环分类

### 2.1 观察页面

- `ui.viewTargets`
  - 轻量返回可操作目标。
  - 适合 Agent 决定下一步点哪里。
  - 当前返回 path、类型、角色、identifier、短文本、frame、状态、`availableActions`。
  - 证据：`UIViewTargetSummary.toJSON()` 输出这些字段，见 `Sources/iOSExploreUIKit/Commands/ViewTargets/UIViewTargetsModels.swift:294`。

- `ui.topViewHierarchy`
  - 返回更完整的 view 树。
  - 适合排查页面结构、文字、颜色、控件状态。
  - 它会签发 `snapshotID`，也返回 `screen`、`nodeCount`、`root` 或 `matches`。
  - 证据：`UIViewHierarchyCollector.collectTopViewHierarchy` 组装这些字段，见 `Sources/iOSExploreUIKit/Commands/TopViewHierarchy/UIViewHierarchyCollector.swift:47`。

- `ui.screenshot`
  - 返回 PNG base64 和 `snapshotID`。
  - 适合失败证据、人工排查、未来 Mac 侧视觉模型辅助。
  - 不应该成为默认每一步都调用的主路径。
  - 证据：`UIScreenshotCollector.collect` 返回 `image`、尺寸、`snapshotID`，见 `Sources/iOSExploreUIKit/Commands/Screenshot/UIScreenshotCollector.swift:126`。

判断：

```text
保留。
```

这三类观察能力方向正确。`viewTargets` 是 Agent 默认入口，`topViewHierarchy` 是深度排查，`screenshot` 是证据和兜底。

需要调整的是：缺一个更统一的“当前页面摘要”。Agent 经常只需要知道顶部控制器、snapshot、可操作目标、是否有弹窗，而不一定要自己在三个命令之间选择。

## 3. 动作命令体检

### 3.1 点击与控件事件

- `ui.tap`
  - 支持 identifier、path、window 坐标。
  - path 可搭配 `snapshotID` 做陈旧校验。
  - 对目标做 hit-test，避免点到不一致的 view。
  - 最终对 `UIControl` 派发 `.touchUpInside`。
  - 证据：`UITapInput` 的互斥输入规则见 `Sources/iOSExploreUIKit/Commands/Tap/UITapModels.swift:50`；执行器的 hit-test 与能力校验见 `Sources/iOSExploreUIKit/Support/Action/UIKitActionExecutor.swift:153`。

- `ui.control.sendAction`
  - 直接向 `UIControl` 发送指定事件。
  - 适合明确知道控件事件时使用。
  - 与 `ui.tap` 共用能力判断，避免发现和执行规则分叉。
  - 证据：执行器复用 `UIKitActionCapabilityResolver` 校验 action，见 `Sources/iOSExploreUIKit/Support/Action/UIKitActionExecutor.swift:274`。

判断：

```text
保留，但要明确默认使用顺序。
```

建议：

- Agent 默认优先用 `accessibilityIdentifier`。
- 其次用 `path + snapshotID`。
- 坐标点击只能作为最后兜底。
- `ui.tap` 成功只能解释为“动作已发出”，不能解释为“测试步骤成功”。

### 3.2 文本输入

- `ui.input`
  - 支持 replace / append。
  - 只允许 `UITextField` / `UITextView` / `UISearchTextField`。
  - 写完会比对最终文本。
  - secure 输入会脱敏，不返回明文。
  - 证据：输入白名单和最终文本比对见 `Sources/iOSExploreUIKit/Support/Action/UITextInputExecutor.swift:64` 和 `Sources/iOSExploreUIKit/Support/Action/UITextInputExecutor.swift:101`。

判断：

```text
保留。
```

它已经比较符合 Agent 使用。后续重点不是推翻，而是把“输入后如何等待页面变化”接进统一协议。

### 3.3 滚动

- `ui.scroll`
  - 在滚动容器上按方向和距离滚动。
  - 可缺省定位，滚动最前面的 scrollView。
  - 返回滚动前后 offset 和是否到边界。
  - 证据：`UIScrollInput` 支持缺省容器和方向，见 `Sources/iOSExploreUIKit/Commands/Scroll/UIScrollModels.swift:40`；执行返回 offset 摘要见 `Sources/iOSExploreUIKit/Support/Action/UIScrollExecutor.swift:18`。

- `ui.scrollToElement`
  - 按文本或 identifier 找目标，并滚到可见。
  - 当前明确不签发新 snapshot，要求 Agent 滚动后重新观察。
  - 证据：模型注释说明“滚动后画面变化，agent 应重新 screenshot”，见 `Sources/iOSExploreUIKit/Commands/ScrollToElement/UIScrollToElementModels.swift:12`；执行器同样说明不签发 snapshot，见 `Sources/iOSExploreUIKit/Support/Action/UIScrollToElementExecutor.swift:20`。

判断：

```text
保留，但要调整动作后反馈。
```

滚动本身可以保留。问题是滚动后页面已经变了，但命令没有返回新的可操作目标或 snapshot。短期可以通过 Agent 使用协议要求“滚动后必须重新 observe”。中期可以考虑让状态改变类命令返回一个轻量 final observation。

### 3.4 键盘和返回

- `ui.keyboard.dismiss`
  - 查找 first responder，执行 resign 或 endEditing。
  - 没有键盘时返回 `dismissed=false`，不是失败。
  - 证据：无 first responder 时正常返回，见 `Sources/iOSExploreUIKit/Support/Action/UIKeyboardDismissExecutor.swift:26`。

- `ui.navigation.back`
  - 支持 dismiss、navigation pop、auto。
  - 返回实际使用的策略和前后控制器。
  - 证据：`auto` 先 dismiss 再 pop，见 `Sources/iOSExploreUIKit/Support/Action/UINavigationBackExecutor.swift:42`；返回 `topBefore/topAfter`，见 `Sources/iOSExploreUIKit/Support/Action/UINavigationBackExecutor.swift:116`。

判断：

```text
保留。
```

它们是 Agent 探索时很实用的基础动作。仍然需要补一条使用规则：返回或收起键盘之后，Agent 应重新观察或等待明确结果。

## 4. 等待命令体检

当前已有 `ui.wait`。

它支持：

- `idle`：等待页面稳定；
- `targetExists`：目标出现；
- `targetGone`：目标消失；
- `textExists`：文本出现；
- `snapshotChanged`：页面指纹变化。

证据：等待模式定义见 `Sources/iOSExploreUIKit/Commands/Wait/UIWaitModels.swift:4`。

问题在于，它是单条件等待：

```text
等到了 → satisfied=true
等不到 → wait_timeout
```

证据：超时时抛 `waitTimeout`，见 `Sources/iOSExploreUIKit/Support/Wait/UIWaitExecutor.swift:123`。

这对普通工具足够，但对“自然语言测试案例 → Agent 自己跑并判断结果”不够。

真实测试步骤经常不是一个结果，而是多个可能终态：

```text
点击登录
→ 可能进入首页
→ 可能提示密码错误
→ 可能出现网络重试
→ 可能弹出验证码
→ 可能仍在加载
```

如果只有单条件等待，Agent 要自己连续调用多次 `ui.wait`，逻辑会复杂，也容易漏掉失败分支。

判断：

```text
保留 ui.wait 作为底层单条件等待。
新增或改造一个“多结果等待并返回最终页面”的能力。
```

这个新能力不一定必须叫 `ui.waitFor`。关键语义是：

```text
传入多个可能结果
→ 最先命中的结果返回 conditionID
→ 超时也返回当前最终页面
→ 返回新的 snapshot 和可继续操作的 targets
```

## 5. 弹窗命令体检

当前有 `ui.alert.respond`，但它的真实能力是“查询弹窗”。

它当前：

- 能找到当前 `UIAlertController`；
- 能返回标题、消息、按钮、输入框；
- 默认 `dryRun=true`；
- `dryRun=false` 不会点击按钮，而是抛错。

证据：执行器注释明确“当前版本仅查询，不能关闭 alert”，见 `Sources/iOSExploreUIKit/Support/Action/UIAlertRespondExecutor.swift:6`；输入模型也说明 `dryRun=false` 一律抛错，见 `Sources/iOSExploreUIKit/Commands/Alert/UIAlertRespondModels.swift:11`。

判断：

```text
需要调整，优先级高。
```

原因：得物文章里“条件弹窗存在时处理，不存在时跳过”是非常关键的经验。对 Agent 来说，弹窗不是边角能力，而是探索 App 时的高频阻断点。

当前命令名叫 `respond`，但实际不能 respond，容易误导 Agent。

建议二选一：

1. 改清楚语义：把当前能力定位为 `ui.alert.query`。
2. 补齐响应能力：实现真正的 `ui.alert.respond`，支持按按钮 index / title / role 点击。

如果短期不敢直接点击系统 alert，至少要在 MCP 工具描述中明确：当前只能查询，不能处理。

## 6. 截图和视觉模型边界

截图能力应该保留，但不应该成为默认执行链路。

得物文章使用视觉模型，是因为它要跨 iOS、Android、HarmonyOS 统一执行。我们的当前项目在 App 内部，能直接拿 UIKit 结构信息。

因此默认优先级应该是：

```text
结构化页面信息
→ identifier / path + snapshotID
→ 安全动作
→ 结构化等待
→ 必要时截图
→ 未来才由 Mac 侧视觉模型辅助
```

判断：

```text
保留截图。
推翻“每一步默认截图给视觉模型判断”的路线。
```

运行验证补充：Example App 主页闭环中，`ui.screenshot` 返回 589×1280、base64 约 149 KB。这个体积可以作为失败证据接受，但不适合作为每一步默认动作。

## 6.1 运行验证新增边界

2026-07-02 的三层运行验证补充了静态体检没有发现的边界。详见 [runtime-validation-2026-07-02.md](../agent-mcp-exploration/runtime-validation-2026-07-02.md)。

### 6.1.1 NavigationBar 按钮当前不可达

Example App 的「控件测试」入口是导航栏里的 `UIBarButtonItem`。实测发现：

- `ui.topViewHierarchy` 和 `ui.viewTargets` 都采不到这个按钮；
- 坐标点击命中内部 `_UIModernBarButton` 后，`ui.tap` 因不是 `UIControl` 返回 `requested action is not supported for target`；
- 结果是 Agent 无法通过现有命令进入 `ControlTestViewController`。

影响：很多真实 App 的编辑、完成、筛选、更多、返回等按钮都在导航栏。这个不是小缺口，而是会阻断探索闭环的硬问题。

判断：

```text
新增高优先级能力缺口：navigationBar / UIBarButtonItem 可观察、可操作。
```

### 6.1.2 `ui.wait textExists` 只等当前可见文本

运行验证里，`textExists "started"` 超时，但 `textExists "POST"` 立即满足。原因是 `started` 日志已经滚出可见区域并被 cell 复用回收。

因此，`textExists` 的普通解释应该是：

```text
等待当前可见区域里出现某段文本。
```

它不是“在整个数据源、整个列表历史、所有滚出屏幕的 cell 里查文本”。

判断：

```text
需要在 Agent 使用协议里写清：等文本前要先保证目标文本可见；列表场景通常要 scroll → observe → wait。
```

### 6.1.3 运行验证确认的错误分类

实测确认以下错误分类是清楚的：

- 当前无弹窗时，`ui.alert.respond dryRun=true` 返回 `alert_unavailable`；
- root 页面执行返回时，`ui.navigation.back` 返回 `navigation_back_unavailable`；
- 无键盘时，`ui.keyboard.dismiss` 返回 `code: ok` + `dismissed: false`。

这说明“失败先分类”的方向成立，Agent 可以按 code 做下一步判断。

## 7. 保留 / 调整 / 推翻 / 新增清单

### 7.1 保留

- `ui.viewTargets`
  - 作为 Agent 默认观察入口。

- `ui.topViewHierarchy`
  - 作为深度结构排查能力。

- `ui.screenshot`
  - 作为证据、人工排查、未来视觉辅助。

- `ui.tap`
  - 作为安全点击能力，但不能解释为业务成功。

- `ui.control.sendAction`
  - 作为精确控件事件能力。

- `ui.input`
  - 作为文本输入能力。

- `ui.scroll`
  - 作为基础滚动能力。

- `ui.scrollToElement`
  - 作为滚动到目标能力。

- `ui.keyboard.dismiss`
  - 作为键盘处理能力。

- `ui.navigation.back`
  - 作为返回能力。

- `ui.wait`
  - 作为底层单条件等待能力。

### 7.2 调整

- 调整 `ui.wait` 的定位说明：
  - 它是单条件等待，不是完整测试步骤验证器。

- 调整动作类命令的使用协议：
  - `tap/input/scroll/back` 后必须等待或重新观察，不能把动作成功当测试成功。

- 调整 `ui.alert.respond`：
  - 当前只能查询，名字和能力不完全一致。
  - 要么改名/补文档，要么实现真正按钮响应。

- 调整文档：
  - 明确 Agent 默认闭环，不要让调用方自己猜命令顺序。

- 调整 `ui.wait textExists` 的说明：
  - 它只检测当前可见文本；滚出可视区的列表内容不能直接等到。

- 调整 navigationBar 能力说明：
  - 当前 NavigationBar / UIBarButtonItem 不在结构化采集树内，也不能通过现有 `ui.tap` 成功点击。

### 7.3 推翻

- 推翻“为了 AI Native，每一步都截图给视觉模型猜”的默认路线。
- 推翻“坐标点击是常规路径”的路线。
- 推翻“`ui.tap` 成功等于测试步骤成功”的理解。
- 推翻“当前必须兼容旧命令语义，所以不能重命名或新增更清楚命令”的包袱。

### 7.4 新增

优先新增的不是更多零散动作，而是让现有动作组成闭环的能力。

1. 多结果等待并返回最终页面

   普通说法：

   ```text
   等几种可能结果，谁先出现就告诉 Agent；如果都没出现，也把最后页面返回。
   ```

   可能命名：

   - `ui.waitFor`
   - `ui.observeUntil`
   - `ui.waitForState`

   命名可以后定，语义必须明确。

2. 当前页面摘要命令

   普通说法：

   ```text
   给 Agent 一份适合下一步判断的页面摘要。
   ```

   它可以组合：

   - 顶部控制器；
   - snapshotID；
   - 可操作目标；
   - 是否有 alert；
   - 截图是否需要另取。

   不一定要立刻做成 iPhone 命令，也可以先在 Mac MCP 层组合现有命令。

3. 弹窗处理能力

   普通说法：

   ```text
   弹窗存在时按明确规则点击按钮；不存在时告诉 Agent 没有弹窗。
   ```

   注意：不能做一个含糊的“关闭所有弹窗”。必须按按钮标题、角色或 index 明确操作。

4. Agent 使用协议文档

   普通说法：

   ```text
   告诉 Agent 每一步该怎么用这些工具。
   ```

   至少写清：

   - 先 observe，再 act；
   - act 后必须 wait 或 observe；
   - stale / ambiguous / disabled 必须重新 observe；
   - 默认不用坐标；
   - 默认不用截图；
   - 弹窗处理必须有明确按钮；
   - 测试是否通过由最终页面证据判断。

5. navigationBar / UIBarButtonItem 可达能力

   普通说法：

   ```text
   Agent 应该能看到并操作导航栏里的按钮。
   ```

   运行验证已经证明这是当前硬阻断。能力设计时要同时解决两件事：

   - 观察：`viewTargets` / 页面摘要里能出现导航栏按钮；
   - 操作：能按稳定标识或明确描述触发对应按钮，而不是靠坐标硬点。

## 8. 建议的近期实施顺序

1. 写清 Agent 使用协议。

   这是最便宜但收益最大的动作。否则命令很多，Agent 仍然可能乱用。

2. 补 navigationBar / UIBarButtonItem 可达能力。

   运行验证发现它会直接阻断进入子页面，优先级应高于新增等待能力。

3. 设计“多结果等待并返回最终页面”的能力。

   这是让自然语言测试案例能跑起来的关键。没有它，Agent 很容易退回固定 sleep 或单条件猜测。

4. 修正弹窗能力。

   当前 `ui.alert.respond` 只查询不能响应，这会卡住很多真实 App 流程。

5. 再考虑当前页面摘要是否放在 iPhone 端还是 Mac MCP 层。

   如果只是组合现有命令，优先放 Mac 侧；如果需要更低成本、更一致的 snapshot，才放 iPhone 端。

6. 最后再谈视觉模型和未来测试平台。

   视觉模型可以作为失败诊断或结构化信息不足时的补充，不作为默认路径。

## 9. 本次体检的最终判断

当前实现方向大体可用，不需要全盘推翻。

但要把项目从“很多独立 UI 命令”推进到“Agent 能按自然语言目标持续探索和验证 App”，必须补齐三件事：

```text
第一，明确 Agent 使用协议；
第二，补 navigationBar / UIBarButtonItem 可达性；
第三，补多结果等待和最终页面反馈；
第四，补真正可用的弹窗处理。
```

这些事比继续堆更多普通动作命令更重要。
