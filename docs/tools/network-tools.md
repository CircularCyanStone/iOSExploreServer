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
{ "code": "ok", "data": { "pong": true } }
```

**业务失败响应**：
```json
{ "code": "unknown_action", "message": "no handler for 'foo'" }
```

错误码：`unknown_action` / `invalid_data` / `internal_error` / `bad_request`。

## 内置命令

| action | 入参 | 成功 data |
|---|---|---|
| `ping` | 忽略 | `{ "pong": true }` |
| `echo` | 任意对象 | 原样回显入参 `data` |
| `info` | 忽略 | `{ "system":..., "app":..., "bundle":... }`（来自 `ProcessInfo`/`Bundle`） |
| `ui.topViewHierarchy` | 可选筛选参数 | 当前顶部控制器 view 层级或匹配节点列表（UIKit 平台） |
| `ui.viewTargets` | 可选筛选参数 | 返回 canonical targets、可用动作与 `viewSnapshotID`（UIKit 平台） |
| `ui.control.sendAction` | `accessibilityIdentifier` 或 `path` + `viewSnapshotID` + `event` | 向指定 UIControl 发送显式 target-action 事件（UIKit 平台） |
| `ui.tap` | `accessibilityIdentifier` 或 `path` + `viewSnapshotID` | 对 canonical target 执行默认激活动作（UIKit 平台） |

## UIKit 命令

> UIKit 命令由独立模块 `iOSExploreUIKit` 提供，core **不会自动注册**。宿主 App 必须在创建 `ExploreServer` 后显式调用 `server.registerUIKitCommands()` 才开放下列 14 个 `ui.*` action；未注册时 `help` 不含任何 `ui.*`。SPMExample 已在 `ViewController` 调用该方法。

### 定位语义（所有 `ui.*` 交互命令通用）

定位参数按优先级解析：**`accessibilityIdentifier` 精确 → `path` 只读 → 按命令语义使用 `viewSnapshotID` 陈旧防护**。

- `accessibilityIdentifier`（优先）：按业务层 identifier **精确匹配，不截断、不做 prefix 匹配**。匹配多个 view 返回 `invalid_data`，避免误触发。
- `path`：来自 `ui.viewTargets` / `ui.topViewHierarchy` 的只读路径（`root/0/2`），仅描述当前 view 树内位置，不写回业务 UI。动作授权以 `ui.viewTargets` 为准。
- `viewSnapshotID`：只由 `ui.viewTargets` 签发，代表本次返回 canonical targets 的结构指纹表，不是截图 ID。`ui.tap` / `ui.control.sendAction` 必填，且 identifier/path 都校验 freshness；`ui.input` / `ui.scroll` 仅在 `path + viewSnapshotID` 组合下做可选陈旧校验；`ui.wait(snapshotChanged)` 必填；`ui.screenshot` / `ui.topViewHierarchy` 不签发。页面已变动、snapshot 过期/淘汰或 path 未被签发时返回 `stale_locator`，固定提示调用方重新 `ui.viewTargets`。

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

无筛选时响应 `data.root` 是完整树；带 identifier 筛选时响应 `data.matches` 是匹配节点列表。每个节点包含 `path`、`type`、accessibility 字段、`frame`、`bounds`、`state`、`text`、`appearance`、`control`、`image`、`scroll` 和 `subviews`。`ui.topViewHierarchy` 不签发 `viewSnapshotID`；动作前需要调用 `ui.viewTargets` 获取可执行 canonical target 与 freshness 标识。

事件下发前可先用轻量目标发现命令获取扁平 targets 列表：

```bash
curl -X POST http://localhost:38321/ \
  -H 'Content-Type: application/json' \
  -d '{"action":"ui.viewTargets","data":{"includeStaticText":true,"textLimit":80}}'
```

`ui.viewTargets` 可选参数：`includeHidden`/`includeDisabled`/`includeStaticText`/`includeContainers`（schema 兼容；canonical-only 规则下普通 label/container/gesture view 不进 targets）、`maxDepth`、`accessibilityIdentifier`/`accessibilityIdentifierPrefix`（筛选）、`textLimit`（展示文本截断，默认 80，上限 200）、`maxTargets`（最多返回目标数，默认 `200`，范围 `1...512`；达到上限时响应 `truncated=true`，应缩小筛选范围后重新查询）。每个 target 含 `path`、`role`、`availableActions`、短文本与基础交互状态；disabled target 仍可观察，但 `availableActions` 为空。响应含 `viewSnapshotID`，签发集合与最终返回 targets 一致。

### `ui.control.sendAction`

向当前顶部控制器 view 层级中的指定 `UIControl` 发送 target-action 事件。常用请求：

```bash
curl -X POST http://localhost:38321/ -d '{"action":"ui.control.sendAction","data":{"accessibilityIdentifier":"mine.header.avatar","viewSnapshotID":"snap-1","event":"touchUpInside"}}'
curl -X POST http://localhost:38321/ -d '{"action":"ui.control.sendAction","data":{"path":"root/0/2/1","viewSnapshotID":"snap-1","event":"valueChanged"}}'
```

定位参数与上文「定位语义」一致：`accessibilityIdentifier`（精确，不截断，匹配多个返回 `invalid_data`）或 `path`，并且必须携带 `ui.viewTargets` 返回的 `viewSnapshotID` 做陈旧防护。

事件名：

- `touchDown`
- `touchUpInside`
- `valueChanged`
- `editingChanged`
- `editingDidBegin`
- `editingDidEnd`

成功响应包含 `sent`、`event`、`path`、`type`、`accessibilityIdentifier`、`isEnabled`、`isSelected`。请求 event 必须在目标的 `availableActions` 中以 `control.<event>` 形式出现；disabled 或不支持该 event 的控件返回 `invalid_data`。该命令只调用 `UIControl.sendActions(for:)`，不模拟真实触摸坐标、命中测试或控件高亮过程；需要默认激活时使用 `ui.tap`。

### `ui.tap`

对 `ui.viewTargets` 签发的 canonical target 执行默认激活动作。它不是触摸注入，不接受坐标，不做 `window.hitTest`，也不找祖先 `UIControl` fallback：

```bash
curl -X POST http://localhost:38321/ -d '{"action":"ui.tap","data":{"accessibilityIdentifier":"mine.header.avatar","viewSnapshotID":"snap-1"}}'
curl -X POST http://localhost:38321/ -d '{"action":"ui.tap","data":{"path":"root/0/2/1","viewSnapshotID":"snap-1"}}'
```

定位方式二选一，且必须携带 `viewSnapshotID`：

- `accessibilityIdentifier`: 按业务 identifier **精确**定位 view，不截断。
- `path`: 按 `ui.viewTargets` 返回的只读路径定位 view。

默认激活路由：

- `UIButton`：`sendActions(for: .touchUpInside)`，响应 `activationRoute="control.touchUpInside"`。
- `UISwitch`：翻转 `isOn` 后发送 `.valueChanged`，响应 `activationRoute="switch.toggle"`。
- `UITextField` / `UITextView`：`becomeFirstResponder()`，响应 `activationRoute="input.focus"`。
- `UISlider` / `UISegmentedControl` / 普通 `UIView` / 未知自定义 control：没有默认 tap，返回 `unsupported_target` 或只暴露精确动作。

成功响应包含 `activated`、`activationRoute`、`path`、`type` 和对应 route 的补充字段。动作成功只表示默认激活动作已发出，不代表页面跳转或测试通过；后续必须 `ui.wait` 或重新 observe。

## 注册自定义命令

库内或 App 内：
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
- handler 签名：`@Sendable (Input) async throws -> ExploreResult`，`Input` 必须 conform `CommandInput`。
- 字段名、默认值、类型、范围和 `help.inputSchema` 由 `CommandFields`/`CommandInputSchema` 统一声明，避免 schema 与解析逻辑分叉。
- 无参数命令使用 `EmptyCommandInput.self`；需要原样读取 `data` 的命令使用 `RawJSONInput.self`。
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
curl -X POST http://localhost:38321/ -d '{"action":"ui.viewTargets"}'
curl -X POST http://localhost:38321/ -d '{"action":"ui.tap","data":{"accessibilityIdentifier":"mine.header.avatar","viewSnapshotID":"snap-1"}}'
curl -X POST http://localhost:38321/ -d '{"action":"ui.wait","data":{"mode":"snapshotChanged","viewSnapshotID":"snap-1","timeoutMs":3000}}'
curl -X POST http://localhost:38321/ -d '{"action":"ui.waitAny","data":{"timeoutMs":8000,"conditions":[{"id":"home","mode":"targetExists","accessibilityIdentifier":"home.root"},{"id":"err","mode":"textExists","text":"密码错误"}]}}'
```

- 模拟器无需 iproxy：Mac 与模拟器共享网络栈，直接 `curl http://127.0.0.1:38321/` 即可（前提模拟器 App 已启动 Server）。
- 服务端**不校验 Content-Type**，`curl -d` 默认 `application/x-www-form-urlencoded` 也能工作；规范起见可加 `-H 'Content-Type: application/json'`。

## iproxy 工作原理（重要）

`iproxy <macport> <deviceport>` 在 Mac 监听 `macport`，**被动等待** Mac 客户端连接；客户端一连，它把连接通过 USB 转发到设备 `deviceport`。所以 `proxy.sh` 启动后显示 `waiting for connection` 是**正常状态**——它在等 `curl` 来连，不是在等设备。详见 `docs/runbooks/debugging.md`。

## 端口

- 默认 **38321**（库默认 + `proxy.sh` 默认）。
- 集成测试用 **38399**（避开生产默认，见 `Tests/iOSExploreServerTests/IntegrationTests.swift`）。
