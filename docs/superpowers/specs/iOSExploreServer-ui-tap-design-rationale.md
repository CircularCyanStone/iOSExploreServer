# iOSExploreServer：`ui.tap` 重构设计说明与决策基线

> **文档性质**：设计说明 / 决策基线，不是逐文件实施清单。  
> **读者**：Codex CLI、Claude Code 及参与后续实现、评审、测试的 Agent。  
> **目的**：统一理解“为什么保留 `ui.tap`、它到底代表什么、边界在哪里、为什么这样设计能让 Agent 更可靠地探索 iOS App”。  
> **前提**：iOSExploreServer 是 App 内嵌的 iOS 结构化探索服务；主链路不依赖截图、不依赖 VLM、不使用 UIKit 私有 API；项目仍处探索阶段，可一次性收敛协议语义，不需要为旧调用保留兼容层。

---

## 1. 本次重构真正要解决什么

当前问题不是“`ui.tap` 这个名字不好听”，也不是简单地把它删掉或改名。

当前实现的真实行为是：无论 Agent 给的是 `accessibilityIdentifier`、`path` 还是 window 坐标，最终都可能通过 hit-test 与祖先链查找，落到某个最近的 `UIControl`，然后固定执行：

```swift
control.sendActions(for: .touchUpInside)
```

这使当前 `ui.tap` 同时出现三类问题：

1. **语义不准确**：`tap` 容易让人理解为“模拟真实手指点击”，实际只是某类 `UIControl` 的 target-action 派发。
2. **能力不一致**：`ui.tap` 对不同 UIKit 控件都发 `.touchUpInside`，但 switch、slider、segmented control、文本输入框的真实用户操作语义并不相同。
3. **观察与执行不一致**：采集层可能返回按钮内部的 label/image；这些节点自身不是独立可执行对象，但当前 executor 又可能借助祖先 fallback 间接激活父 control。

本次重构的目标不是消灭 Agent 层的“点击”概念，而是消灭这种不透明的“猜测式点击”。

最终要建立的能力是：

```text
Agent 表达：激活这个已观察到的目标
        ↓
服务端确认：该目标是否是本次结构化观察签发的 canonical target
        ↓
服务端确认：该 target 是否存在明确、公开、可靠的默认激活 adapter
        ↓
按 target 类型执行确定性行为
        ↓
Agent 重新观察并判断结果
```

---

## 2. 与得物 `ai_tap` 的关系：借鉴应用层抽象，不复制 VLM 路线

得物的 `ai_tap`、`ai_long_tap`、`ai_swipe` 等接口表达的是 **Agent 面向 UI 的高层操作语言**。Agent 不需要了解 Android、iOS、HarmonyOS 的内部驱动细节，只表达“点击”“输入”“滑动”等意图；底层 driver 再按平台能力完成执行。

iOSExplore 也应吸收这一点：Agent 不应该被迫理解 `UIButton.sendActions(for:)`、`UIControl.Event`、UIKit 内部层级等平台细节。

但两者的感知方式不同：

```text
得物：截图 → VLM 理解目标 → 底层驱动

iOSExplore：UIKit 结构化观察 → 目标与能力声明 → 公开 UIKit adapter
```

因此，iOSExplore **应该保留 `ui.tap` 这个 Agent 层动作**，但不能假装自己拥有得物那种 VLM 定位与真实手势驱动能力。

本项目的原则是：

> 上层动作名称可以接近人类交互意图；底层执行必须严格受限于当前 iOS 环境中公开、确定、可验证的能力。

这意味着：

- 可以有 `ui.tap`；
- 不能把它解释成“点击任意屏幕坐标”；
- 不能把它解释成“任意 UIView 都可被真实触摸”；
- 没有可靠 adapter 的操作，宁可不声明能力，也不做猜测执行。

---

## 3. iOSExplore 的核心路线：结构化 UIKit observe-first

iOSExplore 的主闭环必须始终是结构化信息优先：

```text
ui.viewTargets / ui.topViewHierarchy
→ Agent 阅读 JSON 中的 UIKit 结构、语义文本、状态、可用动作
→ Agent 选择明确动作
→ 服务端执行公开 UIKit adapter
→ ui.wait 或重新 observe
→ Agent judge
```

这条链路只要求 Agent 能读取 JSON；纯文本 LLM 也能使用。

### 3.1 截图的定位

`ui.screenshot` 可以保留，但只能承担辅助角色：

- 人工排障或回放证据；
- 支持多模态的 Agent 的可选增强信息；
- 失败分析时的补充材料。

截图不是：

- target locator 的权威来源；
- action 授权依据；
- freshness / stale 校验依据；
- 使用 iOSExplore 的前置条件。

### 3.2 `snapshotID` 的真实含义

当前项目中的 `snapshotID` 本质上不是图片快照，而是一次 UIKit 结构化观察对应的 target 指纹集合版本。

为了避免和 screenshot 概念混淆，本次公共协议应收敛为：

```text
snapshotID → viewSnapshotID
```

`viewSnapshotID` 的正式定义：

> 由一次 `ui.viewTargets` 产生的 canonical interaction target 指纹快照标识。它用于防止 Agent 在页面结构、目标身份或关键语义已经变化后，继续使用旧 observation 的 locator 执行动作。

它不是：

```text
不是 PNG ID
不是图片 hash
不是 VLM 推理结果
不是图像 diff 版本
不是多模态依赖
```

### 3.3 为什么只让 `ui.viewTargets` 签发 `viewSnapshotID`

`ui.viewTargets` 的职责是输出“本次可直接操作的 canonical target 集合”。

因此应当确立单一不变式：

```text
ui.viewTargets 返回的 canonical target 集合
=
viewSnapshotID 内签发的 fingerprint 集合
=
ui.tap / ui.control.sendAction 允许引用的目标集合
```

这样 Agent 不能猜 path，也不能绕过观察阶段去操作没有被本次结构化观察声明的对象。

这正是 observe → act 闭环中“先看见、再行动”的结构化保障。

---

## 4. 三层模型：观察、意图、adapter

为了避免再次把 `tap`、UIKit event、真实触摸混在一起，后续设计必须明确分三层。

### 4.1 观察层：回答“当前有什么可操作对象”

命令：`ui.viewTargets`

职责：返回当前页面的 **canonical interaction targets**，以及每个 target 当前可执行的 `availableActions`。

它不再应该等同于“输出一棵包含所有 label/image/container 的 view 树”。完整结构观察属于 `ui.topViewHierarchy`。

`ui.viewTargets` 只回答：

```text
当前有哪些对象是系统能直接、确定操作的？
每个对象具有什么用户可理解的语义？
它当前支持哪些动作？
```

### 4.2 意图层：回答“Agent 想做什么”

命令包括：

```text
ui.tap
ui.input
ui.scroll
ui.navigation.tapBarButton
ui.alert.respond
```

这些是 Agent 的操作语言。Agent 不应直接决定 UIKit 的内部实现细节。

### 4.3 adapter 层：回答“当前 iOS 上如何可靠执行”

这里才是 UIKit 的公开能力：

```text
UIButton        → sendActions(.touchUpInside)
UISwitch        → setOn(...) + sendActions(.valueChanged)
UITextInput     → becomeFirstResponder()
UIControl event → sendActions(for: explicitEvent)
```

adapter 的要求是：

1. 仅使用公开 API；
2. 语义明确；
3. 可验证；
4. 不猜测；
5. 不因目标内部 view 层级变化而改变行为。

---

## 5. `ui.tap` 的最终设计

## 5.1 正式定义

`ui.tap` 的定义应固定为：

> 对本次 `ui.viewTargets` 结构化观察中签发、且明确声明 `tap` capability 的 canonical target，执行该 target 类型对应的默认激活动作。

这里的关键词是：

```text
结构化观察签发
canonical target
明确声明 tap capability
默认激活
```

`ui.tap` 不表示：

```text
真实触摸注入
任意坐标点击
任意 UIView 都可点击
寻找最近父 UIControl
向所有对象统一发送 touchUpInside
```

## 5.2 输入边界

`ui.tap` 只接受由结构化观察可验证的 locator：

```json
{
  "action": "ui.tap",
  "data": {
    "path": "root/3/1",
    "viewSnapshotID": "view_snapshot_xxx"
  }
}
```

或者：

```json
{
  "action": "ui.tap",
  "data": {
    "accessibilityIdentifier": "checkout.submit",
    "viewSnapshotID": "view_snapshot_xxx"
  }
}
```

`path` 与 `accessibilityIdentifier` 是定位方式，不是能力声明；最终解析出的对象必须属于该 `viewSnapshotID` 签发的 canonical target 集合。

无论使用 path 还是 identifier，都必须执行 freshness 校验。identifier 不能成为绕过结构快照校验的后门。

## 5.3 删除裸坐标 tap

以下输入从 `ui.tap` 删除：

```text
x
y
coordinateSpace
windowPoint locator
```

原因不是坐标毫无价值，而是当前项目没有公开、可靠的“按坐标完成真实用户触摸”能力。

当前坐标 tap 的真实含义只是：

```text
坐标 → hitTest → 命中某个 view → 寻找祖先 control → touchUpInside
```

这既不等于得物的视觉点击，也不等于真实 UIKit 手势。保留它会误导 Agent，并会鼓励“先盲点、再碰运气”的策略。

若未来需要排查布局或命中问题，可独立提供纯观察的 `ui.hitTest`；它只能告诉 Agent 某点命中什么、是否对应 canonical target，不能执行动作。

---

## 6. 默认激活路由：什么应该 `tap`，什么不应该

`ui.tap` 的价值不在于“把所有控件压成一个 `.touchUpInside`”，而在于针对少数语义清晰的 target 提供统一的默认激活。

### 6.1 应支持 `tap` 的对象

| target | 默认激活 adapter | 为什么合理 | 返回应说明什么 |
|---|---|---|---|
| `UIButton` 及其明确 button 语义子类 | `sendActions(for: .touchUpInside)` | 与按钮的默认用户激活语义一致 | `activationRoute = control.touchUpInside` |
| `UISwitch` | `setOn(!isOn, animated: false)` 后 `sendActions(for: .valueChanged)` | 用户点击 switch 的核心结果是状态翻转，而不是 button event | `activationRoute = switch.toggle`、旧值、新值、`valueChanged` |
| `UITextField` / `UISearchTextField` / `UITextView` | `becomeFirstResponder()` | Agent 的合理后续意图通常是输入文本；“tap 输入框”本质是聚焦 | `activationRoute = input.focus`、是否成为 first responder |

### 6.2 自定义 `UIControl` 的原则

不能因为一个对象继承 `UIControl`，就默认宣称它支持 `tap`。

`UIControl` 是 target-action 基类，不是“按钮”的同义词。自定义 control 可能是范围选择器、手势容器、数值选择器、复合组件，`touchUpInside` 未必代表用户的默认行为。

因此 V1 的保守规则应是：

```text
标准 UIButton：自动声明 tap。
UISwitch：自动声明 tap。
文本输入对象：自动声明 tap（聚焦语义）。
未知 / 自定义 UIControl：默认不自动声明 tap。
```

自定义 control 只有在未来具备显式注册的 default activation adapter，或项目建立了可审计的 button-like 判定后，才可加入 `tap`。

这体现的是：

> 宁可少声明一个 tap，也不把错误的默认行为交给 Agent。

### 6.3 不应支持 `tap` 的对象

| target | 为什么不支持 | 正确方向 |
|---|---|---|
| `UISlider` | tap 没有说明目标 value | 后续 `ui.slider.setValue` |
| `UISegmentedControl` | tap 没有说明目标 segment index | 后续 `ui.segment.select` |
| 普通 UIView / gesture view | 没有公开、可靠的手势注入路径 | 明确 `unsupported_target`；必要时宿主注册显式 debug action |
| UIControl 内部 `UILabel` / `UIImageView` | 它们不是独立交互对象 | 由父 canonical control 承担语义与执行 |
| 任意 window 坐标 | 当前无可靠触摸注入 | 删除执行能力，仅未来可提供观察型 hit-test |

---

## 7. `ui.control.sendAction` 的最终设计

`ui.control.sendAction` 不应删除。它不是 `ui.tap` 的重复品，而是精确调试工具。

正式定义：

> 对当前、未陈旧、且自身就是 `UIControl` 的 canonical target，发送调用方明确指定的 `UIControl.Event`。

典型请求：

```json
{
  "action": "ui.control.sendAction",
  "data": {
    "path": "root/3/1",
    "viewSnapshotID": "view_snapshot_xxx",
    "event": "touchDown"
  }
}
```

它的边界必须固定为：

```text
- target 自身必须是 UIControl；
- event 由调用方明确指定；
- 不接受坐标；
- 不做 hit-test；
- 不找 nearest ancestor control；
- 必须通过同一份 viewSnapshotID freshness 校验；
- 只能发送当前 target 已声明的精确 control.* capability。
```

成功语义也必须诚实：

> 成功仅表示服务端向该 UIControl 发出了对应 target-action event；不表示真实用户手势已合成，也不保证控件状态或业务流程必然成功。

由此形成清晰分工：

```text
ui.tap
= Agent 的默认交互意图

ui.control.sendAction
= 精确、低层、可控的 UIKit event 派发
```

---

## 8. canonical interaction target：为什么必须收敛采集层

当前 `ui.viewTargets` 如果把 UIControl 内部 label/image、静态文本、container、普通带 identifier 的 view 都当作 target，会造成错误的 Agent 心智模型：

```text
“它出现在 targets 里”
≠
“它是一个可以直接操作的对象”
```

这正是 ancestor fallback 会出现的根源。

重构后，`ui.viewTargets` 应明确只返回：

> 已经具备直接、确定的公开 command adapter 的 canonical interaction target。

### 8.1 应作为 canonical target 输出的对象

```text
UIButton / 明确 button target
UISwitch
UISlider（有精确 valueChanged，但没有 tap）
UISegmentedControl（有精确 valueChanged，但没有 tap）
UITextField / UITextView / UISearchTextField
UIScrollView / UITableView / UICollectionView（按现有 scroll 语义）
```

disabled target 仍可被观察到，以便 Agent 理解页面状态；但它不应拥有可执行 action。

### 8.2 不应作为 canonical target 输出的对象

```text
按钮内部 label/image
普通静态 UILabel
container view
普通 gesture-only view
仅仅拥有 identifier 或 accessibilityLabel、但没有确定 adapter 的普通 UIView
```

这些对象并非“消失”；它们仍可通过 `ui.topViewHierarchy` 被观察。

区别在于：

```text
ui.topViewHierarchy = 描述页面结构
ui.viewTargets       = 描述可直接操作的对象
```

### 8.3 如何保证 Agent 仍能看见按钮文字

不能靠把按钮内部 `UILabel` 暴露成另一个可操作 target。

应该把语义汇总到真正可操作的父 target：

```text
优先：accessibilityLabel
其次：UIButton.title(for: .normal)
其次：accessibilityValue / accessibilityIdentifier
必要时：严格受控的可见 descendant text 聚合
```

例如，Agent 应看到：

```json
{
  "path": "root/3",
  "type": "UIButton",
  "role": "button",
  "semanticText": "提交订单",
  "availableActions": ["tap", "control.touchUpInside"]
}
```

而不是看到一个 `UILabel(path: root/3/0, text: 提交订单)`，再猜它属于哪个按钮。

---

## 9. freshness：为什么它是结构化安全边界，而不是截图保证

Agent 的 UI 操作存在天然时序问题：观察之后，页面可能跳转、刷新、被弹窗覆盖、重建 view tree，甚至同一路径变成另一个业务对象。

`viewSnapshotID` 的作用是防止：

```text
Agent 在旧页面观察到“删除按钮”
→ 页面刷新后同一路径变成“确认按钮”
→ Agent 仍按旧理解操作
```

执行时统一遵循：

```text
1. 通过 path 或 identifier resolve 当前真实 target；
2. 得到当前 canonical path；
3. 确认该 path 属于本次 viewSnapshotID 签发集合；
4. 重采 target 的 UIKit fingerprint；
5. 比较 context、path、类型、关键状态与 semanticDigest；
6. 任一不一致则拒绝，并要求 Agent 重新 observe。
```

### 9.1 `semanticDigest` 的意义

仅比较 path 和类型不够。例如一个 `UIButton` 可能原地复用：路径、类型、frame 都没变，但标题已从“提交”变成“删除”。

因此 canonical target 的 fingerprint 应纳入关键语义摘要的 hash，例如：

```text
role
accessibilityLabel
accessibilityValue
button title
placeholder / 输入状态摘要
switch isOn
selected index
```

它存储摘要 hash，不应把额外业务明文写进日志或 snapshot store。

效果是：当按钮语义改变时，即使结构位置未变，旧 action 也会被拒绝，迫使 Agent 重新读取新的结构化状态。

---

## 10. navigationBar 与 alert：保持专用能力，不强行塞回 `ui.tap`

### 10.1 navigationBar

navigation bar button 的发现与执行已经有独立语义模型：`navigationBar` 观察区块与 `ui.navigation.tapBarButton`。

本次不应为了追求“所有点击都叫 ui.tap”而重构或回退它。

原因：

```text
- UIBarButtonItem 不是普通 rootView subtree 中可 path 定位的 UIView；
- 现有 navigation 专用能力已经正确表达其语义；
- 本轮把它塞入 ui.tap 会扩大 locator、fingerprint、路由和回归范围；
- 这与“本次独立重构 ui.tap，不破坏 navigationBar 成果”的边界冲突。
```

Agent 的操作语言不必只有一个动词。对结构化系统而言，**类型明确的专用动作比伪统一的万能 tap 更可靠**。

因此当前协议是：

```text
页面中的 canonical UIKit target → ui.tap / ui.control.sendAction
navigationBar item              → ui.navigation.tapBarButton
```

### 10.2 alert

`ui.alert.respond` 当前尚未具备真实执行器时，alert action 不能被宣布为 `tap` target。

不能因为 Agent 希望“点弹窗按钮”，就让系统返回一个看似可 tap、实际无法稳定执行的能力。

待 alert 具备公开、确定的执行器后，再单独让其进入专用语义链路。当前必须诚实保持 query/dry-run 边界。

---

## 11. 明确不做：这不是能力缺失，而是可靠性选择

本轮明确不做：

```text
- 真实 UITouch / UIEvent 触摸注入；
- UIKit 私有 API；
- 手工调用 touchesBegan / touchesEnded 伪造手势；
- 裸 window 坐标执行；
- child view → nearest ancestor UIControl 的隐式 fallback；
- 对普通 gesture view 的 best-effort 点击；
- 把未实现的 alert 执行伪装成 tap；
- 为了统一命名而改造 navigationBar 已完成能力；
- 因得物存在 ai_long_tap / ai_drag 就提前暴露 iOSExplore 不能可靠实现的命令。
```

这不是保守到“什么都不做”，而是把系统的可信边界写清楚：

> 不确定的动作不应伪装成成功；不支持比误操作更安全。

这与得物文章强调的“宁可漏点，不可误点”在质量原则上是一致的，只是 iOSExplore 的判断依据是结构化 UIKit 信息，而不是 VLM 置信度。

---

## 12. 预期效果与收益

### 12.1 对 Agent：操作语言简单，但不失真

Agent 仍可表达自然的流程：

```text
观察“登录”按钮 → ui.tap
观察开关 → ui.tap
观察输入框 → ui.tap → ui.input
观察滚动容器 → ui.scroll
观察导航栏按钮 → ui.navigation.tapBarButton
```

Agent 不需要在常规场景理解 `touchUpInside`、`valueChanged`、父子 view 路径等低层细节。

同时，`availableActions` 会让 Agent 只看到当前真正可执行的动作，减少“盲猜 API”与无效重试。

### 12.2 对执行正确性：消除错误的统一 `.touchUpInside`

重构后：

```text
按钮      → button 激活
switch    → 状态翻转 + valueChanged
输入框    → focus
slider    → 不接受模糊 tap
普通 view → 明确 unsupported
```

这比“所有东西都 sendActions(.touchUpInside)”更接近每类 target 的真实交互语义。

### 12.3 对观察与执行一致性：不再出现隐式 alias

重构后：

```text
collector 声明可操作什么
=
viewSnapshotID 签发什么
=
executor 允许操作什么
```

不再出现：

```text
label 不声明可操作
但 Agent 手工传 label path
最后却激活了祖先 button
```

这种一致性会显著降低 Agent 行为的不可解释性。

### 12.4 对稳定性：UI 内部层级变化影响更小

按钮内部换了 label、image、stack view，Agent 仍操作父 canonical target；只要其结构身份与语义未变化，操作模型不受内部视图细节影响。

若语义变化，`semanticDigest` 会触发 stale，Agent 必须重新观察。

### 12.5 对纯文本模型：不依赖视觉能力

整个主链路都可由 JSON 完成：

```text
type / role / semanticText / accessibilityIdentifier / frame / state / availableActions
```

因此不会把多模态能力、截图质量、OCR 准确率作为 Agent 探索 App 的基础依赖。

---

## 13. 代价与接受的限制

该设计会主动放弃一些“看起来覆盖更广”的能力：

```text
- 不能按任意像素坐标点击；
- 不能自动驱动任意 custom gesture view；
- 不能把 long tap、multiple tap、drag 当成仅改命令名就能实现的能力；
- 对未知 custom UIControl 可能先表现为 unsupported；
- Agent 必须遵守 observe → act → observe，而不是缓存旧 path 长时间使用。
```

这是可接受且应当接受的成本。

iOSExplore 的目标不是伪造一个“任何界面、任何手势、任何坐标都能点”的测试驱动器；目标是成为一个：

> 对 Agent 来说可理解、对 UIKit 来说合法、对执行结果来说可解释、对失败来说可诊断的 App 内探索服务。

对于确实需要 custom gesture 的业务场景，正确方向是后续引入宿主显式注册的 debug action / semantic action，而不是让 executor 猜测某个 UIView 的手势含义。

---

## 14. 对未来能力扩展的准入规则

未来可以考虑 `longTap`、`multipleTap`、`drag`、`slider.setValue`、`segment.select`、宿主自定义 action，但每一个新动作必须先满足以下条件：

```text
1. Agent 意图足够明确：输入能完整描述目标结果；
2. 存在公开、可靠的 iOS adapter；
3. 不依赖 UIKit 私有 API 或未定义触摸伪造；
4. target 能由结构化 observation 明确签发；
5. 能纳入 viewSnapshotID freshness；
6. 成功响应的语义可以诚实描述；
7. action 后能通过重新 observe 验证结果。
```

例如：

```text
ui.slider.setValue(value)
```

比：

```text
ui.tap(slider)
```

更值得实现，因为它参数完整、行为明确、可用公开 API 验证。

---

## 15. 实现时必须守住的几个设计不变式

实现 Agent 可以自行按仓库真实结构拆分文件和测试，但不得破坏以下不变式：

```text
A. ui.tap 保留，且是 Agent 层默认激活动作；不是触摸注入。

B. ui.tap 不接受裸坐标；ui.control.sendAction 也不接受裸坐标。

C. ui.tap 只作用于 ui.viewTargets 签发的 canonical target；不允许 child view 借父 control 激活。

D. snapshotID 公共语义收敛为 viewSnapshotID，且它只代表 UIKit 结构指纹状态，不代表截图。

E. path 与 accessibilityIdentifier 都必须经过同一 freshness 校验。

F. availableActions 的声明必须与 executor 的实际 adapter 路由完全一致。

G. ui.control.sendAction 只服务直接 UIControl + 显式 event，不承担默认激活。

H. navigationBar 与 alert 的既有专用能力不得被回退或伪装成普通 UIView tap。

I. 没有公开、确定 adapter 的 target 必须拒绝，不做 best-effort 误操作。

J. 所有错误仍通过 UIKitCommandError 工厂与现有 HTTP envelope 返回。
```

---

## 16. 最终一句话

```text
iOSExplore 保留 ui.tap，
但它不再是“按坐标找最近 control 后发 touchUpInside”的伪点击。

它是基于 UIKit 结构化观察、viewSnapshotID 防陈旧校验、canonical target 与明确 adapter 路由的 Agent 默认激活能力。

能确定执行的，就按类型准确执行；
不能确定执行的，就明确拒绝并要求重新观察。
```
