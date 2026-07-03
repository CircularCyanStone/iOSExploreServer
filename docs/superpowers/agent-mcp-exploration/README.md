# Agent MCP 应用探索服务改造地图

> 日期：2026-07-02；最近更新：2026-07-03
>
> 这个目录是本轮“吸取得物 AI UITester 经验，重新确定 iOSExploreServer 方向”的入口地图。它记录：我们为什么做这轮讨论、已经形成哪些分析文档、当前进度到哪里、后续需要验证什么。

## 1. 本轮目标

当前目标不是做完整测试平台。

当前目标是：

```text
让开发者用自然语言描述一段测试案例，
Agent 能通过 MCP 服务持续观察 App、执行动作、拿到反馈，
最终判断这个测试案例是否通过。
```

这里的 MCP 服务，可以理解为“Agent 和 App 之间的一组工具”。它应该让 Agent 能可靠地：

- 看当前页面；
- 找到可操作目标；
- 执行点击、输入、滚动、返回等动作；
- 等待动作后的页面反馈；
- 根据反馈继续下一步或判断测试结果。

得物文章里的用例平台、批量生成、报告系统、版本归档和大规模自愈工作台，属于更上层能力。当前只在设计上保留余地，不把它们放进原生端库当前目标。

## 2. 文档地图

### 2.1 外部输入与历史输入

- [iOSExploreServer_AI_Native_UI_Execution_Plan_v2.md](../specs/iOSExploreServer_AI_Native_UI_Execution_Plan_v2.md)
  - 由得物文章和当前项目初步分析出来的旧版方案。
  - 价值：提出“点击后等待可验证结果”这个方向。
  - 问题：比当前代码慢一个版本，未充分考虑现有 `ui.wait` 已存在。

### 2.2 本轮方向稿

- [2026-07-02-agent-mcp-app-exploration-direction.md](../specs/2026-07-02-agent-mcp-app-exploration-direction.md)
  - 记录本项目当前基调。
  - 明确：当前不是 Agent Tester 平台，而是 Agent MCP 应用探索服务。
  - 明确：最终效果仍然是自然语言测试案例由 Agent 借助 MCP 服务完成操作和验证。
  - 明确：得物经验要吸收，但不照搬跨端视觉路线。

### 2.3 现有命令体检

- [2026-07-02-agent-mcp-command-health-check.md](../specs/2026-07-02-agent-mcp-command-health-check.md)
  - 对当前 `ui.*` 命令做闭环体检。
  - 结论：现有基础能力可保留，不需要全盘推翻。
  - 关键缺口：
    - Agent 使用协议还没写清；
    - `ui.wait` 是单条件等待，不足以覆盖多个可能结果；
    - 动作后的最终页面状态没有统一返回；
    - ~~`ui.alert.respond` 只能查询、不能真正响应弹窗~~（已解决：`dryRun=false` 通过 Debug-only 私有方法 `_dismissWithAction:` 实现真实触发与关闭，见 §6.2）。

### 2.4 运行验证记录

- [runtime-validation-2026-07-02.md](./runtime-validation-2026-07-02.md)
  - 三层验证记录：`swift test`、iOS framework build/test、Example App 真实闭环。
  - 结果：SPM 185 个测试全过；framework 258 个测试全过；主页 `observe → scroll → wait → observe` 跑通。
  - 新发现：
    - navigationBar / UIBarButtonItem 当前不可达；
    - `ui.tap` 对非 `UIControl` 的 UIBarButtonItem 内部视图会拒绝；
    - `ui.wait textExists` 只检测当前可见文本。
- [runtime-validation-2026-07-03.md](./runtime-validation-2026-07-03.md)
  - navigationBar / `ui.tap` 默认激活 / `ui.waitAny` / alert query-only 全部落地后的第二轮真实闭环（SPMExample + iPhone 17 模拟器）。
  - `observe → navigation.tapBarButton → tap/control.sendAction → waitAny → re-observe` 在 ControlTest 子页完整跑通。
  - 修了 2 个只有真机跑才暴露的问题：curl 协议 `navigation.tapBarButton` 示例多带的 `dryRun` 字段、SPMExample `ControlTestViewController.switchChanged()` 自翻转。
  - 测试基线推进到 SPM 210 / framework 310。

### 2.5 Agent 使用协议

- [agent-usage-protocol.md](./agent-usage-protocol.md)
  - 说明 Agent 应该如何组合现有命令。
  - 明确：`observe → act → wait/observe again → judge` 是默认闭环。
  - 明确：动作成功不等于测试通过；测试是否通过必须看最终页面证据。
  - 已同步 navigationBar 专用动作、`ui.tap` 结构化默认激活和 `ui.alert.respond`（含 `dryRun=false` 真实触发）；`textExists` 仍只查当前可见文本。

- [curl-json-loop-protocol.md](./curl-json-loop-protocol.md)
  - 给外部 Agent / 人工调试者的可运行 curl/JSON 操作协议。
  - 用真实 HTTP body 展示 `observe → action → ui.wait(snapshotChanged) → re-observe → verify`。
  - 明确 freshness 字段、滚动后重新观察、navigationBar/alert 的当前边界。

### 2.6 navigationBar 可达性设计与执行任务包

- [2026-07-02-navigationbar-reachability-design.md](../specs/2026-07-02-navigationbar-reachability-design.md)
  - 设计如何让 Agent 看见并触发导航栏按钮。
  - 推荐方案：把导航栏按钮作为语义目标返回，并新增专门动作，不依赖 UIKit 私有 view。

- [claude-code-navigationbar-task.md](./claude-code-navigationbar-task.md)
  - 给 Claude Code 的执行任务包。
  - 约束实现范围、建议文件、错误码、测试命令和回报格式。

- [2026-07-02-navigationbar-reachability.md](../plans/2026-07-02-navigationbar-reachability.md)
  - navigationBar 可达性的实施计划。
  - 把设计拆成模型、检查器、动作命令、观察命令、注册、文档和验证任务。

### 2.7 `ui.tap` 结构化默认激活锚点

- [iOSExploreServer-ui-tap-design-rationale.md](../specs/iOSExploreServer-ui-tap-design-rationale.md)
  - 记录为什么保留 `ui.tap`，以及为什么它不能继续表示坐标点击、真实触摸注入或“找最近父 control”。
  - 这是由得物 AI UITester 文章触发的单点深挖：吸收“Agent 层动作语言”，但不复制截图/VLM/跨端 driver 路线。

- [iOSExploreServer-ui-tap-final-refactor-plan.md](../specs/iOSExploreServer-ui-tap-final-refactor-plan.md)
  - `ui.tap` 重构的决策基线：`viewSnapshotID`、canonical target、默认激活 route、`ui.screenshot` 不签发快照、`ui.wait snapshotChanged` 使用结构快照。

- [2026-07-02-ui-tap-structural-default-activation.md](../plans/2026-07-02-ui-tap-structural-default-activation.md)
  - 给 Claude Code 的实施计划。
  - 把重构拆成输入协议、snapshot 签发、semanticDigest、capability、executor、docs/tests 等任务。

## 3. 当前进度

| 阶段 | 状态 | 产物 | 说明 |
|---|---|---|---|
| 吸取得物文章经验 | 已完成第一轮 | 方向稿 | 已区分“吸收原则”和“不照搬实现”。 |
| 明确当前项目目标 | 已完成第一轮 | 方向稿 | 当前是 Agent MCP 应用探索服务，不是完整测试平台。 |
| 静态体检现有命令 | 已完成第一轮 | 命令体检稿 | 已按观察、动作、等待、截图、弹窗、导航分类评估。 |
| 建立文档入口地图 | 已完成第一版 | 本文件 | 后续所有关键讨论和进度都应挂到这里。 |
| 运行现有测试验证能力边界 | 已完成第一轮（历史基线） | [runtime-validation-2026-07-02.md](./runtime-validation-2026-07-02.md) | 该记录是 navigationBar 可达性和 `ui.tap` 结构化默认激活之前的历史基线：当时 SPM 185、framework 258 全过，主页 observe→act(scroll)→wait→observe 跑通，并暴露 navigationBar 不可达、旧 `ui.tap` 边界、`textExists` 只检测可见文本。前两项已在后续阶段补齐；`textExists` 可见性限制仍成立。 |
| 真实闭环复验 | 已完成第一轮 | [runtime-validation-2026-07-03.md](./runtime-validation-2026-07-03.md) | SPMExample + iPhone 17 模拟器真跑 `observe → navigation.tapBarButton → tap → waitAny → re-observe`；修了 curl 协议 `dryRun` 字段与 ControlTest switch 自翻转两个真机才暴露的问题；基线 SPM 210 / framework 310。 |
| 真机闭环计时（USB） | 已完成 | [runtime-validation-2026-07-03.md](./runtime-validation-2026-07-03.md) §7 | iPhone 16 Pro Max / iOS 26.5 真机闭环全通；viewTargets USB 往返 ~10ms（连续 8 次 8.7–14.5ms），证明 waitAny 命中后 re-observe 非瓶颈 → 方案 B 成立，不需要 returnObservation。 |
| 写 Agent 使用协议 | 已完成第一版 | [agent-usage-protocol.md](./agent-usage-protocol.md) | 已写清观察、动作、等待、重新观察、最终判断，以及 stale、ambiguous、wait_timeout、navigationBar 不可达等边界。 |
| 设计 navigationBar 可达性 | 已完成第一版 | [navigationbar 设计稿](../specs/2026-07-02-navigationbar-reachability-design.md) + [实施计划](../plans/2026-07-02-navigationbar-reachability.md) + [Claude Code 任务包](./claude-code-navigationbar-task.md) | 推荐把导航栏按钮作为语义目标返回，并新增 `ui.navigation.tapBarButton`，不依赖私有 view，不放宽坐标点击。 |
| 实现 navigationBar 可达性 | 已完成第一轮 | [navigationBar 设计稿](../specs/2026-07-02-navigationbar-reachability-design.md) + `ui.navigation.tapBarButton` | `ui.viewTargets` / `ui.topViewHierarchy` 响应现暴露 `navigationBar` 摘要；`ui.navigation.tapBarButton` 按 `placement + index` 触发 `UIBarButtonItem`，支持 `title` / `accessibilityIdentifier` 二次确认。执行核心按 selector 签名派发，避开 `UIApplication.sendAction` 在单测里不派发无参 action 的问题；该阶段回归基线为 SPM 196 + framework 290（后续 `ui.tap` 结构化默认激活与 `ui.waitAny` 已将基线推进到 SPM 210 + framework 310）。 |
| 设计 `ui.tap` 结构化默认激活 | 已完成 | [`ui.tap` 设计说明](../specs/iOSExploreServer-ui-tap-design-rationale.md) + [最终重构方案](../specs/iOSExploreServer-ui-tap-final-refactor-plan.md) + [实施计划](../plans/2026-07-02-ui-tap-structural-default-activation.md) | 由得物文章触发，明确 `ui.tap` 保留为 Agent 层默认动作，但不再表示坐标点击、真实触摸注入或 ancestor fallback。 |
| 实现 `ui.tap` 结构化默认激活 | 已完成第一轮 | `UITapInput` / `UIKitDefaultActivationResolver` / `UIKitActionExecutor` / `UIViewTargetsCollector` / snapshot 相关改造 | `ui.tap` 现在只接受 `accessibilityIdentifier` 或 `path` + 必填 `viewSnapshotID`；先校验 `ui.viewTargets` 签发的结构快照，再按 route 执行：按钮 `touchUpInside`、开关 toggle + `valueChanged`、文本输入 focus。`ui.screenshot` 不再签发快照；`ui.wait snapshotChanged` 使用 `viewSnapshotID`；`ui.viewTargets` 只签发最终返回 target 的 fingerprint。 |
| 设计多结果等待能力 | 已完成 | 决定新增命令而非改造 `ui.wait` | 保持 `ui.wait` 单条件不变；新增 `ui.waitAny` 一次轮询等待多个结局，命中后默认不返回页面快照，只回 `matchedID`/`matchedIndex`/`matchedMode`。 |
| 实现多结果等待能力 | 已完成 | `ui.waitAny`（`UIWaitAnyCommand` / `UIWaitAnyModels` / `UIWaitAnyExecutor`） | 与 `ui.wait` 共享五模式判断原语（`ConditionProbe`）；cancel 与瞬时层级不可用收敛到 `wait_timeout`；本阶段完整回归为 SPM 210 + framework 310。 |
| 弹窗 dryRun=false 触发 | 已完成 | [2026-07-03-alert-respond-dryrun-false-design.md](../specs/2026-07-03-alert-respond-dryrun-false-design.md) + [agent-usage-protocol.md](./agent-usage-protocol.md) §7 | `dryRun=false` 通过 Debug-only 私有方法 `_dismissWithAction:` 让系统自动 dismiss + 调 handler，simple/threeButtons/loginInput/actionSheet/nested 五案例真机验证通过；Release 下回退 `alert_button_required`（私有 API 被 `#if DEBUG` 隔离）。 |

## 3.1 协作执行方式

为了节省主会话额度，本轮后续按这个分工推进：

- 分析、评估、方向判断、关键文档沉淀，由当前会话负责。
- 大量源码实现、批量改造、长时间构建测试，交给 Claude Code 执行。
- Claude Code 执行前，当前会话应尽量给清楚任务包：目标、文件范围、验收命令、不能越界的地方。
- Claude Code 执行后，当前会话要看产物和真实输出，再决定是否进入下一步。

## 3.2 关键锚点：`ui.tap` 结构化默认激活是本轮能力改造的起点

本轮最初的总纲是“吸取得物 AI UITester 经验，重新确定 iOSExploreServer 方向”。其中第一个真正落到协议和源码的大改造，是 `ui.tap` 结构化默认激活。

后续分析、评估和继续改造，默认以这个锚点为基线，而不是以旧版“坐标 tap / hit-test / nearest UIControl fallback”语义为基线。

锚点定义：

```text
锚点：2026-07-03 ui.tap structural default activation
触发来源：得物 AI UITester 文章引发的点击语义讨论
设计文档：iOSExploreServer-ui-tap-design-rationale.md
执行基线：iOSExploreServer-ui-tap-final-refactor-plan.md
实施计划：2026-07-02-ui-tap-structural-default-activation.md
核心代码：UITapInput / UIKitDefaultActivationResolver / UIKitActionExecutor / UIViewTargetsCollector / UIKitSnapshotStore
```

这个锚点确立的协议边界：

- `ui.viewTargets` 是结构化 observe-first 的动作授权来源，返回 canonical targets、`availableActions` 和 `viewSnapshotID`。
- `viewSnapshotID` 只由 `ui.viewTargets` 签发；`ui.screenshot` 和 `ui.topViewHierarchy` 不签发、不刷新、不拥有该 ID。
- `ui.tap` 只作用于 `ui.viewTargets` 签发的 canonical target，输入为 `accessibilityIdentifier` 或 `path` 加必填 `viewSnapshotID`。
- `ui.tap` 是默认激活，不是触摸注入：`UIButton` → `touchUpInside`，`UISwitch` → toggle + `valueChanged`，文本输入 → focus。
- `UISlider`、`UISegmentedControl`、普通 view、gesture-only view、未知自定义 control 不拥有默认 `tap`；需要精确能力时走 `ui.control.sendAction` 或后续专用命令。
- `ui.control.sendAction` 保留为精确 UIKit event 工具，也必须携带 `viewSnapshotID` 并校验 freshness。
- `ui.wait snapshotChanged` 使用 `viewSnapshotID` 做结构指纹表变化等待；它仍是单条件等待，不等于多结果等待能力。

后续所有文档或源码评估，如果发现旧说法仍在暗示“截图签发 snapshot”“坐标点击兜底”“identifier 可绕过 freshness”“child label path 可借父 control 激活”，都应按本锚点修正。

## 4. 当前已经确定的判断

### 4.1 保留的方向

- 结构化观察优先于截图。
- `accessibilityIdentifier` 优先于 path。
- `path + viewSnapshotID` 可作为无稳定 identifier 时的安全定位方式；`accessibilityIdentifier + viewSnapshotID` 是更稳定的同等入口，两者都必须通过 freshness 校验。
- `viewSnapshotID` 只由 `ui.viewTargets` 签发，代表一次结构化 target 指纹快照；`ui.screenshot` / `ui.topViewHierarchy` 不再签发。
- `ui.viewTargets` 是动作前的轻量发现与授权层：返回 canonical interaction targets、语义文本、状态、`availableActions` 和 `viewSnapshotID`。它不再把普通 label、container、gesture-only view、仅有 identifier/a11y label 的普通 view 当作可执行 target。
- `ui.tap` 不再做坐标点击 / hit-test / ancestor fallback，只做"默认激活动作"（button/switch/可聚焦输入框）；无默认激活路由的目标（slider/segmented/普通 view/未知自定义 control）返回 `unsupported_target` 或只暴露精确 `control.*`。
- `ui.control.sendAction` 是精确 UIKit event 工具，不承担默认激活，也必须携带 `viewSnapshotID`。
- 导航栏按钮不并入 `ui.tap`，继续使用 `ui.navigation.tapBarButton`。
- 截图用于证据、人工排查、视觉辅助，不作为默认每一步主路径。
- `ui.tap` 成功只表示动作已发出，不表示测试步骤成功。

### 4.2 需要调整的方向

- 命令不能只是一堆零散工具，要有 Agent 使用协议。
- 动作后必须等待或重新观察。
- 等待能力要支持多个可能结果，而不是只等一个条件。
- 弹窗能力必须能支撑真实流程，否则 Agent 很容易被阻断。
- navigationBar / UIBarButtonItem 可达性已补齐（`ui.navigation.tapBarButton`，`ui.viewTargets`/`ui.topViewHierarchy` 暴露 `navigationBar` 摘要）。
- `ui.tap` 已重构为结构化默认激活；后续文档和评估必须以 3.2 锚点为基线，不再沿用旧坐标点击语义。
- `ui.wait textExists` 只检测当前可见文本，列表场景要先滚动并重新观察。

### 4.3 暂不做的方向

- 不做完整测试平台。
- 不做用例平台导入和批量用例生成。
- 不做测试报告和版本归档系统。
- 不把视觉模型放进 iPhone 端库。
- 不把每一步默认变成截图加视觉模型判断。

## 5. 关于是否需要运行测试项目

需要。

只读代码能判断“设计形状”，但不能证明实际能力边界。比如：

- `ui.tap` 在真实控件、遮挡、转场时是否稳定；
- `ui.wait` 的等待语义是否符合 Agent 使用；
- ~~`ui.alert.respond` 只能查询会卡住哪些流程~~（已解决，`dryRun=false` 已实现）；
- `ui.scrollToElement` 滚动后不签发 snapshot，对后续操作影响多大；
- `ui.screenshot` 的体积、速度、失败场景是否可接受；
- Example App 是否足够覆盖我们想让 Agent 走的闭环。

2026-07-02 已完成第一轮运行验证，记录见 [runtime-validation-2026-07-02.md](./runtime-validation-2026-07-02.md)。后续每次进入具体能力改造前，仍应按同样思路复验相关边界。

建议分三层：

1. 跑现有自动化测试。

   ```bash
   swift test
   ```

   目的：确认当前基础逻辑和 TCP 命令协议没有坏。

2. 跑 iOS framework 构建或测试。

   ```bash
   xcodebuild -project iOSExploreServer/iOSExploreServer.xcodeproj -scheme iOSExploreServer -sdk iphonesimulator build
   ```

   目的：确认 UIKit 模块和 framework 工程仍能编译。若本机模拟器环境不稳定，至少跑 generic iOS 构建或记录具体环境问题。

3. 跑示例 App 做真实闭环验证。

   目的不是验证“测试全绿”，而是亲自看一遍 Agent 真实会遇到的流程：

   ```text
   observe
   → tap/input/scroll/back
   → wait
   → observe again
   ```

   这一步尤其要验证弹窗、等待、滚动后重新观察、截图证据这些边界。

## 6. 下一步建议

`ui.tap` 结构化默认激活、navigationBar 可达性、`ui.waitAny`、`ui.alert.respond`（含 `dryRun=false` 真实触发）均已落地，并经模拟器 + 真机闭环验证。**当前阶段剩一件实质工作**：

### 6.1 Mac 侧 MCP server（让 agent 用 MCP 协议而非 curl 操作应用）

这是"让 agent 操作应用"的最后一公里：把 iPhone 端 18 个 HTTP action 包装成 MCP 工具，agent 通过标准 MCP 协议调用，不再 `curl` 裸打。其中 `ui.waitAny → ui.viewTargets` 的固定编排（命中后自动重新观察）在这一层用代码固化，不再靠协议自觉。

**真机计时已证明不需要 `returnObservation`**：USB 链路上一次 viewTargets 往返 **~10ms**（连续 8 次 8.7–14.5ms），相对 waitAny 秒级 timeout 占比 < 1%，round trip 不是瓶颈。方案 B（MCP 层编排）完全够用，iPhone 端 waitAny 响应保持只返回 matchedID。详见 [2026-07-03-final-observation-after-action.md](../specs/2026-07-03-final-observation-after-action.md)。**开建时的范围、已定约束与起点 checklist 见 [2026-07-03-mac-mcp-server-scope.md](../specs/2026-07-03-mac-mcp-server-scope.md)。**

### 6.2 ui.alert.respond dryRun=false（已完成）

`dryRun=false` 已实现：通过 Debug-only 私有方法 `UIAlertController._dismissWithAction:` 让系统像真人点按钮一样自动 dismiss + 调 handler，executor 不手动 dismiss，嵌套 present 也由系统协调。simple / 三按钮 / 输入框 / actionSheet / 嵌套两层五案例在 iPhone 17 模拟器 iOS 26.3.1 真机验证全部通过。Release 构建下私有 API 被 `#if DEBUG` 隔离，`dryRun=false` 回退 `alert_button_required`。详见 [2026-07-03-alert-respond-dryrun-false-design.md](../specs/2026-07-03-alert-respond-dryrun-false-design.md) 与 [agent-usage-protocol.md](./agent-usage-protocol.md) §7。

> 多结果等待（`ui.waitAny`）、动作后 final observation 归属（方案 B，不改 iPhone 端）均已结案；源码级 review + 真实闭环验证（原第一、第三优先级）已完成。
