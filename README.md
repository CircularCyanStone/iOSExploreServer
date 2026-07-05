# iOSExploreServer

手机端 HTTP Server（基于 `NWListener`）的 SPM 库。Mac 经 `iproxy`（USB）转发后用 `curl` 向 iPhone App 发送 JSON 命令，App 按 `action` 分发执行并返回统一 envelope。为后续 Mac 侧 MCP 对接铺路。

## 通信链路

```
Mac curl ──→ localhost:38321 ──[iproxy 38321 38321]──→ iPhone :38321 ──→ ExploreServer
```

## 快速开始

1. 在手机/模拟器上运行集成了 iOSExploreServer 的 App（见 `Examples/SPMExample`），启动 Server。
2. Mac 上起转发（真机）：
   ```bash
   ./scripts/proxy.sh
   ```
   > 模拟器无需 `iproxy`：App 监听的端口 Mac 本机直接可达。
3. 发命令：
   ```bash
   curl -X POST http://localhost:38321/ -d '{"action":"ping"}'
   curl -X POST http://localhost:38321/ -d '{"action":"ui.screenshot"}'
   ```

## 命令协议

请求：`POST /`，body `{"action":"<name>","data":{...}}`。
响应：`{"code":"ok","data":{...}}` 或 `{"code":"...","message":"..."}`。

### 命令清单

**core 内置**（`ExploreServer.init` 自动注册；只依赖 Foundation + Network）：

| action | 说明 |
|---|---|
| `ping` | 存活探活，返回 `pong` + uptime |
| `echo` | 原样回显入参 |
| `info` | 设备/系统/应用信息 |
| `help` | 列出全部已注册命令及输入 schema |

**UIKit 扩展**（`server.registerUIKitCommands()` 显式注册；仅 iOS，由宿主决定开启）：

| action | 说明 |
|---|---|
| `ui.topViewHierarchy` | 完整 view 树快照（文本/颜色/控件状态） |
| `ui.viewTargets` | canonical interaction targets 列表（UIControl 系 + UIScrollView 系；返回 path + 可用动作 + viewSnapshotID） |
| `ui.tap` | 对 `ui.viewTargets` 签发的 canonical target 执行默认激活动作（accessibilityIdentifier / path + 必填 viewSnapshotID） |
| `ui.control.sendAction` | 向 UIControl 发 target-action 事件（path/identifier + 必填 viewSnapshotID + 显式 event） |
| `ui.screenshot` | 截屏（PNG base64，降采样；可选视觉证据，不再签发 viewSnapshotID） |
| `ui.input` | 向 UITextField / UITextView 注入文本（UITextInput.insertText） |
| `ui.keyboard.dismiss` | 收起当前 first responder / 键盘 |
| `ui.scroll` | 在 UIScrollView 上按方向 + 距离滚动 |
| `ui.navigation.back` | 返回上一页（auto 先 dismiss 再 navigation pop） |
| `ui.navigation.tapBarButton` | 触发导航栏 UIBarButtonItem（placement + index，可用 title/identifier 防误点） |
| `ui.wait` | 等待 UI 稳定或等待目标/文本/快照变化 |
| `ui.waitAny` | 一次轮询等待多个条件，第一个命中返回 matchedID/matchedIndex |
| `ui.scrollToElement` | 滚动到包含指定文本/identifier 的元素可见 |
| `ui.alert.respond` | 查询 UIAlertController（dryRun=true）；dryRun=false 触发指定按钮 handler 并关闭弹窗 |

UIKit 命令不会自动注册，宿主 App 须显式开启：

```swift
import iOSExploreServer
import iOSExploreUIKit

let server = ExploreServer()
server.registerUIKitCommands()   // 一次性注册 14 个 ui.* 命令
```

`ui.*` 典型闭环：先 `ui.viewTargets` 观察页面拿到 canonical target 的 `path` 与本次 `viewSnapshotID`（仅此命令签发，`ui.screenshot` / `ui.topViewHierarchy` 都不再签发）→ 优先用 `accessibilityIdentifier`，必要时用 `path + viewSnapshotID` 调动作。`ui.tap` / `ui.control.sendAction` 必填 `viewSnapshotID` 并校验 freshness；`ui.input` / `ui.scroll` 只有在 `path + viewSnapshotID` 组合下做可选陈旧防护；滚动后应重新 `ui.viewTargets`。动作后用 `ui.wait` 等待明确反馈，或重新 `ui.viewTargets` 观察页面；必要时用 `ui.screenshot` 留失败证据。`ui.tap` 成功只表示激活动作已发出，不表示测试步骤成功。可直接照跑的 JSON/curl 闭环见 `docs/superpowers/agent-mcp-exploration/curl-json-loop-protocol.md`。

**Diagnostics 扩展**（`server.registerDiagnosticsCommands()` 显式注册；不依赖 UIKit）：

| action | 说明 |
|---|---|
| `app.logs.mark` | 建立当前进程日志检查点，返回 `captureSessionID + id` cursor |
| `app.logs.read` | 读取 cursor 之后由 iOSExplore 实际捕获并保留的增量日志 |

已支持 `explore`（iOSExplore 内部日志）、`bridge`（宿主主动 `ExploreAppLog.emit`），以及默认关闭、Debug 下显式开启的 stdout/stderr/NSLog/Apple Unified Logging 捕获。宿主用 `DiagnosticsConfiguration(captureStdout: true, captureStderr: true, captureNSLog: true, captureOSLog: true)` 开启后，stdout 每行以 `source="stdout"` / `level="info"` 写入，stderr 每行以 `source="stderr"` / `level="error"` 写入，`NSLog` 识别为 `source="nslog"`，`os_log` 与 Swift `Logger` 通过当前进程 `OSLogStore` 写入 `source="oslog"`。如果当前 OS 或沙箱不允许读取 unified logging，`capture.oslog` 会返回 `unavailable`，不会伪装成没有日志。

```swift
import iOSExploreServer
import iOSExploreDiagnostics

let server = ExploreServer()
server.registerDiagnosticsCommands()
ExploreAppLog.emit(.error, category: "auth", message: "login failed token=...")
```

`Examples/SPMExample` 已在 Debug 集成 `iOSExploreDiagnostics`，`help` 会列出 `app.logs.mark/read`。示例 App 在 Debug 构建下通过 `ViewController.exampleDiagnosticsConfiguration()` 直接打开 stdout/stderr/NSLog/os_log 四个 capture（Release 构建关闭），不再通过环境变量或启动参数控制。它提供 `debug.emitAppLog`、`debug.emitStdout`、`debug.emitStderr`、`debug.emitNSLog`、`debug.emitOSLog`、`debug.emitLogger` 六个验证命令。典型流程是先 `app.logs.mark`，再触发其中一个 debug 命令，最后 `app.logs.read(after:)` 按 `sources:["bridge"]`、`sources:["stdout"]`、`sources:["stderr"]`、`sources:["nslog"]` 或 `sources:["oslog"]` 读取对应日志。

### 注册自定义命令

```swift
struct GreetInput: CommandInput {
    static let name = CommandFields.optionalString("name", description: "姓名")
    static let inputSchema = CommandInputSchema(fields: [name.erased])

    let nameValue: String

    static func parse(decoding decoder: inout CommandInputDecoder) throws -> GreetInput {
        GreetInput(nameValue: try decoder.read(name) ?? "world")
    }
}

server.register(action: "greet", description: "按 name 打招呼", input: GreetInput.self) { input in
    .success(["message": .string("Hello, \(input.nameValue)")])
}
```

## 现状与路线图

**已实现**：core 4 个 action 自动注册；UIKit 扩展显式注册 14 个 `ui.*` action；Diagnostics 扩展显式注册 2 个 `app.logs.*` action。Example App 额外注册 `greet` / `device` / `debug.emitAppLog` / `debug.emitStdout` / `debug.emitStderr`，并显式开放 UIKit 与 Diagnostics 命令。现有能力链已覆盖查询（`viewTargets` / `topViewHierarchy`）→ 看屏（`screenshot`）→ 操作（`tap` / `input` / `scroll` / `control` / `navigation` / `keyboard`）→ 等待（`ui.wait` 单条件 / `ui.waitAny` 多分支）→ 读取动作后的进程内增量日志（`app.logs.mark/read`）。

**质量**：macOS `swift test` 225 用例 + iOS framework 344 用例全绿；历史三层验证记录见 `docs/superpowers/agent-mcp-exploration/runtime-validation-2026-07-02.md`。

**最近修复**：HTTPListener 连接槽耗尽后 server 不响应（Network 层 `newConnectionLimit` 被误设为业务上限，连接关闭后不释放）。

**下一步**：Agent 使用协议已写入 `docs/superpowers/agent-mcp-exploration/agent-usage-protocol.md`，可运行的 curl/JSON 闭环写入 `docs/superpowers/agent-mcp-exploration/curl-json-loop-protocol.md`。navigationBar / UIBarButtonItem 可达性与 `ui.tap` 结构化默认激活已完成；`ui.alert.respond` 的 `dryRun=false` 已实现——通过 Debug-only 私有方法 `_dismissWithAction:` 让系统自动 dismiss + 调 handler，五案例（simple/threeButtons/loginInput/actionSheet/nested）真机验证通过；多结果等待（`ui.waitAny`）已完成——一次轮询等待多个可能结局，按命中 `matchedID` 分支。目标是让 Agent 能按自然语言测试目标持续观察、操作并验证 App，而不是只暴露一组零散命令。

## 调试日志

组件默认不输出内部日志到 Unified Logging。调试时在 App 启动阶段开启：

```swift
ExploreLogging.setEnabled(true)
ExploreLogging.setMinimumLevel(.debug)
```

日志走 Apple Unified Logging，subsystem 为 `iOSExploreServer`，category 包括 `server`、`listener`、`http`、`router`、`command`。可在 Xcode 控制台或 macOS Console 中按 subsystem/category 过滤查看。若已注册 `iOSExploreDiagnostics`，`ExploreLogging` 的内部日志还会进入 Diagnostics 内存 store，即使 Unified Logging output 没有开启。

## 开发

```bash
swift test                              # macOS SPM 测试
swift test --enable-code-coverage       # 覆盖率
xcodebuild -project iOSExploreServer/iOSExploreServer.xcodeproj \
  -scheme iOSExploreServer -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17' test            # iOS framework 测试
```

更多详见 `AGENTS.md`（架构硬规则、模块边界、完整命令清单）与 `docs/`（架构总览、构建/排障 runbook、UIKit 模块档案、设计 spec）。

端口默认 `38321`，构造时可配。不强制鉴权（依赖 USB 物理连接隔离），App 须保持前台。
