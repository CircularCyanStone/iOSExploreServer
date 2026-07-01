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

### 命令清单（11 个）

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
| `ui.viewTargets` | 扁平可交互目标列表（path + 可用动作 + snapshotID） |
| `ui.tap` | 点击（accessibilityIdentifier / path 定位，或 window 坐标） |
| `ui.control.sendAction` | 向 UIControl 发 target-action 事件 |
| `ui.screenshot` | 截屏（PNG base64，降采样 + 签发 snapshotID） |
| `ui.input` | 向 UITextField / UITextView 注入文本（UITextInput.insertText） |
| `ui.keyboard.dismiss` | 收起当前 first responder / 键盘 |
| `ui.scroll` | 在 UIScrollView 上按方向 + 距离滚动 |

UIKit 命令不会自动注册，宿主 App 须显式开启：

```swift
import iOSExploreServer
import iOSExploreUIKit

let server = ExploreServer()
server.registerUIKitCommands()   // 一次性注册 9 个 ui.* 命令
```

`ui.*` 典型闭环：先 `ui.viewTargets`（或 `topViewHierarchy`）拿到目标的 `path` 和 `snapshotID` → 用 `path` + `snapshotID` 调 `ui.tap` / `ui.input` / `ui.scroll`（snapshotID 做陈旧防护，防画面已变还按旧坐标操作）→ 必要时用 `ui.keyboard.dismiss` 收起键盘 / `ui.navigation.back` 返回上一页 → `ui.screenshot` 截图看效果。这就是 AI agent 驱动 UI 的完整循环。

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

**已实现**：11 个 action（core 4 + UIKit 7），补齐了 AI agent 闭环驱动 iPhone UI 的能力链——查询（`viewTargets` / `topViewHierarchy`）→ 看屏（`screenshot`）→ 操作（`tap` / `input` / `scroll` / `control`）。

**质量**：macOS `swift test` 165 用例 + iOS framework 207 用例全绿，行覆盖 91.5%。

**最近修复**：HTTPListener 连接槽耗尽后 server 不响应（Network 层 `newConnectionLimit` 被误设为业务上限，连接关闭后不释放）。

**下一步**：Mac 侧 MCP server——把每个 `action` 暴露为一个 MCP tool，让 AI（如 Claude）直接驱动 iPhone App，不必手写 `curl`。

## 调试日志

组件默认不输出内部日志。调试时在 App 启动阶段开启：

```swift
ExploreLogging.setEnabled(true)
ExploreLogging.setMinimumLevel(.debug)
```

日志走 Apple Unified Logging，subsystem 为 `iOSExploreServer`，category 包括 `server`、`listener`、`http`、`router`、`command`。可在 Xcode 控制台或 macOS Console 中按 subsystem/category 过滤查看。

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
