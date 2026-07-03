# Agent MCP 运行验证记录

> 日期：2026-07-02
> 关联：[README.md](./README.md) / [命令体检稿](../specs/2026-07-02-agent-mcp-command-health-check.md) / [方向稿](../specs/2026-07-02-agent-mcp-app-exploration-direction.md)
>
> 目的：本轮不改代码，验证当前 `iOSExploreServer` / `iOSExploreUIKit` 的实际能力边界，确认能否支撑 Agent 的 `observe → act → wait → observe again` 闭环。结论以当前源码和真实运行结果为准，不只凭旧设计文档。
>
> 当前状态说明：这是 `5b9885a feat(uikit): 重构 ui.tap 默认激活链路` 之前的历史验证记录。文中 `snapshotID`、坐标 `ui.tap`、navigationBar 不可达、12 个 `ui.*` action 等描述只反映 2026-07-02 当时状态；当前协议以 `viewSnapshotID`、`ui.viewTargets` 唯一签发、`ui.tap` 默认激活、navigationBar 专用动作和 14 个 `ui.*` 命令为准。当前可运行闭环见 [curl-json-loop-protocol.md](./curl-json-loop-protocol.md)。

## 1. 环境

- 仓库：iOSExploreServer @ main（HEAD: `ecc908a`）
- 机器：macOS Darwin 25.5.0，Xcode 17C52，iOS 26.2 simulator SDK
- 模拟器：iPhone 17（iOS 26.3，Booted，UDID `065CC8DB-…`）

## 2. 第一层：SPM 测试

命令：`swift test`

结果：**185 个测试全部通过**，6 个 suites，总耗时 0.288 秒。

真实输出尾部：

```
✔ Test "stopAndWait 后新 server 可立即复用端口" passed after 0.006 seconds.
✔ Test "端到端 ping 经真实 TCP 往返" passed after 0.001 seconds.
✔ Test "超过连接上限时拒绝新连接并返回 503" passed after 0.204 seconds.
✔ Suite IntegrationTests passed after 0.287 seconds.
✔ Test run with 185 tests in 6 suites passed after 0.288 seconds.
```

判断：基础逻辑（HTTP 解析/路由/envelope/typed input/统一错误工厂/UIKit 模型与解析/snapshot store）全绿。无源码问题、无端口冲突、无环境问题。集成测试串行用端口 38399 全部通过。

## 3. 第二层：framework 构建与测试

构建命令：

```bash
xcodebuild -project iOSExploreServer/iOSExploreServer.xcodeproj \
           -scheme iOSExploreServer -sdk iphonesimulator \
           -destination 'generic/platform=iOS Simulator' build
```

结果：**BUILD SUCCEEDED**（`iOSExploreServer.framework` + `iOSExploreUIKit.framework`，arm64 + x86_64 双架构，iOS 26.2 simulator SDK）。

测试命令（用已 Booted 的 iPhone 17）：

```bash
xcodebuild -project iOSExploreServer/iOSExploreServer.xcodeproj -scheme iOSExploreServer \
           -sdk iphonesimulator \
           -destination 'platform=iOS Simulator,name=iPhone 17' test
```

结果：**258 个测试全部通过**，7 个 suites，`** TEST SUCCEEDED **`（2.888s）。

真实输出尾部：

```
✔ Test "screenshot: base64 估算超限返回 responseTooLarge" passed after 1.242 seconds.
✔ Test "registerUIKitCommands 后 help 经 HTTP 含 12 个 ui.* action" passed after 0.062 seconds.
✔ Test "响应 body 超限时改发 response_too_large envelope" passed after 0.017 seconds.
✔ Suite IntegrationTests passed after 1.277 seconds.
✔ Test run with 258 tests in 7 suites passed after 1.384 seconds.
** TEST SUCCEEDED **
```

判断：UIKit 真实执行路径在 iOS 模拟器全绿——hit-test tap、`sendActions(for:)`、`scrollRectToVisible`、wait 轮询、screenshot base64 解码与降采样、snapshot 陈旧判定、`registerUIKitCommands` 12 个 ui.* 正向注册断言均通过。

> 文档校对：本次验证时发现 `AGENTS.md`、`README.md`、`docs/runbooks/build-and-test.md` 的测试数量为旧值；已在后续处理里同步为 SPM 185、framework 258。

## 4. 第三层：Example App 真实闭环

### 4.1 启动方式（含临时验证钩子，已恢复）

`SPMExample` 的 server 监听绑在主页「启动 Server」按钮，该按钮无 `accessibilityIdentifier`；进入 `ControlTestViewController` 的入口是导航栏「控件测试」`UIBarButtonItem`。

本环境 `XcodeBuildMCP` 只启用了 simulator workflow 工具，UI 点击（tap/type/swipe）未启用；`simctl` 无原生 tap 能力；`SPMExampleUITests` 是空壳模板。为不修改产品行为地启动 server，给 `ViewController.swift` 加了**环境变量门控的临时自动启动钩子**（仅 `AUTO_START_SERVER=1` 时在 `viewDidLoad` 末尾自动 `server.start()`），验证完用 `git checkout` 完全恢复，并 `grep` 确认无 `RUNTIME-VALIDATION-TEMP` 残留。

启动链路与首次响应：

```
xcrun simctl install booted /tmp/SPMExample-dd/.../SPMExample.app
SIMCTL_CHILD_AUTO_START_SERVER=1 xcrun simctl launch booted com.coo.SPMExample
# App PID 41370；ping 第 2 次重试返回：
{"code":"ok","data":{"pong":true}}
```

`help` 返回 `data.commands` 共 18 个 action（4 内置 + 12 个 ui.* + greet + device）。

### 4.2 observe → act → wait → observe 闭环（主页）

| 步骤 | 命令 | 真实结果 |
|---|---|---|
| observe | `ui.viewTargets` | `snap-9`，20 个目标 |
| act | `ui.scroll direction=down amount=2` | `container=UITableView`，`offsetBefore.y=0 → offsetAfter.y=2`，`reachedExtent=left` |
| wait | `ui.wait mode=idle stableMs=300 timeoutMs=3000` | `satisfied=true`，5 轮，419ms |
| wait | `ui.wait mode=textExists text=POST timeoutMs=2000` | `satisfied=true`，1 轮，0ms（立即可见） |
| observe again | `ui.viewTargets` | `snap-10`（snapshotID 变化，证明检测到画面变化） |
| screenshot | `ui.screenshot` | `snap-11`，589×1280 @scale=3，base64 约 149 KB |

闭环链路通畅。`scroll` 的 `amount=2` 实测位移很小（offset 0→2）；`reachedExtent=left` 是水平边界标记，垂直小位移时也会出现，amount 语义偏「轻推一下」，Agent 用时需注意量纲。screenshot 单张约 150 KB，对 Agent 可接受，但不能默认每步截。

### 4.3 关键边界发现（真实运行暴露，体检稿未提及）

#### 发现 1：UINavigationBar / UIBarButtonItem 完全不在结构化采集树

`ui.topViewHierarchy` 遍历 `keyWindow.rootView` 子树。`UINavigationController` 的 navigationBar 不在 child VC 的 `rootView` 子树内，因此「控件测试」`UIBarButtonItem`：

- 在 `topViewHierarchy`（maxDepth=8）里**采不到**——按 `Bar`/`Button`/`控件` 搜索 0 命中，只找到主页两个普通 `UIButton`（「启动 Server」「停止」）。
- 在 `viewTargets` 里**不存在**。

影响：任何带 NavigationBar 的页面，Agent **看不到、也定位不到**导航栏按钮（编辑/完成/筛选/返回等高频按钮）。这是当前工具层的真实断点。

#### 发现 2：`ui.tap` 因 capability 校验无法点击 UIBarButtonItem

坐标兜底点击「控件测试」(x=359, y=76)：

```
ui.tap {"x":359,"y":76}
→ {"code":"invalid_data","message":"requested action is not supported for target"}
```

`UIBarButtonItem` 内部视图 `_UIModernBarButton` 不是 `UIControl`，`UIKitActionCapabilityResolver` 拒绝。即使坐标命中，也无法点击。

影响：发现 1 + 发现 2 叠加，导致**本次验证无法进入 `ControlTestViewController`**（那里才有带 identifier 的 `test.button` 等控件）。`ui.input` 写入反馈、`scrollToElement` 列表、真实 `alert` 弹窗等场景本次只能由第二层的 258 个 framework 测试背书，未在闭环里亲历。

#### 发现 3：`ui.wait textExists` 只检测当前可见文本

闭环里 `textExists "started"` 超时，但 `textExists "POST"` 立即满足。排查：

`topViewHierarchy` 提取出 16 个可见 `UILabel` 文本——「● 监听中 :38321」「← POST action=ui.viewTargets」「→ 200 ok=true」等，其中**没有**「started」。最早的 `started :38321` 日志已被新日志 `insert(at: 0)` 推到底部、并被 cell 复用机制回收，滚出可视区。

影响：`textExists` 检测的是 `UIKitVisibleTextCollector` 当前可见文本。目标文本若需滚动才出现，Agent 必须「先 scroll 再 wait」——但 scroll 后旧 `snapshotID` 又会陈旧。协议必须写清。

### 4.4 边界错误场景（验证错误分类）

| 命令 | 场景 | 真实返回 |
|---|---|---|
| `ui.alert.respond dryRun=true` | 当前无 `UIAlertController` | `code: alert_unavailable`（`message: alert unavailable`） |
| `ui.navigation.back strategy=auto` | 已在 root VC，无上页 | `code: navigation_back_unavailable` |
| `ui.keyboard.dismiss` | 无 first responder | `code: ok` + `dismissed: false`（非失败，是「无需操作」） |

错误分类清晰，Agent 能据 `code` 决策下一步。✅

## 5. 失败或跳过的部分

| 项 | 状态 | 原因 |
|---|---|---|
| 进入 `ControlTestViewController` | 跳过 | 发现 1+2：BarButtonItem 结构化采集缺失 + `ui.tap` capability 拒绝，无路可达 |
| 真实弹窗验证 | 跳过 | 主页无触发入口，且无法进入子页（同上）；仅 `alert.respond` 无弹窗分支已验证 |
| `ui.input` 写入反馈实跑 | 跳过 | 同上，未进入 `test.textfield` 所在页 |
| `ui.tap` 点击「启动 Server」 | 未做 | server 已在运行，点击会触发重复 `start()`（副作用不可控）；改用 `ui.scroll` 作安全 act |
| `XcodeBuildMCP` UI 点击 | 不可用 | 本环境只启用 simulator workflow tools，`ui_tap`/`ui_type`/`ui_swipe` 未启用 |

说明：上述跳过的命令在第二层 258 个 framework 测试里有真实 UIKit 执行断言覆盖，只是没在本次"主页闭环"里亲历组合。

## 6. 当前能力边界（实测汇总）

**能做：**

- 结构化 observe：`viewTargets` / `topViewHierarchy` / `screenshot`（均签发 `snapshotID`）
- 安全 act：`tap`（identifier / path / 坐标，限 `UIControl`）/ `control.sendAction` / `input` / `scroll` / `scrollToElement` / `keyboard.dismiss` / `navigation.back`
- 单条件 wait：`idle` / `targetExists` / `targetGone` / `textExists`（仅可见文本）/ `snapshotChanged`（whole-table 指纹比对）
- 清晰错误分类：`alert_unavailable` / `navigation_back_unavailable` / `stale_locator` / `target_not_found` / `wait_timeout` / `response_too_large` 等

**做不到 / 有坑：**

- **navigationBar 内所有按钮不可达**（采集缺失 + tap capability 拒绝，发现 1+2）
- **`alert.respond` 只能查询，不能真点击**（`dryRun=false` 抛 `alertButtonRequired`，体检稿已提）
- **`scrollToElement` 不签发 snapshot**，滚动后必须重新 observe（体检稿已提）
- **`textExists` 只见可见文本**（发现 3，体检稿未明确）
- **`ui.wait` 是单条件**（体检稿已提）
- **截图约 150 KB/张**，每步截图成本高（体检稿建议非默认，实测体积支持该判断）
- Example App 主页控件**无 `accessibilityIdentifier`**（仅 `ControlTest` 子页有），且 `ViewController.swift:58-60` 注释只列 4 个命令，实际注册 12 个——注释滞后，功能完整

## 7. 对命令体检稿的修正意见

体检稿（`2026-07-02-agent-mcp-command-health-check.md`）整体准确，本次运行**新增/强化**：

1. **新增「navigationBar 不可达」风险**：体检稿只说「identifier 优先、path 兜底、坐标最后」，没提 `UIBarButtonItem` 这类系统控件当前**完全不可达**。应单列一条风险，并在 Agent 协议里写清「导航栏按钮需宿主提供替代入口（自定义 action 或专用命令）」。
2. **强化 `textExists` 可见性限制**：体检稿只说「不含用户输入」，应补「只检测当前可见文本，滚出可视区的目标检测不到；Agent 应先确保目标可见再 wait」。
3. **截图体积量化**：体检稿说「截图用于证据」，本次实测单张 ~150 KB（降采样后），为「不能每步截」提供了量化依据。
4. **`alert.respond` / `scrollToElement` / `ui.wait` 单条件**：体检稿描述准确，本次运行未推翻。
5. **错误分类**：体检稿第 4 节「失败要先分类」，本次 `alert_unavailable` / `navigation_back_unavailable` 实测确认分类清晰，方向正确。

## 8. 下一步建议

### 8.1 先写 Agent 使用协议（README 与本次验证一致结论）

协议必须写清本次发现的边界：

- 每步先 observe；
- identifier 优先；path 配 `snapshotID`；
- **导航栏按钮当前不可达**——遇到需宿主补 action 或等后续补采集；
- **`textExists` 目标需可见**——等不到先 scroll 再 observe 再 wait；
- 动作后必须 wait 或 observe（scroll/tap/input 后旧 snapshot 陈旧）；
- alert 只能查询不能关闭，遇弹窗流程需宿主介入或人工；
- 默认不截图，失败时取一次证据；
- `stale` / `ambiguous` / `disabled` 必须重新 observe。

### 8.2 能力补齐顺序（本次发现调整了优先级）

本次把「navigationBar 可达性」提到了比体检稿更高的优先级——它直接阻断了闭环进入子页。建议顺序：

1. **Agent 使用协议**（最便宜最高收益）；
2. **navigationBar 采集补齐**（新优先级——本次发现的硬阻断）；
3. 多结果等待能力（体检稿原 #2）；
4. 真正的 alert 响应能力（体检稿原 #3）；
5. 动作后统一返回轻量 final observation（体检稿原 #4，含 `scrollToElement` 签发 snapshot）。

### 8.3 先写协议 vs 先做多结果等待

**先写协议。** 本次发现的 1+2+3 都是「Agent 怎么正确使用现有命令」的问题，协议写清能立即缓解；而多结果等待是新增能力，不解决当前边界。先协议后能力。
