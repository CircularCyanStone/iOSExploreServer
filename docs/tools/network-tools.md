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
| `ui.topViewHierarchy` | 可选筛选参数 | 当前顶部控制器 view 层级或匹配节点列表（UIKit 平台） |
| `ui.control.sendAction` | `accessibilityIdentifier` 或 `path` + `event` | 向指定 UIControl 发送 target-action 事件（UIKit 平台） |
| `ui.tap` | `accessibilityIdentifier`、`path` 或 window 坐标 | 命中测试后执行点击语义（第一版 UIControl fallback） |

## UIKit 命令

### `ui.topViewHierarchy`

返回当前前台 window 的顶部控制器 view 及其全部子视图的结构化快照。常用请求：

```bash
curl -X POST http://localhost:38321/ -d '{"action":"ui.topViewHierarchy"}'
curl -X POST http://localhost:38321/ -d '{"action":"ui.topViewHierarchy","data":{"maxDepth":2}}'
curl -X POST http://localhost:38321/ -d '{"action":"ui.topViewHierarchy","data":{"accessibilityIdentifierPrefix":"mine."}}'
```

可选参数：

- `detailLevel`: `basic` / `appearance` / `full`，默认 `appearance`。
- `maxDepth`: 最大递归深度，`0` 表示只返回根 view。
- `includeHidden`: 是否包含隐藏 view，默认 `false`。
- `accessibilityIdentifier`: 按 identifier 精确筛选。
- `accessibilityIdentifierPrefix`: 按 identifier 前缀筛选。

无筛选时响应 `data.root` 是完整树；带 identifier 筛选时响应 `data.matches` 是匹配节点列表。每个节点包含 `path`、`type`、accessibility 字段、`frame`、`bounds`、`state`、`text`、`appearance`、`control`、`image`、`scroll` 和 `subviews`。

事件下发前可先用轻量目标发现命令获取扁平 targets 列表：

```bash
curl -X POST http://localhost:38321/ \
  -H 'Content-Type: application/json' \
  -d '{"action":"ui.viewTargets","data":{"includeStaticText":true,"textLimit":80}}'
```

### `ui.control.sendAction`

向当前顶部控制器 view 层级中的指定 `UIControl` 发送 target-action 事件。常用请求：

```bash
curl -X POST http://localhost:38321/ -d '{"action":"ui.control.sendAction","data":{"accessibilityIdentifier":"mine.header.avatar","event":"touchUpInside"}}'
curl -X POST http://localhost:38321/ -d '{"action":"ui.control.sendAction","data":{"path":"root/0/2/1","event":"valueChanged"}}'
```

定位参数二选一：

- `accessibilityIdentifier`: 按业务层设置的 identifier 精确定位。若匹配多个 view，会返回 `invalid_data`，避免误触发。
- `path`: 使用 `ui.viewTargets` 或 `ui.topViewHierarchy` 返回的只读路径，例如 `root/0/2/1`。

事件名：

- `touchDown`
- `touchUpInside`
- `valueChanged`
- `editingChanged`
- `editingDidBegin`
- `editingDidEnd`

成功响应包含 `sent`、`event`、`path`、`type`、`accessibilityIdentifier`、`isEnabled`、`isSelected`、`isHighlighted`。该命令只调用 `UIControl.sendActions(for:)`，不模拟真实触摸坐标、命中测试或控件高亮过程；需要真实点击时应使用后续独立的 `ui.tap`。

### `ui.tap`

执行更接近用户点击语义的操作。第一版会先做 `window.hitTest` 校验，再对命中的 `UIControl` 使用 `.touchUpInside` fallback：

```bash
curl -X POST http://localhost:38321/ -d '{"action":"ui.tap","data":{"accessibilityIdentifier":"mine.header.avatar"}}'
curl -X POST http://localhost:38321/ -d '{"action":"ui.tap","data":{"path":"root/0/2/1"}}'
curl -X POST http://localhost:38321/ -d '{"action":"ui.tap","data":{"x":120,"y":300,"coordinateSpace":"window"}}'
```

定位方式三选一：

- `accessibilityIdentifier`: 按业务 identifier 精确定位 view。
- `path`: 按 `ui.viewTargets` 或 `ui.topViewHierarchy` 返回的只读路径定位 view。
- `x` + `y`: 直接使用 window 坐标；`coordinateSpace` 第一版仅支持 `window`。

按 view 定位时，命令取目标 view 中心点转换到 window 坐标，并校验 `hitTest` 命中的 view 是目标或其子孙/祖先关系中的相关 view。如果中心点被其他 view 遮挡，会返回 `invalid_data`。

成功响应包含 `tapped`、`dispatchMode`、`event`、`x`、`y`、`target`、`hitType`、`hitPath`、`controlType`、`controlPath`、`accessibilityIdentifier`。第一版 `dispatchMode` 为 `controlActionFallback`，表示内部调用 `UIControl.sendActions(for: .touchUpInside)`；非 UIControl 暂不伪造系统触摸事件，会返回明确不支持。

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
curl -X POST http://localhost:38321/ -d '{"action":"ui.topViewHierarchy","data":{"maxDepth":2}}'
curl -X POST http://localhost:38321/ -d '{"action":"ui.control.sendAction","data":{"accessibilityIdentifier":"mine.header.avatar","event":"touchUpInside"}}'
curl -X POST http://localhost:38321/ -d '{"action":"ui.tap","data":{"accessibilityIdentifier":"mine.header.avatar"}}'
```

- 模拟器无需 iproxy：Mac 与模拟器共享网络栈，直接 `curl http://127.0.0.1:38321/` 即可（前提模拟器 App 已启动 Server）。
- 服务端**不校验 Content-Type**，`curl -d` 默认 `application/x-www-form-urlencoded` 也能工作；规范起见可加 `-H 'Content-Type: application/json'`。

## iproxy 工作原理（重要）

`iproxy <macport> <deviceport>` 在 Mac 监听 `macport`，**被动等待** Mac 客户端连接；客户端一连，它把连接通过 USB 转发到设备 `deviceport`。所以 `proxy.sh` 启动后显示 `waiting for connection` 是**正常状态**——它在等 `curl` 来连，不是在等设备。详见 `docs/runbooks/debugging.md`。

## 端口

- 默认 **38321**（库默认 + `proxy.sh` 默认）。
- 集成测试用 **38399**（避开生产默认，见 `Tests/iOSExploreServerTests/IntegrationTests.swift`）。
