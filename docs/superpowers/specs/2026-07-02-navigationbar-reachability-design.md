# navigationBar / UIBarButtonItem 可达性设计

> 日期：2026-07-02
>
> 本文处理运行验证暴露的硬阻断：Agent 当前看不到、也点不了导航栏里的按钮。这里的 navigationBar 指 iOS 页面顶部由 `UINavigationController` 管理的导航栏；`UIBarButtonItem` 指导航栏左侧或右侧的按钮项，例如“完成”“编辑”“筛选”“控件测试”。

## 1. 问题是什么

第一轮真实闭环验证发现：

```text
ui.viewTargets 看不到导航栏按钮；
ui.topViewHierarchy 也看不到导航栏按钮；
坐标点击虽然能 hit-test 到 _UIModernBarButton，
但 ui.tap 认为它不是 UIControl，于是拒绝执行。
```

这不是小问题。很多真实 App 的关键入口都放在导航栏里：

- 完成；
- 编辑；
- 筛选；
- 更多；
- 发布；
- 保存；
- 测试页入口。

如果 Agent 看不到这些按钮，自然语言测试案例就会卡住。例如 Example App 当前无法进入 `ControlTestViewController`，因为入口在导航栏按钮上。

## 2. 根因

当前观察命令都从顶部控制器的 `rootView` 开始遍历普通 view 树：

- `ui.viewTargets` 在 `UIViewTargetsCollector.collect` 里从 `context.rootView` 递归 subviews；
- `ui.topViewHierarchy` 在 `UIViewHierarchyCollector.collectTopViewHierarchy` 里也只把 `context.rootView` 建成树；
- `ui.tap` 的 path 定位也只在 `context.rootView` 下解析 `root/0/1` 这类路径。

导航栏不是顶部控制器 `rootView` 的普通子 view。它由 `UINavigationController` 管理，按钮本身又是 `UIBarButtonItem`，不是普通 `UIView`。

所以当前工具不是“找得不准”，而是从入口上就没有把导航栏纳入可观察范围。

## 3. 设计目标

本次只解决一个目标：

```text
Agent 能看到当前页面的导航栏按钮，
并能用安全、明确的方式触发其中一个按钮。
```

成功标准：

- `ui.viewTargets` 或同级观察结果里能返回导航栏按钮；
- Agent 能知道按钮在左侧还是右侧、下标、标题、是否可用；
- Agent 能用稳定字段触发按钮，不依赖私有 view 类型；
- 按钮不可用、按钮已经变化、按钮不存在时，工具明确失败；
- Example App 能通过这个能力进入 `ControlTestViewController`；
- 文档和测试数同步更新。

## 4. 不做什么

本次不做：

- 不做完整测试平台；
- 不引入视觉模型；
- 不把每一步默认改成截图识别；
- 不把 `ui.tap` 放宽成“只要坐标命中就乱点”；
- 不依赖 `_UIModernBarButton` 这类 UIKit 私有类型；
- 不重做整个 path 定位系统；
- 不把所有导航行为都塞进一个万能命令。

## 5. 可选方案

### 方案 A：让 `ui.tap` 允许点击 `_UIModernBarButton`

做法：坐标 hit-test 到导航栏内部 view 后，放宽能力检查，允许这类 view 被点击。

优点：

- 改动看起来小；
- 可能很快绕过当前 Example App 阻断。

问题：

- Agent 仍然看不到导航栏按钮，只能靠坐标猜；
- `_UIModernBarButton` 是 UIKit 私有实现，系统版本变化后可能失效；
- 点击内部 view 不一定等价于触发对应 `UIBarButtonItem`；
- 会破坏当前“目标不确定就不点”的安全原则。

结论：

```text
不推荐。
```

### 方案 B：把导航栏内部 view 合并进普通 view 树

做法：采集时不再只从 `topViewController.view` 开始，而是把 `navigationController.view` 或 `navigationBar` 的 subviews 也纳入 `root/0/1` 路径。

优点：

- `ui.viewTargets` 和 `ui.topViewHierarchy` 仍然像现在一样返回 path；
- 表面上与现有定位体系统一。

问题：

- 导航栏内部 view 层级同样属于 UIKit 实现细节；
- path 会混入页面 root 和导航栏 root，语义变复杂；
- `UIBarButtonItem` 不是 view，仍然不能保证 path 对应到业务按钮项；
- 陈旧校验和 fingerprint 口径要一起改，容易扩大影响。

结论：

```text
不作为第一步。
```

### 方案 C：把导航栏按钮作为“语义目标”暴露，并新增专门动作

这里的“语义目标”意思是：不要把按钮伪装成普通 view path，而是明确告诉 Agent：

```text
这是导航栏右侧第 0 个按钮；
标题是“控件测试”；
当前可用；
可用动作是 ui.navigation.tapBarButton。
```

做法：

- 观察命令返回一个 `navigationBar` 区块；
- 区块里列出 left/right 按钮；
- 新增动作 `ui.navigation.tapBarButton`；
- 动作按 `placement + index` 找按钮，并用 title / identifier 做二次确认；
- 触发时直接走 `UIBarButtonItem` 的 target-action，或 customView 的 UIControl action。

优点：

- Agent 能看见导航栏按钮；
- 不依赖私有 view；
- 不污染普通 `root/0/1` path 语义；
- 能清楚区分“普通 view 点击”和“导航栏按钮触发”；
- 失败可以分类清楚：按钮不存在、按钮不可用、按钮已变化、按钮没有可触发动作。

代价：

- 要新增一个动作命令；
- Agent 使用协议需要说明：导航栏按钮不要用 `ui.tap`，要用专门动作。

结论：

```text
推荐。
```

## 6. 推荐设计

采用方案 C。

### 6.1 观察返回

在 `ui.viewTargets` 响应中新增顶层字段：

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

字段解释：

- `available`：当前顶部控制器是否在导航控制器里；
- `title`：当前导航栏标题；
- `leftItems` / `rightItems`：显式配置的左右按钮；
- `placement`：按钮在左侧还是右侧；
- `index`：按钮在当前侧的下标；
- `title`：按钮标题，可能为空；
- `accessibilityIdentifier`：如果业务设置了稳定标识，就返回；
- `isEnabled`：按钮当前是否可用；
- `availableActions`：Agent 应该使用的动作。

`ui.topViewHierarchy` 也建议返回同样的 `navigationBar` 区块。这样深度排查时不会再出现“viewTargets 能看到、topViewHierarchy 看不到”的分叉。

### 6.2 动作命令

新增命令：

```text
ui.navigation.tapBarButton
```

输入建议：

```json
{
  "placement": "right",
  "index": 0,
  "title": "控件测试",
  "accessibilityIdentifier": "example.controlTest",
  "waitAfterMs": 300
}
```

字段规则：

- `placement` 必填：`left` 或 `right`；
- `index` 必填：从 0 开始；
- `title` 可选：如果传入，执行前必须和当前按钮标题一致；
- `accessibilityIdentifier` 可选：如果传入，执行前必须和当前按钮 identifier 一致；
- `waitAfterMs` 默认 300ms，用于等待页面转场稳定。

为什么要传 `title` / `accessibilityIdentifier`：

```text
placement + index 只能说明“当前位置”；
title / identifier 能防止页面已经变化后点错按钮。
```

### 6.3 触发方式

执行器按下面顺序处理：

1. 重新读取当前顶部控制器和 navigationItem；
2. 按 `placement + index` 找到当前 `UIBarButtonItem`；
3. 校验 `isEnabled`；
4. 如果请求带了 title / identifier，做一致性校验；
5. 如果是 `customView` 且它是 `UIControl`，发送 `.touchUpInside`；
6. 否则如果 `UIBarButtonItem` 有 `action`，用 `UIApplication.shared.sendAction` 触发；
7. 触发后等待 `waitAfterMs`；
8. 返回 `performed=true`、按钮摘要、`topBefore/topAfter`。

如果以上条件不满足，要返回明确业务错误，不要坐标兜底。

### 6.4 错误码建议

新增或复用这些错误：

| code | 普通解释 | Agent 应该怎么做 |
|---|---|---|
| `navigation_bar_unavailable` | 当前页面没有导航栏 | 重新观察，确认是不是已经跳转或不是导航页面 |
| `navigation_bar_item_not_found` | 指定侧和下标没有按钮 | 重新观察，不要重试旧输入 |
| `navigation_bar_item_mismatch` | 标题或 identifier 和观察时不一致 | 重新观察，说明页面已经变了 |
| `navigation_bar_item_disabled` | 按钮存在但不可用 | 不要点，观察页面状态或等待 |
| `navigation_bar_item_unsupported` | 按钮存在但没有可触发动作 | 记录能力缺口，必要时宿主补自定义 action |

### 6.5 为什么不直接扩展 `ui.tap`

短期不建议让 `ui.tap` 同时处理普通 view、坐标、导航栏按钮。

原因：

- `ui.tap` 当前语义是“对 UIView 目标执行点击”；
- 导航栏按钮本质是 `UIBarButtonItem`，不是普通 view；
- 混进 `ui.tap` 会让 locator 字段变复杂；
- Agent 出错时不容易区分是普通 view 失败，还是导航栏按钮失败。

等语义目标稳定后，未来可以再考虑统一成更高层的 `ui.activate`，但这不是本次目标。

## 7. 文件范围建议

建议 Claude Code 只改这些区域：

- `Sources/iOSExploreUIKit/Commands/Navigation/`
  - 新增 `UINavigationBarButtonModels.swift`
  - 新增 `UINavigationBarButtonCommand.swift`
- `Sources/iOSExploreUIKit/Support/Action/`
  - 新增 `UINavigationBarButtonExecutor.swift`
- `Sources/iOSExploreUIKit/Support/Navigation/`
  - 新增 `UINavigationBarInspector.swift`
- `Sources/iOSExploreUIKit/Commands/ViewTargets/UIViewTargetsCollector.swift`
  - 响应里追加 `navigationBar` 字段；
- `Sources/iOSExploreUIKit/Commands/TopViewHierarchy/UIViewHierarchyCollector.swift`
  - 响应里追加 `navigationBar` 字段；
- `Sources/iOSExploreUIKit/UIKitCommandRegistrar.swift`
  - 注册新 action；
- `Tests/iOSExploreServerTests/`
  - 补模型解析、schema、inspector、executor、registrar/help 测试；
- `Examples/SPMExample/SPMExample/ViewController.swift`
  - 给“控件测试”导航栏按钮补稳定 `accessibilityIdentifier`，方便 Agent 使用；
- 文档：
  - `README.md`
  - `AGENTS.md`
  - `docs/runbooks/build-and-test.md`
  - `docs/superpowers/agent-mcp-exploration/README.md`
  - `docs/superpowers/agent-mcp-exploration/agent-usage-protocol.md`

不要改 core 的 `Sources/iOSExploreServer/`。

## 8. 测试要求

至少需要这些验证：

1. `swift test`
   - 目标：macOS SPM 模型、解析、注册、schema 测试全过。

2. iOS framework 测试
   - 目标：UIKit 真类型、`UIBarButtonItem` target-action、customView UIControl、disabled、mismatch 都覆盖。

3. Example App 真实闭环
   - 目标：通过 `ui.viewTargets` 看到“控件测试”导航栏按钮；
   - 调 `ui.navigation.tapBarButton` 进入 `ControlTestViewController`；
   - 再 `ui.viewTargets` 或 `ui.wait textExists` 证明目标页面出现。

## 9. 与 Agent 使用协议的关系

协议需要更新为：

```text
普通页面目标：优先 identifier，其次 path + snapshotID，再其次坐标兜底。
导航栏按钮：不要用 ui.tap，不要坐标硬点；使用 ui.navigation.tapBarButton。
```

导航栏按钮动作后，仍然不能直接判定测试通过。Agent 仍要：

```text
tapBarButton
→ wait 或 observe again
→ 根据最终页面证据判断
```

## 10. 设计结论

本次不推翻现有 UIKit 命令体系。

正确改法是补一条旁路能力：

```text
观察命令暴露 navigationBar 语义目标；
动作命令按语义触发 UIBarButtonItem；
失败时给 Agent 明确错误分类；
动作后继续按协议等待或重新观察。
```

这能解决当前硬阻断，同时不破坏已有普通 view 的 path、snapshotID 和安全点击规则。
