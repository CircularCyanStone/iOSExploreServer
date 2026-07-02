# Agent MCP 应用探索服务改造地图

> 日期：2026-07-02
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
    - `ui.alert.respond` 当前只能查询，不能真正响应弹窗。

### 2.4 运行验证记录

- [runtime-validation-2026-07-02.md](./runtime-validation-2026-07-02.md)
  - 三层验证记录：`swift test`、iOS framework build/test、Example App 真实闭环。
  - 结果：SPM 185 个测试全过；framework 258 个测试全过；主页 `observe → scroll → wait → observe` 跑通。
  - 新发现：
    - navigationBar / UIBarButtonItem 当前不可达；
    - `ui.tap` 对非 `UIControl` 的 UIBarButtonItem 内部视图会拒绝；
    - `ui.wait textExists` 只检测当前可见文本。

### 2.5 Agent 使用协议

- [agent-usage-protocol.md](./agent-usage-protocol.md)
  - 说明 Agent 应该如何组合现有命令。
  - 明确：`observe → act → wait/observe again → judge` 是默认闭环。
  - 明确：动作成功不等于测试通过；测试是否通过必须看最终页面证据。
  - 明确：navigationBar 当前不可达、`textExists` 只查当前可见文本、弹窗当前只能查询。

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

## 3. 当前进度

| 阶段 | 状态 | 产物 | 说明 |
|---|---|---|---|
| 吸取得物文章经验 | 已完成第一轮 | 方向稿 | 已区分“吸收原则”和“不照搬实现”。 |
| 明确当前项目目标 | 已完成第一轮 | 方向稿 | 当前是 Agent MCP 应用探索服务，不是完整测试平台。 |
| 静态体检现有命令 | 已完成第一轮 | 命令体检稿 | 已按观察、动作、等待、截图、弹窗、导航分类评估。 |
| 建立文档入口地图 | 已完成第一版 | 本文件 | 后续所有关键讨论和进度都应挂到这里。 |
| 运行现有测试验证能力边界 | 已完成第一轮 | [runtime-validation-2026-07-02.md](./runtime-validation-2026-07-02.md) | SPM `swift test` 185 个、framework `xcodebuild test` 258 个全过；主页 observe→act(scroll)→wait→observe 闭环跑通；实测暴露 3 个体检稿未提及的边界：navigationBar/UIBarButtonItem 完全不可达、`ui.tap` 拒绝非 UIControl、`textExists` 只检测可见文本。结论：先写 Agent 使用协议，navigationBar 可达性补齐优先级上调。 |
| 写 Agent 使用协议 | 已完成第一版 | [agent-usage-protocol.md](./agent-usage-protocol.md) | 已写清观察、动作、等待、重新观察、最终判断，以及 stale、ambiguous、wait_timeout、navigationBar 不可达等边界。 |
| 设计 navigationBar 可达性 | 已完成第一版 | [navigationbar 设计稿](../specs/2026-07-02-navigationbar-reachability-design.md) + [实施计划](../plans/2026-07-02-navigationbar-reachability.md) + [Claude Code 任务包](./claude-code-navigationbar-task.md) | 推荐把导航栏按钮作为语义目标返回，并新增 `ui.navigation.tapBarButton`，不依赖私有 view，不放宽坐标点击。 |
| 实现 navigationBar 可达性 | 已完成第一轮 | [navigationBar 设计稿](../specs/2026-07-02-navigationbar-reachability-design.md) + `ui.navigation.tapBarButton` | `ui.viewTargets` / `ui.topViewHierarchy` 响应现暴露 `navigationBar` 摘要；`ui.navigation.tapBarButton` 按 `placement + index` 触发 `UIBarButtonItem`，支持 `title` / `accessibilityIdentifier` 二次确认。SPM 190 + framework 269 全绿；执行核心按 selector 签名派发，避开 `UIApplication.sendAction` 在单测里不派发无参 action 的问题。 |
| 设计多结果等待能力 | 未开始 | 待补 | 需要决定是新增命令还是改造现有 `ui.wait`。 |
| 修正弹窗能力 | 未开始 | 待补 | 需要决定改名为 query，还是补齐 respond。 |

## 3.1 协作执行方式

为了节省主会话额度，本轮后续按这个分工推进：

- 分析、评估、方向判断、关键文档沉淀，由当前会话负责。
- 大量源码实现、批量改造、长时间构建测试，交给 Claude Code 执行。
- Claude Code 执行前，当前会话应尽量给清楚任务包：目标、文件范围、验收命令、不能越界的地方。
- Claude Code 执行后，当前会话要看产物和真实输出，再决定是否进入下一步。

## 4. 当前已经确定的判断

### 4.1 保留的方向

- 结构化观察优先于截图。
- `accessibilityIdentifier` 优先于 path。
- `path + snapshotID` 可作为无稳定 identifier 时的安全定位方式。
- 坐标点击只能作为最后兜底。
- 截图用于证据、人工排查、视觉辅助，不作为默认每一步主路径。
- `ui.tap` 成功只表示动作已发出，不表示测试步骤成功。

### 4.2 需要调整的方向

- 命令不能只是一堆零散工具，要有 Agent 使用协议。
- 动作后必须等待或重新观察。
- 等待能力要支持多个可能结果，而不是只等一个条件。
- 弹窗能力必须能支撑真实流程，否则 Agent 很容易被阻断。
- navigationBar / UIBarButtonItem 目前不可达，需要补观察和操作能力。
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
- `ui.alert.respond` 当前只能查询，这在真实 App 里会卡住哪些流程；
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

下一步交给 Claude Code 实现 navigationBar / UIBarButtonItem 可达性。

原因：运行验证已经证明，这不是小体验问题，而是硬阻断。很多真实 App 的“完成”“编辑”“筛选”“更多”“返回右侧入口”等按钮都在 navigationBar 上。Agent 当前既看不到这些按钮，也不能用现有 `ui.tap` 安全点击它们。

任务包已经写好：[claude-code-navigationbar-task.md](./claude-code-navigationbar-task.md)。

navigationBar 补齐后，再设计“多结果等待并返回最终页面”的能力。
