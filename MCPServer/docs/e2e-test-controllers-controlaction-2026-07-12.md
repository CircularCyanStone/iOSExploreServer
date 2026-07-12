# 端到端测试报告：Controllers + ControlAction 命令

- **测试日期**：2026-07-12
- **测试范围**：`Sources/iOSExploreUIKit/Commands/Controllers/`（`ui.controllers`）与 `Sources/iOSExploreUIKit/Commands/ControlAction/`（`ui.control.sendAction`）
- **测试方式**：用 `scripts/mcp-inspector.mjs` + `curl` 走真实 MCP 协议 → MCPServer → SPMExample（iPhone 17 模拟器，38321 端口，autostart）。自行构造场景（新增 `ControllerStructureTestViewController`，覆盖 Navigation / Tab / Modal 链 / Child / Split 五类容器结构），不依赖既有页面。
- **测试 App**：`Examples/SPMExample`（本次新增 `ControllerStructureTestViewController.swift` 专门构建多层 controller 结构）

## 结论速览

| # | 严重度 | 命令 | 问题 |
|---|---|---|---|
| Bug #1 | 中 | `ui.inspect` | UIButton 的 `text` 返回 null，按钮标题（titleLabel.text）未提取 |
| Bug #2 | **严重** | `ui.topViewHierarchy` | `controller` 参数对**非栈顶** VC 返回空视图树，核心用途失效 |
| Bug #3 | 中 | `ui.control.sendAction` | 响应不回传控件的 previousValue/currentValue，与 `ui.tap` switchToggle 不一致 |
| Bug #4 | 中 | `ui.inspect` / `ui.topViewHierarchy` | UIStepper 的 value 读不到（accessibilityValue 不暴露），设值闭环断裂 |
| Bug #5 | 轻 | `ui.control.sendAction` | textfield 发 editingChanged 传 string value 被拒，错误信息未引导 `ui.input` |
| Bug #6 | **严重** | `ui.controllers` | presented modal/split 被**转发散落**到多个容器节点，controllerCount 虚高、topPath 指向错误挂载点 |

---

## Bug #1（中）：`ui.inspect` 对 UIButton 返回 `text: null`

### 现象
在 Controller 结构测试页 inspect，所有 UIButton 的 `text` 字段为 `null`：
```json
{ "path": "root/0/0/3", "type": "UIButton", "text": null,
  "availableActions": ["tap","control.touchUpInside","control.touchDown"] }
```
按钮实际标题（"Push 一层 VC"）完全丢失。对比 UIListContentView / UILabel 的 text 能正确提取（"🎮 控件测试"）。

### 影响
agent 在 `ui.inspect` 结果里看不到任何按钮的文字，只能靠 path 索引盲猜按钮功能，无法按文字定位按钮。这是 UI 探索场景的高频痛点。

### 根因方向
`UIViewHierarchyCollector.textInfo(from:)` 对 UILabel / cell label / UITextField / UITextView 都有分支提取文本，但 **UIButton 没有提取 `button.title(for: .normal)` / `button.currentTitle`**（文件第 ~280-310 行的 textInfo 分支）。UIButton 的标题在 `titleLabel` 子视图里，但 inspect 把 UIButton 节点本身的 text 留空，子 UILabel（titleLabel）又往往被归为 minimal 不输出文本。

### 修复方向
`textInfo` 增加 UIButton 分支：`button.currentTitle ?? button.title(for: .normal)`，与 cell label 分支同口径。

---

## Bug #2（严重）：`ui.topViewHierarchy` 的 `controller` 参数对非栈顶 VC 返回空视图树

### 现象
navigation stack 有 3 层（nav[0]=主页、nav[1]=ControllerStructureTest、nav[2]=SimpleTest，栈顶 nav[2]）时，用 `controller` 参数采集各层：

| controller path | nodeCount | subviewCount | 结果 |
|---|---|---|---|
| `root.tab[0].nav[2]`（栈顶） | 4 | 2 | ✓ 正常 |
| `root.tab[0].nav[1]`（中间层） | **1** | **0** | ✗ 空树 |
| `root.tab[0].nav[0]`（栈底主页） | **1** | **0** | ✗ 空树 |

栈顶 nav[2] 能采集，nav[0]/nav[1]（即使 `isViewLoaded=true`）全部返回只有根节点、subviews 为空的 UIView。主页 ViewController 实际有几十个子视图（TableView、按钮等），全部丢失。

### 影响
`controller` 参数的**唯一核心用途**就是"采集非栈顶 / 非当前可见控制器的视图"（description 与 controllerNote 都这么承诺）。现在这个用途完全失效——agent 传任何非栈顶 controller path，都只能拿到空树，等于功能不可用。

### 根因（已定位到代码）
`UIViewHierarchyCollector.swift` 第 207-218 行的 **window 归属守卫**：
```swift
let isInWindowHierarchy = Self.isAttachedToWindow(view)
let subviews: [UIView]
if isInWindowHierarchy {
    subviews = view.subviews
} else {
    subviews = []   // ← 非 window 内的 view，子树强制清空
}
```
`isAttachedToWindow`（第 264-275 行）沿 superview 链查 window。**非栈顶 VC 的 view 不在 window 的视图层级里**（UINavigationController 只把栈顶 VC 的 view 加到容器），所以 `view.window == nil` 且 superview 链全 nil → 返回 false → subviews 强制清空。

这个守卫的设计意图（注释说）是防 `sendActions` 后短暂脱离层级的过渡 view，但它**误伤了所有不在当前 window 层级里的 VC view**，与 `controller` 参数的设计意图根本冲突。

### 修复方向
`controller` 参数路径下绕过 window 守卫（目标 VC 的 view 本就可能不在 window 里，这是预期的、合法的采集目标）。守卫只应作用于默认（栈顶）采集路径，或只对"sendAction 后的过渡 view"生效（可通过更精确的条件区分过渡 view 与合法非栈顶 VC view）。`loadViewIfNeeded()` 已经保证 view 存在，守卫在此路径下是多余且有害的。

---

## Bug #3（中）：`ui.control.sendAction` 响应不回传控件值

### 现象
对 UISwitch / UISlider / UISegmentedControl / UIStepper 发 valueChanged 带 value，响应只返回：
```json
{ "sent": true, "event": "valueChanged", "type": "UISwitch",
  "isEnabled": true, "isSelected": false, ... }
```
**没有 previousValue / currentValue**。agent 无法从单次响应确认值是否生效，必须再调一次 `ui.inspect`。

对比：`ui.tap` 的 switchToggle 路由（`UIKitActionExecutor.swift` 第 233-241 行）却返回了 `previousValue` 和 `currentValue`：
```json
{ "activated": true, "activationRoute": "switch.toggle",
  "previousValue": false, "currentValue": true }
```
**两个命令对同一个 UISwitch 返回值的口径不一致**。

### 越界值的静默处理（加重影响）
`applyValue`（第 328-340 行）不做范围校验，直接写入，UIKit 静默处理：
- `slider value=999` → UIKit clamp 到 1.0（响应仍 `sent=true`，不告知变成 1.0）
- `switch value=5` → 非 0 即 true → on
- `segmented value=99`（越界段）→ **selectedSegmentIndex=99 无效，实际保持原值 2，但响应 `sent=true`**

agent 设 segmented=99，响应说成功，实际值根本没变——这是最容易误导 agent 的场景。

### 根因
`executeControlEvent`（第 306-314 行）返回字段固定为 `sent/event/path/type/accessibilityIdentifier/isEnabled/isSelected`，刻意没采集控件当前值。而 switchToggle 路由采集了。

### 修复方向
- sendAction 响应按控件类型回传当前值（slider→value、switch→isOn、segmented→selectedSegmentIndex、stepper→value），并补 previousValue（在 applyValue 前记录）
- 越界值（如 segmented 超出段数、slider 超过 max/min）应在 applyValue 后比对并提示，或在校验阶段拒绝并给出范围

---

## Bug #4（中）：UIStepper 的 value 读不到，设值闭环断裂

### 现象
对 UIStepper 发 `valueChanged value=5`，响应 `sent=true`。但 `ui.inspect` / `ui.topViewHierarchy` 读取 UIStepper 的 value 始终为 `null`：
```json
{ "id": "test.stepper", "type": "UIStepper", "value": null }
```
对比同页 UISlider（"1.0"）、UISwitch（"on"）、UISegmentedControl（"2"）的 value 都能读到。

### 影响
UIStepper 是 sendAction 的四类值控件之一，但设值后**完全无法验证**（响应不回传值 + inspect 读不到）。整个 UIStepper 的"设值→验证"闭环断裂，agent 对 stepper 的操作结果不可观测。

### 根因
`UIViewHierarchyCollector` 第 176 行，value 从 `view.accessibilityValue` 读取。UISlider / UISwitch / UISegmentedControl 的 accessibilityValue 由 UIKit 自动暴露，但 **UIStepper 默认不自动暴露数值型 accessibilityValue**（除非显式配置 accessibility traits/value），所以读不到。

### 修复方向
对 UIStepper（及任何 value 不在 accessibilityValue 的控件）补一个直接读 `control.value` 的分支，类似 `controlInfo` 已有的特殊控件处理。

---

## Bug #5（轻）：textfield 发 editingChanged 传 string value 被拒

### 现象
```bash
ui.control.sendAction { accessibilityIdentifier:"test.textfield", event:"editingChanged", value:"hello" }
→ { "code": "invalid_data", "message": "value must be a finite number" }
```

### 影响
sendAction 的 `value` 字段类型固定为 number（`CommandFields.number`），只服务 slider/segmented/stepper/switch。textfield 的 `control.editingChanged` / `editingDidBegin` / `editingDidEnd` 在 availableActions 里暴露，agent 合理地想用 sendAction 设文本，结果被 number 校验拒绝。错误信息 "value must be a finite number" 没有引导 agent 改用 `ui.input`。

### 属设计边界（非崩溃）
按 model 注释，value 只对四类值控件有效。但错误信息应明确提示"文本控件请用 ui.input"。

### 修复方向
- 错误信息细化：对 textfield/uitextview 传非 number value 时，提示 "sendAction 不支持文本值，请使用 ui.input"
- 或文档/描述里更醒目地说明 value 仅对四类值控件生效

---

## Bug #6（严重）：`ui.controllers` 对 presented modal/split 转发散落

### 现象
**只 present 一次**链式 modal（3 层：Modal1→Modal2→Modal3，从 nav[1] present），`ui.controllers` 返回 `controllerCount=18`，树里出现 **8 个 modal 节点**散落在每个容器节点：

```
root (UITabBarController)
└─ tab[0] (UINavigationController)
   ├─ nav[0] (ViewController)
   │   └─ presented (Modal1)          ← 转发，nav[0] 没 present 任何东西
   │       └─ presented (Modal2)
   │           └─ presented (Modal3)
   ├─ nav[1] (ControllerStructureTest)  ← 真实调用 present 的 VC
   │   └─ presented (Modal1)          ← 叶子（visited 去重）
   └─ presented (Modal1)              ← 转发
─ tab[1] ... presented (Modal1)       ← 转发
─ tab[2] ... presented (Modal1)       ← 转发
─ root.presented (Modal1)             ← 转发
```

同一个 SplitView modal 同样散落到 3 个节点（nav[0]/nav[1]/tab[0]）。

**后果**：
1. `controllerCount` 严重虚高（18 vs 实际约 5 个真实 VC）
2. `topPath` 指向**错误的挂载点**：`root.tab[0].nav[0].presented.presented.presented`（nav[0]），但 modal 实际是从 nav[1] present 的
3. dismiss 一层 modal 后，topPath 仍指向 nav[0]（`nav[0].presented.presented`），挂载点持续错误

### 影响
agent 拿到的 controller 结构树是**错误的、虚高的**。当存在 modal/sheet 时，agent 无法从 controllers 输出判断"真实有几个界面"、"modal 真正挂在谁下面"、"哪个 VC 是呈现者"。这在任何有弹窗的真实 App 里都会触发，是 controllers 命令的核心正确性问题。

### 根因（已定位到代码）
`UIControllersCollector.edges(of:)` 第 184-190 行对**每个**节点都查 `presentedViewController` 并附加为子节点：
```swift
if let presented = controller.presentedViewController {
    result.append(ControllerEdge(segment: .presented, child: presented, ...))
}
```
但 UIKit 的 `UIViewController.presentedViewController` 文档定义为 "The view controller presented by this view controller **or one of its descendants**"。容器层级（UINavigationController / UITabBarController / root）会**转发**返回后代 present 的 modal —— 所以 nav[0] / nav[1] / nav / tab[1] / tab[2] / root 的 `presentedViewController` 都返回同一个 Modal1 对象。

`buildNode` 的 `visited` 集合（第 96-99 行）只防止对 Modal1 的**重复展开**（避免死循环），但 Modal1 仍作为**重复叶子节点**出现在每个父节点下，导致 controllerCount 虚高、树结构错误。

### 修复方向
在 `edges(of:)` 附加 presented 子节点前，用 **真实持有者关系** 过滤，而非无条件信任 `presentedViewController`：
```swift
if let presented = controller.presentedViewController,
   presented.presentingViewController === controller {   // 只在真实呈现者处挂载
    result.append(ControllerEdge(segment: .presented, child: presented, ...))
}
```
`presentingViewController` 返回的是"负责呈现该 VC 的 VC"，是确定的、非转发的。这样 modal 只会挂在真实的 presentation context（呈现者）下，散落问题消除。
> 注：实施前需实测确认 `modal.presentingViewController` 的实际值（是调用 present 的 VC，还是 window rootViewController），以决定过滤条件的具体形式。

---

## 正面发现（正常工作，非 bug）

- **controllers 基础结构识别正确**：root tab（UITabBarController 3 tabs）/ navigation stack（push/pop 后 controllerCount 与 topPath 正确变化）/ child VC（`nav[1].child[0]`，role=child）/ split（`split[0]` 段）均按预期采集。
- **controllers maxDepth 参数正确**：`maxDepth=0`→只 root；`=1`→root+3 tabs；`=-1`→"non-negative integer"；`="abc"`→"must be an integer"。
- **sendAction 正向用例全部生效**：switch/slider/segmented/stepper 设值后用 inspect 复核，值确实改变（switch→on、slider→0.8、segmented→2）。UIKit 自动 clamp（slider=999→1.0）也生效。
- **sendAction 参数校验完整**：identifier/path 互斥、event 必填、viewSnapshotID 必填、非法 event 名、不存在的 identifier（target_not_found）、给 button 发 valueChanged（"requested action is not supported"）均有正确业务错误。
- **sendAction 与 ui.tap 的 event 路由协同**：UIButton inspect 暴露 `control.touchUpInside` / `control.touchDown`，sendAction 和 ui.tap 都能走该路由。

## 修复优先级建议

1. **Bug #6（controllers 散落）** + **Bug #2（controller 参数空树）**：都是严重正确性问题，直接影响 agent 对界面结构的判断，优先修。
2. **Bug #1（UIButton text）** + **Bug #3（sendAction 不回传值）**：中等问题，影响 agent 可观测性与定位能力，第二优先。
3. **Bug #4（stepper value 读不到）** + **Bug #5（textfield value 报错）**：边界与可用性，第三优先。

---

## 修复结果（2026-07-12）

6 个 bug 全部修复，经 subagent 独立核对确认 + TDD 修复 + curl 真机闭环验证 + 468 iOS framework test / 284 macOS swift test 全通过。

### 核对阶段的纠正（重要）

- **Bug #1 根因定位错了**：报告原说根因在 `UIViewHierarchyCollector.textInfo`，核对 subagent 读代码发现 `textInfo`（292-300 行）**本就有 UIButton 分支**（对 topViewHierarchy 有效）。真实缺口在 `Sources/iOSExploreUIKit/Commands/Inspect/UIInspectCollector.swift` 的 `textualValue`（无 UIButton 分支）。修复按核对纠正的位置改。
- **Bug #4 修复缺口（人工审核发现）**：批 1 只修了 `UIViewHierarchyCollector`（topViewHierarchy 端）的 stepper value，漏了 `UIInspectCollector.value`（inspect 端）同样缺 stepper 分支。已补修 + 补测试。

### 各 bug 修复

| Bug | 修复文件 | 修复方式 | curl 真机验证 |
|---|---|---|---|
| #1 UIButton text | `UIInspectCollector.swift` textualValue | 加 UIButton 分支读 `currentTitle ?? title(for:.normal)` | ✅ "启动 Server"/"停止"（修复前 null）|
| #2 controller 参数空树 | `UIViewHierarchyCollector.swift` UIKitViewElement | 加 `skipWindowGuard` 参数，controller-override 路径跳过 window 守卫，沿子树递归传递 | ✅ nav[0] nodeCount 1→91、subviews 0→8 |
| #3 sendAction 不回传值 | `UIKitActionExecutor.swift` executeControlEvent | 新增 `controlValue(_:)` helper，applyValue 前采 previous、sendActions 后采 current，按控件类型（switch/slider/segmented/stepper）回传 | ✅ switch prev=false→cur=true；slider 999 越界 prev=0.85→cur=1（反映 clamp）|
| #4 stepper value | `UIViewHierarchyCollector.swift` + `UIInspectCollector.swift` | 两处都加 UIStepper 分支读 `stepper.value`（批 1 改 topViewHierarchy，人工补 inspect） | ✅ inspect 读到 "0.0"（修复前 null）|
| #5 textfield 引导 | `UIControlSendActionModels.swift` parse | editing* 事件 + 非 number value 时，抛带 "文本输入请使用 ui.input 命令" 引导的友好错误 | ✅ 错误信息引导 ui.input |
| #6 controllers 散落 | `UIControllersCollector.swift` edges | 附加 presented 前加 `presented.presentingViewController === controller` 过滤，只在真实呈现者挂载 | ✅ 链式 modal count 18→11，8 散落→3 单一链，topPath 从错误的 nav[0]→正确的 root.presented |

### 测试与验证
- **iOS framework test**：468 passed（12 suites），TEST SUCCEEDED，无回归。新增测试覆盖每个 bug 的 RED→GREEN。
- **macOS swift test**：284 passed（含 Bug #5 的 Foundation-only parse 测试）。
- **curl 真机闭环**：6 个 bug 全部在真实运行的 SPMExample（iPhone 17 模拟器）上逐个验证修复效果，现象与修复预期一致。

