# iOSExploreServer：`ui.tap` 最终重构方案（执行基线）

> **用途**：本文件是给 Codex CLI、Claude Code 或其他实现 Agent 的单一决策基线。  
> **目标**：在不依赖截图、不依赖 VLM、不使用 UIKit 私有 API 的前提下，重构 `ui.tap`，消除它与 `ui.control.sendAction` 的语义重叠与名实错位。  
> **状态**：项目仍处探索期，无需保留旧调用兼容层；可一次性收敛公共协议、模型、测试与文档。  
> **本文件要求**：实现前先按“必读文件”核实仓库当前代码；若目录名、类型名、测试名与本文不同，以仓库当前事实为准，但**不得改变本文已经确定的架构决策**。

---

## 0. 先读这些文件，再动代码

实现 Agent 必须按此顺序阅读并核实当前代码，不得凭本文猜测实现细节：

1. `AGENTS.md`
2. `docs/superpowers/agent-mcp-exploration/README.md`
3. `docs/superpowers/agent-mcp-exploration/agent-usage-protocol.md`
4. `docs/superpowers/specs/2026-07-02-agent-mcp-app-exploration-direction.md`
5. `Sources/iOSExploreUIKit/Support/Action/UIKitActionExecutor.swift`
6. `Sources/iOSExploreUIKit/Support/Action/UIKitActionCapabilityResolver.swift`
7. `Sources/iOSExploreUIKit/Commands/Tap/UITapModels.swift`
8. `Sources/iOSExploreUIKit/Commands/ControlAction/UIControlSendActionModels.swift`
9. `Sources/iOSExploreUIKit/Commands/ViewTargets/UIViewTargetsCollector.swift`
10. `Sources/iOSExploreUIKit/Support/Snapshot/UIKitFingerprintCollector.swift`  
    （若当前实际目录不同，搜索 `UIKitFingerprintCollector`）
11. `UIKitSnapshotStore`、`UIKitCommandError`、`ExploreError` 的当前实现
12. navigationBar / `ui.navigation.tapBarButton` 相关 collector、executor、测试
13. `ui.alert.respond` 相关模型、executor、测试

实现 Agent 在动代码前，应先输出一段简短的“代码核实结果”：

- 当前 `ui.tap` 的全部输入类型；
- 当前 `ui.tap` 的最终执行路径；
- 当前 `ui.control.sendAction` 的执行路径；
- 当前 `snapshotID` 的签发、存储和校验路径；
- 当前 navigationBar 与 alert 的真实执行状态；
- 当前测试数量和测试文件位置。

这一步只用于确认，不重新讨论本文件的决策。

## 0.1 当前源码差异核实清单

实施 Agent 在开始改代码前，必须把以下差异当作已知迁移点逐项确认。它们不是可选优化，而是本方案相对当前实现必须补齐的协议断点。

### 当前 `ui.tap` 仍是旧语义

当前 `UITapInput` 仍接受：

```text
accessibilityIdentifier
path
snapshotID
x
y
coordinateSpace
```

并且当前规则是：

```text
snapshotID 只允许和 path 搭配；
accessibilityIdentifier 不能携带 snapshotID；
x/y 会进入 windowPoint tap；
coordinateSpace 当前只允许 window。
```

实施后必须变成：

```text
path + viewSnapshotID
或
accessibilityIdentifier + viewSnapshotID
```

`x`、`y`、`coordinateSpace`、`windowPoint` 必须从 `ui.tap` 公共输入、typed model、help schema、测试和文档中同时删除。

### 当前 executor 仍存在三类旧行为

当前 `UIKitActionExecutor` 的 `ui.tap` 执行链路仍包含：

```text
1. view locator → 取目标中心点 → window.hitTest；
2. windowPoint → 直接 hitTest；
3. hit view / located view → nearest ancestor UIControl → sendActions(.touchUpInside)。
```

实施后必须删除：

```text
hit-test 派发；
坐标 tap 分支；
child view → nearest ancestor UIControl fallback；
dispatchMode = controlActionFallback；
x / y / hitPath / hitType / controlPath 等响应字段。
```

### 当前 capability 与 executor 不一致

当前 `UIKitActionCapabilityResolver.controlActions` 会把：

```text
UISwitch
UISlider
UISegmentedControl
```

都声明为：

```text
tap + control.valueChanged
```

但旧 executor 对所有 tap 最终都发送 `.touchUpInside`。实施后必须保证：

```text
UISwitch: tap + control.valueChanged，tap route = switch.toggle
UISlider: 仅 control.valueChanged，无 tap
UISegmentedControl: 仅 control.valueChanged，无 tap
UITextField / UITextView: tap 表示 focus，不表示 touchUpInside
```

### 当前 `ui.viewTargets` 不是 canonical-only

当前 `UIViewTargetsInput.shouldInclude` 默认会把以下对象也纳入 targets：

```text
有 gesture recognizer 的普通 view；
仅有 accessibilityIdentifier 的普通 view；
仅有 accessibilityLabel 的普通 view；
普通 UIControl；
可选静态文本 / container。
```

实施后，`ui.viewTargets` 必须只输出可由当前公开 command 直接、确定操作的 canonical interaction targets。普通 identifier / accessibilityLabel 只能作为语义字段或 `ui.topViewHierarchy` 观察信息，不能单独让普通 view 成为 executable target。

### 当前 fingerprint 签发可能超过响应集合

当前 `UIViewTargetsCollector` 会按 `maxTargets` 截断返回 targets，但 `UIKitFingerprintCollector.collectMatching` 当前明确不让 `maxTargets` 参与 fingerprint 签发。

实施后必须改为：

```text
最终返回 targets 的 path 集合
=
viewSnapshotID 签发 fingerprint 的 path 集合
=
tap / sendAction 可执行 path 集合
```

禁止 snapshot 中包含响应没有返回的额外 path，否则 Agent 仍可猜 path 执行。

### 当前 `ui.screenshot` 会签发 snapshotID

当前 `UIScreenshotCollector` 仍会：

```text
collectFingerprints(UIViewTargetsInput.default)
→ UIKitSnapshotStore.shared.insert(...)
→ 返回 snapshotID / snapshotUnavailableReason
```

本方案要求 `ui.screenshot` 不签发、不刷新、不返回 `viewSnapshotID`。实施时必须同步修改 screenshot 响应模型、注释、日志、测试、README 和 agent usage protocol，不能只改 `ui.tap`。

### 当前 `ui.wait snapshotChanged` 依赖 snapshotID

当前 `UIWaitExecutor.snapshotChanged` 会通过：

```text
input.snapshotID
→ UIKitSnapshotStore.signingQuery(for:)
→ collectFingerprints(...)
→ matchesWholeTable(...)
```

判断页面指纹表是否变化。实施后必须明确迁移为：

```text
input.viewSnapshotID
```

并且只能接受由 `ui.viewTargets` 签发的结构化 target snapshot。若本轮不改变 `ui.wait` 输入名，就不得声称公共协议已经完成 `snapshotID → viewSnapshotID` 原子迁移。

---

# 1. 项目定位与基本原则

## 1.1 iOSExplore 的感知主链路是 UIKit 结构，不是截图

本项目的主闭环是：

```text
ui.viewTargets / ui.topViewHierarchy
→ 返回结构化 UIKit 信息
→ Agent 基于 JSON 做决策
→ ui.tap / ui.control.sendAction / ui.input / ui.scroll
→ ui.wait 或再次 observe
→ Agent judge
```

`ui.screenshot` 只能是：

- 人工排障证据；
- 多模态 Agent 的可选增强输入；
- 失败分析的辅助材料。

它**不是**：

- 目标定位或动作授权的基础；
- freshness / stale 校验的基础；
- `viewSnapshotID` 的签发来源；
- 纯文本 Agent 使用本项目的前置条件。

项目必须保证：只会读取 JSON 的非多模态 Agent，也能够完整完成 observe → act → wait/observe → judge 闭环。

---

## 1.2 `viewSnapshotID` 是结构指纹快照，不是 screenshot ID

本次将所有公共协议中语义为“UIKit 可执行 target 指纹快照”的 `snapshotID` 原子重命名为：

```text
viewSnapshotID
```

它的正式定义：

> `viewSnapshotID` 是某次 `ui.viewTargets` 返回的 canonical interaction targets 对应的 UIKit 结构指纹快照标识。它用于防止 Agent 在 UI 已变化后继续按旧结构化定位器执行动作。

它不是：

```text
不是 PNG ID
不是 screenshot hash
不是 VLM 识别结果
不是图像 diff 版本
不是多模态模型的依赖
```

### `viewSnapshotID` 的签发规则

本轮确定以下规则：

```text
只有 ui.viewTargets 可以签发 viewSnapshotID。
ui.screenshot 不签发、不刷新、不拥有 viewSnapshotID。
ui.topViewHierarchy 默认不签发 viewSnapshotID。
```

原因：`ui.viewTargets` 是唯一返回“可执行 canonical target 集合”的观察命令；因此只有它可以定义“哪些 target 已被本次观察授权操作”。

---

## 1.3 不能可靠合成 UIKit 真实触摸

`UIWindow.sendEvent(_:)` 是公开的事件分发 API；但 UIKit 没有公开、稳定、受支持的方式，让 App 从零构造一整套可被 UIKit 当作真实手指触摸处理的 `UITouch` / touch-type `UIEvent` 生命周期。

因此本项目明确不做：

```text
- 构造 UITouch / UIEvent 进行触摸注入；
- 使用 UIKit 私有 API；
- 手动调用 touchesBegan / touchesEnded 伪造触摸；
- 将 window 坐标点击伪装成真实触摸；
- 对普通 gesture view 做 best-effort 猜测执行。
```

这个限制不意味着不能提供 Agent 层 `ui.tap`。

`ui.tap` 是**高层交互意图**，底层由当前 target 类型路由到公开、确定、可验证的 UIKit adapter；它不是“真实手指注入 API”。

---

# 2. 最终命令职责

| 命令 | 层次 | 最终职责 |
|---|---|---|
| `ui.viewTargets` | 结构化观察层 | 返回当前可直接操作的 canonical interaction targets、语义信息、`availableActions`、`viewSnapshotID` |
| `ui.tap` | Agent 默认动作层 | 对 canonical target 执行目标类型对应的默认激活 |
| `ui.control.sendAction` | 精确 UIKit 层 | 对 target 自身为 `UIControl` 的对象发送调用方显式指定的 `UIControl.Event` |
| `ui.input` | 文本语义层 | 对 text input 执行文本输入 |
| `ui.scroll` | 滚动语义层 | 对 scroll target 执行结构化滚动 |
| `ui.navigation.tapBarButton` | navigation 专用层 | 对 `UIBarButtonItem` 语义目标执行既有专用能力 |
| `ui.alert.respond` | alert 专用层 | 对 alert action 执行专用能力；当前仍保持 query/dry-run，不能假装可执行 |
| `ui.screenshot` | 可选辅助观察 | 提供视觉证据；不参与结构化 freshness、动作授权或 locator 签发 |

核心区分：

```text
ui.tap
= “默认激活这个已观察到的 canonical target”

ui.control.sendAction
= “向这个 UIControl 发送我明确指定的 UIKit event”
```

两者都保留，但职责不重叠。

---

# 3. `ui.tap` 的最终协议

## 3.1 保留 `ui.tap`，但改变其定义

`ui.tap` 正式定义为：

> 对本次 `ui.viewTargets` 结构化观察中签发的、具有 `tap` capability 的 canonical target，执行其默认激活路由。

`ui.tap` 不再表示：

```text
- 点击任意屏幕坐标；
- 真实模拟手指触摸；
- 任意 UIView 都能点；
- 先 hit-test 再猜最近父 UIControl；
- 固定向所有目标发送 touchUpInside。
```

这与得物 `ai_tap` 的“Agent 层操作意图”相似，但不复制得物的 VLM 路线：

```text
得物：截图 → VLM 理解 / 定位 → 平台 driver
本项目：UIKit 结构化 observe → canonical target → UIKit public adapter
```

---

## 3.2 `ui.tap` 只接受结构化 locator

允许：

```json
{
  "action": "ui.tap",
  "data": {
    "path": "root/3/1",
    "viewSnapshotID": "view_snapshot_xxx"
  }
}
```

或：

```json
{
  "action": "ui.tap",
  "data": {
    "accessibilityIdentifier": "checkout.submit",
    "viewSnapshotID": "view_snapshot_xxx"
  }
}
```

强制规则：

```text
1. path 与 accessibilityIdentifier 二选一。
2. viewSnapshotID 必填。
3. path 与 identifier 均必须经过 freshness 校验。
4. locator 的最终解析对象必须属于该 viewSnapshotID 已签发的 canonical target 集合。
5. 不接受 x / y / coordinateSpace。
6. 不接受内部 child view path 作为“借父 control 激活”的隐式别名。
```

### 删除的旧输入

从 `ui.tap` 删除：

```text
x
y
coordinateSpace
UITapCoordinateSpace
windowPoint locator
```

不把坐标输入迁移到 `ui.control.sendAction`。

当前没有可靠的“按坐标真实点击”能力；保留它只会误导 Agent。

如未来确实需要坐标诊断，可另开纯观察命令 `ui.hitTest`；本任务不实现该命令。

---

## 3.3 identifier 不再绕过 freshness

重构后，无论 locator 是 path 还是 identifier，统一走：

```text
1. 定位当前真实 UIView。
2. 得到当前 canonical path。
3. 检查该 path 是否属于 viewSnapshotID 已签发的 target 集合。
4. 校验 snapshot context。
5. 重采当前 UIKit fingerprint。
6. 比对 path、context、fingerprint、semanticDigest。
7. 校验 target 当前仍可操作。
8. 进入 ui.tap 默认激活或 ui.control.sendAction 精确事件路径。
```

identifier 只是更稳定的定位方式，绝不是绕过 stale guard 的特殊通道。

---

# 4. `ui.tap` 默认激活路由

新增一个被 capability resolver 和 executor 共用的内部解析器，例如：

```text
UIKitDefaultActivationResolver
```

其职责：

```text
给定一个 canonical UIKit target，判断它是否具有默认激活语义；
若有，返回确定的 default activation route；
若无，返回 nil。
```

**不允许** collector 说可 `tap`、executor 却做不同事情；两处必须使用同一套 route 判定。

## 4.1 路由表

| target 类型 | `availableActions` 是否含 `tap` | `ui.tap` 实现 | 备注 |
|---|---:|---|---|
| `UIButton` 及子类 | 是 | `sendActions(for: .touchUpInside)` | 默认按钮激活 |
| button-like 自定义 `UIControl` | V1 否 | 无 | 后续需显式 adapter 或单独设计，不在本轮 |
| `UISwitch` | 是 | `setOn(!isOn, animated: false)` 后 `sendActions(for: .valueChanged)` | 语义是切换，不是 touchUpInside |
| `UITextField` / `UISearchTextField` / `UITextView` | 是 | `becomeFirstResponder()` | 语义是聚焦，不是触摸注入 |
| `UISlider` | 否 | 无 | 需要未来的 value-setting 专用能力 |
| `UISegmentedControl` | 否 | 无 | 需要未来的 index-selection 专用能力 |
| 普通 `UIView` | 否 | 无 | `unsupported_target` |
| gesture-only view | 否 | 无 | 不伪造 gesture |
| UIControl 内部 `UILabel` / `UIImageView` | 否 | 无 | 不是 canonical target |
| navigationBar `UIBarButtonItem` | 本轮不并入 `ui.tap` | 保持 `ui.navigation.tapBarButton` | 不改刚完成的 navigationBar 能力 |
| alert action | 当前不暴露为 tap | 保持 `ui.alert.respond` 当前状态 | 实际执行器完成后另开任务 |

---

## 4.2 button-like 自定义 `UIControl` 的严格判定

不得使用：

```text
只要是 UIControl → 默认 tap
```

建议条件：

```text
- UIButton 或 UIButton 子类：直接支持；
- 非 UIButton 的 UIControl：
  * accessibilityTraits 包含 .button；
  * 当前 capability 明确允许 control.touchUpInside；
  * 可交互、可见、enabled；
  * 不属于 UISwitch / UISlider / UISegmentedControl / text input 等已知特殊语义类型。
```

如果不能确定它是 button-like：

```text
不宣布 tap；
最多只暴露精确 control.* event；
宁可漏点，不猜测默认激活。
```

### V1 收敛规则

为降低首轮重构风险，本轮 V1 不实现复杂的 custom button-like 判定。

V1 `ui.tap` 只自动支持：

```text
UIButton / UIButton 子类
UISwitch
UITextField / UISearchTextField / UITextView
```

未知自定义 `UIControl` 即使带有 `.button` accessibilityTraits，本轮也默认不声明 `tap`，只在它自身是 `UIControl` 且当前状态允许时暴露可验证的 `control.*` 精确事件。

原因：

```text
1. `.button` trait 不足以证明 `.touchUpInside` 是业务默认激活动作；
2. custom control 可能是复合控件、范围选择器、手势容器或业务自绘组件；
3. 本轮目标是先消灭错误默认激活，不扩大推断面。
```

后续若要支持 custom button-like control，必须另开任务设计显式注册或可审计 adapter，不在本轮夹带。

---

## 4.3 `UISwitch` 的 route

`UISwitch` 用户语义是切换状态：

```swift
let oldValue = toggle.isOn
let newValue = !oldValue
toggle.setOn(newValue, animated: false)
toggle.sendActions(for: .valueChanged)
```

响应示例：

```json
{
  "activated": true,
  "activationRoute": "switch.toggle",
  "path": "root/4/1",
  "type": "UISwitch",
  "event": "valueChanged",
  "previousValue": false,
  "currentValue": true
}
```

不得将 switch 的 `tap` 实现成 `.touchUpInside`。

---

## 4.4 text input 的 route

`UITextField` / `UITextView` 的默认激活语义是聚焦：

```swift
let focused = textInput.becomeFirstResponder()
```

后续文本写入由 `ui.input` 完成。

响应示例：

```json
{
  "activated": true,
  "activationRoute": "input.focus",
  "path": "root/2/0",
  "type": "UITextField",
  "isFirstResponder": true
}
```

若 `becomeFirstResponder()` 返回 `false`，必须通过 `UIKitCommandError` 工厂返回明确错误；不得返回成功。

---

## 4.5 slider / segmented control 的边界

以下请求没有足够参数定义正确行为：

```text
ui.tap(slider)：目标 value 是多少？
ui.tap(segmentedControl)：应选哪个 index？
```

因此本轮明确：

```text
ui.tap(slider) → unsupported_target
ui.tap(segmentedControl) → unsupported_target
```

未来可单独设计：

```text
ui.slider.setValue
ui.segment.select
```

不是本轮范围。

---

# 5. `ui.control.sendAction` 最终协议

`ui.control.sendAction` 保留，成为精确 UIKit event 工具。

允许：

```json
{
  "action": "ui.control.sendAction",
  "data": {
    "path": "root/3/1",
    "viewSnapshotID": "view_snapshot_xxx",
    "event": "touchUpInside"
  }
}
```

或：

```json
{
  "action": "ui.control.sendAction",
  "data": {
    "accessibilityIdentifier": "checkout.submit",
    "viewSnapshotID": "view_snapshot_xxx",
    "event": "touchDown"
  }
}
```

强制规则：

```text
1. target 自身必须是 UIControl。
2. target 必须是 viewSnapshotID 中签发的 canonical target。
3. 不做 hit-test。
4. 不找 nearest ancestor UIControl。
5. 不接受坐标。
6. event 必须由调用方显式给出。
7. event 必须存在于该 target 当前 `availableActions`。
8. disabled / hidden / 不可交互 target 不能执行。
9. path、identifier 均必须携带并校验 viewSnapshotID。
```

成功只表示：

> 已向当前、未陈旧、直接定位到的 `UIControl` 发送指定 `UIControl.Event`。

成功不表示：

```text
不是已合成真实手势；
不是控件状态一定变化；
不是业务流程一定成功。
```

例如，发送 `valueChanged` 不自动修改 slider 的 value，也不自动修改 segmented control 的 selected index。

---

# 6. `ui.viewTargets` 重构：canonical interaction targets

## 6.1 新定义

`ui.viewTargets` 不再是“所有看起来有意义的 UIView 节点列表”。

新定义：

> 返回当前页面中可由现有公开 command 直接、确定操作的 canonical interaction targets。

完整视图树、静态文本、container、普通 view 的观察职责由：

```text
ui.topViewHierarchy
```

承担。

---

## 6.2 应输出的 target

| 类型 | 输出 | 可用能力示例 |
|---|---:|---|
| `UIButton` / `UIButton` 子类 | 是 | `tap`、`control.touchDown`、`control.touchUpInside` |
| 未知自定义 `UIControl` | 是 | 仅可验证的 `control.*` 精确事件，无 `tap` |
| `UISwitch` | 是 | `tap`、`control.valueChanged` |
| `UISlider` | 是 | `control.valueChanged`，无 `tap` |
| `UISegmentedControl` | 是 | `control.valueChanged`，无 `tap` |
| `UITextField` / `UITextView` | 是 | `tap`、`input`、editing events |
| `UIScrollView` / table / collection | 是 | `scroll` |
| disabled direct target | 是 | 仅观察状态，`availableActions = []` |
| navigationBar item | 不放普通 targets | 保持现有 navigationBar 语义区块 |
| alert action | 当前不放 executable target | 等 alert 执行器实际完成后再做 |

---

## 6.3 不应输出为 target 的节点

```text
- UIControl 内部 UILabel / UIImageView；
- 普通 UILabel、静态文本；
- container view；
- gesture-only UIView；
- 有 identifier 但没有公开、确定执行能力的普通 UIView；
- 任意仅因为 accessibilityLabel 存在而被误认为可执行的 view。
```

### 禁止祖先 alias

必须删除旧语义：

```text
Agent 传内部 label path
→ executor 向上找最近 UIControl
→ 仍然执行父 control
```

内部 label/image 可以作为父 canonical target 的**语义文本来源**，但不能以自身 path 成为 action locator。

---

## 6.4 canonical target 的语义文本

`UIViewTargetSummary`（或当前等价模型）应能在 canonical target 上携带稳定、受限的语义信息，例如：

```text
role
semanticText
semanticTextSource
accessibilityIdentifier
accessibilityLabel
accessibilityValue
isEnabled / isSelected / isOn 等状态
```

按钮文本提取优先级建议：

```text
1. accessibilityLabel
2. UIButton.title(for: .normal)
3. accessibilityValue
4. accessibilityIdentifier
5. 受严格限制的可见 descendant text 聚合
```

若使用 descendant text fallback：

```text
- 只收集 canonical target 自身子树内可见文本；
- 不返回 child path；
- 结果顺序必须稳定；
- 设置数量和长度上限；
- 不记录明文业务文本到日志；
- 文本摘要必须参与 semanticDigest。
```

例：

```json
{
  "path": "root/3",
  "type": "UIButton",
  "role": "button",
  "semanticText": "提交订单",
  "semanticTextSource": "buttonTitle",
  "accessibilityIdentifier": "checkout.submit",
  "isEnabled": true,
  "availableActions": [
    "tap",
    "control.touchDown",
    "control.touchUpInside"
  ]
}
```

---

# 7. `viewSnapshotID`、fingerprint 与 freshness 不变式

本重构最重要的不变式：

```text
ui.viewTargets 最终返回的 canonical target path 集合
=
viewSnapshotID 内签发 fingerprint 的 path 集合
=
ui.tap / ui.control.sendAction 被允许操作的 path 集合
```

绝不允许：

```text
未在 ui.viewTargets 返回的 child path
→ 靠猜测或 ancestor fallback 执行成功。
```

## 7.1 fingerprint 要覆盖语义变化

在现有结构 fingerprint 基础上，增加或确认存在：

```text
semanticDigest
```

建议由稳定的语义字段计算哈希：

```text
role
+ accessibilityLabel
+ accessibilityValue
+ button title
+ 文本输入 placeholder / value 摘要
+ selected index
+ switch isOn
+ 与 route 相关的关键状态
```

规则：

```text
semanticDigest 存 hash，不存明文业务文本。
```

目标：即使 path 和 type 没变，只要按钮从“提交”变成“删除”、switch 状态或关键语义改变，旧观察对应的执行也应因 freshness 校验失败而被拒绝，迫使 Agent 重新 observe。

### `semanticDigest` 落地要求

实施时不要把语义摘要写成临时字符串拼接散落在 collector / executor 两边。必须形成一个可复用的内部构造入口，例如：

```text
UIKitTargetSemanticDigest
```

职责：

```text
1. 从 UIView 读取与 action 路由相关的稳定语义；
2. 按固定字段顺序构造摘要输入；
3. 对摘要输入计算 stable hash；
4. 只把 hash 写入 UIKitTargetFingerprint；
5. 不把业务明文写入 snapshot store 或日志。
```

建议纳入摘要的字段：

```text
role
viewType
accessibilityIdentifier hash
accessibilityLabel hash
accessibilityValue hash
UIButton normal/current title hash
UITextField placeholder hash
UITextView 是否可编辑 / 是否 firstResponder 不纳入旧观察稳定性判断
UISwitch isOn
UISlider value 的有限精度摘要
UISegmentedControl selectedSegmentIndex
available default activation route
```

字段选择原则：

```text
会改变 Agent 对目标含义或默认激活风险的字段，应进入 semanticDigest；
高频瞬态视觉状态（highlighted、tracking）不应进入 semanticDigest；
用户输入全文不应进入 semanticDigest 明文输入日志，但可以用 hash 摘要参与判断；
若字段只影响“当前是否可执行”（enabled/hidden/alpha/userInteraction），继续由现有 fingerprint / actionability 校验负责。
```

测试必须覆盖：

```text
按钮 title 改变 → semanticDigest 改变；
accessibilityLabel 改变 → semanticDigest 改变；
switch isOn 改变 → semanticDigest 改变；
segmented selected index 改变 → semanticDigest 改变；
相同语义重复采集 → semanticDigest 稳定不变。
```

## 7.2 fingerprint 集合必须在输出裁剪之后生成

collector 必须先完成所有会影响返回 target 集合的筛选，再签发 fingerprints：

```text
visibility
maxDepth
identifier / filter
maxTargets
canonical target 判定
```

然后：

```text
returnedTargets
→ fingerprints
→ viewSnapshotID
```

禁止出现：

```text
snapshot 中签发了 100 个 target，
但 API 只返回 20 个，
Agent 仍可猜测其余 80 个 path 并执行。
```

---

# 8. 统一 freshness 校验流程

`ui.tap` 与 `ui.control.sendAction` 都必须使用同一 freshness 校验路径：

```text
1. 接收 path 或 accessibilityIdentifier。
2. resolve 当前真实 UIKit target。
3. 得到当前 canonical path。
4. 验证该 path 是否属于 viewSnapshotID 已签发集合。
5. 验证当前 context 是否仍属于同一页面/窗口语义上下文。
6. 重新采集当前 fingerprint + semanticDigest。
7. 与 snapshot 中对应记录比对。
8. 验证 view 可见、可交互、enabled 等当前状态。
9. 才进入默认激活 route 或精确 event dispatch。
```

所有错误走 `UIKitCommandError` 工厂，不改变 core HTTP envelope。

建议错误语义：

| 场景 | 建议错误 |
|---|---|
| 缺少 `viewSnapshotID` | `invalid_data` |
| path / identifier 找不到 | `target_not_found` |
| identifier 命中多个 target | `target_ambiguous` |
| 当前 path 不在已签发集合 | `stale_locator` |
| context、fingerprint、semanticDigest、TTL 不一致 | `stale_locator` |
| 普通 UIView / gesture view 请求 tap | `unsupported_target` |
| slider / segmented 请求 tap | `unsupported_target` |
| target 未声明该 action | `unsupported_action` |
| `becomeFirstResponder()` 失败 | 复用合适工厂；无合适语义时新增 `activation_failed` |
| disabled / 不可交互 | 复用现有错误体系中的合适 factory，保证机器可识别 |

---

# 9. 响应模型调整

## 9.1 `ui.tap` 成功响应

删除旧实现泄漏字段，例如：

```text
tapped
dispatchMode = controlActionFallback
x / y
hitPath
hitType
controlPath
```

改为语义响应：

```json
{
  "activated": true,
  "activationRoute": "control.touchUpInside",
  "path": "root/3",
  "type": "UIButton",
  "accessibilityIdentifier": "checkout.submit",
  "event": "touchUpInside"
}
```

switch：

```json
{
  "activated": true,
  "activationRoute": "switch.toggle",
  "path": "root/4/1",
  "type": "UISwitch",
  "event": "valueChanged",
  "previousValue": false,
  "currentValue": true
}
```

text input：

```json
{
  "activated": true,
  "activationRoute": "input.focus",
  "path": "root/2/0",
  "type": "UITextField",
  "isFirstResponder": true
}
```

## 9.2 `ui.control.sendAction` 成功响应

保留精确 event 语义：

```json
{
  "sent": true,
  "path": "root/3",
  "type": "UIButton",
  "event": "touchDown",
  "isEnabled": true,
  "isSelected": false
}
```

不返回 `activationRoute`。

---

# 10. navigationBar 与 alert 边界

## 10.1 navigationBar：本轮不并入 `ui.tap`

navigationBar / `UIBarButtonItem` 的可达性刚完成，当前已有独立的：

```text
navigationBar 语义观察区块
+
ui.navigation.tapBarButton
```

本轮不得：

```text
- 通过 navigationBar 私有 subview 寻找 bar button；
- 将 UIBarButtonItem 硬塞进普通 UIView path 模型；
- 改写或回退既有 ui.navigation.tapBarButton；
- 为了统一 API 而冒险破坏 navigationBar 成果。
```

Agent 协议明确：

```text
页面内 canonical target → ui.tap
navigationBar button → ui.navigation.tapBarButton
```

未来若要统一为 single `ui.tap`，必须先单独设计一个跨普通 view / navigation item 的结构化 action reference 协议；不是本次任务范围。

## 10.2 alert：本轮不宣告为可 tap

`ui.alert.respond` 当前仍是 query/dry-run。

因此：

```text
alert action 当前不得在 ui.viewTargets 中被声明为 tap。
ui.tap 不路由 alert。
```

等有真实、公开、稳定的 alert 执行器后，另开任务设计其 observation + locator + executor；不要提前伪造支持。

---

# 11. 明确不做的事情

```text
- 不删除 ui.tap。
- 不新增 ui.activate。
- 不保留裸坐标 ui.tap。
- 不将坐标并入 ui.control.sendAction。
- 不保留 child view → nearest UIControl 的 ancestor fallback。
- 不构造 UITouch / UIEvent。
- 不使用 UIKit 私有 API。
- 不调用 UIResponder.touchesBegan / touchesEnded 伪造手势。
- 不对普通 gesture view 做 best-effort 点击。
- 不新增 long tap / multiple tap / drag。
- 不把 screenshot 作为 snapshot/freshness 基础。
- 不把 navigationBar 回退成普通 UIView hit-test。
- 不提前实现 alert 真正响应。
- 不改变 core HTTP envelope。
- 不提交 git commit。
```

---

# 12. 需要修改的文件范围

> 文件名以当前仓库为准。若实际位置不同，按类型/职责搜索并更新。新增 public 类型、方法、属性必须有中文 `///` 文档注释；新增命令或关键路径必须补日志；代码需兼容 SPM Swift 6.2 和 framework `SWIFT_VERSION=5.0`。

## 12.1 `ui.tap` 输入与命令层

1. `Sources/iOSExploreUIKit/Commands/Tap/UITapModels.swift`
   - 删除 window point target、`x/y/coordinateSpace`、坐标 schema。
   - `snapshotID` → `viewSnapshotID`。
   - path 与 identifier 都强制 `viewSnapshotID`。
   - 更新 public 注释、schema 描述与 help 文案。

2. `Sources/iOSExploreUIKit/Commands/Tap/UITapCommand.swift`
   - 命令描述从“点击 / 坐标点击”改为“默认激活 canonical target”。
   - 构造新的 tap action plan。

3. locator 相关模型（例如 `UIKitLocator.swift`）
   - 删除 `.windowPoint` 与坐标相关逻辑。

## 12.2 action plan、capability、executor

4. `Sources/iOSExploreUIKit/Support/Action/UIKitActionPlan.swift`
   - `snapshotID` 字段改名为 `viewSnapshotID`。
   - 删除 window-point plan 支持。
   - 明确 `.tap` 是 default activation，不是 touch injection。

5. 新增 `Sources/iOSExploreUIKit/Support/Action/UIKitDefaultActivationResolver.swift`
   - 集中实现默认激活 route 判定。
   - 提供 button / switch / text-input 路由。
   - 不返回跨 actor 的 UIKit 对象；必要 UIKit 操作保持 `@MainActor`。

6. `Sources/iOSExploreUIKit/Support/Action/UIKitActionCapabilityResolver.swift`
   - 删除 `nearestControl` 借用 tap capability 的设计。
   - 用 `UIKitDefaultActivationResolver` 决定 `tap` 是否存在。
   - 精确 `control.*`、`input`、`scroll` capability 保持真实、明确。
   - slider / segmented 不能出现 tap。

7. `Sources/iOSExploreUIKit/Support/Action/UIKitActionExecutor.swift`
   - 删除坐标 tap 分支。
   - 删除 hit-test 后寻找最近 control 的 tap 分支。
   - 删除 `dispatchTap` / `controlActionFallback` 等旧命名和响应字段。
   - 新增统一 `validateViewSnapshot` 或等价路径。
   - 新增 default activation 执行：
     - button `.touchUpInside`；
     - switch toggle + `.valueChanged`；
     - text input `becomeFirstResponder()`。
   - identifier / path 都进入同一 freshness 校验。
   - `ui.control.sendAction` 同步使用统一 freshness 校验。
   - 补全关键日志，但不得记录明文业务文本或隐私输入内容。

## 12.3 `ui.control.sendAction`

8. `Sources/iOSExploreUIKit/Commands/ControlAction/UIControlSendActionModels.swift`
   - `snapshotID` → `viewSnapshotID`。
   - identifier/path 均必须提供 `viewSnapshotID`。
   - 注释明确它是精确 event dispatch，不是默认 tap。

9. `Sources/iOSExploreUIKit/Commands/ControlAction/UIControlSendActionCommand.swift`
   - 更新 help/schema 描述，确保无坐标输入、无 ancestor fallback。

## 12.4 canonical target、fingerprint、snapshot

10. `Sources/iOSExploreUIKit/Commands/ViewTargets/UIViewTargetsModels.swift`
    - target 模型增加或规范：`role`、`semanticText`、`semanticTextSource`、`availableActions`。
    - 所有新增 public 字段加中文 `///`。

11. `Sources/iOSExploreUIKit/Commands/ViewTargets/UIViewTargetsCollector.swift`
    - 只输出 canonical interaction targets。
    - 排除内部 label/image、静态文本、container、gesture-only view 等非可执行对象。
    - 保持 navigationBar 独立语义区块，不回退。
    - 对 canonical target 提取安全、稳定的语义文本。
    - 完成所有筛选/截断后再生成 fingerprint / `viewSnapshotID`。

12. `UIKitFingerprintCollector.swift`
    - 只为最终返回的 canonical target 采集指纹。
    - 增加或强化 `semanticDigest`。
    - 存 hash，不存明文业务文本。

13. `UIKitSnapshotStore.swift`
    - `snapshotID` 语义和 public 字段重命名为 `viewSnapshotID`。
    - 支持“目标 path 是否属于该 snapshot 签发集合”的检查。
    - 保持 context / TTL / fingerprint stale 判断。

14. 所有使用公共 `snapshotID` 的 response/request model
    - 原子重命名为 `viewSnapshotID`。
    - 特别审查 `ui.screenshot`：它不得再签发或声称签发该 ID。

15. `Sources/iOSExploreUIKit/Commands/Screenshot/UIScreenshotCollector.swift`
    - 删除 `collectFingerprints(...) + UIKitSnapshotStore.shared.insert(...)` 签发逻辑。
    - 删除响应中的 `snapshotID` / `snapshotUnavailableReason`，不得改名为 `viewSnapshotID` 后继续返回。
    - 更新 public 注释和日志，明确 screenshot 是视觉证据，不参与结构化 freshness。
    - 更新截图相关测试：只断言 image/format/width/height/scale/pixelScale，不再断言 snapshot。

16. `Sources/iOSExploreUIKit/Commands/Wait/` 与 `Sources/iOSExploreUIKit/Support/Wait/UIWaitExecutor.swift`
    - 将 `snapshotChanged` 输入字段从 `snapshotID` 迁移为 `viewSnapshotID`。
    - `viewSnapshotID` 必须来自 `ui.viewTargets`，不能来自 `ui.screenshot`。
    - `UIKitSnapshotStore.signingQuery(for:)` 仍可复用，但 signing query 的来源必须是 `ui.viewTargets`。
    - 更新 wait help/schema、错误文案和 tests。
    - 若实施时决定暂不迁移 `ui.wait`，则必须把本方案降级为“tap/sendAction 局部迁移”，不得声称公共协议已完成 `snapshotID → viewSnapshotID`。

## 12.5 错误、注册、文档

17. `UIKitCommandError.swift`
    - 优先复用 `staleLocator`、`unsupportedTarget`、`unsupportedAction`。
    - 若现有错误无法表达 `becomeFirstResponder()` 失败，可新增受控 factory，例如 `activationFailed`。
    - `staleLocator` 文案必须从“call ui.screenshot first”改为“call ui.viewTargets first”，避免继续暗示 screenshot 签发 snapshot。

18. `ExploreError.swift`
    - 只有在现有 error code 无法表达需要时才扩展。
    - 不修改 core envelope。

19. UIKit command registration / help
    - 保留 `ui.tap` 注册。
    - 不新增 `ui.activate`。
    - 更新说明，删除坐标点击文案。

---

# 13. 测试计划

## 13.1 输入解析测试

至少覆盖：

```text
- ui.tap path + viewSnapshotID 成功解析；
- ui.tap identifier + viewSnapshotID 成功解析；
- 缺少 viewSnapshotID 失败；
- path 和 identifier 同时提供失败；
- x/y 失败；
- coordinateSpace 失败；
- ui.control.sendAction path/identifier + viewSnapshotID + event 成功解析；
- sendAction 缺 event / 缺 viewSnapshotID 失败。
```

## 13.2 `ui.tap` route 测试

```text
- UIButton → control.touchUpInside；
- UIButton 子类 → control.touchUpInside；
- 未知自定义 UIControl 不声明 tap；
- UISwitch → state 翻转 + valueChanged；
- UITextField → first responder；
- UITextView → first responder；
- UISlider → unsupported_target；
- UISegmentedControl → unsupported_target；
- 普通 UIView → unsupported_target；
- gesture-only UIView → unsupported_target；
- 内部 UILabel path 不会激活父 UIButton；
- disabled / hidden / alpha / userInteractionEnabled 不满足的 target 被拒绝。
```

## 13.3 freshness 测试

```text
- path + viewSnapshotID：fingerprint 一致时成功；
- identifier + viewSnapshotID：resolve current path 后成功；
- identifier 当前指向不同结构 target：stale_locator；
- path 存在但 semanticDigest 改变：stale_locator；
- path 不属于 snapshot 已签发集合：stale_locator；
- top view controller / context 改变：stale_locator；
- TTL 过期：stale_locator；
- maxTargets 截断后未返回 target：不可执行。
```

## 13.3.1 screenshot / wait 迁移测试

```text
- ui.screenshot 响应不包含 snapshotID；
- ui.screenshot 响应不包含 viewSnapshotID；
- ui.screenshot 不调用 UIKitSnapshotStore.insert；
- ui.wait snapshotChanged 接受 viewSnapshotID；
- ui.wait snapshotChanged 拒绝旧 snapshotID 字段；
- ui.wait snapshotChanged 使用 viewTargets 签发时记录的 query 重采 fingerprint；
- stale_locator 对外 message 不再提示 call ui.screenshot first；
- stale_locator 对外 message 提示重新调用 ui.viewTargets。
```

## 13.4 collector / fingerprint 测试

```text
- UIButton 是 canonical target；
- button 内 UILabel / UIImageView 不出现在 targets；
- button title / a11y label 可出现在父 target 的 semanticText；
- 普通 UILabel 不出现在 targets；
- gesture-only view 不出现在 targets；
- disabled control 出现在 targets，但 availableActions 为空；
- UISwitch 有 tap + control.valueChanged；
- UISlider 无 tap，仍可有 control.valueChanged；
- UITextField 有 tap + input + editing events；
- 返回 targets 的 path 集合 == fingerprint 签发 path 集合；
- button title / accessibility label 改变时 semanticDigest 改变。
- maxTargets=1 时，snapshot 只签发返回的 1 个 target；
- includeStaticText/includeContainers 不会让非 executable view 进入普通 targets；
- 普通 accessibilityIdentifier / accessibilityLabel view 不进入 targets，但仍可由 ui.topViewHierarchy 观察。
```

## 13.5 `ui.control.sendAction` 测试

```text
- 非 UIControl 目标拒绝；
- child label path 拒绝；
- disabled control 拒绝；
- unsupported event 拒绝；
- valueChanged 仅派发 event，不承诺自动改变 value/index；
- identifier 和 path 都走 freshness。
```

## 13.6 非回归测试

必须保持：

```text
- ui.navigation.tapBarButton 正常；
- navigationBar 观察区块正常；
- ui.alert.respond 仍为当前 dry-run/query-only 行为；
- core HTTP envelope 未变；
- 现有 input / scroll / wait 功能未被回退。
```

---

# 14. 文档更新

## 14.1 `README.md`

删除或修正：

```text
- ui.tap 支持 window 坐标点击；
- screenshot 签发 snapshotID；
- ui.tap 是任意元素通用点击。
```

写清：

```text
- ui.tap 是默认激活，不是触摸注入；
- ui.tap 仅操作 ui.viewTargets 签发的 canonical target；
- viewSnapshotID 是 UIKit 结构指纹快照，不是截图；
- ui.screenshot 仅为可选诊断能力；
- ui.tap 成功不等于业务步骤成功，必须 wait / observe 后判断。
```

## 14.2 `docs/superpowers/agent-mcp-exploration/agent-usage-protocol.md`

新的 Agent 使用顺序：

```text
1. 调 ui.viewTargets。
2. 保存本次 viewSnapshotID。
3. 从 target 的 availableActions 选择动作。
4. button / switch / 可聚焦 text input：优先 ui.tap。
5. 特殊 UIControl event：ui.control.sendAction。
6. navigationBar：ui.navigation.tapBarButton。
7. 动作后 ui.wait 或再次 ui.viewTargets。
8. 成功响应不等于业务成功，必须重新 observe / judge。
9. stale_locator 后不得重试旧 locator，必须重新观察。
10. 不使用裸坐标点击。
```

## 14.3 `docs/superpowers/agent-mcp-exploration/README.md`

记录本次架构结论：

```text
- UIKit structure observe-first；
- 不依赖 VLM；
- 不依赖 screenshot；
- ui.tap 是 Agent 语义动作；
- executor 仅使用公开、确定、可验证的 UIKit adapter；
- 宁可 unsupported，不做触摸伪造。
```

## 14.4 新增设计文档

新增：

```text
docs/superpowers/specs/2026-07-02-ui-tap-structural-default-activation.md
```

至少包括：

```text
- 为什么保留 ui.tap；
- 为什么 ui.tap 不等于真实触摸；
- 为什么 snapshotID 改名为 viewSnapshotID；
- canonical target 不变式；
- default activation route 表；
- navigation / alert 边界；
- 为什么不做坐标 tap、long tap、multiple tap、drag；
- 为什么不使用 UIKit 私有 API；
- 与得物 ai_tap 的相同点和差异。
```

---

# 15. 推荐实施顺序

严格按顺序做，避免中间状态发生“schema、collector、capability、executor 不一致”。

## 阶段 0：写当前行为锁定测试

```text
先写失败测试锁定目标协议：
- ui.tap 不接受 x/y/coordinateSpace；
- ui.tap path/identifier 都必须带 viewSnapshotID；
- ui.screenshot 不返回 snapshotID/viewSnapshotID；
- ui.wait snapshotChanged 使用 viewSnapshotID；
- maxTargets 后返回 path 集合 == snapshot 签发 path 集合；
- child label path 不会激活父 button。
```

这些测试必须先失败，避免实现过程中误把旧兼容行为保留下来。

## 阶段 1：先收敛结构快照与 canonical target

```text
snapshotID → viewSnapshotID
ui.viewTargets → canonical interaction targets
fingerprint 集合 == 最终返回 target 集合
identifier 与 path 都走 freshness
ui.screenshot 停止签发结构 snapshot
ui.wait snapshotChanged 改用 viewSnapshotID
```

## 阶段 2：收敛 capability

```text
删除 nearestControl 借用 tap capability
新增 UIKitDefaultActivationResolver
availableActions.tap 与实际 route 一一对应
```

## 阶段 3：替换 `ui.tap` executor

```text
删除坐标
删除 hit-test
删除 ancestor fallback
新增 button / switch / input focus route
更新响应模型和日志
```

## 阶段 4：强化 `ui.control.sendAction`

```text
identifier/path 都必须带 viewSnapshotID
只允许 target 自身为 UIControl
不做 fallback
```

## 阶段 5：文档、help、测试、非回归

确保：

```text
源码协议
=
schema / help
=
availableActions
=
executor
=
Agent usage protocol
=
测试断言
```

---

# 16. 验收

实现阶段至少运行：

```bash
swift test
```

```bash
xcodebuild \
  -project iOSExploreServer/iOSExploreServer.xcodeproj \
  -scheme iOSExploreServer \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  test
```

人工闭环验证：

```text
ui.viewTargets
→ 看到 UIButton canonical target 与 semanticText
→ 得到 viewSnapshotID
→ ui.tap(path + viewSnapshotID)
→ activationRoute = control.touchUpInside
→ ui.wait
→ 再次 ui.viewTargets
```

```text
ui.viewTargets
→ 看到 UISwitch
→ ui.tap
→ isOn 确实翻转、valueChanged 被派发
→ 再次 observe 能看到新状态
```

```text
ui.viewTargets
→ button 内 UILabel 不作为 target 返回
→ 手工使用旧 label path 调 ui.tap
→ 不会再沿祖先 fallback 激活 button
→ 返回 stale_locator 或 unsupported_target
```

```text
navigationBar
→ 仍用 ui.navigation.tapBarButton
→ 正常工作
```

```text
ui.screenshot
→ 不签发、不刷新 viewSnapshotID
→ 不参与 freshness
```

---

# 17. 最终一句话

```text
保留 ui.tap，但它只操作由 UIKit 结构化 observe 签发的 canonical target，
并按 target 类型路由到公开、确定、可验证的默认激活 adapter。

删除坐标 tap、删除祖先 UIControl fallback、将 snapshotID 明确为 viewSnapshotID。

ui.control.sendAction 保留为精确事件派发工具；
navigationBar 与 alert 继续使用专用命令；
没有公开可靠 adapter 的动作，一律不假装支持。
```
