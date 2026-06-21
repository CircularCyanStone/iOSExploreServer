# 网络协议与命令工具

## HTTP 协议（单端点 + JSON 分发）

**请求**：`POST /`，body 为 JSON：
```json
{ "action": "ping", "data": {} }
```
- `action`（必填，字符串）：命令名。
- `data`（可选，对象）：命令参数。

**成功响应**：
```json
{ "ok": true, "data": { "pong": true } }
```

**业务失败响应**：
```json
{ "ok": false, "error": { "code": "unknown_action", "message": "no handler for 'foo'" } }
```

错误码：`unknown_action` / `invalid_data` / `internal_error` / `bad_request`。

## 内置命令

| action | 入参 | 成功 data |
|---|---|---|
| `ping` | 忽略 | `{ "pong": true }` |
| `echo` | 任意对象 | 原样回显入参 `data` |
| `info` | 忽略 | `{ "system":..., "app":..., "bundle":... }`（来自 `ProcessInfo`/`Bundle`） |

## 注册自定义命令

库内或 App 内：
```swift
await server.register(action: "greet") { req in
    let name = req.data["name"]?.stringValue ?? "world"
    return .success(["message": .string("Hello, \(name)")])
}
```
- handler 签名：`@Sendable (ExploreRequest) async throws -> ExploreResult`
- `req.data["key"]` 返回 `JSONValue?`，用 `.stringValue`/`.doubleValue`/`.boolValue` 取值。
- 需要 UIKit（如 `UIDevice`）时，在 handler 内 `await MainActor.run { ... }` 取值再返回（见 SPMExample 的 `device` handler）。

## Mac 侧调用（iproxy + curl）

```bash
# 1) 手机上启动 App，点「启动 Server」
# 2) Mac 起转发（前台，Ctrl-C 停）
./scripts/proxy.sh          # 等价 iproxy 38321 38321
# 3) 另开终端发命令
curl -X POST http://localhost:38321/ -d '{"action":"ping"}'
curl -X POST http://localhost:38321/ -d '{"action":"info"}'
curl -X POST http://localhost:38321/ -d '{"action":"greet","data":{"name":"Claude"}}'
```

- 模拟器无需 iproxy：Mac 与模拟器共享网络栈，直接 `curl http://127.0.0.1:38321/` 即可（前提模拟器 App 已启动 Server）。
- 服务端**不校验 Content-Type**，`curl -d` 默认 `application/x-www-form-urlencoded` 也能工作；规范起见可加 `-H 'Content-Type: application/json'`。

## iproxy 工作原理（重要）

`iproxy <macport> <deviceport>` 在 Mac 监听 `macport`，**被动等待** Mac 客户端连接；客户端一连，它把连接通过 USB 转发到设备 `deviceport`。所以 `proxy.sh` 启动后显示 `waiting for connection` 是**正常状态**——它在等 `curl` 来连，不是在等设备。详见 `docs/runbooks/debugging.md`。

## 端口

- 默认 **38321**（库默认 + `proxy.sh` 默认）。
- 集成测试用 **38399**（避开生产默认，见 `Tests/iOSExploreServerTests/IntegrationTests.swift`）。
