# Typed Command Input 与 inputSchema 重构设计

- 日期：2026-06-25
- 状态：待实现
- 关联：
  - `docs/superpowers/specs/2026-06-22-command-protocol-redesign.md`
  - `docs/superpowers/specs/2026-06-24-uikit-query-decode-redesign.md`
  - `docs/superpowers/specs/2026-06-25-uikit-query-abstraction-design.md`

## 1. 背景与动机

当前命令系统把参数描述拆成两套来源：

1. `Command.parameters: [CommandParameter]` 负责 `help` 自省和 Router 顶层类型校验。
2. 各命令的 query/input 解析在 `handle(_ request:)` 内读取 `ExploreRequest.data`，字段名、默认值、范围和互斥规则再次手写。

这导致两个问题：

- `parameters` 作为数组只适合展示清单，不适合对外表达真实请求体。HTTP 请求的 `data` 本质是 JSON object，对外 schema 应该是 `inputSchema.properties`，便于 Mac 侧 MCP 网关直接映射 `tools/list`。
- 字段名和规则散落在 schema 与解析代码里，`UIViewTargetsQuery.parse` 这类实现必须重复写 `"includeHidden"`、`"textLimit"` 等 key。现有 `UIKitQueryKeyConsistencyTests` 只能兜底检查"解析读取的 key 已声明"，不能消除重复和语义漂移。

项目仍处于开发期，尚未投入使用，因此本次设计不考虑向后兼容。目标是一次性把命令模型调整到 typed input + `inputSchema/properties` 的形态，删除旧 `CommandParameter` 主路径，而不是继续围绕数组 schema 打补丁。

## 2. 目标与非目标

**目标**

- `help` 对外输出 JSON Schema 风格的 `inputSchema`，主结构为 `type: object` + `properties` + `required`。
- `Command` 改为 typed input 模型：每个命令声明一个 `Input` 类型，Router 在调用 handler 前完成 input 解析。
- 字段定义成为单一来源：字段名、类型、默认值、范围、枚举值、描述由 `CommandField` 定义，解析和 `inputSchema` 都引用它。
- Router 内部用类型擦除保存命令，保持 `action -> command` 的运行期分发表。
- 内置命令、UIKit 四个命令、示例 App 自定义命令、测试和文档一次性迁移。
- 继续满足 core 库只依赖 `Foundation` + `Network`，UIKit 类型不穿过 public 边界的硬约束。
- 保持 Swift 5 语言模式可编译，避免 Swift 6 only 语法。

**非目标**

- 不保留旧 `parameters` 数组输出。
- 不保留旧 `server.register(action:description:parameters:_:)` API。
- 不实现完整 JSON Schema 规范解释器，只实现本项目命令输入需要的子集。
- 不改变 HTTP 协议：仍然是 `POST /`，body 为 `{"action":"...","data":{...}}`，响应仍为统一 envelope。
- 不改变 UIKit 命令的业务语义，例如 `ui.viewTargets` 仍是轻量目标发现，`ui.topViewHierarchy` 仍是重型布局检查。

## 3. 采用方案

采用完整 typed command 方案：

```swift
public protocol CommandInput: Sendable {
    static var inputSchema: CommandInputSchema { get }
    static func parse(from data: JSON) throws -> Self
    static func parse(decoding decoder: inout CommandInputDecoder) throws -> Self
}

public protocol Command: Sendable {
    associatedtype Input: CommandInput

    var action: String { get }
    var description: String { get }

    func handle(_ input: Input) async throws -> ExploreResult
}
```

`Command` 带 `associatedtype` 后不能直接作为统一存在类型调用，所以 Router 不再保存 `[String: any Command]`，而是保存类型擦除后的 `AnyCommand`：

```swift
struct AnyCommand: Sendable {
    let action: String
    let description: String
    let inputSchema: CommandInputSchema
    let logCategory: CommandLogCategory
    let handle: @Sendable (ExploreRequest) async -> ExploreResult
}
```

注册时将具体命令包成 `AnyCommand`。分发时 Router 只知道 `AnyCommand`，但每个 `AnyCommand` 的闭包内部仍调用具体 `Input.parse(from:)` 和具体命令的 `handle(_:)`。

`CommandInput` 把 `parse(from:)` 也列为协议 requirement，并提供默认实现。这样 `AnyCommand` 的泛型调用会动态使用具体 input 的实现；`RawJSONInput` 这类特殊 input 可以覆盖默认行为。默认实现统一创建 decoder、执行 unknown-field 校验，再调用领域解析，避免普通 input 自己决定是否校验：

```swift
public extension CommandInput {
    static func parse(from data: JSON) throws -> Self {
        var decoder = CommandInputDecoder(data, schema: inputSchema)
        try decoder.validateNoUnknownFields()
        return try parse(decoding: &decoder)
    }
}
```

`AnyCommand` 只调用 `C.Input.parse(from: request.data)`，不直接创建 decoder。这样通用校验入口只有一处。

## 4. 详细设计

### 4.1 CommandInputSchema

新增 `CommandInputSchema` 表达命令输入对象：

```swift
public struct CommandInputSchema: Sendable, Equatable {
    public let fields: [AnyCommandField]
    public let additionalProperties: Bool
    public let constraints: [CommandInputConstraint]
}
```

对外 JSON 输出固定为：

```json
{
  "type": "object",
  "properties": {
    "textLimit": {
      "type": "integer",
      "minimum": 1,
      "maximum": 200,
      "default": 80,
      "description": "title/text/placeholder/value 最大字符数"
    }
  },
  "required": [],
  "additionalProperties": false
}
```

`fields` 在 Swift 内部保留声明顺序，输出 JSON 时转成 `properties` object。JSON object 本身不保证顺序，因此如果 Mac 侧需要稳定展示顺序，`inputSchema` 额外输出 `x-iosExplore-propertyOrder: [String]`。`required` 由 `fields` 中的字段 schema 派生，不单独手写，避免 required 列表与字段定义漂移。

`CommandInputSchema` 初始化时必须校验重复字段名；重复字段名是开发期错误，应在注册命令时触发明确 failure 或 precondition，而不是让后写字段静默覆盖先写字段。

### 4.2 CommandField

新增字段定义类型。字段定义是唯一来源，负责同时派生 schema 和解析行为。

```swift
public struct CommandField<Value: Sendable>: Sendable {
    public let name: String
    public let schema: CommandFieldSchema
    public let decode: @Sendable (JSONValue?) throws -> Value
}

public struct AnyCommandField: Sendable, Equatable {
    public let name: String
    public let schema: CommandFieldSchema
}

public enum CommandJSONSchemaType: String, Sendable, Equatable {
    case string
    case number
    case integer
    case boolean
    case object
    case array
}

public struct CommandFieldSchema: Sendable, Equatable {
    public let type: CommandJSONSchemaType
    public let required: Bool
    public let description: String
    public let defaultValue: JSONValue?
    public let minimum: Double?
    public let maximum: Double?
    public let enumValues: [String]
}
```

因为不同字段的 `Value` 泛型不同，`CommandInputSchema` 不能直接保存 `[CommandField<Value>]`。每个字段通过 `erased` 暴露给 schema：

```swift
public extension CommandField {
    var erased: AnyCommandField { AnyCommandField(name: name, schema: schema) }
}
```

字段工厂放在非泛型命名空间，避免 `CommandField.bool(...)` 在 Swift 类型推断中需要显式写 `CommandField<Bool>`：

```swift
public enum CommandFields {
    public static func bool(_ name: String, default defaultValue: Bool, description: String) -> CommandField<Bool>
    public static func optionalString(_ name: String, description: String) -> CommandField<String?>
    public static func requiredString(_ name: String, description: String) -> CommandField<String>
    public static func optionalFiniteNumber(_ name: String, description: String) -> CommandField<Double?>
    public static func optionalNonNegativeInt(_ name: String, description: String) -> CommandField<Int?>
    public static func int(_ name: String, range: ClosedRange<Int>, default defaultValue: Int, description: String) -> CommandField<Int>
    public static func enumValue<E>(_ name: String, type: E.Type, default defaultValue: E, description: String) -> CommandField<E>
        where E: RawRepresentable & CaseIterable & Sendable, E.RawValue == String
    public static func requiredEnum<E>(_ name: String, type: E.Type, description: String) -> CommandField<E>
        where E: RawRepresentable & CaseIterable & Sendable, E.RawValue == String
}
```

数值字段明确区分 `number` 与 `integer`。现有 `ParameterKind.number` 太粗，不足以表达 `maxDepth`、`textLimit`、`maxTargets` 这些整数语义。

字段解码规则必须固定：

- 缺失字段：可选字段返回 `nil`，带默认值字段返回默认值，必填字段抛 `missing required parameter '<name>'`。
- `.null`：按缺失处理；必填字段仍抛 missing，避免 `null` 绕过 required。
- 类型不符：抛 `parameter '<name>' expects <type>`。
- 浮点数字段：必须是有限数，不能接受 `nan` 或 `infinity`。
- 整数字段：底层仍从 `JSONValue.double` 读取，但必须是有限整数且在范围内。
- 枚举字段：错误文案使用 `must be one of ...`，顺序来自 `CaseIterable.allCases`。
- 枚举字段实现时先把 `E.allCases.map(\.rawValue)` 固化成 `[String]`，避免在 `@Sendable` decode 闭包里捕获不确定 Sendable 的集合类型。

### 4.3 CommandInputDecoder

新增 `CommandInputDecoder`，替换 UIKit 专用的 `QueryDecoder` 主路径。

```swift
public struct CommandInputDecoder: Sendable {
    let data: JSON
    public init(_ data: JSON, schema: CommandInputSchema)
    public mutating func read<Value>(_ field: CommandField<Value>) throws -> Value
    public func validateNoUnknownFields() throws
}
```

解析流程：

1. `AnyCommand.handle` 调用 `C.Input.parse(from: request.data)`。
2. `CommandInput.parse(from:)` 默认实现创建 decoder。
3. decoder 先根据 `schema.fields` 检查未知字段。默认 `additionalProperties = false`。
4. `Input.parse(decoding:)` 通过 `read(field)` 读取字段。
5. decoder 或 `Input.parse(decoding:)` 抛 `CommandInputParseError`。
6. Router 将解析错误统一转成 `invalid_data` envelope。

旧 `QueryParseError` 由新 `CommandInputParseError` 替代。迁移完成后 Router 只处理一个 input parse error 类型，UIKit 命令不再保留独立的 query parse error 主路径。

`data` 保持 internal，只供 core 内置的 `RawJSONInput` 和少数库内迁移代码使用。公开解析能力必须通过 `read(field)` 暴露，避免业务方重新绕过字段定义。

`read(field)` 必须校验字段已经存在于当前 `CommandInputSchema.fields`。如果 input 读取了未声明字段，应抛开发期错误并由测试覆盖；这能防止 `Fields.all` 和 `parse(decoding:)` 再次漂移。

### 4.4 领域约束

schema 字段只能覆盖类型、必填、默认值、范围、枚举值。互斥、成对、二选一这类领域规则由 `CommandInputConstraint` 表达给 `help`，由 `Input.parse(decoding:)` 执行。

建议先支持这些约束：

```swift
public enum CommandInputConstraint: Sendable, Equatable {
    case exactlyOneOf([String])
    case atMostOneOf([String])
    case allOrNone([String])
    case oneOf([[String]])
}
```

输出 JSON 时映射成接近 JSON Schema 的结构：

- `exactlyOneOf(["accessibilityIdentifier", "path"])` 输出 `oneOf`。
- `allOrNone(["x", "y"])` 输出 `dependentRequired` 或 `oneOf` 辅助表达。
- `atMostOneOf` 可输出项目自定义扩展字段 `x-iosExplore-constraints`，避免伪装成完整 JSON Schema。

`inputSchema` 的主体必须保持合法 JSON Schema 子集；`x-iosExplore-*` 只用于表达标准 JSON Schema 子集无法清晰覆盖的补充约束。Mac 侧 MCP 网关应优先消费标准字段，忽略不了解的扩展字段也不影响基础工具注册。

Swift 侧不做通用约束解释器的第一版实现。`Input.parse(decoding:)` 继续写领域判断，但字段取值必须来自 `CommandField`，错误文案要与 schema 约束一致。

### 4.5 Router

Router 迁移为保存 `AnyCommand`：

```swift
public final class Router: Sendable {
    private let handlers = Mutex<[String: AnyCommand]>([:])

    public func register<C: Command>(_ command: C) {
        register(AnyCommand(command))
    }

    func route(_ request: ExploreRequest) async -> ExploreResult {
        let command = handlers.withLock { $0[request.action] }
        guard let command else { ... }
        return await command.handle(request)
    }
}
```

`AnyCommand` 负责 catch input parse error、业务失败和 handler thrown：

- input parse error -> `ExploreServerError.invalidData(action:message:)`
- `ExploreResult.failure` -> 原样返回，并打业务失败日志
- handler throw -> `ExploreServerError.handlerThrown(action:error:)`

Swift 没有 typed throws，因此错误契约必须写硬：

- `CommandField.decode` 和 `Input.parse(decoding:)` 的参数/领域校验只能抛 `CommandInputParseError`。
- `AnyCommand` 单独 catch `CommandInputParseError`，转成 `invalid_data`，并记录 input parse failure。
- parse 阶段出现其他 `Error` 视为命令实现 bug，转成 `internal_error`，日志必须区分为 unexpected parse error。
- handler 执行阶段的业务失败继续返回 `ExploreResult.failure`；未捕获异常按既有 `handlerThrown` 收敛。

Router 日志继续保留 action、payload key count、error code、HTTP/业务结果摘要，不记录完整 payload。

### 4.6 HelpCommand

`HelpCommand` 改为输出：

```json
{
  "commands": [
    {
      "action": "ui.viewTargets",
      "description": "返回当前顶部控制器中可用于事件下发的轻量 UI 目标列表",
      "inputSchema": {
        "type": "object",
        "properties": {
          "includeHidden": {
            "type": "boolean",
            "default": false,
            "description": "是否包含隐藏 view"
          }
        },
        "required": [],
        "additionalProperties": false
      }
    }
  ]
}
```

不再输出旧 `parameters` 数组。因为项目未投入使用，不需要双写兼容。

### 4.7 闭包注册入口

删除旧闭包入口：

```swift
register(action:description:parameters:_:)
```

新增 typed 闭包入口：

```swift
public func register<Input: CommandInput>(
    action: String,
    description: String = "",
    input: Input.Type,
    _ handler: @escaping @Sendable (Input) async throws -> ExploreResult
)
```

无参数命令使用 `EmptyCommandInput`：

```swift
public struct EmptyCommandInput: CommandInput, Sendable, Equatable {
    public static let inputSchema = CommandInputSchema.empty
    public static func parse(decoding decoder: inout CommandInputDecoder) throws -> EmptyCommandInput {
        return EmptyCommandInput()
    }
}
```

需要原始 `data` 的命令使用显式 `RawJSONInput`：

```swift
public struct RawJSONInput: CommandInput, Sendable, Equatable {
    public static let inputSchema = CommandInputSchema(additionalProperties: true)
    public let data: JSON
    public static func parse(decoding decoder: inout CommandInputDecoder) throws -> RawJSONInput {
        RawJSONInput(data: decoder.data)
    }
    public static func parse(from data: JSON) throws -> RawJSONInput {
        // RawJSONInput 刻意绕过默认 unknown-field 校验，保留完整 data。
        RawJSONInput(data: data)
    }
}
```

示例 App 中的 `greet` 应迁移为 typed input；`device` 使用 `EmptyCommandInput`。

### 4.8 UIKit 命令迁移

`UIViewTargetsQuery` 改名或重定位为 `UIViewTargetsInput`，并作为 `ViewTargetsCommand.Input`：

```swift
public struct UIViewTargetsInput: CommandInput, Sendable, Equatable {
    enum Fields {
        static let includeHidden = CommandFields.bool("includeHidden", default: false, description: "是否包含隐藏 view")
        static let includeDisabled = CommandFields.bool("includeDisabled", default: true, description: "是否包含 disabled control")
        static let includeStaticText = CommandFields.bool("includeStaticText", default: false, description: "是否包含仅展示文本的节点")
        static let includeContainers = CommandFields.bool("includeContainers", default: false, description: "是否包含普通容器 view")
        static let maxDepth = CommandFields.optionalNonNegativeInt("maxDepth", description: "最大递归深度, 0 表示仅根 view")
        static let accessibilityIdentifier = CommandFields.optionalString("accessibilityIdentifier", description: "按 accessibilityIdentifier 精确筛选")
        static let accessibilityIdentifierPrefix = CommandFields.optionalString("accessibilityIdentifierPrefix", description: "按 accessibilityIdentifier 前缀筛选")
        static let textLimit = CommandFields.int("textLimit", range: 1...200, default: 80, description: "title/text/placeholder/value 最大字符数")
        static let maxTargets = CommandFields.int("maxTargets", range: 1...UIKitSnapshotLimits.maxFingerprints, default: 200, description: "单次响应最多返回的目标数")
        static let all: [AnyCommandField] = [
            includeHidden.erased,
            includeDisabled.erased,
            includeStaticText.erased,
            includeContainers.erased,
            maxDepth.erased,
            accessibilityIdentifier.erased,
            accessibilityIdentifierPrefix.erased,
            textLimit.erased,
            maxTargets.erased,
        ]
    }

    public static let inputSchema = CommandInputSchema(fields: Fields.all)

    public static func parse(decoding d: inout CommandInputDecoder) throws -> UIViewTargetsInput {
        return UIViewTargetsInput(
            includeHidden: try d.read(Fields.includeHidden),
            includeDisabled: try d.read(Fields.includeDisabled),
            includeStaticText: try d.read(Fields.includeStaticText),
            includeContainers: try d.read(Fields.includeContainers),
            maxDepth: try d.read(Fields.maxDepth),
            accessibilityIdentifier: try d.read(Fields.accessibilityIdentifier),
            accessibilityIdentifierPrefix: try d.read(Fields.accessibilityIdentifierPrefix),
            textLimit: try d.read(Fields.textLimit),
            maxTargets: try d.read(Fields.maxTargets)
        )
    }
}
```

`ViewTargetsCommand.handle` 只接收 typed input：

```swift
struct ViewTargetsCommand: Command {
    let action = "ui.viewTargets"
    let description = "返回当前顶部控制器中可用于事件下发的轻量 UI 目标列表"

    func handle(_ input: UIViewTargetsInput) async throws -> ExploreResult {
        let data = try await UIViewTargetsCollector.collect(query: input)
        return .success(data)
    }
}
```

`ui.tap`、`ui.control.sendAction` 的互斥规则用字段定义 + `CommandInputConstraint` 对外表达，Swift 侧继续在 input parse 中做精确判断。

UIKit 命令里重复出现的字段应抽到 Foundation-only 的共享字段命名空间，但必须区分“筛选字段”和“定位字段”。同名 key 在不同命令里的语义不同，不能用一段 description 硬套所有命令：

```swift
enum UIKitFilterFields {
    static let accessibilityIdentifier = CommandFields.optionalString("accessibilityIdentifier", description: "按 accessibilityIdentifier 精确筛选")
    static let accessibilityIdentifierPrefix = CommandFields.optionalString("accessibilityIdentifierPrefix", description: "按 accessibilityIdentifier 前缀筛选")
    static let maxDepth = CommandFields.optionalNonNegativeInt("maxDepth", description: "最大递归深度, 0 表示仅根 view")
    static let includeHidden = CommandFields.bool("includeHidden", default: false, description: "是否包含隐藏 view")
}

enum UIKitLocatorFields {
    static let accessibilityIdentifier = CommandFields.optionalString("accessibilityIdentifier", description: "按 accessibilityIdentifier 精确定位目标 view")
    static let path = CommandFields.optionalString("path", description: "按 ui.viewTargets 或 ui.topViewHierarchy 返回的 root/0/1 路径定位目标 view")
    static let snapshotID = CommandFields.optionalString("snapshotID", description: "快照标识, 仅用于 path 定位的陈旧校验")
}
```

命令可以复用共享字段，也可以在本命令内定义更具体的 description；如果 description 需要分命令表达不同语义，应保留同一个 `name`，但必须在同一文件相邻声明，避免散落字符串。`ui.topViewHierarchy` 和 `ui.viewTargets` 默认使用 `UIKitFilterFields`，`ui.tap` 和 `ui.control.sendAction` 默认使用 `UIKitLocatorFields`。

为避免 locator 字段在 parser 里重新手写，新增 Foundation-only helper：

```swift
enum UIKitLocatorInput {
    static func parse(decoder: inout CommandInputDecoder,
                      identifierField: CommandField<String?>,
                      pathField: CommandField<String?>) throws -> UIKitViewLookupTarget
}
```

helper 内部只能通过 `decoder.read(identifierField)` 和 `decoder.read(pathField)` 读取，再复用 `UIKitViewLookupTarget.parse(identifier:rawPath:)` 做二选一和 path 文法校验。

`ui.tap` 的 schema 约束必须表达三类目标：

- view 目标：`accessibilityIdentifier` 或 `path` 二选一。
- 坐标目标：`x` 与 `y` 必须同时提供，`coordinateSpace` 默认 `window` 且第一版只允许 `window`。
- view 目标与坐标目标互斥；`snapshotID` 只允许和 `path` 一起出现。若 `snapshotID` 搭配 `accessibilityIdentifier` 或 `x/y`，parser 返回 `invalid_data`，避免调用方误以为发生了陈旧校验。

`ui.tap` 需要额外字段工厂，不能把 `x/y` 当整数处理：

```swift
enum UITapInputFields {
    static let x = CommandFields.optionalFiniteNumber("x", description: "window 坐标 x, 需要与 y 同时提供")
    static let y = CommandFields.optionalFiniteNumber("y", description: "window 坐标 y, 需要与 x 同时提供")
    static let coordinateSpace = CommandFields.enumValue("coordinateSpace", type: UITapCoordinateSpace.self, default: .window, description: "坐标空间, 第一版仅支持 window")
}
```

`ui.tap` 的 `inputSchema` 至少要输出下面的约束信息（字段内容省略）：

```json
{
  "type": "object",
  "properties": {
    "accessibilityIdentifier": { "type": "string" },
    "path": { "type": "string" },
    "snapshotID": { "type": "string" },
    "x": { "type": "number" },
    "y": { "type": "number" },
    "coordinateSpace": { "type": "string", "enum": ["window"], "default": "window" }
  },
  "oneOf": [
    { "required": ["accessibilityIdentifier"], "not": { "anyOf": [{ "required": ["path"] }, { "required": ["x"] }, { "required": ["y"] }, { "required": ["snapshotID"] }] } },
    { "required": ["path"], "not": { "anyOf": [{ "required": ["accessibilityIdentifier"] }, { "required": ["x"] }, { "required": ["y"] }] } },
    { "required": ["x", "y"], "not": { "anyOf": [{ "required": ["accessibilityIdentifier"] }, { "required": ["path"] }, { "required": ["snapshotID"] }] } }
  ],
  "x-iosExplore-constraints": [
    "snapshotID is valid only with path",
    "coordinateSpace currently supports only window"
  ]
}
```

`ui.control.sendAction` 的 schema 约束必须表达：

- `event` 必填，枚举值来自 `UIControlSendActionEvent.allCases`。
- `accessibilityIdentifier` 与 `path` 必须二选一。
- `snapshotID` 只允许和 `path` 一起出现。搭配 `accessibilityIdentifier` 时返回 `invalid_data`。

这些约束不能只写在描述文案里，必须同时进入 `CommandInputSchema.constraints` 和 parse 测试。

### 4.9 日志与错误

本次重构会改变命令入口位置，必须同步补齐日志点：

- `Router.register`：记录 action、schema field count、constraint count。
- `Router.route`：记录 action、payload key count、input parse start/success/failure。
- `AnyCommand`：记录 typed input 解析失败的 error code/message 摘要。
- `HelpCommand`：记录输出 command count。
- UIKit 命令：保留现有 start/complete/failed 日志，但 start 日志从 `request.data.storage.count` 改为 typed input 摘要，避免 handler 再依赖原始 request。

UIKit 命令的 parse 失败会发生在 `AnyCommand` 中，handler 不会进入。为了不违反 UIKit 扩展模块的日志要求，类型擦除层必须知道命令日志通道：

```swift
struct AnyCommand: Sendable {
    let action: String
    let description: String
    let inputSchema: CommandInputSchema
    let logCategory: CommandLogCategory
    let handle: @Sendable (ExploreRequest) async -> ExploreResult
}
```

core 命令使用 `ExploreLogger` 的 `.command`；UIKit 命令通过注册时的 metadata 使用 `ExploreLogging.emitExtension(category: "command")`。parse start、parse failed、execute start、execute complete/failed 必须都能在 UIKit 日志中按 action 串起来。迁移后 UIKit handler 内的日志语义从“command start”改为“execute start”，parse 层日志由 `AnyCommand` 负责。

错误来源统一：

- input 解析错误使用 `CommandInputParseError`。
- Router 将其转成 `ExploreServerError.invalidData`。
- UIKit 业务错误继续用 `UIKitCommandError`，由 command handler 顶层 catch 或 executor 外层转换成业务失败 envelope。

## 5. 迁移范围

**core**

- `Sources/iOSExploreServer/Command.swift`
- `Sources/iOSExploreServer/Router.swift`
- `Sources/iOSExploreServer/ExploreServer.swift`
- `Sources/iOSExploreServer/Handlers/BuiltinHandlers.swift`
- 新增 `CommandInput.swift`、`CommandInputSchema.swift`、`CommandField.swift`、`CommandInputDecoder.swift`

**UIKit**

- `Sources/iOSExploreUIKit/Support/Parsing/QueryDecoder.swift`
- `Sources/iOSExploreUIKit/Support/Parsing/UIKitQueryParsing.swift`
- `Sources/iOSExploreUIKit/Commands/*/*Models.swift`
- `Sources/iOSExploreUIKit/Commands/*/*Command.swift`

**示例与文档**

- `Examples/SPMExample/SPMExample/ViewController.swift`
- `README.md`
- `docs/architecture/index.md`
- `docs/tools/network-tools.md`
- `docs/uikit/README.md`
- `docs/uikit/reading-guide.md`
- `docs/uikit/uikit-file-reference.md`

**测试**

- Router 参数校验测试改为 input parse/schema 测试。
- `help` 测试改断言 `inputSchema.properties`。
- UIKit query key consistency 测试删除，替换为字段定义单一来源测试。
- 新增 typed closure registration 测试。
- 新增 unknown field、integer range、enum values、default value、required、constraint message 测试。
- `ui.tap` 具体矩阵：`x` 缺 `y`、`y` 缺 `x`、非法 `coordinateSpace`、identifier/path/x/y 混用、`snapshotID` 搭配 identifier 或 x/y、unknown field、合法 identifier、合法 path、合法 window point。
- `ui.control.sendAction` 具体矩阵：missing event、invalid event 且错误文案顺序对齐 `allCases`、missing target、identifier+path 同时存在、invalid path、`snapshotID` 搭配 identifier、合法 identifier、合法 path。
- `ui.viewTargets` 保留 Foundation-only 策略测试：`shouldInclude`、`maxTargets` 边界、`textLimit`、hidden subtree pruning、editable text 不泄露。
- schema 单一来源测试：`decoder.read(field)` 读取未声明字段会失败；每个命令 `inputSchema.fields` 与 parse 覆盖的字段集合一致；`help` 输出包含 `x-iosExplore-propertyOrder`。

## 6. 风险与处理

- **类型擦除复杂度上升**：集中在 `AnyCommand`，不让每个命令感知类型擦除。
- **Swift 5 语言模式兼容**：实现避免宏、property wrapper 强依赖和 Swift 6 only 标准库类型。`any` 已在现有代码使用，可继续实测 framework 工程。
- **schema 子集不完整**：只承诺本项目使用的 JSON Schema 子集；无法标准表达的互斥规则放入 `x-iosExplore-constraints`。
- **领域错误文案漂移**：约束定义与 `Input.parse` 必须同文件相邻，测试覆盖每条领域约束的错误文案。
- **一次性迁移面大**：先迁移 core 内置命令和 Router，再迁移 UIKit 四个命令，最后改示例与文档。每一步都跑针对性测试，避免大爆炸式提交。

## 7. 验证标准

- `swift test` 通过。
- `xcodebuild -project iOSExploreServer/iOSExploreServer.xcodeproj -scheme iOSExploreServer -sdk iphonesimulator build` 通过。
- `help` 响应不再包含旧 `parameters` 数组，所有命令都有 `inputSchema`。
- `ui.viewTargets` 的 `includeHidden`、`textLimit`、`maxTargets` 等字段名在 schema 和解析中只通过 `Fields.*` 定义出现。
- `ui.tap`、`ui.control.sendAction` 的互斥和成对规则在 `inputSchema` 与 parse 测试中都有覆盖。
- 示例 App 使用 typed 闭包注册，不再调用旧 `register(action:description:parameters:_:)`。

## 8. 后续实现顺序

1. 新增 core schema/input/field/decoder 基础类型和单元测试。
2. 引入 `AnyCommand`，改造 Router 注册、路由、metadata。
3. 迁移内置命令和 `help` 输出。
4. 迁移 typed 闭包注册入口和示例 App。
5. 迁移 UIKit 四个命令 input 与 command handler。
6. 删除旧 `CommandParameter`、`ParameterKind`、`QueryDecoder` 主路径和旧一致性测试。
7. 更新 README、architecture、network-tools、uikit 文档。
8. 跑 `swift test` 和 framework build，修正 Swift 5 语言模式问题。
