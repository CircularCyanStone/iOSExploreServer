# iOSExploreServer

手机端 HTTP Server（基于 `NWListener`），让 Mac 经 iproxy 转发后用 curl 向 App 发送命令。SPM 库 + 可编译的 framework 工程。

## 通信链路

```
Mac curl ──→ localhost:38321 ──[iproxy 38321 38321]──→ iPhone :38321 ──→ ExploreServer
```

## 快速开始

1. 在手机上运行集成了 iOSExploreServer 的 App（见 `Examples/SPMExample`），点击「启动 Server」。
2. Mac 上起转发：
   ```bash
   ./scripts/proxy.sh
   ```
3. 另开终端发命令：
   ```bash
   curl -X POST http://localhost:38321/ -d '{"action":"ping"}'
   curl -X POST http://localhost:38321/ -d '{"action":"info"}'
   ```

## 命令协议

请求：`POST /`，body `{"action":"<name>","data":{...}}`。
响应：`{"ok":true,"data":{...}}` 或 `{"ok":false,"error":{"code":"...","message":"..."}}`。

内置命令：`ping`、`echo`、`info`、`help`。

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

## 调试日志

组件默认不输出内部日志。调试时在 App 启动阶段开启：

```swift
ExploreLogging.setEnabled(true)
ExploreLogging.setMinimumLevel(.debug)
```

日志走 Apple Unified Logging，subsystem 为 `iOSExploreServer`，category 包括
`server`、`listener`、`http`、`router`、`command`。可在 Xcode 控制台或 macOS
Console 中按 subsystem/category 过滤查看。

## 开发

```bash
swift test                 # 运行测试
swift test --enable-code-coverage
```

端口默认 `38321`，构造时可配。MVP 不做强制鉴权（依赖 USB 物理连接），App 须保持前台。
