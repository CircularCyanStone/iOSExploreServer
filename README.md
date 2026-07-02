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

### 命令清单（17 个内置 action）

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
| `ui.navigation.back` | 返回上一页（auto 先 dismiss 再 navigation pop） |
| `ui.navigation.tapBarButton` | 触发导航栏 UIBarButtonItem（placement + index，可用 title/identifier 防误点） |
| `ui.wait` | 等待 UI 稳定或等待目标/文本/快照变化 |
| `ui.scrollToElement` | 滚动到包含指定文本/identifier 的元素可见 |
| `ui.alert.respond` | 查询当前 UIAlertController；当前版本只能 dryRun 查询 |

UIKit 命令不会自动注册，宿主 App 须显式开启：

```swift
import iOSExploreServer
import iOSExploreUIKit

let server = ExploreServer()
server.registerUIKitCommands()   // 一次性注册 13 个 ui.* 命令
```

`ui.*` 典型闭环：先 `ui.viewTargets`（或 `topViewHierarchy`）观察页面并拿到目标的 `path` / `snapshotID` → 优先用 `accessibilityIdentifier`，必要时用 `path + snapshotID` 调 `ui.tap` / `ui.input` / `ui.scroll`（snapshotID 做陈旧防护，防画面已变还按旧路径操作）→ 动作后用 `ui.wait` 等待明确反馈，或重新 `ui.viewTargets` 观察页面 → 必要时用 `ui.screenshot` 留失败证据。`ui.tap` 成功只表示动作已发出，不表示测试步骤成功。

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

**已实现**：17 个内置 action（core 4 + UIKit 13）。Example App 额外注册 `greet` / `device`，`help` 实测共 19 个 action。现有能力链已覆盖查询（`viewTargets` / `topViewHierarchy`）→ 看屏（`screenshot`）→ 操作（`tap` / `input` / `scroll` / `control` / `navigation` / `keyboard`）→ 等待（`ui.wait`）。

**质量**：macOS `swift test` 190 用例 + iOS framework 269 用例全绿；最近一次三层验证记录见 `docs/superpowers/agent-mcp-exploration/runtime-validation-2026-07-02.md`。

**最近修复**：HTTPListener 连接槽耗尽后 server 不响应（Network 层 `newConnectionLimit` 被误设为业务上限，连接关闭后不释放）。

**下一步**：Agent 使用协议已写入 `docs/superpowers/agent-mcp-exploration/agent-usage-protocol.md`。接下来优先补 navigationBar / UIBarButtonItem 可达性，再处理多结果等待与弹窗响应能力。目标是让 Agent 能按自然语言测试目标持续观察、操作并验证 App，而不是只暴露一组零散命令。

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
