# ui.swipe / ui.longPress 端到端测试报告

> 测试日期: 2026-07-13
> 测试对象: `ui.swipe`（action `ui.swipe`）、`ui.longPress`（action `ui.longPress`）
> 测试方法: `MCPServer/scripts/mcp-inspector.mjs` 驱动真 stdio + 真 HTTP，打模拟器 SPMExample（38321 端口）
> 测试页面: `Examples/SPMExample/SPMExample/SwipeTestViewController.swift`、`LongPressTestViewController.swift`

## 修复状态（2026-07-13，subagent 修复 + 端到端复测）

| 问题 | 状态 | 修复内容 |
|---|---|---|
| 1 假阳性 | ✅ 已修 | `trySwipeActions` 诚实返回 false（iOS 26 无公开 API 真正触发 scrollView swipe actions），删 3 个死函数（`simulatePanGesture`/`findSwipeActionGesture`/`findPanGesture`）+ 死代码；A1/A2/A7 → `unsupported_target` |
| 2 pan state | ✅ 已修 | `tryPanGesture` 设 `.began`/`.ended` 序列；A6 log label 出现 began/ended（不再只有 state=0） |
| 3 duration 阻塞 | ✅ 已修 | duration ≤10s 上限（B6b duration=100 被拒）+ executor 改 `async`：`execute`/`tryLongPressGesture` 变 async，`RunLoop.current.run` 换成 `Task.sleep(nanoseconds:)`。插队实测——longPress duration=4 期间 ui.inspect 耗时 **54ms**（改造前 RunLoop 方案 ~3.5-4s），`Task.sleep` yield MainActor 生效，其他 `ui.*` 能插队 |
| 4 系统 pan | ✅ 已修 | `tryPanGesture` 开头 `if view is UIScrollView { return nil }`；A13 → `unsupported_target` |
| 5 错误信息 | ✅ 已修 | `UIKitCommandError.unsupportedTarget` 加可选 message 参数，tap 3 个调用方不传保持默认；swipe/longPress 传专用文案 |
| 6 tableview 高度 0 | ✅ 已修 | **根因**：`logLabel` 闭包漏设 `translatesAutoresizingMaskIntoConstraints = false`，autoresizing mask 隐式约束与显式 Auto Layout 约束冲突，破坏整个 VC 垂直布局（连带 tableView 压成 0、gestureView 压成 ~50、cells 不渲染）。补上后 tableView=300、cells 0–4 正常渲染 |

**验证**：`swift test` 285 全绿（原 284 + 1 个 message 单测，无现有测试破坏）；新增 3 个 duration 上限单测（`#if canImport(UIKit)` 门控，iOS framework 工程跑）；端到端复测 11 个用例全部符合预期（含 A3/B1/B6c 回归用例）。

**后续未做**：
- **问题 1 真正支持 swipe actions**：需 cell 定位参数（swipe actions 是 per-row）+ action 选择参数（一个 cell 可能有删除/归档多个）+ 直接调 `UIContextualAction.handler`（绕过合成触摸死路），可选配 `ui.swipeActions.list` 命令先列出某 cell 的 available actions。

> async 改造的两个实现细节（subagent 实测调整，非偏离设计）：① `MainActor.run { async body }` 重载在 Xcode 编译器里与 sync body 重载歧义（SPM 通过但 Xcode 报错），改用独立的 `@MainActor private func executeOnMainActor` 方法，功能等价；② `Task.sleep(for: .seconds())` 需 iOS 16+，但部署目标是 iOS 13，改用 `Task.sleep(nanoseconds:)`（iOS 13+）。

---

## 一、测试方法

### 驱动链路

```
mcp-inspector.mjs ─stdio JSON-RPC─► dist/index.js ─HTTP POST /─► SPMExample:38321
```

调用示例：

```bash
cd MCPServer
node scripts/mcp-inspector.mjs ui_swipe '{"direction":"left","accessibilityIdentifier":"swipe.tableview"}'
```

完整说明见 `MCPServer/docs/local-mcp-test.md`。

### 三重验证（关键）

不能只看命令返回的 `triggered:true`，必须独立确认 UI 真的变化：

1. **命令返回**：mcp-inspector 打印的 JSON-RPC 响应，`content[0].text` 解出 `code`/`data`/`message`
2. **log label 文本**：`ui_inspect` 定位 `swipe.test.log` / `longpress.test.log`，读节点 `text`，对比操作前后是否出现新事件
3. **截图观察**：XcodeBuildMCP `screenshot`，确认 swipe action 按钮是否真的弹出

判定假阳性的依据：命令返回 `triggered:true` 但 log label 未更新 + 截图无变化。

### 环境搭建

- profile: `sim-app`（iPhone 17 模拟器，simulatorId `065CC8DB-8978-46C5-82D6-C96625B608D8`）
- 进入 Swipe 测试页: `launch_app_sim(env={"IOS_EXPLORE_OPEN_SWIPE_TEST":"1"})`
- 进入 LongPress 测试页: `launch_app_sim(env={"IOS_EXPLORE_OPEN_LONGPRESS_TEST":"1"})`
- autostart 在 `ViewController.swift:351` 硬编码 `true`，server 自动起 38321
- 切换测试页需 `stop_app_sim()` → `launch_app_sim(env=...)` 重启
- 模拟器与 Mac 共享 localhost，不需要 iproxy

## 二、测试结果汇总

### A. ui.swipe（SwipeTestViewController）

| 用例 | 命令返回 code | triggered/route | log label 变化 | 截图观察 | 判定 |
|---|---|---|---|---|---|
| A1 swipe left on tableview | ok | true / scrollView.swipeActions | 未更新 | 无 swipe action 按钮 | ❌ 假阳性（问题 1） |
| A2 swipe right on tableview | ok | true / scrollView.swipeActions | 未更新 | 无 swipe action 按钮 | ❌ 假阳性（问题 1） |
| A3 swipe left on gesture.view | ok | true / swipeGesture.targetAction | "UISwipeGestureRecognizer: left 触发" | N/A | ✅ 通过 |
| A4 swipe right on gesture.view | ok | true / swipeGesture.targetAction | "UISwipeGestureRecognizer: right 触发" | N/A | ✅ 通过 |
| A5 swipe up on gesture.view | unsupported_target | N/A | N/A | N/A | ✅ 通过（错误信息误导，见问题 5） |
| A6 swipe left on pan.view | ok | true / panGesture.targetAction | "UIPanGestureRecognizer: 0"（state=.possible） | N/A | ❌ state 错误（问题 2） |
| A7 swipe left（缺省定位） | ok | true / scrollView.swipeActions | 未更新 | N/A | ❌ 假阳性（问题 1） |
| A8 swipe left on 不存在的 id | target_not_found | N/A | N/A | N/A | ✅ 通过 |
| A9 swipe {}（缺 direction） | invalid_data | N/A | N/A | N/A | ✅ 通过 |
| A10 swipe left distance=0 | invalid_data | N/A | N/A | N/A | ✅ 通过 |
| A11 swipe left distance=1.5 | invalid_data | N/A | N/A | N/A | ✅ 通过 |
| A12 swipe left distance=0.5 on gesture.view | ok | true / swipeGesture.targetAction | "UISwipeGestureRecognizer: left 触发" | N/A | ✅ 通过 |
| A13 swipe up on tableview | ok | true / panGesture.targetAction | 无新日志（系统 pan handler 不写 log） | N/A | ❌ 假阳性（问题 4） |
| A14 stale viewSnapshotID | stale_locator | N/A | N/A | N/A | ✅ 通过 |

### B. ui.longPress（LongPressTestViewController）

| 用例 | 命令返回 code | triggered/route | log label 变化 | 判定 |
|---|---|---|---|---|
| B1 longPress on gesture.view | ok | true / longPressGesture.targetAction | "began 触发" + "ended 触发" | ✅ 通过 |
| B2 longPress duration=2.0 | ok | true / longPressGesture.targetAction | "began 触发" + "ended 触发" | 功能正确但 Thread.sleep 阻塞 MainActor（问题 3） |
| B3 longPress on nogesture.view | unsupported_target | N/A | N/A | ✅ 通过（错误信息误导，见问题 5） |
| B4 longPress {}（缺省定位） | ok | true / longPressGesture.targetAction | "began 触发" + "ended 触发" | ✅ 通过 |
| B5 longPress on 不存在的 id | target_not_found | N/A | N/A | ✅ 通过 |
| B6 longPress duration=0 | invalid_data | N/A | N/A | ✅ 通过 |
| B7 longPress duration=-1 | invalid_data | N/A | N/A | ✅ 通过 |
| B8 longPress on cell.0 | target_not_found | N/A | N/A | ⚠️ 未按预期返回 unsupported_target（tableView height=0，cell 未渲染，见问题 6） |
| B9 stale viewSnapshotID | stale_locator | N/A | N/A | ✅ 通过 |
| B6b longPress duration=100 | MCP 超时无响应 | N/A | N/A | ❌ 无上限校验 + Thread.sleep 阻塞全部 UIKit 命令 100s（问题 3） |

## 三、发现的问题清单

### 问题 1（高）：`simulatePanGesture` 空实现导致 `trySwipeActions` 假阳性

- **影响用例**: A1、A2、A7
- **命令/参数**: `ui.swipe` with `direction: left/right` on `UIScrollView`（如 `swipe.tableview`）
- **预期**: 弹出 trailing/leading swipe action 按钮（删除/归档/收藏/分享），log label 出现 "Trailing Swipe" / "Leading Swipe"
- **实际**: 命令返回 `triggered:true, route:scrollView.swipeActions`，但 log label 未更新、截图无 swipe action 按钮弹出
- **根因**: `simulatePanGesture`（`UISwipeExecutor.swift:221-242`）函数体只有注释和一条 log，遍历 `explore_targetActionPairs()` 后仅 log selector 名字，**从未调用 `UIGestureTargetExecutor.invokeGestureAction`**。但 `trySwipeActions`（`UISwipeExecutor.swift:179-184`）在 `simulatePanGesture` 返回后直接 `return true`
- **对 agent 的影响**: agent 拿到 `triggered:true` 会以为 swipe to delete 成功，继续后续流程，实际 cell 没删除、action 没触发，整个链路静默失败
- **修复方向**: iOS 没有公开 API 合成 UITouch 序列触发 swipe actions，需要换方案：
  - 选项 A：调用 UITableView 私有 API `_showSwipeActions`（或等价的 `setEditing(_:animated:)` 配合）
  - 选项 B：用 `XCUICoordinate` 风格的事件注入（需引入 XCUI，可能不适合 Debug-only 库）
  - 选项 C：诚实降级——scrollView swipe actions 路径不真正触发时返回 `unsupported_target`，而非假阳性 `triggered:true`
- **源码位置**: `Sources/iOSExploreUIKit/Support/Action/UISwipeExecutor.swift:179-184`（调用并 return true）、`:221-242`（空实现）

### 问题 2（中）：`tryPanGesture` 只 invoke 一次不设 state，pan handler 收到 `.possible`

- **影响用例**: A6
- **命令/参数**: `ui.swipe` with `direction: left` on `swipe.pan.view`
- **预期**: log label 出现 "UIPanGestureRecognizer: began" / "changed" / "ended"（或至少 began + ended）
- **实际**: log label 出现 "UIPanGestureRecognizer: 0"——`gesture.state` 为 `.possible`（rawValue=0），handler 的 switch 走到 `default` 分支
- **根因**: `tryPanGesture`（`UISwipeExecutor.swift:290-306`）直接调 `UIGestureTargetExecutor.invokeGestureAction` 一次，不设 `gesture.state`。对比 `UILongPressExecutor.tryLongPressGesture` 会显式设 `.began` / `.ended`。注意 `UIGestureRecognizer.state` 虽是 `public var`，但实际由 UIKit 内部管理，直接赋值对持续手势（pan）可能不生效或被忽略
- **源码位置**: `Sources/iOSExploreUIKit/Support/Action/UISwipeExecutor.swift:290-306`

### 问题 3（高）：`Thread.sleep` 阻塞 MainActor + duration 无上限校验

- **影响用例**: B2、B6b
- **命令/参数**: `ui.longPress` with `duration: 2.0`（B2）或 `duration: 100`（B6b）
- **预期**: 命令在 duration 秒后返回，期间其他命令正常响应
- **实际**:
  - B2 (duration=2.0): 命令总耗时 5.6s（含 MCP 开销），功能正确（began+ended 均触发），但主线程被阻塞 2s
  - B6b (duration=100): 输入校验通过（无上限），`Thread.sleep(100)` 阻塞 MainActor 100 秒。期间 `ping`（core 命令，不需要 MainActor）正常响应，但 `ui.inspect`（UIKit 命令，需要 MainActor）超时无响应。MCP inspector 也未收到 tools/call 响应
- **对 agent 的影响**: agent 误传大 duration（如 100）会让整个 UIKit 命令通道卡死 100 秒，期间所有 `ui.*` 命令超时，agent 会误判 App 挂了
- **根因**: `UILongPressExecutor.swift:92` 的 `Thread.sleep(forTimeInterval: max(duration, 0.1))` 在 `@MainActor` 上执行；`UILongPressModels.swift:71` 的 parse 只校验 `duration <= 0`，无上限
- **修复方向**: ① 给 duration 加上限（建议 10 秒）；② 把 `Thread.sleep` 改成不阻塞 MainActor 的等待（`Task.sleep` 在非主 actor 执行，或用 `RunLoop.current.run(until:)` 让主线程继续抽帧）
- **源码位置**: `Sources/iOSExploreUIKit/Support/Action/UILongPressExecutor.swift:92`、`Sources/iOSExploreUIKit/Commands/LongPress/UILongPressModels.swift:71`

### 问题 4（中）：UITableView 系统 pan gesture 导致 swipe up/down 假阳性

- **影响用例**: A13
- **命令/参数**: `ui.swipe` with `direction: up` on `swipe.tableview`
- **预期**: `unsupported_target`（swipe actions 不处理 up/down，tableView 无自定义 swipe gesture）
- **实际**: `triggered:true, route:panGesture.targetAction, targetType:UITableView`——策略 3 `tryPanGesture` 命中 UITableView 内置的 `UIScrollViewPanGestureRecognizer`（用于滚动），invoke 了其内部 target-action，但实际没有滚动发生
- **根因**: `tryPanGesture` 不区分"用户添加的 pan gesture"和"UIScrollView 系统内置的 pan gesture"。UITableView 的 `gestureRecognizers` 包含系统 pan gesture，策略 3 找到它并 invoke 返回 true，但系统 pan handler 需要完整 touch 序列才能滚动，单次 invoke 无效
- **修复方向**: `tryPanGesture` 跳过 `UIScrollView` 及其子类（`UITableView`/`UICollectionView`/`UITextView`）上的系统 pan gesture，只处理用户显式添加的 pan gesture
- **源码位置**: `Sources/iOSExploreUIKit/Support/Action/UISwipeExecutor.swift:290-306`

### 问题 5（低）：`unsupported_target` 错误信息对 swipe/longPress 误导

- **影响用例**: A5、B3
- **预期**: 错误信息说明"未找到匹配的 swipe gesture recognizer"或"未找到 UILongPressGestureRecognizer"
- **实际**: 错误信息为 "target has no default activation route (UIButton / UISwitch / text input only)"——这是 `ui.tap` 的失败信息，提到 UIButton/UISwitch/text input，与 swipe/longPress 的失败原因无关
- **根因**: `UIKitCommandError.unsupportedTarget` 工厂方法硬编码了 tap 专用的 message，swipe 和 longPress 的 executor 直接复用此工厂，没有传入自定义 message
- **修复方向**: 给 `unsupportedTarget` 工厂加可选 message 参数，swipe/longPress executor 传入自己的说明
- **源码位置**: `Sources/iOSExploreUIKit/UIKitCommandError.swift:112-116`（subagent 报告位置，修复时确认）

### 问题 6（低）：测试页面 UITableView frame height 为 0，cell 未渲染

- **影响用例**: B8（间接影响问题 1 的完整验证）
- **现象**: `ui.inspect` 显示 `swipe.tableview` 和 `longpress.tableview` 的 frame height 均为 0，accessibilityLabel 为 "Empty list"，cells 不可见。B8 预期对 cell 执行 longPress 返回 `unsupported_target`，实际返回 `target_not_found`（cell 未渲染）
- **根因**: 测试页面 tableView 虽然写了 `heightAnchor.constraint(equalToConstant: 300)`（SwipeTestVC:156）/ `200`（LongPressTestVC:159），但 push 后实际 frame height 为 0，可能是 Auto Layout 时机或约束冲突
- **影响**: 问题 1 修复后，若 tableview 仍不渲染，swipe actions 也无法真正触发。**修问题 1 前需先确认此布局问题**
- **源码位置**: `Examples/SPMExample/SPMExample/SwipeTestViewController.swift:156`、`LongPressTestViewController.swift:159`

## 四、通过的用例（确认行为正确，无需改动）

**swipe**:
- A3/A4/A12: 对自定义 `UISwipeGestureRecognizer` 触发——log 正确显示 "UISwipeGestureRecognizer: left/right 触发"
- A5: swipe up on gesture.view——方向不匹配，正确返回 `unsupported_target`
- A8: 不存在的 identifier——正确返回 `target_not_found`
- A9: 缺 direction——正确返回 `invalid_data`（必填字段缺失）
- A10: distance=0——正确返回 `invalid_data` "distance must be in range (0, 1]"
- A11: distance=1.5——正确返回 `invalid_data`
- A14: 陈旧 viewSnapshotID——正确返回 `stale_locator`

**longPress**:
- B1/B4: 对 `UILongPressGestureRecognizer` 触发——log 正确显示 "began 触发" + "ended 触发"（B4 缺省定位正确回退到 foremost longPress view）
- B3: 无 gesture view——正确返回 `unsupported_target`
- B5: 不存在的 identifier——正确返回 `target_not_found`
- B6/B7: duration=0 / duration=-1——正确返回 `invalid_data` "duration must be positive"
- B9: 陈旧 viewSnapshotID——正确返回 `stale_locator`

## 五、修复优先级建议

| 优先级 | 问题 | 理由 |
|---|---|---|
| P0 | 问题 1 + 问题 6 | 问题 6（tableview 不渲染）阻塞问题 1 的验证；问题 1 是假阳性，agent 会静默走错流程 |
| P0 | 问题 3 | duration=100 可卡死全部 UIKit 命令 100s，是可用性风险 |
| P1 | 问题 4 | swipe up/down on scrollView 假阳性，影响 agent 判断 |
| P1 | 问题 2 | pan gesture state 错误，handler 走 default 分支 |
| P2 | 问题 5 | 错误信息误导，不影响功能但影响排障 |

## 六、附：错误码说明

任务初期文档预期的 `not_found` 错误码，实际代码中为 `target_not_found`——这是 `UIKitCommandError.targetNotFound` 工厂方法（`UIKitCommandError.swift`）的统一编码，所有 UIKit 命令的目标未找到均使用此码。本文档已统一使用实际码值。
