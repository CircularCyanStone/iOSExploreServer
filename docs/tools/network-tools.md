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

错误码：`unknown_action` / `invalid_data` / `internal_error` / `bad_request` / `stale_cursor` 等。通信层错误用 HTTP 状态码，业务失败用 HTTP 200 + 顶层 `code/message`。

## 内置命令

| action | 入参 | 成功 data |
|---|---|---|
| `ping` | 忽略 | `{ "pong": true }` |
| `echo` | 任意对象 | 原样回显入参 `data` |
| `info` | 忽略 | `{ "system":..., "app":..., "bundle":... }`（来自 `ProcessInfo`/`Bundle`） |
| `ui.topViewHierarchy` | 可选筛选参数 | 当前顶部控制器 view 层级或匹配节点列表（UIKit 平台） |
| `ui.inspect` | 可选筛选参数 | 返回 canonical targets、可用动作与 `viewSnapshotID`（UIKit 平台） |
| `ui.control.sendAction` | `accessibilityIdentifier` 或 `path` + `viewSnapshotID` + `event` | 向指定 UIControl 发送显式 target-action 事件（UIKit 平台） |
| `ui.tap` | `accessibilityIdentifier` 或 `path` + `viewSnapshotID` | 对 canonical target 执行默认激活动作（UIKit 平台） |
| `ui.input` | 顶层 `fields` 数组 + 可选 `viewSnapshotID`/`stopOnFailure` | 按顺序向多个文本字段写入文本（UIKit 平台） |
| `app.logs.mark` | 忽略 | 当前进程日志 cursor 与 source 捕获状态（Diagnostics 显式注册后） |
| `app.logs.read` | `after` cursor、`limit`、`sources`、`minimumLevel` | 当前进程内已捕获日志的增量列表（Diagnostics 显式注册后） |

## Diagnostics 命令

> Diagnostics 命令由独立模块 `iOSExploreDiagnostics` 提供，core **不会自动注册**。宿主 App 必须在创建 `ExploreServer` 后显式调用 `server.registerDiagnosticsCommands()` 才开放 `app.logs.*`。

标准用法是动作前打检查点，动作后读增量日志：

```bash
curl -X POST http://localhost:38321/ -d '{"action":"app.logs.mark"}'
curl -X POST http://localhost:38321/ -d '{"action":"ping"}'
curl -X POST http://localhost:38321/ -d '{"action":"app.logs.read","data":{"after":{"captureSessionID":"...","id":1},"limit":100}}'
```

`app.logs.*` 只承诺返回当前 App 进程内、Diagnostics Runtime 启用后、iOSExplore 实际捕获并保留的日志。稳定来源包括 `explore`（内部命令/路由日志）、`bridge`（宿主 `ExploreAppLog.emit`），以及配置打开后的 stdout/stderr/NSLog/Apple Unified Logging 捕获。stdout/stderr 默认关闭；打开后 stdout 每行返回 `source="stdout"` / `level="info"`，stderr 每行返回 `source="stderr"` / `level="error"`。`NSLog` 通过 stderr 行识别进入 `source="nslog"`；`os_log` 与 Swift `Logger` 通过当前进程 `OSLogStore` 进入 `source="oslog"`，如果系统不允许读取会在 `capture.oslog` 返回 `unavailable`。

`app.logs.read` 是按 cursor 向新日志方向读取的增量命令。省略 `after` 时只返回当前可见的最近 `limit` 条，并把 `nextCursor` 指到这次读到的最新 id；它不支持向更旧日志翻页，因此该场景下 `hasMore=false`。需要连续消费时，后续请求传入上一轮返回的 `nextCursor`。

`Examples/SPMExample` 在 Debug 构建下已通过 `ViewController.exampleDiagnosticsConfiguration()` 直接打开 stdout/stderr/NSLog/os_log 四个 capture（Release 构建关闭），无需任何环境变量或启动参数。直接用示例 App 的 Debug 命令写入唯一文本：

```bash
curl -X POST http://localhost:38321/ -d '{"action":"app.logs.mark"}'
curl -X POST http://localhost:38321/ -d '{"action":"debug.emitStdout","data":{"message":"stdout-curl-check-001"}}'
curl -X POST http://localhost:38321/ -d '{"action":"debug.emitStderr","data":{"message":"stderr-curl-check-001"}}'
curl -X POST http://localhost:38321/ -d '{"action":"debug.emitNSLog","data":{"message":"nslog-curl-check-001"}}'
curl -X POST http://localhost:38321/ -d '{"action":"debug.emitOSLog","data":{"message":"oslog-curl-check-001"}}'
curl -X POST http://localhost:38321/ -d '{"action":"debug.emitLogger","data":{"message":"logger-curl-check-001"}}'
curl -X POST http://localhost:38321/ -d '{"action":"app.logs.read","data":{"after":{"captureSessionID":"替换为 mark 返回值","id":0},"sources":["stdout"],"limit":20}}'
curl -X POST http://localhost:38321/ -d '{"action":"app.logs.read","data":{"after":{"captureSessionID":"替换为 mark 返回值","id":0},"sources":["stderr"],"limit":20}}'
curl -X POST http://localhost:38321/ -d '{"action":"app.logs.read","data":{"after":{"captureSessionID":"替换为 mark 返回值","id":0},"sources":["nslog"],"limit":20}}'
curl -X POST http://localhost:38321/ -d '{"action":"app.logs.read","data":{"after":{"captureSessionID":"替换为 mark 返回值","id":0},"sources":["oslog"],"limit":20}}'
```

## UIKit 命令

> UIKit 命令由独立模块 `iOSExploreUIKit` 提供，core **不会自动注册**。宿主 App 必须在创建 `ExploreServer` 后显式调用 `server.registerUIKitCommands()` 才开放下列 14 个 `ui.*` action；未注册时 `help` 不含任何 `ui.*`。SPMExample 已在 `ViewController` 调用该方法。

### 定位语义（所有 `ui.*` 交互命令通用）

定位参数按优先级解析：**`accessibilityIdentifier` 精确 → `path` 只读 → 按命令语义使用 `viewSnapshotID` 陈旧防护**。

- `accessibilityIdentifier`（优先）：按业务层 identifier **精确匹配，不截断、不做 prefix 匹配**。匹配多个 view 返回 `invalid_data`，避免误触发。
- `path`：来自 `ui.inspect` / `ui.topViewHierarchy` 的只读路径（`root/0/2`），仅描述当前 view 树内位置，不写回业务 UI。动作授权以 `ui.inspect` 为准。
- `viewSnapshotID`：只由 `ui.inspect` 签发，代表本次返回 canonical targets 的结构指纹表，不是截图 ID。`ui.tap` / `ui.control.sendAction` 必填，且 identifier/path 都校验 freshness；`ui.input` 顶层可选携带，适用于 `fields` 中的 identifier/path 两种定位；`ui.scroll` 也可选携带，缺省时不做陈旧校验；`ui.wait(snapshotChanged)` 必填；`ui.screenshot` / `ui.topViewHierarchy` 不签发。页面已变动、snapshot 过期/淘汰或 path 未被签发时返回 `stale_locator`，固定提示调用方重新 `ui.inspect`。

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

无筛选时响应 `data.root` 是完整树；带 identifier 筛选时响应 `data.matches` 是匹配节点列表。每个节点包含 `path`、`type`、accessibility 字段、`frame`、`bounds`、`state`、`text`、`appearance`、`control`、`image`、`scroll` 和 `subviews`。`ui.topViewHierarchy` 不签发 `viewSnapshotID`；动作前需要调用 `ui.inspect` 获取可执行 canonical target 与 freshness 标识。

事件下发前可先用轻量目标发现命令获取扁平 targets 列表：

```bash
curl -X POST http://localhost:38321/ \
  -H 'Content-Type: application/json' \
  -d '{"action":"ui.inspect","data":{"includeStaticText":true,"textLimit":80}}'
```

`ui.inspect` 可选参数：`includeHidden`/`includeDisabled`/`includeStaticText`/`includeContainers`（schema 兼容字段，canonical-only 时代已不参与决策，保留只为不破坏旧调用方）、`maxDepth`、`accessibilityIdentifier`/`accessibilityIdentifierPrefix`（筛选，**只作用于 full 节点**，不影响 minimal 节点可见性）、`textLimit`（展示文本截断，默认 80，上限 200）、`maxTargets`（最多返回 full 目标数，默认 `200`，范围 `1...512`；达到上限时响应 `truncated=true`，应缩小筛选范围后重新查询）。响应里每个节点带 `isFull`/`isMinimal` 分档：**full 节点**含完整 `path`、`role`、`availableActions`、短文本与基础交互状态并进入 `viewSnapshotID` 签发集合（可被 `ui.tap`/`ui.control.sendAction` 直接操作）；**minimal 节点**只输出 `{path, type}`、强制 `availableActions=[]`、不签发指纹（仅维持层级可见性，让 agent 看见 cell 内 `UILabel` 等子节点位置）。对 minimal 节点调 `ui.tap`/`ui.control.sendAction` 返回业务码 `not_actionable`。disabled target 仍可观察，但 `availableActions` 为空。cell 内 `UILabel`/子 view 通过 `cellAncestor` 自动进 full，可直接按标题文本定位。响应含 `viewSnapshotID`，签发集合与最终返回的 full targets 一致。

### `ui.control.sendAction`

向当前顶部控制器 view 层级中的指定 `UIControl` 发送 target-action 事件。常用请求：

```bash
curl -X POST http://localhost:38321/ -d '{"action":"ui.control.sendAction","data":{"accessibilityIdentifier":"mine.header.avatar","viewSnapshotID":"snap-1","event":"touchUpInside"}}'
curl -X POST http://localhost:38321/ -d '{"action":"ui.control.sendAction","data":{"path":"root/0/2/1","viewSnapshotID":"snap-1","event":"valueChanged"}}'
```

定位参数与上文「定位语义」一致：`accessibilityIdentifier`（精确，不截断，匹配多个返回 `invalid_data`）或 `path`，并且必须携带 `ui.inspect` 返回的 `viewSnapshotID` 做陈旧防护。

事件名：

- `touchDown`
- `touchUpInside`
- `valueChanged`
- `editingChanged`
- `editingDidBegin`
- `editingDidEnd`

成功响应包含 `sent`、`event`、`path`、`type`、`accessibilityIdentifier`、`isEnabled`、`isSelected`。请求 event 必须在目标的 `availableActions` 中以 `control.<event>` 形式出现；disabled 或不支持该 event 的控件返回 `invalid_data`。该命令只调用 `UIControl.sendActions(for:)`，不模拟真实触摸坐标、命中测试或控件高亮过程；需要默认激活时使用 `ui.tap`。

### `ui.tap`

对 `ui.inspect` 签发的 canonical target 执行默认激活动作。它不是触摸注入，不接受坐标，不做 `window.hitTest`，也不找祖先 `UIControl` fallback：

```bash
curl -X POST http://localhost:38321/ -d '{"action":"ui.tap","data":{"accessibilityIdentifier":"mine.header.avatar","viewSnapshotID":"snap-1"}}'
curl -X POST http://localhost:38321/ -d '{"action":"ui.tap","data":{"path":"root/0/2/1","viewSnapshotID":"snap-1"}}'
```

定位方式二选一，且必须携带 `viewSnapshotID`：

- `accessibilityIdentifier`: 按业务 identifier **精确**定位 view，不截断。
- `path`: 按 `ui.inspect` 返回的只读路径定位 view。

默认激活路由：

- `UIButton`：`sendActions(for: .touchUpInside)`，响应 `activationRoute="control.touchUpInside"`。
- `UISwitch`：翻转 `isOn` 后发送 `.valueChanged`，响应 `activationRoute="switch.toggle"`。
- `UITextField` / `UITextView`：`becomeFirstResponder()`，响应 `activationRoute="input.focus"`。
- `UISlider` / `UISegmentedControl` / 普通 `UIView` / 未知自定义 control：没有默认 tap，返回 `unsupported_target` 或只暴露精确动作。

成功响应包含 `activated`、`activationRoute`、`path`、`type` 和对应 route 的补充字段。动作成功只表示默认激活动作已发出，不代表页面跳转或测试通过；后续必须 `ui.wait` 或重新 observe。

### `ui.input`

按顺序向一个或多个文本控件输入内容。`ui.input` 只有批量形态，单字段输入也必须放进顶层 `fields` 数组：

```bash
curl -X POST http://localhost:38321/ -d '{"action":"ui.input","data":{"viewSnapshotID":"snap-1","fields":[{"accessibilityIdentifier":"login.username","text":"test"},{"accessibilityIdentifier":"login.password","text":"123456"}]}}'
curl -X POST http://localhost:38321/ -d '{"action":"ui.input","data":{"viewSnapshotID":"snap-1","stopOnFailure":false,"fields":[{"path":"root/0/2/1","text":"hello","mode":"replace"},{"path":"root/0/2/2","text":" world","mode":"append","submit":true}]}}'
```

顶层参数：

- `fields`: 必填对象数组，长度 `1...16`。每个元素必须包含 `text`，且 `accessibilityIdentifier` / `path` 二选一。
- `viewSnapshotID`: 可选但推荐，来自同一屏的 `ui.inspect`；identifier/path 两种定位都会校验 freshness。
- `stopOnFailure`: 默认 `true`。某个字段失败后停止后续字段；已成功写入的字段不回滚。

每个 field 支持：

- `text`: 要输入的文本。空字符串表示清空字段。
- `mode`: `replace`（默认，先清空再写入）或 `append`（在原内容末尾追加）。
- `submit`: 默认 `false`。仅当业务依赖 Return / Done / Search 或结束编辑语义时设为 `true`。

成功响应走顶层 `code:"ok"`，`data` 内表达整批是否完成：

```json
{
  "completed": false,
  "failedIndex": 1,
  "results": [
    { "index": 0, "completed": true, "code": "ok", "target": "id=login.username", "type": "UITextField", "finalText": "test", "textLength": 4, "maskedText": "••••" },
    { "index": 1, "completed": false, "code": "target_not_found", "message": "...", "target": "id=login.password" }
  ]
}
```

安全输入字段不返回明文，只返回长度和 masked 值。字段失败不会变成顶层 HTTP/业务失败；只有请求结构非法（例如缺 `fields`、字段不是对象、定位字段同时传）才返回顶层 `invalid_data`。

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
iproxy 38321 38321
# 3) 另开终端发命令
curl -X POST http://localhost:38321/ -d '{"action":"ping"}'
curl -X POST http://localhost:38321/ -d '{"action":"info"}'
curl -X POST http://localhost:38321/ -d '{"action":"greet","data":{"name":"Claude"}}'
curl -X POST http://localhost:38321/ -d '{"action":"ui.topViewHierarchy","data":{"maxDepth":2}}'
curl -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}'
curl -X POST http://localhost:38321/ -d '{"action":"ui.tap","data":{"accessibilityIdentifier":"mine.header.avatar","viewSnapshotID":"snap-1"}}'
curl -X POST http://localhost:38321/ -d '{"action":"ui.wait","data":{"mode":"snapshotChanged","viewSnapshotID":"snap-1","timeoutMs":3000}}'
curl -X POST http://localhost:38321/ -d '{"action":"ui.waitAny","data":{"timeoutMs":8000,"conditions":[{"id":"home","mode":"targetExists","accessibilityIdentifier":"home.root"},{"id":"err","mode":"textExists","text":"密码错误"}]}}'
```

- 模拟器无需 iproxy：Mac 与模拟器共享网络栈，直接 `curl http://127.0.0.1:38321/` 即可（前提模拟器 App 已启动 Server）。
- 服务端**不校验 Content-Type**，`curl -d` 默认 `application/x-www-form-urlencoded` 也能工作；规范起见可加 `-H 'Content-Type: application/json'`。

## iproxy 工作原理（重要）

`iproxy <macport> <deviceport>` 在 Mac 监听 `macport`，**被动等待** Mac 客户端连接；客户端一连，它把连接通过 USB 转发到设备 `deviceport`。所以启动后显示 `waiting for connection` 是**正常状态**——它在等 `curl` 来连，不是在等设备。详见 `docs/runbooks/debugging.md`。

## 端口

- 默认 **38321**（库默认端口；真机转发使用 `iproxy 38321 38321`）。
- 集成测试用 **38399**（避开生产默认，见 `Tests/iOSExploreServerTests/IntegrationTests.swift`）。
