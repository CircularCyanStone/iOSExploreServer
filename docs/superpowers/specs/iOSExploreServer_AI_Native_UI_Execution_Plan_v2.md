# iOSExploreServer：面向 Agent 的 UI 执行闭环升级方案

> **文档用途**：本文件是给 Codex CLI、Claude Code CLI 与维护者共同阅读的设计说明和实施任务书。先完整阅读仓库根目录 `AGENTS.md`、`CLAUDE.md`、`docs/` 与本文，再检查当前工作树。本文基于 2026-07-01 对 `main` 分支的阅读；若工作树与本文描述不一致，以工作树和既有硬规则为准，并在实现前记录差异。
>
> **当前要实施的范围**：实现第一阶段 `ui.waitFor`，并补齐相应文档、日志、测试与 Agent 使用约定。V1 仅面向 **UIKit**；不要在这一轮实现业务任务中心、SSE/WebSocket、VLM、全局网络拦截、完整测试用例平台，或为了兼容未来平台而削弱现有 UIKit 原生能力。

---

## 0. 一句话结论

`iOSExploreServer` 已经具备 **观察 UI → 操作 UI** 的原生能力，但还缺少一个关键环节：

```text
观察当前 UI
→ 派发一个 UIKit 动作
→ 等待可验证的 UI 结果
→ 再次观察最新 UI
```

因此，本项目下一步最重要的能力不是“让 Agent 更会点”，也不是“自动捕获所有 URLSession 请求”，而是：

> **让 Agent 在点击后可靠地等待并获得页面的可验证结果。**

第一阶段新增 `ui.waitFor`，让 Agent 以“等待页面状态”而非“固定 sleep”完成异步 UI 流程。之后，再按实际需要逐步建设条件动作、业务任务上报和事件推送。

---

# 1. 背景：得物 ai_uitester 给出的启发

用户提供的《AI UITester：AI Native 的 UI 自动化测试新范式｜得物技术》描述的是一个面向多端 UI 自动化测试的 AI Native 系统。其核心方法不是单纯“截图识别按钮”，而是一个反复运行的状态闭环：

```text
截图/观察
→ 理解当前页面
→ 执行一个动作
→ 等待/确认页面结果
→ 再观察
→ 决定下一步
```

文章中值得吸收的思想包括：

1. **逐步执行，而不是一次性预规划整个流程**
   - 每一步之后 UI 都可能改变；后续决策必须基于最新状态。

2. **点击不等于步骤成功**
   - “点击已派发”只是动作层成功。
   - 页面跳转、列表出现、错误提示、加载完成等，才是用户可观察的结果层成功。

3. **失败先分类，再决定恢复动作**
   - 设备/传输/超时/业务分支/目标失效不能混为同一种失败。

4. **宁可不点，也不要点错**
   - 不确定或歧义目标不应强行操作。

5. **条件动作能消除流程噪声**
   - 弹窗存在时处理；不存在时跳过。

6. **知识库与执行器分离**
   - 页面入口、成功状态、常见弹窗、业务前置条件等知识应在外部文档/Agent 知识层维护，而不是硬编码进低层驱动。

7. **自愈应基于证据**
   - 失败截图、最新页面状态、结构化错误和业务知识共同决定下一步；不是“自动乱点”。

---

# 2. 两个系统的关系：相似，但层级不同

得物系统和 iOSExploreServer 都属于“Agent 驱动 UI”的方向，但职责不同：

```text
得物 ai_uitester
测试用例 / 调度 Agent / VLM
    ↓
执行规划、失败诊断、用例自愈、知识库消费
    ↓
跨平台 Driver
    ↓
iOS / Android / HarmonyOS App

本项目 iOSExploreServer
外部 Agent / 将来的 Mac MCP Server
    ↓
调用 observe / activate / wait 工具
    ↓
iOSExploreServer + iOSExploreUIKit
    ↓
UIKit App
```

因此，iOSExploreServer 的正确定位是：

> **可靠的 iOS 原生 UI Driver 与 Agent 工具服务。**

它不应在 iPhone 内承担：

- LLM 推理；
- 测试用例生成；
- VLM 页面理解；
- 用例自愈策略；
- 跨 Android/HarmonyOS 的统一驱动；
- 所有业务网络请求的自动追踪。

这些更适合位于 Mac 侧 MCP Server、外部 Agent，或未来独立的测试编排层。

---

# 3. 当前仓库事实与问题定位

## 3.1 当前已具备的能力

当前仓库已经有较扎实的底座：

```text
Mac curl / 后续 MCP
  ↓ USB iproxy
ExploreServer (NWListener + HTTP)
  ↓ Router / typed Command
UIKit extension
  ↓
viewTargets / topViewHierarchy / screenshot
  ↓
tap / control.sendAction / input / scroll
  ↓
UIKit App
```

已存在的关键能力：

- `ui.viewTargets`：返回可交互目标、`path`、可用动作和 `snapshotID`。
- `ui.topViewHierarchy`：返回完整 view 树快照。
- `ui.screenshot`：返回 PNG base64 和 snapshot。
- `ui.tap`：按 accessibility identifier、path 或 window 坐标点击。
- `ui.control.sendAction`：向 `UIControl` 发送指定事件。
- `ui.input` / `ui.scroll`。
- `UIKitSnapshotStore`：在 `path + snapshotID` 情况下做 30 秒 TTL 的陈旧检测，避免旧 path 指向页面变化后的错误 view。
- UIKit 代码与 core 分离：core 仅依赖 `Foundation + Network`；UIKit 实现在独立扩展模块中。
- 明确的 Swift 并发规则：跨边界 `Sendable`、共享状态 `Mutex`、锁内禁止 `await`、UIKit 访问收敛到 `@MainActor`。

## 3.2 当前 `ui.tap` 的准确语义

当前 tap 的核心动作是对解析到的 `UIControl` 调用：

```swift
control.sendActions(for: .touchUpInside)
```

所以 `ui.tap` 成功的准确含义是：

```text
目标已解析
→ 目标仍有效（若携带 path + snapshotID）
→ UIKit 已执行 touchUpInside 派发
```

它**不表示**：

```text
按钮内部发起的网络请求成功
页面已渲染完成
导航已经完成
加载动画已经消失
业务数据已经更新
```

举例：

```swift
@IBAction func refreshTapped(_ sender: UIButton) {
    Task {
        let data = try await api.fetchData()
        render(data)
    }
}
```

调用顺序是：

```text
Agent 调 ui.tap
→ UIKit 调用 refreshTapped
→ 业务 Task 发起网络请求
→ ui.tap 很快返回“tap 已派发”
→ 网络请求仍在执行
→ 几秒后成功更新 UI，或失败显示错误
```

因此，不能把 `ui.tap` 的 `tapped: true` 当作业务成功。

## 3.3 当前传输模型不适合“点击后主动推送”

当前 `ClientSession` 是短连接、一请求一响应模型：

```text
读完整 HTTP 请求
→ Router.route
→ 发送一个 HTTP 响应
→ close 连接
```

当前实现不支持 keep-alive、pipelining、chunked transfer encoding 或长期订阅。默认连接资源上限与默认命令超时也面向短命令设计。

`ExploreServer.events()` 是 App 内部 `AsyncStream<ServerEvent>`，用于测试 App/宿主日志；它不会通过 HTTP 返回给 Mac。现有 `ServerEvent.responded` 的含义也只是“ExploreServer 对一个控制命令发送了响应”，不是“点击产生的业务网络任务完成”。

---

# 4. 核心设计原则

## 4.1 把一次 UI 步骤拆成三层结果

所有调用方与 API 文档必须区分以下三层：

| 层级 | 含义 | 示例 | 是否由现有 `ui.tap` 证明 |
|---|---|---|---|
| 动作派发层 | UIKit 动作确实被派发 | `touchUpInside` 已发送 | 是 |
| UI 结果层 | 用户看得见的状态已经出现 | 首页出现、列表出现、错误页出现 | 否 |
| 业务任务层 | 某个业务异步操作已明确结束 | 上传完成、接口返回、支付校验结束 | 否 |

第一阶段专注解决 **UI 结果层**。

## 4.2 Agent 应以 UI 结果判断，而不是猜网络状态

对于多数 UI 自动化场景，正确闭环是：

```text
ui.viewTargets
→ ui.tap
→ ui.waitFor(成功 UI 状态 / 失败 UI 状态)
→ 根据最终 observation 决策
```

而不是：

```text
ui.tap
→ sleep 2 秒
→ 猜测接口应该成功了
```

也不是：

```text
ui.tap
→ 试图从底层拦截所有 URLSession
→ 猜这个请求是不是这次点击发起的
```

## 4.3 原生结构化 UI 信息优先，截图/VLM 作为补充

得物的纯视觉路线是跨 iOS、Android、HarmonyOS 的合理折中。iOSExploreServer 位于 App 内部，能拿到 UIKit 的真实结构化信息：

- `UIView` 层级；
- `accessibilityIdentifier`；
- `UIControl` 状态与 action capability；
- path；
- 顶部控制器；
- snapshot/fingerprint；
- 截图。

因此优先级应是：

```text
稳定 accessibilityIdentifier / 结构化 UIKit target
→ path + snapshotID（带陈旧保护）
→ 截图供 Agent 理解和人工诊断
→ 坐标 hit-test 作为最后兜底
```

不要为了模仿跨端 VLM 系统而放弃已有的 iOS 原生优势。

## 4.4 “宁可不点，不要点错”是硬原则

动作命令不能在以下情况静默猜测：

- identifier 对应多个候选；
- snapshot 过期或 path 指纹不一致；
- 控件 disabled；
- hit-test 命中与目标不一致；
- 非 `UIControl` 且当前不支持其动作。

当前项目已有多项防护；后续新增能力不能绕过这些防护。

## 4.5 低层 Driver 负责事实，外部 Agent 负责推理

iOSExploreServer 应返回尽可能准确、可复核的事实：

```text
点击是否派发
等待到哪种状态
耗时多久
观察到哪个 identifier
新的 viewTargets / snapshot
目标是否过期、歧义或不可操作
```

Mac MCP / Codex / Claude 负责：

```text
下一步点什么
是否处理弹窗
是否重试
是否认为这是业务失败
是否需要截图、知识库或人工介入
```

---

# 5. 推荐目标架构

## 5.1 目标闭环

```text
┌──────────────────────────────────────────────────────────┐
│ Mac-side Agent / MCP                                      │
│                                                          │
│ observe → decide → act → wait → observe → decide ...    │
└──────────────────────┬───────────────────────────────────┘
                       │ HTTP POST / action envelope
┌──────────────────────▼───────────────────────────────────┐
│ iOSExploreServer core                                    │
│ HTTPListener → ClientSession → Router → typed Command   │
└──────────────────────┬───────────────────────────────────┘
                       │
┌──────────────────────▼───────────────────────────────────┐
│ iOSExploreUIKit                                           │
│ collector / locator / action executor / wait evaluator   │
└──────────────────────┬───────────────────────────────────┘
                       │ @MainActor
┌──────────────────────▼───────────────────────────────────┐
│ UIKit App                                                  │
└──────────────────────────────────────────────────────────┘
```

## 5.2 第一阶段以后，典型 Agent 调用

```text
1. ui.viewTargets
2. ui.tap(login.submit, snapshotID)
3. ui.waitFor(
     home.root exists,
     login.error exists,
     network.retry exists
   )
4. 使用 waitFor 的 finalObservation 判断下一步
```

注意：第 3 步不是“等网络请求”，而是“等用户可观察的结果”。

---

# 6. 第一阶段实施任务：`ui.waitFor`

## 6.1 目标

新增一个 UIKit 扩展命令：

```text
ui.waitFor
```

它在给定的有限时间内，周期性、轻量地检查当前 UIKit 页面是否满足任一条件；满足、超时或上下文不可用时，返回明确结果和最终观察数据。

它解决：

```text
点击后页面正在异步加载
Agent 不应固定 sleep
Agent 需要知道成功页面、失败页面、重试页面或仍无结果
```

它**不解决**：

```text
任意 URLSession 的真实完成时间
业务 API 响应体
后台上传是否最终完成
服务端业务语义是否正确
```

## 6.2 V1 只做最小可靠条件集

V1 条件仅支持基于 `accessibilityIdentifier` 的状态标记：

```text
identifierExists
identifierAbsent
```

示例：

```json
{
  "action": "ui.waitFor",
  "data": {
    "timeoutMs": 8000,
    "pollIntervalMs": 250,
    "conditions": [
      {
        "id": "loginSucceeded",
        "kind": "identifierExists",
        "accessibilityIdentifier": "home.root"
      },
      {
        "id": "invalidCredentials",
        "kind": "identifierExists",
        "accessibilityIdentifier": "login.error"
      },
      {
        "id": "networkUnavailable",
        "kind": "identifierExists",
        "accessibilityIdentifier": "network.retry"
      }
    ]
  }
}
```

### 为什么 V1 不支持文本、坐标、截图匹配、自然语言条件

- 文本可能本地化、截断、动态变化，且有隐私暴露风险；
- 坐标会因设备、布局、滚动而不稳定；
- 截图匹配会引入昂贵传输和视觉不确定性；
- 自然语言条件属于 Mac 侧 Agent/VLM 的推理职责，不应塞进 iPhone Driver；
- 这个项目已有 `accessibilityIdentifier` 和 UIKit 结构化能力，应该先发挥它们。

### 为什么 V1 不支持 path 条件

`path` 是一次 UI 结构中的位置；异步页面变化后它天然不稳定。`ui.waitFor` 的目标是等待“状态标记”，而不是持续相信旧页面的路径。因此 V1 仅允许 identifier。

## 6.3 建议的请求模型

建议 Foundation-only typed input（命名可按当前仓库规范微调）：

```swift
struct UIWaitForInput: CommandInput {
    let timeoutMs: Int
    let pollIntervalMs: Int
    let conditions: [UIWaitCondition]
}

enum UIWaitConditionKind: String, Sendable {
    case identifierExists
    case identifierAbsent
}

struct UIWaitCondition: Sendable {
    let id: String
    let kind: UIWaitConditionKind
    let accessibilityIdentifier: String
}
```

### 输入约束（必须在 typed parsing 阶段校验）

- `conditions` 必须非空。
- V1 上限建议为 8 条，避免每轮 UI 扫描的无意义膨胀。
- `id` 必须非空且在同一请求内唯一。
- `accessibilityIdentifier` 必须非空。
- `timeoutMs` 建议允许 `100...30_000`。
- `pollIntervalMs` 建议允许 `100...1_000`。
- `pollIntervalMs` 不得大于 `timeoutMs`。
- 不要接受未知字段/未知 condition kind 后静默忽略；应返回统一 `invalid_data`。

### 超时设计

当前全局命令默认超时为 10 秒；`ui.waitFor` 不能直接依赖它，否则例如 `timeoutMs: 8_000` 再加处理开销时会有边界竞态。

建议：

- `UIWaitForCommand.timeoutNanoseconds` 显式设置为 **31 秒或 35 秒**；
- `UIWaitForInput.timeoutMs` 最大值限制为 **30 秒**；
- 保留 1–5 秒框架开销；
- Mac 侧 HTTP/MCP 客户端调用该 command 时，读取超时必须高于该上限，例如 40 秒；
- 超时语义由 command 自己返回业务成功 envelope 中的 `outcome: "timeout"`，不要依赖外层 `command_timeout` 表达正常的“页面尚未达到预期”。

## 6.4 建议的返回协议

无论“匹配到条件”还是“等待超时”，都应是 HTTP 200 / `code: "ok"`，因为它们都是一个正常完成的观察操作。

### 匹配到状态

```json
{
  "code": "ok",
  "data": {
    "outcome": "matched",
    "conditionID": "loginSucceeded",
    "conditionKind": "identifierExists",
    "accessibilityIdentifier": "home.root",
    "matchedCount": 1,
    "elapsedMs": 1250,
    "pollCount": 6,
    "finalObservation": {
      "snapshotID": "snap-42",
      "topViewController": "HomeViewController",
      "targetCount": 17,
      "targets": []
    }
  }
}
```

### 正常等待超时

```json
{
  "code": "ok",
  "data": {
    "outcome": "timeout",
    "elapsedMs": 8000,
    "pollCount": 33,
    "finalObservation": {
      "snapshotID": "snap-43",
      "topViewController": "LoginViewController",
      "targetCount": 8,
      "targets": []
    }
  }
}
```

### 重要要求：返回终态的完整、可行动 observation

`finalObservation` 建议复用 `ui.viewTargets` 已有 collector 的 payload 或其结构化等价物，而不是只返回一个无上下文的 `snapshotID`。

理由：

```text
waitFor 返回一个新 snapshotID
但如果不同时返回新 targets/path
Agent 仍必须再调一次 ui.viewTargets 才能安全操作
```

更好的做法是：

```text
轮询期间：只做轻量 identifier 扫描
终态（matched 或 timeout）：执行一次完整 viewTargets collect
→ 签发新的 snapshotID
→ 把最终 targets 与 snapshot 一起返回
```

这样 `ui.waitFor` 自身就是一次“等待后重新 observe”。

### 约定：conditions 的顺序有语义

多个条件同时满足时，返回数组中**最靠前**的条件。该规则必须写入协议和 `help` 描述。

调用方应把终态优先级显式表达出来，例如：

```text
安全阻断/登录失效
→ 明确业务失败
→ 成功页面
```

或者按业务需要定义。不要让服务端自行猜测“成功优先还是失败优先”。

## 6.5 重要的 Agent 使用规则

### 正确用法

```text
ui.tap("feed.refresh")
→ ui.waitFor(
    feed.content exists,
    feed.empty exists,
    feed.error.retry exists
  )
```

### 不推荐的用法

```text
ui.tap("feed.refresh")
→ ui.waitFor(feed.loading absent)
```

原因：loading 可能还没有来得及出现，或者初始页面本来就没有 loading；“loading 消失”本身不能证明刷新成功。

**优先等待正向、可区分的终态**：

```text
新列表容器出现
空状态出现
错误重试入口出现
下一页 root 出现
成功提示出现
```

### 业务 App 需要做的最小配合

为关键页面状态提供稳定、无业务敏感信息的 identifier，例如：

```swift
homeRootView.accessibilityIdentifier = "home.root"
loginErrorView.accessibilityIdentifier = "login.error"
retryButton.accessibilityIdentifier = "network.retry"
feedContentView.accessibilityIdentifier = "feed.content"
feedEmptyView.accessibilityIdentifier = "feed.empty"
```

这些 identifier 是“自动化可观测性接口”，不是测试代码的临时 hack。应保持稳定、语义明确、避免复用到多个无关页面。

## 6.6 实现结构建议

严格保留现有模块边界：

```text
Sources/iOSExploreServer/
  不依赖 UIKit；本阶段无需改动核心协议/传输语义

Sources/iOSExploreUIKit/
  Commands/WaitFor/
    UIWaitForCommand.swift
    UIWaitForInput.swift
    UIWaitCondition.swift          # Foundation-only 数据模型和解析

  Support/Wait/
    UIKitWaitEvaluator.swift       # @MainActor，只做一次轻量 UIKit 观察
    UIKitWaitObservation.swift     # Sendable 观察结果
```

文件名应以当前工作树的实际命名习惯为准；关键是职责边界，不是字面名称。

### 推荐执行流程

```text
UIWaitForCommand.handle(input)
    ↓
循环：
    1. await MainActor 上 UIKitWaitEvaluator.evaluate(...)
       - 取当前 context
       - 遍历当前 rootView
       - 统计各 identifier 的命中数
       - 只返回 Sendable 轻量结果

    2. 若任一 condition 命中
       - 在 MainActor 上调用既有 viewTargets collector
       - 返回 matched + finalObservation

    3. 若到达 deadline
       - 在 MainActor 上调用既有 viewTargets collector
       - 返回 timeout + finalObservation

    4. 否则在 MainActor 之外 Task.sleep(pollInterval)
       - 醒来后重新采集，不持有 UIView/UIViewController
```

### 并发与 UIKit 约束

必须遵守：

- 绝不将 `UIView`、`UIViewController`、`UIWindow` 带离 `@MainActor`。
- 每轮重新获取 UIKit context；不要跨 await 保存 view 引用。
- `Task.sleep` 只能暂停 async task，不得使用 `Thread.sleep`、信号量或 busy-loop。
- 不得在 `Mutex` 锁内 `await`。
- 等待时不得循环截图，不得重复编码 PNG/base64。
- 不得在等待循环内每轮执行完整 `viewTargets` 或 `topViewHierarchy` collect；终态才做一次完整 collect。
- 正确处理 Task cancellation；外层命令超时取消时，循环应尽快停止。

### identifier 搜索语义

轻量 evaluator 可以遍历 root view tree，直接检查 `view.accessibilityIdentifier`。

- `identifierExists`：命中数 `>= 1`。
- `identifierAbsent`：命中数 `== 0`。
- 返回命中数供诊断。
- V1 不把多命中当作错误，因为这不是危险动作；但文档应强烈建议状态 marker 设计成唯一 identifier。

## 6.7 日志要求

仓库硬规则要求新增命令、状态转移与资源限制都有日志。

建议日志点：

```text
ui.waitFor start
  timeoutMs / pollIntervalMs / condition count（不记录敏感完整 UI payload）

ui.waitFor poll
  仅 debug；poll index / elapsedMs / 是否有匹配

ui.waitFor matched
  conditionID / kind / matched count / elapsedMs / poll count

ui.waitFor timeout
  elapsedMs / poll count

ui.waitFor cancelled / context unavailable / collector failure
  错误类别和简要原因
```

避免每一轮记录完整 identifier 列表或完整 view tree，避免日志噪声和隐私泄露。

## 6.8 测试与验收标准

### Foundation/macOS 单元测试

至少覆盖：

- 输入 schema / 各项范围校验；
- 空 condition、重复 id、未知 kind、非法 timeout/poll interval；
- condition 的优先级（多个同时满足时第一个优先）；
- 立即匹配；
- 若干轮后匹配；
- 正常超时；
- cancellation；
- 不使用真实秒级 sleep 的可控时间/测试 sleeper 设计。

### UIKit/iOS 测试

至少覆盖：

- identifier 存在；
- identifier 缺失；
- identifier 在异步调度后加入/移除；
- 最终 observation 能签发并返回 snapshotID；
- UIKit context 不可用时的现有统一错误语义；
- command 已被 `registerUIKitCommands()` 注册，`help` 能发现其 schema。

### 端到端测试

若现有测试结构允许，补充真实 TCP command 级测试：

```text
POST ui.waitFor
→ code ok / outcome timeout 或 matched
→ 连接按既有短连接语义关闭
```

### 完成定义

只有以下全部满足，第一阶段才算完成：

- `ui.waitFor` 完成并注册；
- 现有 11 个 action 的行为未改变；
- core 仍完全不依赖 UIKit；
- 命令级 timeout 与输入 timeout 语义一致；
- 通过现有 SPM 和 iOS framework 构建/测试命令；
- 更新 `README.md`、`AGENTS.md` / `CLAUDE.md` 的命令清单和行为说明；
- 新增一份 architecture/design 文档；
- 日志满足既有硬规则；
- 不引入 VLM、SSE、全局 URLSession 拦截。

---

# 7. 第一阶段后的小增量：条件动作

在 `ui.waitFor` 稳定后，再增加一个低风险条件动作。建议名称：

```text
ui.tapIfPresent
```

语义：

```text
目标存在且可安全点击 → tapped
目标不存在 → notFound（正常 outcome，不算 command 失败）
目标歧义 / snapshot 过期 / disabled / 不支持动作 → 保持原有明确错误，绝不吞掉
```

示例：

```json
{
  "action": "ui.tapIfPresent",
  "data": {
    "accessibilityIdentifier": "global.popup.close"
  }
}
```

返回：

```json
{ "code": "ok", "data": { "outcome": "tapped", "...": "原 ui.tap 成功数据" } }
```

或：

```json
{ "code": "ok", "data": { "outcome": "notFound" } }
```

这个能力对应得物文章中“弹窗存在时处理，不存在时跳过”的经验。

注意：不要先做一个模糊的 `dismissAllPopups`。低层 Driver 不应猜哪个弹窗“安全可关闭”；由 Agent/知识库提供明确 identifier 才可操作。

---

# 8. 第二阶段（可选）：业务异步任务上报

## 8.1 何时需要它

`ui.waitFor` 已能解决绝大多数用户可见的异步流程，但下列场景仅观察 UI 不够：

```text
上传任务在后台持续 30 秒，页面没有明显变化
请求成功但 UI 继续显示旧缓存
一个点击同时发起多个业务请求
任务结果不应/不能立刻映射为 UI
需要验证业务侧明确的成功、失败、取消原因
```

这些场景才需要“业务任务层”。

## 8.2 不要做全局网络拦截

不要试图通过 `URLProtocol`、`URLSessionDelegate` 或全局 hook 自动推断：

```text
某次 ui.tap
→ 对应哪一个网络请求
→ 多个请求何时算整体完成
```

它在真实 App 中不可靠：

- 一个点击可能产生多个请求；
- 请求可来自 SDK、Repository、Combine、Task、OperationQueue 或后台恢复；
- 请求成功不等于 UI 成功；
- UI 改变也可能来自缓存或其他任务；
- 请求与点击的因果关联在通用层无法可靠恢复。

正确方式是：**需要验证的业务流程显式上报**。

## 8.3 建议设计：`ExploreTaskCenter`

这是后续独立阶段，建议放在 core（Foundation-only），不放 UIKit：

```text
Sources/iOSExploreServer/Tasks/
  ExploreTaskCenter.swift
  ExploreTaskHandle.swift
  ExploreTaskModels.swift
  TaskCommands.swift
```

概念模型：

```text
Task ID
name
interactionID（可选）
state: running / succeeded / failed / cancelled
startedAt / completedAt
safe summary（白名单、无敏感 payload）
```

建议公开 API 形态（伪代码，仅表达语义）：

```swift
let task = server.tasks.begin(
    name: "profile.reload",
    interactionID: ExploreInteraction.currentID
)

Task {
    do {
        let profile = try await api.fetchProfile()
        task.succeed(summary: ["source": "network"])
        render(profile)
    } catch {
        task.fail(code: "profile_reload_failed", message: "request failed")
        showError(error)
    }
}
```

对应 command：

```text
task.get(taskID)
task.wait(taskID, timeoutMs)
task.list(...)          # 仅调试/诊断需要时
```

`task.wait` 和 `ui.waitFor` 一样：

- terminal state → 正常 `code: ok`；
- 等待窗口结束但任务仍 running → 正常 `code: ok, outcome: timeout/pending`；
- task 不存在或输入非法 → 明确业务错误；
- 不应把“本次等待超时”错误解释为“任务失败”。

## 8.4 任务与点击如何关联

这是高级问题，不属于第一阶段，但必须先明确边界。

未来可让 `ui.tap` 返回 `interactionID`，并在 `sendActions(for:)` 的同步动态作用域内设置一个 Task-local interaction context。业务侧新建 `Task {}` 时可继承该 context。

但这只能是“尽力自动关联”：

- `Task {}` 常可继承；
- `Task.detached`、GCD、第三方 SDK 回调可能不继承；
- 发生跨边界时，业务代码必须显式捕获并传递 interactionID。

因此，设计上必须始终支持显式 `interactionID`，不能承诺零侵入关联所有异步链路。

## 8.5 任务存储与隐私

- 任务完成后保留短 TTL（例如 60–120 秒）供 Agent 查询；
- 设置有界最大数量，超限淘汰最旧终态任务；
- 不记录请求 body、响应 body、Authorization、Cookie、用户输入、完整 URL query；
- summary 只能来自调用方显式白名单字段；
- 任务失败的 message 应可诊断但不能泄露敏感业务数据。

---

# 9. 第三阶段（仅在确实需要时）：事件流/SSE

## 9.1 何时才需要

以下情况才值得考虑推送事件：

- 一个后台任务耗时较长，Mac 侧不希望 long-poll；
- 同时要观察多个任务；
- MCP daemon 需要实时收集设备事件；
- 需要跨多个 Agent 工具调用保留事件队列。

## 9.2 不能直接复用当前 `ClientSession`

当前 short request/response session 会在发送响应后关闭。若做事件流，应作为**独立 transport**，而不是把普通 command 的 POST response 一直挂住。

后续可考虑：

```text
GET /events
Accept: text/event-stream
Last-Event-ID: ...
```

事件示意：

```text
event: task.completed
data: {"taskID":"...","state":"succeeded"}
```

但它会改变当前“唯一 POST / 命令端点”的边界，因此必须在一个独立设计变更中完成，不应偷偷塞入 `ui.waitFor`。

## 9.3 SSE 的真正接收方是 Mac MCP Server，不是 LLM 本身

正确链路是：

```text
iPhone event stream
→ Mac MCP Server / daemon
→ 有界 event queue
→ Agent 调 wait_for_event 或 task.wait 工具
→ 工具结果进入 Agent 上下文
```

LLM 在没有工具调用时通常不会被设备主动塞进一条消息。SSE 只改善传输与事件收集，不替代 Agent 的工具调用与决策循环。

---

# 10. 失败分类与恢复策略

参考得物文章，后续 Mac MCP/Agent 层应区分以下结果，不要统一当作“点击失败”：

| 类别 | 含义 | 应对策略 |
|---|---|---|
| `dispatchFailed` | 目标找不到、过期、歧义、不可操作 | 重新 observe，获得新 snapshot；不要盲重试 |
| `uiMatchedSuccess` | 等到预期成功 UI 状态 | 继续下一步 |
| `uiMatchedFailure` | 等到明确错误/登录失效/重试 UI 状态 | 读取页面证据，走业务分支 |
| `waitTimeout` | 等待窗口结束，未出现任何已定义终态 | 观察最终 UI；检查 loading、弹窗、网络、前置条件；谨慎重试 |
| `transportFailure` | USB/iproxy/HTTP/设备/service 失败 | 视为基础设施问题，不要修改业务流程 |
| `taskFailed`（未来） | 业务显式上报任务失败 | 结合安全 summary 和 UI 处理 |

`ui.waitFor` V1 返回的是 `matched` / `timeout`；Mac 侧可用 condition ID 把 matched 映射为 success/failure 分支。不要让 UIKit 层知道哪个 condition 是“业务成功”。

---

# 11. Agent 知识库/文档应该如何使用

得物文章中的 Wiki 对应到本项目，不是让 iPhone 内置一本业务百科，而是维护可被 Codex/Claude/MCP 读取的外部知识：

```text
模块：登录
入口：profile.tab → login.submit
成功状态：home.root
失败状态：login.error、network.retry
常见阻塞：privacy.popup、permission.notification
前置条件：测试账号状态
危险动作：真实支付、删除、发送验证码
```

建议后续每个业务模块维护一份简短 Markdown，而不是一份大而全、易失真的总文档。

建议位置：

```text
docs/app-knowledge/
  login.md
  feed.md
  order.md
```

知识库原则：

- 宁缺毋滥；
- 状态 identifier 必须能在 App 中验证；
- 标注适用版本/页面；
- 过期信息优先删除或降级，不要让 Agent 以错误知识强行操作；
- 将危险动作明确列为需要人工确认的 stop condition。

这些业务文档不属于 iOSExploreServer core 的编译逻辑，但属于 Agent 正确使用 Driver 的重要基础设施。

---

# 12. 明确不采纳或暂缓的方向

## 12.1 暂不在 iPhone 内实现 VLM 执行引擎

原因：

- iOSExploreServer 已有结构化 UIKit 信号，优先级更高；
- VLM 推理应位于外部 Agent/Mac；
- 图片传输、token、隐私、延迟与不确定性成本更高；
- 截图仍然保留为补充证据，不应变成唯一真相。

## 12.2 暂不实现“完整 AI 测试平台”

例如用例 JSON Pipeline、自动生成脚本、自动修复并持久化、跨端统一 driver、测试报告体系。这些都可能是未来上层项目，但不是当前 iOS Driver 的职责。

## 12.3 暂不把一次 `ui.tap` 挂到业务请求完成

原因：

- 业务请求可能很长、永不结束或多个并发；
- HTTP session 资源将被占用；
- `ui.tap` 语义会变模糊；
- 用户看到的页面状态与网络请求本身不是同一件事。

## 12.4 暂不引入 SSE/WebSocket

在 `ui.waitFor`、MCP usage protocol 和业务任务需求被验证前，长连接只会增加复杂度：连接资源、重连、事件丢失、顺序、缓存、心跳、会话隔离和测试负担。

---

# 13. 推荐实施顺序

## P0：补齐设计契约（本次实现前）

- 将本文或提炼后的版本加入 `docs/architecture/`。
- 更新 root `AGENTS.md`/`CLAUDE.md` 的“UI action 不等于业务完成”规则。
- 明确 `observe → act → wait → observe` 是推荐的 Agent 调用协议。

## P1：实现 `ui.waitFor`（当前任务）

- 完成 V1 identifier conditions。
- 复用现有 typed command、日志、UIKit MainActor 边界与 terminal `viewTargets` collector。
- 补测试、文档、注册与 `help` schema。

## P1.5：实现 `ui.tapIfPresent`（只有在 P1 验证后）

- 只吞掉“not found”；不吞歧义、stale、disabled、unsupported。
- 作为弹窗处理和可选入口的基础能力。

## P2：按真实需求实现 `ExploreTaskCenter`

- 仅为关键业务工作流显式埋点。
- 不做全局 URLSession 自动追踪。
- 提供 `task.get` / `task.wait`。

## P3：建设 Mac MCP Server 行为规范

MCP tool 层应把 `ui.waitFor` 暴露为清晰工具，并在工具描述里写入：

```text
每次 UI 操作后必须根据场景调用 waitFor 或重新 observe；
不得用固定 sleep 作为默认同步手段；
遇到 stale/ambiguous 时必须重新 observe；
不得把 ui.tap 成功解释为业务成功。
```

## P4：仅在 P2/P3 明确证明需要时，再设计 SSE

独立 RFC，不与 P1 混合提交。

---

# 14. 给 Codex CLI / Claude Code CLI 的执行指令

请按下面顺序工作：

1. 阅读根目录 `AGENTS.md`、`CLAUDE.md`、`README.md`、`docs/architecture/`、`docs/uikit/`，以及本文。
2. 检查当前工作树，确认本文引用的 command、collector、registrar、snapshot、测试目录的实际命名；不可假定本文路径 100% 未变。
3. 先给出简短 implementation plan，列出将新增/修改的文件、API、测试和文档。
4. 仅实现 **P1 `ui.waitFor`**，不提前实现 P1.5/P2/P3。
5. 遵守当前架构硬规则：
   - core 不依赖 UIKit；
   - UIKit 类型不跨出 `@MainActor`；
   - 跨边界值 `Sendable`；
   - `Mutex` 锁内绝不 `await`；
   - 不维护两份 SPM/framework 源码；
   - 兼容现有 Swift language mode 约束；
   - 新命令必须有 schema、日志、测试、README/help/docs 更新。
6. 不改变现有 `ui.tap` 成功语义；它仍只表示动作已派发。
7. 不在轮询中调用截图，不做 busy-wait，不做 `Thread.sleep`，不在跨 await 后复用旧 `UIView` 引用。
8. `ui.waitFor` 的正常观察超时必须返回 `code: ok, outcome: timeout`，不能错误地变成 transport/command failure。
9. 完成后运行仓库现有的 SPM 与 iOS framework 测试命令；若环境无法运行某项，明确记录原因和已运行内容。
10. 最终输出应包括：修改摘要、协议示例、测试结果、未实现的后续阶段和任何需要维护者决定的真实风险。

---

# 15. 最终验收问题清单

维护者应能对以下问题全部回答“是”：

1. Agent 点击按钮后，是否能等待“首页/错误页/重试入口”等明确 UI 结果，而不依赖固定 sleep？
2. `ui.tap` 是否仍然只表达“动作派发”，没有被伪装成“网络请求成功”？
3. `ui.waitFor` 的超时是否是正常的观察结果，而不是 HTTP/command 错误？
4. 等待过程中是否只做轻量 UIKit 检查，终态才做一次完整 observation？
5. 最终返回是否包含可直接供下一步操作使用的最新 targets 与 snapshot？
6. 是否严格保留 UIKit/MainActor 与 core/Foundation 的模块边界？
7. Agent 遇到 stale/ambiguous/disabled 是否会重新 observe，而不是盲目重试或坐标硬点？
8. 是否没有在第一阶段引入 VLM、SSE、WebSocket、全局 URLSession 拦截或业务 task center？
9. 文档是否说明了业务 App 需要为关键状态提供稳定 identifier？
10. 新能力是否已经有 schema、日志、单元测试、iOS 测试、端到端/协议测试与使用示例？

---

# 16. 最终定位

本项目不是要立刻复刻一个完整的 AI Native 测试平台。

它要先成为一个可靠的 iOS 原生 Agent Driver：

```text
看得见（observe）
→ 点得准（act）
→ 等得对（wait）
→ 看得到结果（observe again）
```

在这个基础牢固后，Mac 侧可以逐步加入知识库、任务编排、失败诊断、自愈策略和 VLM 辅助；业务侧也可以只在必要路径上显式上报异步任务。

> **第一阶段的成功标准不是“系统知道所有网络请求”。**
>
> **第一阶段的成功标准是：Agent 每次点击后，都能基于页面真实结果而不是猜测，做出下一步决定。**

---

# 17. 修订补充：UIKit 结构化信息优先，Screenshot/VLM 只能受控兜底

> **本节优先级高于本文中可能造成歧义的“截图/观察”表述。**
>
> 得物文章的核心价值是“逐步执行、等待可验证结果、失败分类、条件动作、证据驱动恢复”。本项目只采纳这些**流程思想**，不照搬其跨端环境下的“截图 → VLM → 坐标操作”默认实现。

## 17.1 为什么必须这样调整

得物需要同时支持 iOS、Android、HarmonyOS，不能假定各端都有同样质量的 UI 树，所以用截图和 VLM 做统一抽象是合理折中。

`iOSExploreServer` 的条件完全不同：它运行在 iOS App 进程内部，并且当前 V1 只面向 UIKit。它已经可以直接获取真实、结构化且更确定的事实：

- `UIView` 层级、可见性、是否在 window 内；
- `accessibilityIdentifier`、label/value 等 accessibility 元数据；
- `UIControl` 的 enabled、交互能力与可派发 action；
- 顶部 `UIViewController`；
- view path、snapshotID、fingerprint 与陈旧保护；
- 仅在明确需要时才采集的截图。

因此，若把每一步都改成“截图 → VLM → 坐标点击”，等于主动放弃现有 UIKit 原生可观测性，将确定性的 Driver 降级为概率性的视觉自动化器。

## 17.2 非谈判硬约束

```text
默认 observe：UIKit 结构化 observation
默认定位：稳定 accessibilityIdentifier / 结构化 target / path + snapshotID
默认操作：原生 UIControl target-action / 当前已有安全 action executor
默认等待：MainActor 上检查结构化 UIKit 状态

Screenshot：仅在明确请求、视觉断言、结构化信息不足、失败诊断时使用
VLM：不进入 iOSExploreServer；只能作为 Mac 侧 Agent 的可选外部推理能力
坐标 hit-test：只能作为最后兜底，且不得绕过现有安全校验
```

禁止将下列链路作为默认执行路径：

```text
每一步截图 → 发送给 VLM → VLM 猜元素位置 → 坐标点击 → 再截图
```

## 17.3 正确的默认闭环

```text
ui.viewTargets / ui.topViewHierarchy
    ↓
Agent 基于 identifier、结构化 target、snapshotID 决策
    ↓
ui.tap / ui.control.sendAction
    ↓
ui.waitFor（在 UIKit 树中等待状态 identifier）
    ↓
返回 finalObservation：新的 targets + 新 snapshotID
    ↓
Agent 基于结构化终态决定下一步
```

这个默认链路不需要 screenshot，也不需要 VLM。

以登录为例：

```text
ui.viewTargets
→ ui.tap(login.submit, snapshotID)
→ ui.waitFor(
     home.root exists,
     login.error exists,
     network.retry exists
  )
→ 根据 matched condition + finalObservation 决策
```

这里等待的是“用户能看到的最终 UI 结果”，不是猜测 URLSession 是否已经完成。

## 17.4 证据优先级

```text
1. 稳定 accessibilityIdentifier / 结构化 UIKit target
2. path + snapshotID + fingerprint（带陈旧保护）
3. 顶部控制器、可见性、enabled 状态等结构化事实
4. Screenshot：明确请求、视觉断言、失败现场、结构化信息不足时
5. Mac 侧 VLM：仅在 screenshot 已被明确采集且结构化信息不足时
6. 坐标 hit-test：最后兜底；不得绕过 target ambiguity、snapshot 和 action safety checks
```

第 1–3 层才是 V1 需要重点建设和稳定测试的能力。第 4–6 层不能反过来主导 iOSExplore 的协议设计。

## 17.5 Screenshot 与 VLM 的边界

Screenshot 本身不等于 VLM。截图可以用于：

- 人工调试和失败现场留档；
- 视觉回归；
- 判断布局错位、遮挡、颜色、图片或动画；
- UIKit 树无法表达的自定义渲染内容；
- WebView 或第三方页面缺少可用结构化语义时的辅助诊断。

只有让模型根据图片判断“这是什么页面”“哪个元素该点”时，才进入 VLM 路径。

如果每个动作都依赖 Screenshot/VLM，会导致：

- 延迟更高：截图、PNG/base64、传输和视觉推理都要耗时；
- 成本更高：持续消耗多模态上下文和 token；
- 确定性更差：模型可能漏读、误读或按语义猜测；
- 误点风险更高：遮挡、同名元素、动态布局、字体缩放都会影响视觉坐标；
- 隐私面更大：截图可能含用户内容、订单、聊天、账号或敏感信息；
- 测试更难稳定：结构化条件能单测，纯视觉判断难以稳定复现。

所以：**VLM 不进入 iOSExploreServer，不参与 `ui.waitFor` 的默认判断，也不得替代 snapshot/identifier/原生 action 的安全检查。**

## 17.6 `ui.waitFor` 的明确实现约束

`ui.waitFor` V1 只观察 UIKit 结构化状态：

```text
每轮：在 MainActor 上做轻量 identifier / 可见性 / controller 状态检查
命中或超时：只在终态执行一次完整 viewTargets collect，并签发新 snapshot
```

它不得：

- 截屏、OCR、调用 VLM；
- 在轮询中编码 PNG/base64 或向设备外传 image 数据；
- 每轮执行完整 `viewTargets` 或 `topViewHierarchy` collect；
- 根据自然语言猜页面；
- 尝试判断“某个 URLSession 请求是否完成”；
- 跨 `await` 保存并复用旧 `UIView` / `UIViewController` 引用。

V1 建议仅支持可单测、可稳定验证的条件：

```text
identifierExists
identifierAbsent
```

后续如确有必要，先扩展结构化状态（例如顶部控制器、可见性、enabled），不要优先扩展成截图匹配或自然语言匹配。

## 17.7 Mac 侧 Agent / MCP 的职责边界

iOSExploreServer 提供事实和受控执行：

```text
目标是否存在、是否歧义、是否陈旧、是否 disabled
动作是否已派发
等待命中哪个条件、耗时多久
最终的 targets、snapshot、顶部控制器等 observation
```

Mac 侧 Agent / MCP 才负责：

```text
根据 observation 决定下一步
是否重试或处理条件弹窗
是否把 matched condition 解释为业务成功/失败
是否需要知识库、人工介入或显式请求 screenshot
是否在结构化信息不足时使用 VLM 辅助诊断
```

即使 Mac 侧 VLM 得到“可能应该点这个位置”的建议，也必须回到已有的 identifier、snapshot、ambiguity 和原生 action safety checks；不能把 VLM 坐标作为绕过安全机制的后门。

## 17.8 对 Codex CLI / Claude Code CLI 的追加执行要求

实现 P1 时必须遵守：

1. V1 仅面向 UIKit，不提前抽象 SwiftUI 或跨端视觉层。
2. `viewTargets` / hierarchy / identifier / snapshot 是默认观测和决策依据。
3. `ui.waitFor` 的每轮轮询只做 UIKit 结构化检查；终态才做一次完整 observation。
4. 不为了“AI Native”而在 wait、locate、action verification 中每轮截图、OCR 或调用 VLM。
5. Screenshot 只能由显式 screenshot action、视觉断言或失败诊断触发。
6. VLM 不在 iPhone / iOSExploreServer 内实现；未来如由 Mac 侧使用，也不能绕过 identifier、snapshot、target ambiguity 和原生 action safety checks。
7. 坐标点击只保留为最后兜底，且不得成为正常路径。
8. 最终测试和验收必须能证明：`ui.waitFor` 没有循环截图、没有 PNG/base64 编码、没有 image 传输、没有 OCR/VLM 调用。

## 17.9 最终定位（修订后）

本项目不是要立即复刻完整 AI Native 测试平台，也不是要把 UIKit 原生 Driver 改造成“始终依赖多模态截图的视觉点击器”。

它要先成为可靠的 iOS 原生 Agent Driver：

```text
看得见（结构化 observe）
→ 点得准（原生安全 act）
→ 等得对（结构化 wait）
→ 看得到结果（新的结构化 observation）
```

在这个基础牢固后，Mac 侧可以逐步加入知识库、任务编排、失败诊断、自愈策略和 VLM 辅助；业务侧也可以只在必要路径上显式上报异步任务。

> **第一阶段的成功标准不是“系统知道所有网络请求”。**
>
> **第一阶段的成功标准是：Agent 每次点击后，都能优先基于 UIKit 页面真实结构化结果，而不是固定 sleep 或视觉猜测，做出下一步决定。**
