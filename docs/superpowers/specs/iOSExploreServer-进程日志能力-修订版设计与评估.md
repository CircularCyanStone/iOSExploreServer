# iOSExploreServer：面向 Agent 的进程日志能力——修订版完整设计与评估

> 本文是对《iOSExploreServer：面向 Agent 的进程日志能力设计与评估》的**替代版本**。  
> 它吸收了对原方案的工程评审：保留“宿主 App 日志是 Agent 一等证据”的产品方向，但把高价值、低风险、可验证的能力与高风险 runtime interception 分开交付，避免 `NSLog` hook 绑住全部功能上线。
>
> 本文基于当前仓库主分支的结构编写。关键现状：
>
> - Core `iOSExploreServer` 只依赖 `Foundation + Network`；`iOSExploreUIKit` 是显式注册的独立 product。
> - `ExploreLogging` 是库内部日志的唯一入口，但它目前是“开关 + 最小等级 + 单一 sink”，默认 sink 输出到 Unified Logging，并不保存可查询记录。
> - `Router` 与 `AnyCommand` 对所有 action 记录路由和命令生命周期日志。
> - 当前 UIKit 等待命令是 `ui.wait` / `ui.waitAny`；不存在 `ui.observe`。
>
> 本文中的“V1”指第一个可供 Agent 稳定使用的进程日志能力，不是要求所有可想到的日志系统在同一个提交中完成。

---

## 0. 一页结论

### 0.1 该不该做

**应该做，而且是 iOSExploreServer 的核心诊断能力。**

`ui.tap`、`ui.input`、`ui.scroll` 成功，只能说明 iOSExplore 向宿主发出了预期 UI 操作；不能证明业务真的成功。登录被风控拦截、token 过期、路由守卫回退、网络请求失败、第三方 SDK 接管页面、业务断言失败，往往首先体现在宿主 App 的运行日志中。

因此目标不是“给框架增加一个内部 debug 面板”，而是让 Agent 在操作 App 后能读取**当前 App 进程内、从日志捕获启用后开始、被 iOSExplore 捕获和保留的日志证据**。

### 0.2 对外能力名与命令

正式使用：

```text
app.logs.mark
app.logs.read
```

不要使用：

```text
获取全部 Xcode 控制台日志
debug.logs.tail
读取系统全局日志
```

原因是 Xcode Console 是调试器展示面，不是 App 可由公开稳定 API 完整读取的单一日志数据库。iOSExplore 应只承诺当前 App 进程中本工具实际捕获到的日志。

### 0.3 V1 的真实交付边界

| 来源 | 当前定位 | 可靠性契约 | 是否阻塞 `app.logs` 基础能力上线 |
|---|---|---|---|
| `explore` | 必做 | 高：Diagnostics 已安装后，所有进入 `ExploreLogging` 的记录均进入 store；不依赖 Unified Logging 输出开关 | 是 |
| `bridge` | 必做 | 高：宿主显式调用 `ExploreAppLog` 的记录进入 store | 是 |
| `stdout` | 第二阶段已接入，默认关闭 | 配置打开且安装成功后逐行进入 store；不承诺安装前、绕过 fd、崩溃末尾残片 | 否；关闭或失败时必须明确返回 `notCaptured` / `unavailable` |
| `stderr` | 第二阶段已接入，默认关闭 | 同 stdout；默认 level 为 `error` | 同上 |
| `nslog` | 后续技术 spike，正式接入由验证结果决定 | 只能 best effort；成功安装不代表全量覆盖 | **否** |
| `oslog` / `logger` | 不做透明全量读取 | 不承诺；关键业务事件走 bridge | 否 |

这里的关键取舍是：

> `NSLog` 对产品目标很重要，但 `NSLog` interception 的工程不确定性不能成为 `explore + bridge` 第一阶段核心交付的单点阻塞。

这不是把宿主日志降级为可选项。宿主日志仍是能力中心；只是把**可证明可靠的宿主日志路径**与**需要 ABI / 动态库覆盖验证的 hook 路径**分开设定上线门槛。

### 0.4 需要从原方案调整的决定

1. **删除“NSLog 必须作为 V1 完成门槛”**。保留 `NSLog` spike，正式接入按验证结果进入 V1.1/V1.2。
2. **stdout/stderr 已作为第二阶段接入正式 runtime，但默认关闭**。宿主必须显式设置 `captureStdout` / `captureStderr`；未打开时在 `capture` 中报告 `notCaptured`，安装失败时报告 `unavailable`。
3. **V1 不修改 `Router` / `AnyCommand` 增加 `lifecycleLogging = suppressed`**。先容忍少量 `app.logs.*` 自噪声，或由 Agent 按 `source/category/message` 忽略；只有噪声被实际证明影响诊断时，才做结构化生命周期策略改造。
4. **所有 Agent 示例只使用现有 `ui.wait`、`ui.waitAny`、`ui.viewTargets` 等命令**，不再出现不存在的 `ui.observe`。
5. **不使用“Debug-only product”这种不准确表述**。SwiftPM product 会存在；真正的 release 隔离依赖 `#if DEBUG`、Xcode target membership 和 Release 下明确的禁用结果。

---

## 1. 产品目标、承诺范围与非目标

### 1.1 产品目标

为 Agent 提供“操作前后发生了什么”的进程内证据，以便将 UI 自动化从：

```text
发送动作 → 看结果
```

升级为：

```text
观察 UI → 建立日志检查点 → 发送动作 → 等待 UI 信号 → 读取增量日志 → 基于 UI + 日志判断下一步
```

### 1.2 正式承诺

`app.logs.*` 返回：

> 当前 App 进程中，**在 Diagnostics Runtime 启用之后**，由 iOSExplore 已实际捕获并保留的最近日志。

它会明确返回每个 source 的运行状态，例如：

```json
{
  "capture": {
    "explore": { "state": "enabled" },
    "bridge": { "state": "enabled" },
    "stdout": {
      "state": "notCaptured",
      "reason": "stdout capture is disabled"
    },
    "stderr": {
      "state": "notCaptured",
      "reason": "stderr capture is disabled"
    },
    "nslog": {
      "state": "unavailable",
      "reason": "not shipped in this diagnostics version"
    },
    "oslog": {
      "state": "notCaptured",
      "reason": "use ExploreAppLog bridge for reliable delivery"
    }
  }
}
```

### 1.3 明确不承诺

- 安装前的历史日志。
- Xcode Console 中的一切文本。
- 系统其他进程、其他 App、Safari/WebContent、App Extension 独立进程的日志。
- 所有 `Logger` / `os_log` / unified logging 条目。
- 所有动态库、所有 ABI 路径中的 `NSLog`。
- App 崩溃或被杀死时尚未从 pipe drain 完成的最后一小段输出；正常 `resetForTesting()` / 停止捕获会 flush 已读取或可 drain 的无换行尾部。
- 使用者主动禁用 / 覆盖 stdout、stderr、hook 后仍完整可见。

这些限制必须出现在 command description、README 和 Agent protocol 中，避免“没有返回日志”被误解释成“没有发生”。

---

## 2. 现有仓库的约束与可利用基础

### 2.1 协议与模块边界

当前仓库已经确立了适合本设计的基础：

```text
POST /
{"action":"...", "data":{...}}
→ Router
→ typed Command
→ 统一 success/failure envelope
```

新增能力应继续注册新 action，而不是另开 HTTP endpoint、也不改变通用请求 envelope。

模块结构应保持：

```text
iOSExploreServer       Foundation + Network core
iOSExploreUIKit        UIKit UI 探索命令，宿主显式 registerUIKitCommands()
iOSExploreDiagnostics  新增；进程日志 store、capture、bridge、app.logs.*
```

Diagnostics 只依赖 Core，不依赖 UIKit。日志捕获是 App 进程能力，不应混入 UIKit view resolver 或 UI executor。

### 2.2 当前 `ExploreLogging` 的真实限制

当前 `ExploreLogging` 具备：

- `ExploreLogRecord(level, category, message)`；
- 全局 `isEnabled`、`minimumLevel` 与单一 `sink`；
- 默认 sink 为 Apple Unified Logging；
- 默认关闭；
- Core 和 UIKit 扩展可以汇聚到同一日志入口。

但它还不具备：

- 可查询的 ring buffer；
- 多 observer；
- “录入 diagnostics store”与“输出到 Unified Logging”的独立控制；
- 对外的日志 cursor；
- source 状态与 gap 反馈。

因此不能简单把 `ExploreLogging.setEnabled(true)` 当成日志命令实现。Diagnostics 安装后，库内部日志必须进入自己的内存 store，即使用户没有开启 Unified Logging 输出。

### 2.3 当前命令生命周期日志对自噪声的影响

`Router.route` 会记录 `router route start/success/failure`；`AnyCommand.handle` 也会记录 `command ... start/completed/failed`。

这意味着调用：

```text
app.logs.mark
app.logs.read
```

本身会产生少量 `explore/router/command` 日志。

原方案提出给 `AnyCommand` / `CommandLogCategory` 新增 `lifecycleLogging = normal | suppressed`。方向合理，但它会修改所有命令共用的生命周期路径、注册 API 和测试面。对第一版进程日志能力而言，收益不足以覆盖影响范围。

**V1 决定：先不修改公共命令生命周期模型。**

V1 行为：

- `app.logs.read` 正常返回少量 `app.logs.*` 产生的框架日志；
- Agent protocol 明确：当 `source=explore` 且 `category=router|command`、message 指向 `app.logs.mark` / `app.logs.read` 时，把它视为控制面噪声；
- Diagnostics 自己不再额外写“read completed”等重复业务日志；
- 只有实际使用中证明自噪声妨碍判断时，V1.1 再考虑结构化 suppression。届时应以显式 metadata，而不是 message substring 作为长期方案。

---

## 3. 最终协议：检查点、增量读取、分页与 gap

### 3.1 为什么不是每次全量 tail

每步都读取“最近 500 条”会反复携带旧日志，浪费网络与 Agent 上下文；更严重的是，它使动作与日志之间的因果关系变得模糊。

正确的默认模式是：

```text
建立检查点 A
→ 执行动作
→ 等待 UI / 状态变化
→ 读取 A 之后的新增日志
```

这不是“仅限两个 UI 动作之间”，而是任意两个日志 cursor 之间的增量消费。

### 3.2 Cursor

```json
{
  "captureSessionID": "B8D6036C-95FC-44E2-B2F8-2B4284217B4D",
  "id": 428
}
```

含义：

- `captureSessionID`：当前进程级 Diagnostics Runtime 第一次成功安装时生成；App 重启、Runtime 新建后变化。
- `id`：同一 session 内严格递增的物理日志序号，不因 source、level、filter 而重新编号。
- Cursor 只在同一 `captureSessionID` 内有效。

不使用单独整数，是为了让 Agent 能区分：

```text
日志被 ring buffer 覆盖
```

与：

```text
App 已重启或 Diagnostics Runtime 已换代
```

### 3.3 `app.logs.mark`

作用：返回此刻 store 的最大已分配 cursor，不返回日志正文。

请求：

```json
{
  "action": "app.logs.mark"
}
```

响应：

```json
{
  "code": "ok",
  "data": {
    "cursor": {
      "captureSessionID": "B8D6036C-95FC-44E2-B2F8-2B4284217B4D",
      "id": 428
    },
    "oldestAvailableID": 161,
    "latestAvailableID": 428,
    "capture": {
      "explore": { "state": "enabled" },
      "bridge": { "state": "enabled" },
      "stdout": { "state": "notCaptured", "reason": "stdout capture is disabled" },
      "stderr": { "state": "notCaptured", "reason": "stderr capture is disabled" },
      "nslog": { "state": "unavailable", "reason": "not shipped in this diagnostics version" },
      "oslog": { "state": "notCaptured", "reason": "use bridge" }
    }
  }
}
```

原子性要求：

- 在一次 `AppLogStore` lock 内读取当前 `latestID`；
- 所有 `id <= latestID` 的日志都已可被后续 `read(after:)` 看见；
- 不要求阻塞正在发生的 future log。

### 3.4 `app.logs.read`

请求：

```json
{
  "action": "app.logs.read",
  "data": {
    "after": {
      "captureSessionID": "B8D6036C-95FC-44E2-B2F8-2B4284217B4D",
      "id": 428
    },
    "limit": 200,
    "sources": ["explore", "bridge"]
  }
}
```

字段：

| 字段 | 必填 | 默认 | 约束 |
|---|---:|---:|---|
| `after` | 否 | 无 | 同 session cursor；省略时读取当前保留的最近记录 |
| `limit` | 否 | 100 | `1...500`；严格限制避免 Agent 一次拉入过多文本 |
| `sources` | 否 | 所有可读取 source | 稳定可返回 `explore`, `bridge`；stdout/stderr 配置开启且安装成功后可返回 `stdout`, `stderr`；`nslog` 仅保留枚举与状态，不代表已捕获 |
| `minimumLevel` | 否 | 无 | 按 entry level 过滤；`explore` / `bridge` 使用调用方等级，stdout 固定 info，stderr 固定 error |

V1 不新增无必要的 `app.logs.tail`、`app.logs.cursor`、`app.logs.status`。状态已包含在 `mark/read` response，避免命令面过宽。

### 3.5 `app.logs.read` 响应

```json
{
  "code": "ok",
  "data": {
    "entries": [
      {
        "id": 429,
        "timestamp": "2026-07-04T08:32:11.001Z",
        "source": "explore",
        "level": "info",
        "category": "command",
        "message": "command ui.tap completed ok=true resultKeys=4",
        "messageTruncated": false,
        "metadata": null
      },
      {
        "id": 430,
        "timestamp": "2026-07-04T08:32:11.641Z",
        "source": "bridge",
        "level": "error",
        "category": "auth",
        "message": "login API failed: token expired",
        "messageTruncated": false,
        "metadata": {
          "route": "login"
        }
      }
    ],
    "nextCursor": {
      "captureSessionID": "B8D6036C-95FC-44E2-B2F8-2B4284217B4D",
      "id": 430
    },
    "capturedThrough": {
      "captureSessionID": "B8D6036C-95FC-44E2-B2F8-2B4284217B4D",
      "id": 430
    },
    "hasMore": false,
    "gap": null,
    "oldestAvailableID": 161,
    "capture": {
      "explore": { "state": "enabled" },
      "bridge": { "state": "enabled" },
      "stdout": { "state": "notCaptured", "reason": "stdout capture is disabled" },
      "stderr": { "state": "notCaptured", "reason": "stderr capture is disabled" },
      "nslog": { "state": "unavailable", "reason": "not shipped in this diagnostics version" },
      "oslog": { "state": "notCaptured", "reason": "use bridge" }
    }
  }
}
```

### 3.6 分页语义：必须按“最后扫描的物理 id”推进

日志查询有 source/level filter。若 `nextCursor` 只指向“最后返回的 entry”，被 filter 排除的 id 会在下一页反复扫描，或造成语义不清。

因此 read 在 store lock 内：

1. 固定一个 `capturedThroughID = latestID` 快照；
2. 若省略 `after`，返回当前可见记录中命中 filter 的最近 `limit` 条，`nextCursor` 指向这次读到的最新 id，`hasMore = false`，不暗示可向旧记录翻页；
3. 若传入 `after`，从 `after.id + 1` 扫描到 `capturedThroughID`；
4. 命中 filter 的记录加入结果；
5. 到达 `limit` 或扫描到 `capturedThroughID` 时停止；
6. 返回的 `nextCursor.id` 是**最后扫描到的物理 id**，不是最后返回记录的 id；
7. 只有传入 `after` 且扫描未到 `capturedThroughID` 时，`hasMore = true`；
8. 下一页传入 `nextCursor`，继续消费同一条物理日志序列。

这保证 Agent 即使过滤只看 `stderr`，也能可靠推进 cursor。

### 3.7 buffer 覆盖：必须显式 gap

假设：

```text
after.id = 100
oldestAvailableID = 161
```

说明 101...160 已被有界 ring buffer 驱逐。响应必须包含：

```json
{
  "gap": {
    "kind": "bufferOverrun",
    "requestedAfterID": 100,
    "oldestAvailableID": 161,
    "lostIDRange": {
      "from": 101,
      "to": 160
    }
  }
}
```

不得静默从 161 开始返回，然后让 Agent 误认为 101...160 没有发生。

### 3.8 session 改变：不是 gap，而是失效 cursor

当 `after.captureSessionID` 与当前 session 不一致，返回：

```json
{
  "code": "stale_cursor",
  "message": "The log capture session changed; call app.logs.mark to begin a new stream.",
  "data": {
    "currentCaptureSessionID": "NEW-SESSION-ID"
  }
}
```

Agent 必须重新调用 `app.logs.mark`，不应把两个 App 进程生命周期的日志拼成连续时间线。

### 3.9 省略 `after`：仅用于回看当前近期上下文

```json
{
  "action": "app.logs.read",
  "data": {
    "limit": 200
  }
}
```

含义不是“全历史”，而是：

> 从当前 ring buffer 中选取最近 200 条可用记录。

此模式适合刚连接、人工排障、命令超时后回看。Agent 的常规动作闭环仍使用 mark + incremental read。

---

## 4. Agent 使用协议

### 4.1 标准 UI 动作闭环

```text
1. app.logs.mark
   保存 cursor A

2. ui.tap / ui.input / ui.scroll / ui.alert.respond

3. ui.wait 或 ui.waitAny
   如果没有适合的 wait 条件，重新 ui.viewTargets / ui.topViewHierarchy 观察页面

4. app.logs.read(after: A, limit: 200)

5. 结合：
   - UI 命令 response
   - ui.wait / ui.waitAny 结果
   - 新 view hierarchy / viewTargets
   - 增量日志
   判断业务是否推进、失败还是进入分支页面
```

这里没有 `ui.observe`。当前库中可用于等待与观察的已存在命令是 `ui.wait`、`ui.waitAny`、`ui.viewTargets`、`ui.topViewHierarchy` 和 `ui.screenshot`。

### 4.2 后台异步结果

例如点击“登录”后业务网络请求需要数秒：

```text
A = app.logs.mark
ui.tap(login.submit)
ui.waitAny([loginSucceeded, errorToast, loginPageChanged])
read(after: A)
→ B

若 UI 仍未完成：
ui.wait(...)
read(after: B)
→ C
```

每次把 `nextCursor` 保存为下一个 `after`。不要从 A 反复读取，否则日志与 Agent 上下文会重复累积。

### 4.3 Agent 对自噪声的处理

V1 收到以下类型记录时应忽略它们的业务含义：

```text
source=explore
category=router 或 command
message 包含 app.logs.mark / app.logs.read
```

它们只说明日志控制面自己被路由和执行，不是宿主业务发生了变化。

这条规则只是在 V1 避免扩大 Router/AnyCommand 的改动范围；不应让日志命令额外写第三套“读取成功”日志。

### 4.4 日志不是唯一事实来源

正确判断模型：

```text
UI 操作结果
+ UI 等待/层级证据
+ 动作后增量日志
= Agent 的业务判断依据
```

错误例子：

- 日志出现“request success”不等于 UI 已显示成功页；
- UI 跳回登录页不自动说明 token 为什么失效；
- 无日志不等于无业务事件，因为 source 可能未安装、已丢失或不受捕获支持。

---

## 5. 模块、文件与 Runtime 架构

### 5.1 新增 SwiftPM product

`Package.swift` 增加：

```swift
.library(
    name: "iOSExploreDiagnostics",
    targets: ["iOSExploreDiagnostics"]
)
```

target：

```swift
.target(
    name: "iOSExploreDiagnostics",
    dependencies: ["iOSExploreServer"]
)
```

不要把它描述为“SwiftPM 自动 Debug-only product”。SwiftPM product 本身可被 Debug 与 Release 配置引用；真正的保护将在实现和宿主接入层完成。

### 5.2 推荐目录

```text
Sources/
├── iOSExploreServer/
│   ├── ExploreLogging.swift
│   ├── ExploreLogObservation.swift
│   └── ...
│
├── iOSExploreDiagnostics/
│   ├── ExploreDiagnosticsRegistrar.swift
│   ├── DiagnosticsConfiguration.swift
│   ├── DiagnosticsRegistration.swift
│   ├── ProcessDiagnosticsRuntime.swift
│   ├── AppLogStore.swift
│   ├── AppLogEntry.swift
│   ├── AppLogCursor.swift
│   ├── AppLogsMarkCommand.swift
│   ├── AppLogsReadCommand.swift
│   ├── ExploreLogRecorder.swift
│   ├── ExploreAppLog.swift
│   ├── LogRedactor.swift
│   ├── DiagnosticsStatus.swift
│   ├── StdIOCapture.swift
│   └── NSLog/ ... only after spike outcome
│
└── iOSExploreUIKit/
    └── unchanged for process logging
```

### 5.3 Xcode framework 工程同步

仓库不仅有 SPM，也有 framework 工程。实现时必须同步：

1. 增加 `iOSExploreDiagnostics` framework / target；
2. 设置它依赖 `iOSExploreServer`；
3. 添加对应 test target 或将 tests 链入现有 test plan；
4. 确认 SPMExample 能通过 package 或 framework 两种集成方式导入；
5. 对 Release 配置验证 hook/backend 不被编入可执行路径。

只改 `Package.swift` 会导致“SPM build 通过、framework 集成失败”的双轨不一致。

### 5.4 进程级单例 Runtime

stdout/stderr 和 log store 本质上是**进程级资源**，不是某个 `ExploreServer` 实例私有资源。

```text
ProcessDiagnosticsRuntime
├── captureSessionID
├── AppLogStore
├── ExploreLogging observer token
├── stdout capture state
├── stderr capture state
├── NSLog backend state
└── registration count / owner state
```

设计规则：

- 同一进程只可安装一次实际 stream interception；
- 多次 `server.registerDiagnosticsCommands()` 不可重复 `dup2`、重复 pipe、重复 observer；
- 第二个 server 仅注册同一组 command，读取同一 Runtime store；
- `server.stop()` 只停止 HTTP listener，**不得恢复 stdout/stderr 或清空日志 store**；
- Runtime 生命周期默认到进程退出。V1 不支持 start/stop 动态卸载 capture。

理由：fd 重定向是全进程行为。频繁装卸会造成其他线程写日志时的竞态，也不值得为 Debug 工具引入。

---

## 6. 数据模型

以下是结构方向，具体命名可随现有 `Models.swift` 和 JSON coder 风格调整。

```swift
public enum AppLogSource: String, Sendable, Codable {
    case explore
    case bridge
    case stdout
    case stderr
    case nslog
}

public enum AppLogLevel: String, Sendable, Codable {
    case debug
    case info
    case error
    case fault
    case unknown
}

public struct AppLogCursor: Sendable, Codable, Equatable {
    public let captureSessionID: String
    public let id: UInt64
}

public struct AppLogEntry: Sendable, Codable, Equatable {
    public let id: UInt64
    public let timestamp: Date
    public let source: AppLogSource
    public let level: AppLogLevel
    public let category: String?
    public let message: String
    public let messageTruncated: Bool
    public let metadata: [String: String]?
}
```

约束：

- `id` 由 store 分配；外部 source 不得自行指定。
- `timestamp` 在入 store 时生成，统一使用 ISO 8601 编码。
- `stdout` 固定 `level = info`，`stderr` 固定 `level = error`；`nslog` 等后续纯文本来源在无法可靠推断时才使用 `unknown`。
- `metadata` 只允许 string:string；V1 不承诺任意嵌套 payload，避免把日志 bridge 变成另一个无约束传输通道。
- redaction 在 entry 写入 store 前发生；store 不保留未脱敏原文。

---

## 7. `ExploreLogging` 的必要改造

### 7.1 目标

Diagnostics 安装后，库内部日志需要同时具备两个独立去向：

```text
ExploreLogging.emit(record)
├── observer(s) → AppLogStore（Diagnostics 已安装时）
└── output sink → Unified Logging（用户显式开启时）
```

这两个去向不能共用 `isEnabled` 作为总开关。

### 7.2 新的状态模型

概念上将当前单一 state 拆成：

```swift
private struct ExploreLoggingState {
    var outputEnabled: Bool
    var outputMinimumLevel: ExploreLogLevel
    var outputSink: @Sendable (ExploreLogRecord) -> Void
    var observers: [UUID: @Sendable (ExploreLogRecord) -> Void]
}
```

`emit` 的规则：

1. 在锁内快照 observer 列表；
2. 在锁内判断当前 record 是否应进入 output sink；
3. 解锁；
4. 先投递 observer，再执行 output sink；
5. observer 失败或过慢不得持有 `ExploreLogging` 锁，也不得阻断 output sink；
6. Diagnostics 的 store append 必须是常数时间、有界，不做 IO。

### 7.3 订阅 API

因为 Diagnostics 是独立 module，Core 至少需要一个 public 或 package-visible-to-target 的订阅入口。若项目维持当前广泛兼容的 SwiftPM 配置，最直接的是公开受限 API：

```swift
public struct ExploreLogObservation: Sendable {
    fileprivate let id: UUID
}

public extension ExploreLogging {
    static func addObserver(
        _ observer: @escaping @Sendable (ExploreLogRecord) -> Void
    ) -> ExploreLogObservation

    static func removeObserver(_ observation: ExploreLogObservation)
}
```

`ExploreDiagnostics` 注册 observer；Runtime 进程退出才释放。对普通宿主而言这不是鼓励自行接管日志，而是提供 Diagnostics 所需的模块边界。

### 7.4 必须修正“消息 lazy 化”语义

当前 `ExploreLogger.debug(_:_:)` 形式虽然接受 `@autoclosure`，但内部若在过滤前执行 `message()`，仍会提前构造字符串。

改造时应保证：

- 没有 observer 且 output 未启用 / 被最小等级过滤时，不构造昂贵消息；
- 有 Diagnostics observer 时，按 Diagnostics capture level 决定是否构造；
- 一条 record 的 message 只构造一次，然后供 observer 和 output 共用。

这不是日志功能的额外优化，而是避免 Diagnostics 安装后把高频网络/路由日志的字符串拼接成本无意扩大。

### 7.5 Diagnostics recorder 的职责

`ExploreLogRecorder` 将 Core record 映射为：

```text
source = explore
level = 从 ExploreLogLevel 转换
category = ExploreLogRecord.category
message = ExploreLogRecord.message
```

之后统一经过：

```text
redactor → truncation → AppLogStore.append
```

它不直接使用 `print`、不写回 `ExploreLogging`，避免产生递归日志。

---

## 8. 宿主结构化日志 Bridge

### 8.1 为什么 bridge 是基础能力，不是备胎

透明截获无法可靠覆盖：

- `Logger` / `os_log`；
- 业务已有自定义日志框架；
- 网络层、认证层、路由层中真正关键的业务状态；
- 需要主动脱敏、添加分类和 metadata 的日志；
- 不愿让全部普通 stdout 文本暴露给 Agent 的 App。

因此 `ExploreAppLog` 是稳定宿主可观测性的正式入口，而不是“抓不到才用”的备用方案。

### 8.2 V1 API

```swift
#if DEBUG
import iOSExploreDiagnostics

ExploreAppLog.emit(
    .error,
    category: "auth",
    message: "login API failed: token expired",
    metadata: [
        "route": "login",
        "retryable": "false"
    ]
)
#endif
```

建议 API：

```swift
public enum ExploreAppLog {
    public static func emit(
        _ level: AppLogLevel,
        category: String,
        message: @autoclosure () -> String,
        metadata: [String: String]? = nil
    )
}
```

行为：

- Diagnostics Runtime 已安装：写入 `source = bridge`；
- Runtime 未安装：Debug 下 no-op；不得为了 bridge 自动安装 stdout/stderr；
- Release：public symbol 可以保留为 no-op，但不保留任何 hook / capture 行为；
- 写入前统一 redaction。

### 8.3 建议桥接的位置

优先在业务高信号节点使用，不要求把所有日志复制一遍：

```text
认证：token 缺失、refresh 成败、被踢下线
网络：关键请求开始、HTTP 失败类别、业务码失败
路由：跳转被拦截、深链解析失败、页面降级
支付/风控/第三方 SDK：已开始、取消、失败原因摘要、成功 callback
测试断言：断言失败的业务摘要
```

不要 bridge：

```text
完整请求 body
完整响应 body
Cookie
Authorization
password
身份证/手机号等个人数据
任意没有容量上限的大对象序列化文本
```

---

## 9. stdout / stderr：第二阶段 fd capture

### 9.1 为什么接入

很多 Swift 业务代码仍使用：

```swift
print(...)
debugPrint(...)
dump(...)
```

很多 C / C++ / SDK 输出使用：

```c
fprintf(stderr, ...)
```

忽略这两条流会让 Agent 看不到大量宿主运行信息。所以第二阶段已把 stdout/stderr fd capture 接入 Diagnostics runtime，但默认关闭，避免宿主无意中接管全进程标准流。

它修改的是**整个进程的文件描述符路由**，不是普通对象级 subscription。因此实现必须只在 Debug 下可用，由 `DiagnosticsConfiguration.captureStdout` / `captureStderr` 显式开启；安装失败只能降级对应 source，不能影响 `app.logs.mark/read`、server 或 UI command。

### 9.2 当前实现

当前实现位于 `Sources/iOSExploreDiagnostics/StdIOCapture.swift`：

1. `dup(STDOUT_FILENO)` 与 `dup(STDERR_FILENO)` 保存原始目标；
2. stdout/stderr 分别创建独立 pipe；
3. 使用 `dup2(pipeWriteFD, STDOUT_FILENO)` / `dup2(pipeWriteFD, STDERR_FILENO)` 重定向后续输出；
4. 关闭安装方不再持有的多余 fd；
5. 每条 pipe 使用专用 serial `DispatchQueue + DispatchSourceRead` 消费；
6. 读取到的 bytes 由各自独立的 buffer 按 `\n` 切分，行尾 `\r` 会被去掉；
7. 每行写入 `AppLogStore`，继续复用 store 的 redaction、message 截断、metadata 限制和 ring buffer；
8. stdout entry 使用 `source=stdout`、`level=info`、`category=stdio`；
9. stderr entry 使用 `source=stderr`、`level=error`、`category=stdio`；
10. `teeToOriginalStreams = true` 时，在 reader queue 上通过保存的原 fd 执行底层 `write` 回送，尽量维持 Xcode 原先可见性；
11. 重复 `registerDiagnosticsCommands()` 或 `resetForTesting()` 会先恢复旧 fd，再停止旧 reader；停止时会主动 drain pipe，并把无换行尾部 flush 成最后一条 entry。

### 9.3 关键实现限制

- capture 内部不得 `print` 或 `NSLog` 自己的错误；否则会重入被截获的流。
- tee 只能写保存的原 fd，不能调用 `FileHandle.standardOutput` 等可能重新走新 fd 的高层 API。
- `write` 可能 partial write；实现必须循环直到写完或错误，不能默认一次完成。
- stdout 与 stderr 绝不共用 buffer，避免跨 stream 拼行。
- 多线程写入可能天然交错；工具只能记录实际收到的字节序列，不承诺还原“逻辑上每个 print 调用的一行”。
- pipe reader 与 store append 必须快；store 满时覆盖旧 entry 并报告 gap，不能让写日志线程长期阻塞。
- `server.stop()` 只停止 HTTP listener，不恢复 fd；`resetForTesting()` 会恢复 fd，供单元测试隔离。
- 其他调试工具可能已经重定向 fd。V1 无法完整识别所有第三方 owner；只要 install 失败，必须把 source 标为 unavailable，而不是假装启用。

### 9.4 source 状态

```json
{
  "stdout": {
    "state": "enabled"
  },
  "stderr": {
    "state": "enabled"
  }
}
```

安装异常：

```json
{
  "stdout": {
    "state": "unavailable",
    "reason": "dup2 failed: errno=..."
  }
}
```

日志命令仍可正常读取 `explore` 和 `bridge`。

---

## 10. `NSLog`：V1 必做 spike，非 V1 上线门槛

### 10.1 为什么不能把 stdout/stderr 当 `NSLog` 答案

`print` / stderr 与 `NSLog` 并非一个可靠统一管道。某些环境下 Xcode Console 同时展示它们，不代表 stdout/stderr pipe 一定收到 `NSLog`。因此不能对外宣称：

```text
已截获 stdout/stderr = 已完整获取 NSLog
```

### 10.2 正确的阶段定位

`NSLog` 仍然重要，因为 Objective-C、老 Swift 代码和大量 SDK 使用它。但它要求验证：

- C variadic / `va_list` 的安全格式化；
- `NSLog` 与 `NSLogv` 的实际调用路径；
- simulator 与 device 差异；
- 静态 target、动态 framework、后加载 image 的覆盖范围；
- 与其他 hook 工具共存时是否破坏原始输出；
- reentrancy 与原实现调用。

因此实施顺序固定为：

```text
V1：
  - 进行独立 NSLog spike
  - 命令协议必须能表达 nslog=unavailable / experimental
  - 不因 spike 不通过而阻塞基础日志能力

V1.1 / V1.2：
  - 仅在验证矩阵通过后，接入正式 NSLog backend
  - source 状态只能是 bestEffortEnabled，不能叫 enabled/full
```

### 10.3 spike 不是正式功能承诺

Spike 的产物可以是：

```text
Examples/SPMExample/DiagnosticsSpike/
Tests/.../NSLogCaptureTests/
docs/.../nslog-capture-validation.md
```

而不是先把不成熟 hook 直接放到正式 `registerDiagnosticsCommands()` 默认路径。

Spike 必须回答：

1. 在当前最低部署 iOS、当前 Xcode、simulator/device 上能否截获直接 `NSLog`？
2. 是否完整保留原始 NSLog 行为？
3. 失败时是否只让 source unavailable，而不影响 server、UI command、stdout/stderr？
4. framework 与静态 target 是否覆盖？
5. 有没有启动崩溃、重复记录、死锁、明显性能问题？

### 10.4 若 spike 成功后的正式 backend 契约

```swift
protocol NSLogCaptureBackend: Sendable {
    func install(
        record: @escaping @Sendable (String) -> Void
    ) -> NSLogCaptureInstallResult
}
```

安装成功后的 response：

```json
{
  "nslog": {
    "state": "bestEffortEnabled",
    "limitations": [
      "does not promise complete coverage for all dynamic images",
      "does not read the global unified logging store"
    ]
  }
}
```

安装失败：

```json
{
  "nslog": {
    "state": "unavailable",
    "reason": "NSLog backend validation failed for this build"
  }
}
```

### 10.5 不做的事情

- 不读取 Apple unified logging 数据库；
- 不使用 private API 抓系统全局日志；
- 不因为 `NSLog` backend 失败让 `app.logs.mark/read` 不可用；
- 不在未通过真机验证前承诺 DoKit 风格的稳定截获效果。

---

## 11. Debug / Release 与宿主安装方式

### 11.1 正确的宿主接入

```swift
#if DEBUG
import iOSExploreServer
import iOSExploreUIKit
import iOSExploreDiagnostics

let server = ExploreServer()
server.registerUIKitCommands()

let diagnostics = server.registerDiagnosticsCommands(
    .init(
        captureExploreLogs: true,
        enableBridge: true,
        captureStdout: false,
        captureStderr: false,
        teeToOriginalStreams: true,
        bufferCapacity: 2_000,
        maximumEntryBytes: 8 * 1024,
        maximumMetadataEntries: 32,
        maximumMetadataKeyBytes: 128,
        maximumMetadataValueBytes: 1024,
        redaction: .standard
    )
)
#endif
```

不需要环境变量来决定是否捕获日志。

环境变量 / 启动参数仍适合现有 SPMExample 的：

```text
IOS_EXPLORE_AUTOSTART=1
--ios-explore-autostart
```

即“是否自动启动 server”的测试自动化；而 Diagnostics 安装是架构级能力选择，应由显式 API 调用表达。

### 11.2 SwiftPM 与 Xcode 的现实约束

正确表述：

- `iOSExploreDiagnostics` product / target 可以被 SwiftPM 构建；
- 不能依赖“target 名字带 Diagnostics”就自动不进 Release；
- 需要在 hook、fd capture、NSLog backend 的实现中使用 `#if DEBUG`；
- Release 下 `registerDiagnosticsCommands()` 的行为必须明确。

推荐：

```swift
public extension ExploreServer {
    @discardableResult
    func registerDiagnosticsCommands(
        _ configuration: DiagnosticsConfiguration = .default
    ) -> DiagnosticsRegistration {
#if DEBUG
        return ProcessDiagnosticsRuntime.shared.register(on: self, configuration: configuration)
#else
        return .disabled(
            reason: "iOSExploreDiagnostics is disabled in non-Debug builds."
        )
#endif
    }
}
```

Release 行为：

- 不安装 fd capture；
- 不安装 hook；
- 不注册 `app.logs.mark/read`；
- `ExploreAppLog.emit` no-op；
- `DiagnosticsRegistration` 以明确状态告诉调用方没有启用；
- 文档继续要求宿主不要把整个 Debug 工具链带入上架构建。

### 11.3 为什么不是“默认自动装”

即使项目是 Debug 工具，也不应在 `ExploreServer.init()` 自动修改 stdout/stderr：

- 某些宿主只要 UI command，不想抓全部业务日志；
- 有些项目已有其它调试工具处理 stream；
- 捕获开始的时机应该可见、可复现；
- 显式 `registerDiagnosticsCommands()` 与现有 `registerUIKitCommands()` 的风格一致；
- 发生异常时可以从 registration result 看出哪一条 source 成功、失败或被禁用。

---

## 12. 环形缓冲区、并发与资源限制

### 12.1 默认资源上限

建议 V1 默认：

| 项目 | 默认 | 原因 |
|---|---:|---|
| entry 数量 | 2,000 | 足够覆盖多步 Agent 流程 |
| 单条 message 上限 | 8 KiB | 防止 print 巨大 JSON 占满 store |
| metadata 数量上限 | 32 个键值对 | bridge metadata 只保留摘要，避免响应体膨胀 |
| metadata key 上限 | 128 字节 | 防止异常 key 撑大响应 |
| metadata value 上限 | 1,024 字节 | 防止异常 value 撑大响应 |
| read limit 默认 | 100 | 适合动作后诊断 |
| read limit 最大 | 500 | 限制 response 与 Agent token |
| store 总目标 | 约 4–8 MiB | Debug 工具可接受但保持有界 |

限制不是安全保证，只是防止单个异常日志源吞掉整个 app 内存。

### 12.2 AppLogStore 行为

- 使用当前项目统一的 `Mutex` 保护可变状态；
- 锁内只做 entry append、计数、ring 驱逐、cursor snapshot；
- 不在锁内 redaction、UTF-8 解码、JSON 编码、任何 await 或 IO；
- 每次 append 分配一个物理 id；
- 达到上限先移除最旧 entry；
- 记录 `oldestAvailableID`；
- 由 `read` 负责把 old cursor 与 oldest id 比较并形成 gap。

### 12.3 丢弃不是静默失败

如果 stream 突发导致 entry 被截断 / store 覆盖，必须可见：

```json
{
  "messageTruncated": true
}
```

或：

```json
{
  "gap": {
    "kind": "bufferOverrun"
  }
}
```

不要为了“日志看上去连续”隐瞒已经丢失的证据。

---

## 13. 脱敏与日志安全

### 13.1 风险

UI hierarchy 通常只暴露当前屏幕；日志可能包含：

- Authorization / Bearer token；
- Cookie；
- password；
- 手机号、身份证号；
- 请求体与响应体；
- 服务端异常堆栈中的业务数据。

虽然当前工具依赖开发环境、USB 转发和 Debug 集成，但“仅 Debug”不是不做基本防护的理由。

### 13.2 V1 必须做

写入 store 前统一 redaction：

- key/value 样式：`Authorization:`, `Bearer `, `Cookie:`, `password=`, `token=`, `access_token`, `refresh_token`；
- JSON 常见字段：`"password"`, `"token"`, `"authorization"`, `"cookie"`；
- 只保留 `[REDACTED]`；
- 先 redaction，后截断；
- redactor 规则可配置，但默认 `.standard` 不允许完全关闭为无防护模式；
- 只有宿主显式构造 `.unsafeNoRedaction` 且在 Debug 条件下才允许，且 registration result 标记 `securityWarning=true`。

### 13.3 不自动记录的内容

- iOSExplore HTTP request 的完整 data；
- HTTP response 的完整 data；
- `ExploreAppLog` metadata 中超出大小限制的内容；
- 任意对象通过 `String(describing:)` 序列化后的巨大文本。

---

## 14. 实施顺序与每阶段“完成”定义

这是最重要的工程调整：不再用一句“同一个 V1 全部做完”掩盖不同技术风险。

### 阶段 1：稳定协议与可查询日志核心

目标：先交付不依赖 fd / hook 的可靠闭环。

实现：

1. 新增 `iOSExploreDiagnostics` target/product；
2. `AppLogEntry`、`AppLogCursor`、`AppLogStore`；
3. `app.logs.mark`、`app.logs.read`；
4. `captureSessionID`、pagination、gap、session mismatch；
5. `ExploreLogging` observer 拆分，`explore` source 录入 store；
6. `ExploreAppLog` bridge；
7. redaction、截断、status；
8. SPM 与 framework 工程同步；
9. Agent usage docs 更新为 `mark → action → ui.wait/ui.waitAny → read`。

验收：

```text
不打开 Unified Logging output，
ExploreLogging 的内部路由日志仍能由 app.logs.read 获取；
ExploreAppLog 也可被 read 获取；
cursor/gap/session mismatch/分页全部单元测试覆盖。
```

这一步已经让 Agent 能获得“框架运行 + 宿主主动业务信号”，是完整可用的第一条稳定证据链。

### 阶段 2：stdout / stderr fd capture

目标：把 stdout/stderr fd capture 接入正式 Diagnostics runtime，但保持默认关闭。

交付物：

```text
StdIOCapture.swift
DiagnosticsConfiguration.captureStdout / captureStderr
app.logs.mark/read capture 状态
stdout/stderr 单元回归
resetForTesting fd 恢复
```

验收：

```text
captureStdout=false 时 stdout.state=notCaptured；
captureStdout=true 且安装成功时 stdout.state=enabled；
stdout 写入后可用 sources:["stdout"] 读取，level=info；
stderr 写入后可用 sources:["stderr"] 读取，level=error；
无换行尾部在 reset/停止捕获时 flush；
reset 后不再污染旧 store。
```

### 阶段 3：stdout / stderr 示例 App 开关与 curl 验证入口

目标：在不改变 SPMExample 默认关闭配置的前提下，让真实 App/Agent 能通过稳定开关打开 stdout/stderr capture，并用 HTTP 命令产生可识别输出，再用 `app.logs.read` 验证。

已实现：

1. SPMExample 增加仅 Debug 的配置开关：`IOS_EXPLORE_CAPTURE_STDOUT=1` / `IOS_EXPLORE_CAPTURE_STDERR=1`，以及启动参数 `--ios-explore-capture-stdout` / `--ios-explore-capture-stderr`；
2. SPMExample 增加仅 Debug 的 `debug.emitStdout` / `debug.emitStderr`，分别向 stdout/stderr 写入调用方传入的唯一文本，并在响应里返回 `source`、`message`、`bytes`；
3. SPMExampleTests 覆盖默认关闭、环境变量打开、启动参数打开、debug 命令注册和写流响应契约；
4. 文档给出 autostart + capture 开关 + `app.logs.mark` + `debug.emitStdout` / `debug.emitStderr` + `app.logs.read` 的 curl 验证流程。

仍需真实环境记录：

1. simulator curl 验证 stdout/stderr 读取得到 `source=stdout/level=info` 与 `source=stderr/level=error`；
2. device + iproxy curl 验证同样结果；
3. 验证 `teeToOriginalStreams=true` 时原控制台仍可见；
4. 验证 burst 输出不阻塞 HTTP server。

验收：

```text
stdout/stderr 在 device + simulator 通过真实 App 验证；
stream capture 安装失败只降级对应 source，不破坏 app.logs、server 或 UI command；
文档明确 SPMExample 默认 false 时不能声称已 curl 验证 stdout/stderr。
```

### 阶段 4：NSLog spike

目标：回答“可不可以安全做”，不是承诺“必须本阶段上线”。

实现范围：

- 独立 backend prototype；
- `NSLog` / `NSLogv` 调用路径验证；
- Swift、Objective-C、静态 target、动态 framework、并发 burst、中文/emoji；
- simulator/device；
- 原始 NSLog 行为保留；
- 失败不影响其它 source。

结果分叉：

```text
验证通过：
  设计 V1.1 的 bestEffortEnabled backend，增加明确 limitation。

验证不通过 / 代价超过收益：
  不接入 hook；
  status=unavailable；
  文档引导关键 NSLog 场景改用 ExploreAppLog bridge。
```

### 阶段 5：是否处理 `app.logs.*` 自噪声

前提：真实 Agent run 中证明少量控制面日志使诊断结果难用。

只有届时才改：

```text
Command / AnyCommand / Router
```

建议的长期方案不是 message matching，而是在 command metadata 中加入内部执行日志策略。该改动要有独立 design 和全命令回归，不能搭载在初次 Diagnostics 实现中。

---

## 15. 测试清单

### 15.1 Core / Diagnostics 单元测试

`AppLogStore`：

- id 严格递增；
- 同 session mark/read；
- `after` 为空读取最近 limit；
- source filter；
- `minimumLevel`；
- page `nextCursor` 使用最后扫描 id；
- `hasMore`；
- ring 覆盖 gap；
- capture session mismatch；
- timestamp / order；
- message truncation；
- metadata truncation。

`ExploreLogging`：

- output disabled 时 observer 仍收到 record；
- output minimum level 不改变 Diagnostics capture；
- observer removal；
- observer 不在 logging lock 内执行；
- observer 不阻断 output sink；
- message 在真正需要前不构造。

`ExploreAppLog`：

- runtime 未安装 no-op；
- runtime 安装后写入 bridge；
- redaction；
- metadata 上限；
- release stub 行为。

### 15.2 TCP 端到端测试

通过真实 HTTP listener 请求：

```text
app.logs.mark
→ 注册或触发 bridge 日志
→ app.logs.read(after:)
```

验证：

- JSON envelope；
- 输入 schema；
- cursor JSON decode；
- stale cursor error；
- response size；
- multiple clients 读同一进程 store；
- `help` 能发现两个 action（仅 Debug Diagnostics 已注册时）。

### 15.3 stdout/stderr 单元回归与真实 App 验证

在 simulator + device：

```swift
print("stdout-check-中文-😀")
debugPrint("debug-check")
FileHandle.standardError.write(Data("stderr-check\n".utf8))
```

必要时提供 C helper 测：

```c
fprintf(stderr, "stderr-c-check\n");
```

每次验证同时观察：

1. `app.logs.read` 获取对应 `source` 与文本；
2. Xcode Console 仍可看到输出；
3. 日志只记录一次，不递归；
4. 连续输出、无换行、超长行、UTF-8 chunk 边界正确；
5. UI 主线程计时器仍按预期运行；
6. server 仍可响应 ping / logs read；
7. `server.stop(); server.start()` 后不重复 capture；
8. 重复 registration 会先恢复旧 fd，再安装新捕获，不重复记录同一行。

### 15.4 NSLog spike 矩阵

| 场景 | Simulator | Device | 通过要求 |
|---|---:|---:|---|
| Swift 直接 `NSLog` | 必测 | 必测 | 文本被捕获且原输出存在 |
| Objective-C 直接 `NSLog` | 必测 | 必测 | 同上 |
| `%@`, `%d`, format / `va_list` | 必测 | 必测 | 无崩溃、格式正确 |
| 中文、emoji、超长文本 | 必测 | 必测 | 无乱码和崩溃 |
| 静态 SPM target | 必测 | 必测 | 记录路径明确 |
| 动态 framework | 必测 | 必测 | 覆盖结果明确 |
| 多线程 burst | 必测 | 必测 | 不死锁、不递归 |
| 重复 install | 必测 | 必测 | 不双 hook |

失败要记录为“未支持/覆盖有限”的工程事实，不应被包装成“理论上已经支持”。

---

## 16. 对 Codex 评审的逐项裁决

| Codex 意见 | 结论 | 本修订的具体变化 |
|---|---|---|
| 不要把 `NSLog` hook 作为 V1 完成门槛 | 完全接受 | 改为 V1 spike；正式接入进入 V1.1/V1.2，失败不阻塞基础能力 |
| stdout/stderr 可进第一版，但必须有验证矩阵 | 已按第二阶段接入 | 当前已接入 `StdIOCapture` 并有单元回归；真实 simulator/device 示例 App 验证仍作为后续补充记录 |
| `lifecycleLogging = suppressed` 影响公共路径过大 | 接受 | V1 不改 Router/AnyCommand；容忍少量控制面噪声，后续独立演进 |
| 文档出现不存在的 `ui.observe` | 完全接受 | 所有流程改为 `ui.wait` / `ui.waitAny` / hierarchy observation |
| Debug/Release 要落到 SwiftPM/Xcode 现实 | 完全接受 | 不称 Debug-only product；明确 `#if DEBUG`、Release stubs、framework 同步 |
| Core + Diagnostics 独立模块合理 | 保留 | Diagnostics 继续依赖 Core、不依赖 UIKit |
| `mark + read` 优于 tail | 保留 | 协议固定，增加 last-scanned pagination 语义 |
| cursor + gap + session id 设计扎实 | 保留并加强 | 明确 `stale_cursor` 与 ring overflow 的不同处理 |

---

## 17. 最终完成定义

以下全部满足，才可称为“进程日志能力 V1 已完成”：

### 必须满足

- [ ] `iOSExploreDiagnostics` product 和 framework 集成路径完整；
- [ ] `app.logs.mark`、`app.logs.read` 协议稳定；
- [ ] cursor 包含 `captureSessionID + id`；
- [ ] Pagination、gap、stale cursor 有明确返回；
- [ ] `ExploreLogging` observer 与 Unified Logging output 解耦；
- [ ] `explore` source 可查询，即使 Unified Logging output 未开启；
- [ ] `ExploreAppLog` bridge 可查询且默认脱敏；
- [ ] `stdout/stderr` 默认关闭，配置开启并安装成功后可按 `stdout` / `stderr` source 查询；
- [ ] stream capture 失败只降级 source，不影响 server 与 UI command；
- [ ] Release 下不会安装 fd capture 或 runtime hook；
- [ ] SPM、framework、SPMExample 均有构建和测试记录；
- [ ] Agent protocol 不使用不存在的 action；
- [ ] README / docs 明确“不读取全部 Xcode Console / 系统全局日志”。

### 不作为 V1 完成门槛

- [ ] `NSLog` 正式 interception backend；
- [ ] 透明获取全量 `Logger` / `os_log`；
- [ ] 控制命令生命周期日志 suppression；
- [ ] 面向宿主的公开动态卸载 API；
- [ ] 跨 App / 跨进程日志聚合。

---

## 18. 最终推荐

采用以下路线：

```text
稳定的 App Process Logs 协议
  = app.logs.mark + app.logs.read
  = cursor + gap + bounded store
  = explore + bridge 的可靠基础日志
  = stdout/stderr 默认关闭、按配置启用的 fd capture

NSLog
  = 重要但高风险的独立 spike
  = 结果决定 V1.1/V1.2 是否提供 bestEffortEnabled backend
  = 永远不承诺“完整 Xcode Console”或“全量系统日志”
```

这样做同时满足两个目标：

1. **产品目标不缩水**：Agent 仍能理解宿主 App 的业务运行证据，而不只是看 iOSExplore 自己的 router 日志。
2. **工程节奏不失控**：`NSLog` ABI / hook / image 覆盖的不确定性不会绑架已经可验证、价值很高的日志协议、explore 与 bridge 能力。

已完成的基础路径是：

```text
iOSExploreDiagnostics
→ AppLogStore
→ app.logs.mark / app.logs.read
→ ExploreLogging observer
→ ExploreAppLog bridge
→ cursor/gap/TCP tests
→ StdIOCapture 可选 stdout/stderr fd capture
```

下一步不应把 stdout/stderr 和 `NSLog` 混在一起；stdout/stderr 只需要补真实 simulator + device 的示例 App 验证记录，`NSLog` 仍需要更严格的独立 spike 决定后续版本。

## 18. 当前实现状态更新：NSLog / os_log / Logger 已接入 Debug Diagnostics

本节记录 2026-07-05 后续实现结果，用于覆盖本文早期“NSLog / os_log / Logger 未实现”的阶段性判断。早期章节保留为设计评审历史，但不能再当作当前能力边界引用。

当前 `iOSExploreDiagnostics` 已新增：

- `DiagnosticsConfiguration.captureNSLog`：默认关闭；打开后复用 stderr fd capture 管道，识别 `NSLog` 行并写入 `AppLogStore`，source 为 `nslog`，level 为 `info`。
- `DiagnosticsConfiguration.captureOSLog`：默认关闭；打开后通过 `OSLogStore(scope: .currentProcessIdentifier)` 轮询当前进程 Apple Unified Logging，能读取到的 `os_log` 与 Swift `Logger` entry 写入 `AppLogStore`，source 为 `oslog`。
- `UnifiedLogCapture.swift`：负责 Debug-only `OSLogStore` 读取、状态报告、轮询停止和错误日志。若 OS 或沙箱不允许读取，`capture.oslog` 返回 `unavailable`，不伪装成“没有日志”。
- `SPMExample` Debug 开关：`IOS_EXPLORE_CAPTURE_NSLOG=1` / `--ios-explore-capture-nslog`，`IOS_EXPLORE_CAPTURE_OSLOG=1` / `--ios-explore-capture-oslog`。
- `SPMExample` Debug 命令：`debug.emitNSLog`、`debug.emitOSLog`、`debug.emitLogger`，用于真实 curl 验证。

已补测试覆盖：

- `NSLog` 打开后可通过 `sources:["nslog"]` 读到，关闭时不进入 store。
- `os_log` 与 Swift `Logger` 打开后可通过 `sources:["oslog"]` 读到。
- Example App 默认关闭 stdout/stderr/NSLog/os_log，只有环境变量或启动参数打开时才启用。

仍需注意：`captureOSLog` 依赖 Apple 的当前进程 `OSLogStore` 可读性；不同 iOS 版本、真机策略或沙箱限制可能返回 `unavailable`。这属于运行时状态，不应再写成“未实现”。
