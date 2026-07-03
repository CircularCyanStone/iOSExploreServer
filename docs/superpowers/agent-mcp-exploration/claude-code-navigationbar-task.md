# Claude Code 任务包：补 navigationBar / UIBarButtonItem 可达性

> 日期：2026-07-02
>
> **状态：历史执行包（勿按其中的步骤继续执行）。** navigationBar / UIBarButtonItem 可达性已落地：`ui.viewTargets` / `ui.topViewHierarchy` 响应均带 `navigationBar` 区块，`ui.navigation.tapBarButton` 按 `placement + index` 触发 `UIBarButtonItem`。文中 `swift test` 185 / framework 258 为当时基线，现已推进到 SPM 210 + framework 310。当前事实与下一步以 [README.md](./README.md) 为准。
>
> 这个任务包给 Claude Code 执行。当前会话负责分析、评估和验收；Claude Code 负责大量源码修改和长验证。

## 1. 背景

本项目当前目标不是做完整 Agent Tester 平台，而是做一个让 Agent 能持续观察 App、执行动作、拿到反馈、继续判断的 MCP 应用探索服务。

第一轮真实验证已经跑通三层：

- `swift test`：185 个测试全过；
- iOS framework build/test：258 个测试全过；
- Example App：主页 `observe → scroll → wait → observe` 跑通。

但真实运行暴露一个硬阻断：

```text
navigationBar / UIBarButtonItem 当前不可达。
ui.viewTargets 和 ui.topViewHierarchy 都看不到导航栏按钮。
ui.tap 坐标兜底命中 _UIModernBarButton 后又因为目标不是 UIControl 被拒绝。
```

结果：Agent 无法进入 Example App 的 `ControlTestViewController`。

## 2. 必读文档

执行前先读：

- `docs/superpowers/agent-mcp-exploration/README.md`
- `docs/superpowers/agent-mcp-exploration/agent-usage-protocol.md`
- `docs/superpowers/agent-mcp-exploration/runtime-validation-2026-07-02.md`
- `docs/superpowers/specs/2026-07-02-navigationbar-reachability-design.md`
- `AGENTS.md`

## 3. 实现目标

让 Agent 能：

```text
observe 当前页面
→ 看到 navigationBar 里的按钮
→ 用明确动作触发其中一个按钮
→ wait / observe again
→ 判断是否进入目标页面
```

本次只补 navigationBar / UIBarButtonItem 可达性，不做平台化，不做视觉模型，不重做全部命令。

## 4. 推荐实现方案

按设计稿采用“语义化导航栏按钮”方案：

1. `ui.viewTargets` 响应新增 `navigationBar` 区块。
2. `ui.topViewHierarchy` 响应也新增同样的 `navigationBar` 区块。
3. 新增动作命令：

   ```text
   ui.navigation.tapBarButton
   ```

4. 新命令按 `placement + index` 找当前 `UIBarButtonItem`，并用可选 `title` / `accessibilityIdentifier` 做二次确认。
5. 不允许坐标兜底。
6. 不依赖 `_UIModernBarButton` 这种 UIKit 私有 view。

## 5. 建议文件范围

优先只改这些文件或目录：

- `Sources/iOSExploreUIKit/Commands/Navigation/`
- `Sources/iOSExploreUIKit/Support/Action/`
- `Sources/iOSExploreUIKit/Support/Navigation/`
- `Sources/iOSExploreUIKit/Commands/ViewTargets/UIViewTargetsCollector.swift`
- `Sources/iOSExploreUIKit/Commands/TopViewHierarchy/UIViewHierarchyCollector.swift`
- `Sources/iOSExploreUIKit/UIKitCommandRegistrar.swift`
- `Tests/iOSExploreServerTests/`
- `Examples/SPMExample/SPMExample/ViewController.swift`
- `README.md`
- `AGENTS.md`
- `docs/runbooks/build-and-test.md`
- `docs/superpowers/agent-mcp-exploration/README.md`
- `docs/superpowers/agent-mcp-exploration/agent-usage-protocol.md`

不要改：

- `Sources/iOSExploreServer/` core；
- HTTP 协议；
- MCP 平台化设计；
- 现有 `ui.tap` 的安全边界。

## 6. 响应结构建议

`ui.viewTargets` 和 `ui.topViewHierarchy` 增加：

```json
{
  "navigationBar": {
    "available": true,
    "title": "首页",
    "topViewController": "ViewController",
    "leftItems": [],
    "rightItems": [
      {
        "placement": "right",
        "index": 0,
        "title": "控件测试",
        "accessibilityIdentifier": "example.controlTest",
        "isEnabled": true,
        "availableActions": ["ui.navigation.tapBarButton"]
      }
    ],
    "backAvailable": false
  }
}
```

字段可以按实现需要微调，但必须保持普通开发者能读懂。

## 7. 新命令输入建议

```json
{
  "placement": "right",
  "index": 0,
  "title": "控件测试",
  "accessibilityIdentifier": "example.controlTest",
  "waitAfterMs": 300
}
```

规则：

- `placement` 必填：`left` 或 `right`；
- `index` 必填；
- `title` 可选，但传入时必须一致；
- `accessibilityIdentifier` 可选，但传入时必须一致；
- `waitAfterMs` 默认 300ms，范围建议 0...3000。

## 8. 错误码建议

按设计稿补明确错误：

- `navigation_bar_unavailable`
- `navigation_bar_item_not_found`
- `navigation_bar_item_mismatch`
- `navigation_bar_item_disabled`
- `navigation_bar_item_unsupported`

错误要走现有 `UIKitCommandError` / `ExploreResult` 模式，不要在调用点散写 envelope。

## 9. 测试要求

至少补这些测试：

- input schema 包含 `ui.navigation.tapBarButton`；
- registrar/help 注册新命令；
- navigationBar summary 能列出 right/left items；
- disabled item 不会被触发；
- title / identifier mismatch 返回明确错误；
- target-action 型 `UIBarButtonItem` 能触发；
- customView 为 `UIControl` 时能触发；
- `ui.viewTargets` 返回 `navigationBar` 区块；
- `ui.topViewHierarchy` 返回 `navigationBar` 区块。

## 10. 验收命令

执行并记录真实输出尾部：

```bash
swift test
```

然后跑 iOS framework 测试：

```bash
xcodebuild -project iOSExploreServer/iOSExploreServer.xcodeproj -scheme iOSExploreServer -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' test
```

如果模拟器名不同，先列出实际可用模拟器并说明替换原因。

最后做 Example App 闭环：

```text
ui.viewTargets
→ 找到 navigationBar.rightItems[0] “控件测试”
→ ui.navigation.tapBarButton
→ ui.wait 或 ui.viewTargets
→ 证明进入 ControlTestViewController
```

## 11. 完成后必须回报

回报时请给：

- 改了哪些文件；
- 新增 action 名称；
- `help` 里当前 action 总数；
- `swift test` 实际测试数和尾部输出；
- iOS framework test 实际测试数和尾部输出；
- Example App 闭环是否进入 `ControlTestViewController`；
- 如果没跑成，说明是代码问题还是环境问题。

不要只说“完成”。
