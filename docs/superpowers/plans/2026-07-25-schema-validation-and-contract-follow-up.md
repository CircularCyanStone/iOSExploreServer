# Schema Validation and Contract Follow-up

- 日期：2026-07-25
- 状态：已实施并通过合同/输入验证；`os_log` 环境测试限制见“实际验证结果”
- 当前合同版本：`1.0.0`
- 当前合同 hash：`sha256:f1ca3ffa43d7418af9be345ce7daf5dcb5906e1ab6c6a764ee2faa151421d84b`
- 发布事实：尚未对外开放使用，因此本次不保留旧 Swift schema API 或 `help.inputSchema` 兼容分支

## 结论

Swift 需要校验 App 收到的请求，但不需要保存、输出或解释第二份 schema。

本次采用的最终结构是：

```text
contracts/*.json                         唯一 schema
  ├─> generated TypeScript contracts    MCP/host 使用
  ├─> generated Swift validation calls  App 校验 wire data
  └─> generated contracts.md            文档

generated Swift validation
  -> typed CommandInput parser
  -> UIKit / Diagnostics 领域规则
  -> handler
```

这里的关键区别不是“Swift 不校验”，而是“Swift 不再维护一个 `CommandInputSchema` 对象”。合同生成器把 JSON Schema 在构建期编译成普通 Swift 校验调用；App 运行时只执行这些调用。

## 改造前为什么容易出 bug

以前一条复杂输入同时存在三种 Swift 表达：

```text
CommandInputSchema / CommandFieldSchema
CommandFields(... itemsSchema / description / constraints ...)
CommandInput.parse(decoding:)
```

其中 schema 对象能输出嵌套 `properties`、`items`、`minItems` 等信息，但 decoder 并不会完整执行这些信息。于是改合同后还要判断 Swift schema 对象和手写 parser 是否都需要同步，漏改任意一处都可能出现“声明接受、实际拒绝”或“声明拒绝、实际接受”。本次复查实际遇到的 `ui.waitAny.conditions` 嵌套类型和 `app.logs.read.after.id` 大整数问题都属于这种漂移。

## 改造后的真实代码形态

以 `ui.input.fields` 为例，生成器现在直接产生：

```swift
static let uiInputFieldsField = CommandFields.requiredArray(
    "fields",
    minimumCount: 1,
    maximumCount: 16
)

static let uiInputInput = CommandInputDefinition(
    fields: [uiInputViewSnapshotIDField.erased,
             uiInputStopOnFailureField.erased,
             uiInputFieldsField.erased],
    additionalProperties: false,
    validate: { data in
        try CommandWireValidation.value(
            data["fields"],
            path: "fields",
            required: true,
            types: [.array],
            minimumItems: 1,
            maximumItems: 16
        )
        if case .array(let fields)? = data["fields"] {
            for item in fields {
                try CommandWireValidation.value(
                    item,
                    path: "fields[]",
                    required: true,
                    types: [.object]
                )
                // 生成代码继续检查嵌套未知字段、必填 text、mode enum 和 submit boolean。
            }
        }
    }
)
```

`UIInputInput.parse(decoding:)` 随后只负责把已通过普通 JSON 结构校验的值转换成 Swift 领域模型，并执行 locator 等业务关系。

## 已删除的重复层

- 删除 `Sources/iOSExploreServer/CommandInputSchema.swift`，Swift 不再有 `CommandInputSchema` 或 `CommandFieldSchema`。
- `CommandContract` 不再携带 `inputSchema`。
- `help` command 不再返回每个 action 的 `inputSchema`；只返回 action、provider、稳定性、结果类型、重试/超时策略及 bundle 版本/hash。
- `CommandField` 只保存字段名和 Swift 转换闭包；删除 `description`、`itemsSchema`、`itemDescription` 等 schema 投影参数。
- 删除 `iOSDriver/src/runtime/schemaCompatibility.ts`、对应测试和 Swift schema fixture。Mac 端不再把 canonical schema 与另一份 Swift help 投影逐字段比较。

代码规模上的直接结果是删除约 3000 行旧实现和测试，同时由生成器增加直接校验代码；复杂规则不再依赖手写 schema 对象解释器。

## 仍然保留的 Swift 代码

### `CommandInputDefinition`

它不是 schema，只包含：

- parser 会读取的字段名；
- 顶层是否允许未知字段；
- 由生成器写出的校验闭包。

字段清单还用于自动检查“生成器声明了字段，但 parser 忘记读取”的错误。

### `CommandWireValidation`

它只提供 Foundation-only 原语：JSON 类型、必填、enum、数值范围、JSON safe integer、数组长度、唯一项和未知对象字段。它不接收 JSON Schema object，也不处理 `description`、`default` 或自然语言说明。

### typed parser 与领域校验

以下规则仍应写在 typed parser，因为它们不是普通 JSON 结构：

- locator 的 `accessibilityIdentifier` / `path` 关系及 path 文法；
- `ui.wait` mode 与 text、target、snapshot 字段之间的关系；
- `conditions[].id` 的非空和按 id 唯一；
- 日期字符串解释与日期分量组合；
- UIKit control 类型、当前 view 状态、snapshot 生命周期和对象关系。

`x-iosExplore-constraints` 目前仍用于合同说明这些领域关系，不由通用 wire validator 猜测自然语言语义。

## null 与默认值

缺失和显式 `null` 现在严格区分：

- 合同写 `type: "boolean"` / `"integer"` / `"string"` 时，字段缺失可以使用合同默认值，但显式 `null` 会返回 `invalid_data`。
- 合同明确写 `type: ["number", "null"]` 等 nullable 类型时，Swift 才接受 `null`。
- 不再用“`null` 一律等于没传”的全局规则。

## Host 端如何判断 App 是否匹配

App 不再返回 schema 后，`CapabilityProbe` 检查两个互不混淆的问题：

1. `contractCompatibility`：比较 `protocolVersion`、`contractVersion` 和 `contractHash`，结果为 `exact`、`mismatch` 或 `unknown`。
2. action/module 可用性：根据 `help.commands` 计算当前注册 action、缺失 action，以及 UIKit/Diagnostics 是完整注册、部分注册还是未注册。

合同 hash 相同证明 App 与 host 的生成产物来自同一份 canonical bundle；action 集合说明当前 App 实际装载了哪些模块。CLI `doctor` 不再输出 `schemaDifferences`，合同不匹配或无法确认时失败。

## 对外行为

- HTTP endpoint 仍是 `POST /`。
- 错误的 device action data 仍通过 HTTP 200 + `invalid_data` envelope 返回。
- MCP 工具的 `inputSchema` 仍来自 `iOSDriver/src/generated/deviceActionContracts.ts`，没有删除。
- host operation 仍由 TypeScript 的 generated schema 校验，因为它们不会进入 Swift。
- `help.commands[].inputSchema` 被删除；项目未对外开放，因此不提供旧字段兼容。

## 验收

必须通过：

```bash
swift test
cd iOSDriver && npm run contracts:check
cd iOSDriver && npm test
git diff --check
```

重点回归包括：

- `ui.input.fields` 的嵌套对象类型、必填字段、enum、数组上下限和未知字段；
- `ui.waitAny.conditions` 的嵌套可选字符串类型和未知字段；
- `app.logs.read.after.id` 的 JSON safe integer 范围；
- 非 nullable 默认字段拒绝显式 `null`；
- `help` 不包含 `inputSchema`；
- capability probe 仅按 bundle metadata 和注册 action 判断兼容性/可用性。

### 实际验证结果

- `cd iOSDriver && npm run contracts:check`：通过。
- `cd iOSDriver && npm test`：23 个测试文件、158 项测试通过。
- `swift test --skip 'iOSExploreServerTests.DiagnosticsCommandTests/osLogCapture'`：13 个 suite、304 项测试通过。
- `git diff --check`：通过。
- 未跳过测试的 `swift test` 中，两个依赖 macOS unified logging 实时读取的 `osLogCapture*` 测试在当前 x86_64 SwiftPM helper 环境无法稳定收到日志；单独重跑也失败。它们测试 Diagnostics 的系统日志采集，不经过本次修改的合同生成、wire validation 或 typed input 路径。

## 本次没有一起解决的事项

- action 成功 `data` 目前只有 `json` / `image` / `text` kind，没有完整 result schema；应单独设计。
- `errors` 列表是否表示 handler error、router 公共 error 或完整 host error 并集，仍需单独明确后再审计。
- 模拟器/真机 App 的真实 HTTP 端到端验证仍需在可启动 Debug App 的环境执行；单元测试不能替代 UIKit 运行态验证。
