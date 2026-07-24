# iOSDriver 合同与运行时重构实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 iOSExploreServer 的 App action 合同、Swift 执行端、Node Host runtime、MCP adapter、CLI 收敛到同一份可生成、可校验的公共合同，同时保持现有 HTTP、MCP 工具名、结果 envelope 和截图行为兼容。

**Architecture:** `contracts/` 是跨语言 wire schema 的唯一事实源，只有 `DeviceActionContract` 和 `HostOperationSpec` 两个业务命名空间。生成器输出 Swift metadata/fields、TypeScript schemas、CLI 校验和文档片段。Swift App 继续只执行 `POST /` action；Node 侧拆成 `ActionTransport`、`DriverRuntime`、`CapabilityProbe`、`ArtifactDecoder` 和独立 `WorkflowRunner`。MCP 与 CLI 只做适配、投影、渲染和配置，不管理 `iproxy`、XcodeBuildMCP 或设备生命周期。

**Tech Stack:** Swift 6.2、Swift Package Manager、Foundation/Network、TypeScript 5.x、Node.js 20+、`@modelcontextprotocol/sdk`、Vitest。

---

## Task 1: 建立合同目录和受控 JSON Schema 校验器

**Files:**
- Create: `contracts/bundle.json`
- Create: `contracts/errors.json`
- Create: `contracts/definitions/locator.json`
- Create: `contracts/definitions/view-snapshot.json`
- Create: `contracts/definitions/wait-condition.json`
- Create: `contracts/definitions/protocol-envelope.json`
- Create: `iOSDriver/src/contracts/generator/model.ts`
- Create: `iOSDriver/src/contracts/generator/loadBundle.ts`
- Create: `iOSDriver/src/contracts/generator/validateBundle.ts`
- Create: `iOSDriver/src/contracts/generator/index.ts`
- Create: `iOSDriver/tests/contracts/generator.load.test.ts`
- Create: `iOSDriver/tests/contracts/generator.validate.test.ts`
- Modify: `iOSDriver/package.json`

- [ ] **Step 1: 写失败测试**

`generator.load.test.ts` 先断言 bundle 只含版本和文件清单：

```ts
expect(bundle.protocolVersion).toBe("1");
expect(bundle.contractVersion).toBe("1.0.0");
expect(bundle.generatorVersion).toBe("1");
expect(bundle.files).toContain("device-actions/core.ping.json");
expect(bundle.files).toContain("host-operations/health.json");
```

`generator.validate.test.ts` 构造并拒绝重复 action、未知相对 `$ref`、`required` 指向不存在属性、enum 值类型错误、error code 不在 `errors.json`、非受控 schema 关键字和循环 `$ref`。同时接受 `uniqueItems`、`exclusiveMinimum`、`exclusiveMaximum`、`oneOf`、`allOf`、`not` 与 `x-iosExplore-constraints`。

- [ ] **Step 2: 运行红测试**

```bash
cd iOSDriver
npx vitest run tests/contracts/generator.load.test.ts tests/contracts/generator.validate.test.ts
```

Expected: loader/validator 尚不存在，测试失败。

- [ ] **Step 3: 实现模型、加载和校验**

`model.ts` 定义 `DriverContractBundle`、`DeviceActionContract`、`HostOperationSpec`、`JsonSchema`、`ResultSpec`、`ErrorContract`，并使用下列 metadata 联合值：`provider` 为 `core|uikit|diagnostics|extension`，`stability` 为 `public|experimental|internal`，`result.kind` 为 `json|image|text`，`idempotency` 为 `readOnly|idempotent|sideEffecting`，`timeoutClass` 为 `standard|wait|screenshot`。

`bundle.json` 只写 `protocolVersion`、`contractVersion`、`generatorVersion` 和完整相对文件清单。loader 按文件清单读取 `device-actions/` 与 `host-operations/`，解析每个本地 `$ref` 后再校验；禁止联网或运行时 App 参与。

Schema 子集精确支持：`object`、`array`、`string`、`number`、`integer`、`boolean`、`null`；`properties`、`required`、`additionalProperties`；`items`、`minItems`、`maxItems`、`uniqueItems`；`enum`、`default`、`minimum`、`maximum`、`exclusiveMinimum`、`exclusiveMaximum`；`oneOf`、`allOf`、`not`、`description` 和 `x-iosExplore-constraints`。校验器必须对未列出的关键字报错，而不是静默忽略。

`errors.json` 收录 `ExploreError` 全部稳定 code，以及 `transport_unavailable`、`transport_timeout`、`http_error`、`protocol_error`、`contract_mismatch`、`invalid_config`、`workflow_timeout`、`artifact_decode_failed`。保留错误来源和 HTTP status 语义，不能把业务失败改成 transport error。

- [ ] **Step 4: 运行绿测试并提交**

```bash
npx vitest run tests/contracts/generator.load.test.ts tests/contracts/generator.validate.test.ts
git add contracts iOSDriver/src/contracts/generator iOSDriver/tests/contracts/generator.*.test.ts iOSDriver/package.json
git commit -m "feat: add canonical driver contract loader"
```

Expected: 受控 schema、ref、版本和错误映射测试全部通过。

## Task 2: 冻结全部 DeviceActionContract 与 HostOperationSpec

**Files:**
- Create: `contracts/device-actions/core.ping.json`
- Create: `contracts/device-actions/core.echo.json`
- Create: `contracts/device-actions/core.info.json`
- Create: `contracts/device-actions/core.help.json`
- Create: `contracts/device-actions/uikit.top-view-hierarchy.json`
- Create: `contracts/device-actions/uikit.inspect.json`
- Create: `contracts/device-actions/uikit.control-send-action.json`
- Create: `contracts/device-actions/uikit.tap.json`
- Create: `contracts/device-actions/uikit.screenshot.json`
- Create: `contracts/device-actions/uikit.input.json`
- Create: `contracts/device-actions/uikit.keyboard-dismiss.json`
- Create: `contracts/device-actions/uikit.scroll.json`
- Create: `contracts/device-actions/uikit.navigation-back.json`
- Create: `contracts/device-actions/uikit.navigation-tap-bar-button.json`
- Create: `contracts/device-actions/uikit.wait.json`
- Create: `contracts/device-actions/uikit.wait-any.json`
- Create: `contracts/device-actions/uikit.scroll-to-element.json`
- Create: `contracts/device-actions/uikit.alert-respond.json`
- Create: `contracts/device-actions/uikit.controllers.json`
- Create: `contracts/device-actions/uikit.swipe.json`
- Create: `contracts/device-actions/uikit.long-press.json`
- Create: `contracts/device-actions/uikit.tab-bar-select-tab.json`
- Create: `contracts/device-actions/uikit.date-picker-set-date.json`
- Create: `contracts/device-actions/uikit.picker-select-row.json`
- Create: `contracts/device-actions/uikit.web-view-eval.json`
- Create: `contracts/device-actions/diagnostics.app-logs-mark.json`
- Create: `contracts/device-actions/diagnostics.app-logs-read.json`
- Create: `contracts/host-operations/health.json`
- Create: `contracts/host-operations/capabilities.json`
- Create: `contracts/host-operations/call-action.json`
- Create: `contracts/host-operations/wait-and-inspect.json`
- Create: `contracts/host-operations/tap-and-inspect.json`
- Modify: `contracts/bundle.json`
- Create: `iOSDriver/tests/contracts/contract-baseline.test.ts`

- [ ] **Step 1: 写合同基线测试**

合同测试必须检查所有 27 个 device action（4 core、21 UIKit、2 Diagnostics）和 5 个 host operation 都有唯一名称、provider、stability、result、errors、idempotency、timeoutClass 与 inputSchema。对当前 MCP 静态工具还要检查名称映射：

```ts
expect(toolMapping("ui_inspect")).toEqual("ui.inspect");
expect(toolMapping("app_logs_read")).toEqual("app.logs.read");
expect(toolMapping("wait_and_inspect")).toEqual("wait_and_inspect");
expect(toolMapping("ui_tap_and_inspect")).toEqual("tap_and_inspect");
```

- [ ] **Step 2: 从当前实现转录而不是重新设计字段**

使用以下唯一来源：`core.*` 来自 `Sources/iOSExploreServer/Handlers/BuiltinHandlers.swift`；21 个 `uikit.*` 来自 `Sources/iOSExploreUIKit/Commands/` 的 `Input.inputSchema`、默认值和结果构造；`diagnostics.*` 来自 `Sources/iOSExploreDiagnostics/DiagnosticsCommands.swift`；error code 来自 `Sources/iOSExploreServer/Models.swift`；host operation 来自 `iOSDriver/src/staticTools.ts` 的 schema 和 workflow 字段。

每个 device action 使用 `kind: "deviceAction"`、`action`、`description`、`provider`、`stability`、`inputSchema`、`result`、`errors`、`idempotency`、`timeoutClass`。`contractVersion` 和 `contractHash` 属于 bundle，由生成器注入各语言的运行时 metadata；不得写回 action 源文件形成 hash 自引用。Schema 必须保持当前 parser 的默认值、enum、范围、数组限制、未知字段策略和日期/条件/WebView 的 JSON 形态。复杂语义写入 `x-iosExplore-constraints` 和正反样例，不能把 UIKit 类型放进合同。

HostOperationSpec 的 `wait-and-inspect` 字段必须定义 `waitForStable`、`stableTimeMs`、`inspectDepth`、`inspectMaxTargets` 等组合参数，不能伪装成 `ui.tap` 或 `ui.inspect` 的字段。`init`、`doctor`、`mcp` 不写进业务合同。

- [ ] **Step 3: 运行合同基线**

```bash
cd iOSDriver
npm test -- tests/contracts/contract-baseline.test.ts
```

Expected: 合同文件加载、静态 MCP 映射和当前 schema 深比较全部通过；若发现旧实现与合同不一致，先修正合同转录或记录真实行为，再继续。

- [ ] **Step 4: 提交**

```bash
git add contracts iOSDriver/tests/contracts/contract-baseline.test.ts
git commit -m "test: freeze device and host operation contracts"
```

## Task 3: 引入 CommandContract 并生成 Swift/TypeScript/文档产物

**Files:**
- Create: `Sources/iOSExploreServer/CommandContract.swift`
- Create: `Tests/iOSExploreServerTests/CommandContractTests.swift`
- Create: `iOSDriver/src/contracts/generator/emitTypeScript.ts`
- Create: `iOSDriver/src/contracts/generator/emitSwift.ts`
- Create: `iOSDriver/src/contracts/generator/emitDocs.ts`
- Create: `iOSDriver/src/generated/deviceActionContracts.ts`
- Create: `iOSDriver/src/generated/hostOperationSpecs.ts`
- Create: `iOSDriver/src/generated/contractBundle.ts`
- Create: `Sources/iOSExploreServer/Generated/CoreActionContracts.swift`
- Create: `Sources/iOSExploreUIKit/Generated/UIKitActionContracts.swift`
- Create: `Sources/iOSExploreDiagnostics/Generated/DiagnosticsActionContracts.swift`
- Create: `docs/generated/contracts.md`
- Create: `iOSDriver/tests/contracts/emission.test.ts`
- Modify: `iOSDriver/src/contracts/generator/index.ts`
- Modify: `iOSDriver/package.json`

- [ ] **Step 1: 先测试模型和生成确定性**

```swift
let contract = CommandContract(
    action: "example.read",
    description: "读取示例",
    inputSchema: .empty,
    provider: .core,
    stability: .public,
    resultKind: .json,
    declaredErrors: [],
    idempotency: .readOnly,
    timeoutClass: .standard,
    contractVersion: "1.0.0",
    contractHash: "sha256:" + String(repeating: "0", count: 64)
)
XCTAssertEqual(contract.action, "example.read")
XCTAssertThrowsError(try CommandContract.validateAction("bad action"))
```

`emission.test.ts` 运行两次 generator，断言字节相同、无时间戳/绝对路径，并检查 `deviceActionContracts.ts`、`hostOperationSpecs.ts`、`contractBundle.ts` 和三个 Swift 文件包含对应 action、version、hash，Swift 输出不含 `import UIKit`。

- [ ] **Step 2: 运行红测试**

```bash
swift test --filter CommandContractTests
cd iOSDriver
npx vitest run tests/contracts/emission.test.ts
```

Expected: CommandContract 和 emitters 尚不存在，测试失败。

- [ ] **Step 3: 实现模型和生成器**

`CommandContract` 是 Foundation-only、`Sendable`、不可变值类型，至少包含 `action`、`description`、`inputSchema`、`provider`、`stability`、`resultKind`、`declaredErrors`、`idempotency`、`timeoutClass`、`contractVersion`、`contractHash`，并支持 `contractSource: generated|runtime`。`CommandContract.validateAction` 按 `^[A-Za-z][A-Za-z0-9]*(?:[._-][A-Za-z0-9]+)*$` 拒绝空串、空格和不稳定名称。所有新增 public Swift 类型、属性、方法都按仓库约定补齐简体中文 `///` 注释、参数、返回和错误语义。

TypeScript 生成文件分别导出 readonly device action contracts、host operation specs、bundle version/hash 和 error index；不得把 adapter tool 名或 CLI 命令名写入 generated 文件。生成器先展开本地 `$ref`，再对 key 有序的规范化 bundle 做 SHA-256，输出 `sha256:<64 位小写十六进制>`；hash 不包含任何生成文件或回写字段。Swift 生成文件为 `CoreActionContracts.swift`、`UIKitActionContracts.swift`、`DiagnosticsActionContracts.swift`，使用现有 `CommandFields` 工厂生成 scalar/array 字段声明和 `CommandInputSchema`，只生成 wire-level 字段，不生成 UIKit executor/domain model。生成 field 名按 action + JSON key 稳定派生。

文档 emitter 输出 `docs/generated/contracts.md` 的 action、字段、结果和错误摘要。生成文件只能由 generator 修改。

`iOSDriver/package.json` 增加：

```json
"contracts:generate": "tsx src/contracts/generator/index.ts generate",
"contracts:check": "tsx src/contracts/generator/index.ts check"
```

`build` 和 `test` 在 TypeScript 编译前运行 `contracts:check`，避免 generated drift 被隐藏。

- [ ] **Step 4: 生成、构建和提交**

```bash
cd iOSDriver
npm run contracts:generate
npm run contracts:check
npm run typecheck
cd ..
swift build
swift test --filter CommandContractTests
git add Sources/iOSExploreServer/CommandContract.swift Sources/iOSExploreServer/Generated Sources/iOSExploreUIKit/Generated Sources/iOSExploreDiagnostics/Generated Tests/iOSExploreServerTests/CommandContractTests.swift iOSDriver/src/contracts iOSDriver/src/generated iOSDriver/package.json docs/generated/contracts.md
git commit -m "build: generate cross-language driver contracts"
```

Expected: generated drift、Node typecheck、Swift build 和 CommandContract 测试通过。

## Task 4: 将 Swift Router/Command/help 迁移到完整合同

**Files:**
- Modify: `Sources/iOSExploreServer/Command.swift`
- Modify: `Sources/iOSExploreServer/Router.swift`
- Modify: `Sources/iOSExploreServer/Handlers/BuiltinHandlers.swift`
- Modify: `Sources/iOSExploreServer/ExploreServer.swift`
- Modify: command structs under `Sources/iOSExploreUIKit/Commands/`
- Modify: `Sources/iOSExploreUIKit/UIKitCommandRegistrar.swift`
- Modify: `Sources/iOSExploreDiagnostics/DiagnosticsCommands.swift`
- Modify: affected files under `Tests/iOSExploreServerTests/`
- Test: `Tests/iOSExploreServerTests/HelpContractTests.swift`

- [ ] **Step 1: 先写 help 和注册测试**

断言 help 顶层增加且稳定返回 `protocolVersion == "1"`、`contractVersion == "1.0.0"`、`commands` 数组，并断言 `contractHash` 以 `sha256:` 开头且总长度为 71：

```swift
XCTAssertEqual(data["protocolVersion"]?.stringValue, "1")
XCTAssertEqual(data["contractVersion"]?.stringValue, "1.0.0")
XCTAssertEqual(data["contractHash"]?.stringValue?.hasPrefix("sha256:"), true)
XCTAssertEqual(data["contractHash"]?.stringValue?.count, 71)
XCTAssertNotNil(data["commands"]?.arrayValue)
```

断言 `commands` 仅列当前 Router 已注册 action；未注册 UIKit/Diagnostics 时不伪造为已注册；注册后 UIKit/Diagnostics command 分别报告生成的 provider 和 public stability；runtime extension action 标记 `provider=extension`、`stability=internal`、`contractSource=runtime`，且不改变公共合同 hash。

- [ ] **Step 2: 运行红测试**

```bash
swift test --filter HelpContractTests
```

Expected: help 没有 version/hash/完整 metadata，测试失败。

- [ ] **Step 3: 修改 Command/AnyCommand/Router**

`Command` 和 `AnyCommand` 保存完整 `CommandContract`；Router metadata 和 help 从同一份 contract snapshot 读取。旧的 `register(action:description:input:handler:)` 保留为便利入口，自动使用 `Input.inputSchema`、`provider=extension`、`stability=internal`、`contractSource=runtime`，不进入公共静态 MCP 工具生成；显式 contract 注册入口用于需要对外发布的扩展。

迁移 `PingCommand`、`EchoCommand`、`InfoCommand`、`HelpCommand` 和所有 UIKit/Diagnostics command struct 到对应 generated contract。此任务只替换 metadata 来源；复杂 Input parser 仍原样工作，并由 Task 2 的 schema 等价测试保证 generated schema 与其一致。新增注册、metadata 校验、help 投影日志，日志不打印完整 payload。保持 `unknown_action`、`invalid_data`、timeout、HTTP status 和基础 envelope 不变。

- [ ] **Step 4: 定向验证并提交**

```bash
swift test --filter HelpContractTests
swift test --filter BuiltinHandlersTests
swift test --filter Router

git add Sources/iOSExploreServer Sources/iOSExploreUIKit Sources/iOSExploreDiagnostics Tests/iOSExploreServerTests
git commit -m "feat: expose contract metadata from Swift help"
```

## Task 5: 接入 generated fields，保留 UIKit/Diagnostics 复杂 parser

**Files:**
- Modify: command models under `Sources/iOSExploreUIKit/Commands/`
- Modify: `Sources/iOSExploreDiagnostics/DiagnosticsCommands.swift`
- Modify: `Sources/iOSExploreServer/CommandInputDecoder.swift`
- Modify: generated Swift files only through generator
- Create: `Tests/iOSExploreServerTests/UIKitContractParserCompatibilityTests.swift`
- Create: `Tests/iOSExploreServerTests/DiagnosticsContractParserCompatibilityTests.swift`

- [ ] **Step 1: 写正反向 parser 测试**

覆盖 scalar 默认值/范围/enum、`UIInputInput` fields 数组、`UIWaitAnyInput` conditions、日期二选一、WebView script/function、日志 cursor/limit。必须包含：

```swift
XCTAssertThrowsError(try UIInputInput.parse(from: ["fields": []]))
XCTAssertThrowsError(try UIWaitAnyInput.parse(from: ["conditions": []]))
XCTAssertNoThrow(try UIDatePickerSetDateInput.parse(from: ["path": "0/1", "date": "2026-07-24T10:00:00Z"]))
```

另测 parser 未读取 generated 字段时 `assertAllDeclaredFieldsRead()` 失败。

- [ ] **Step 2: 实现 generated schema 接入**

每个公共 `Input.inputSchema` 改为返回对应 generated contract schema。scalar 字段、默认值、范围、enum 和数组边界只在合同/generated field 声明；parser 继续将 wire scalar 转 Foundation/domain value。`UIInputInput`、`UIWaitAnyInput`、日期、WebView 等复杂 parser 保留 `parse(from:)`，并必须调用 `validateNoUnknownFields()` 与 `assertAllDeclaredFieldsRead()`。不能生成 `UIView`、`Date`、`IndexPath` 或 executor 类型。

合同无法表达的跨字段互斥、mode-specific required field 和日期策略写入 `x-iosExplore-constraints`，由手写 parser 校验；合同兼容测试锁定这些规则。UIKit executor/resolver 行为不变，继续通过 `UIKitCommandLogging` 记录 start/complete/failed、resolver 结果、snapshot store 事件。Diagnostics 继续使用 core boundary。

- [ ] **Step 3: 定向测试与提交**

```bash
swift test --filter ContractParserCompatibilityTests
swift test --filter UIKit
swift test --filter Diagnostics
git add Sources/iOSExploreUIKit Sources/iOSExploreDiagnostics Sources/iOSExploreServer/CommandInputDecoder.swift Tests
git commit -m "refactor: connect generated fields to Swift parsers"
```

## Task 6: 抽出 Host runtime、错误归一化、timeout、retry 和 artifact

**Files:**
- Create: `iOSDriver/src/runtime/actionTransport.ts`
- Create: `iOSDriver/src/runtime/httpActionTransport.ts`
- Create: `iOSDriver/src/runtime/driverRuntime.ts`
- Create: `iOSDriver/src/runtime/driverErrors.ts`
- Create: `iOSDriver/src/runtime/artifacts.ts`
- Create: `iOSDriver/src/runtime/types.ts`
- Modify: `iOSDriver/src/iosExploreClient.ts` as compatibility facade
- Create: `iOSDriver/tests/runtime/actionTransport.test.ts`
- Create: `iOSDriver/tests/runtime/driverRuntime.test.ts`
- Create: `iOSDriver/tests/runtime/artifacts.test.ts`

- [ ] **Step 1: 写 fake transport 测试**

接口必须允许 fake transport 注入和明确 timeout：

```ts
export interface ActionTransport {
  execute(
    request: { action: string; data: JSONObject },
    options: { timeoutMs: number; signal?: AbortSignal }
  ): Promise<{ httpStatus: number; envelope: JSONObject }>;
}
```

测试 connect/read timeout、HTTP 非 2xx、非法 JSON、App success/failure envelope、response data 保留和 abort。`HttpActionTransport` 是唯一知道 URL、POST `/`、headers、fetch 的实现，不能解释 UIKit 数据。等待 action 的 transport timeout 保持当前安全边界：`max(configuredRequestTimeoutMs, businessTimeoutMs + 5000)`，使 App 的 `wait_timeout` 先于 HTTP timeout 返回。

- [ ] **Step 2: 测试 retry 和 InvocationResult**

Host runtime 返回：

```text
InvocationResult { ok: true, data, artifacts, elapsedMs, attempts }
InvocationResult { ok: false, error, data?, artifacts?, elapsedMs, attempts }
```

默认不重试。只有合同 `readOnly` 或 `idempotent`、失败是 connect/reset 等 transport error、且尚未收到任何 App response 时允许一次 transport-only retry。`sideEffecting`（tap、input、navigation、swipe、longPress）永不自动重试。App envelope 失败不抛成 transport error，保留原 `data` 和稳定 code/message。

- [ ] **Step 3: 实现 ArtifactDecoder**

`artifacts.ts` 将 `ui.screenshot` 的 PNG base64 解成 `Artifact { kind: "image", mimeType: "image/png", data, metadata }`，校验 base64、MIME、大小和可选尺寸；非法内容返回 `artifact_decode_failed`。runtime 不把 MCP SDK 类型或大块 base64 写入日志。

- [ ] **Step 4: 验证、迁移兼容 facade、提交**

`IOSExploreClient` 只包装 `DriverRuntime.invoke`，保留现有 import 和错误转换作为 deprecated facade；不保留任意 action 的无条件 retry。

```bash
cd iOSDriver
npx vitest run tests/runtime/actionTransport.test.ts tests/runtime/driverRuntime.test.ts tests/runtime/artifacts.test.ts tests/iosExploreClient.test.ts
git add src/runtime src/iosExploreClient.ts tests/runtime tests/iosExploreClient.test.ts
git commit -m "feat: add typed host runtime and artifact decoding"
```

## Task 7: 实现 CapabilityProbe 和 schema compatibility

**Files:**
- Create: `iOSDriver/src/runtime/capabilityProbe.ts`
- Create: `iOSDriver/src/runtime/schemaCompatibility.ts`
- Create: `iOSDriver/tests/runtime/capabilityProbe.test.ts`
- Create: `iOSDriver/tests/runtime/schemaCompatibility.test.ts`

- [ ] **Step 1: 写能力状态矩阵**

覆盖 endpoint 不可达、ping 可达/help 缺失、全部 action 已注册、UIKit/Diagnostics 未注册、partial action、required field 变化、enum/范围收窄、新增 optional field 和 hash 不同。分别断言：

- health 连接状态为 reachable/unreachable/malformed；
- 模块状态为 registered/partial/not_registered/unknown；
- schema 兼容性为 exact/additive/breaking/unknown。

App 不可达时 action/module 必须是 `unknown`，不能伪造为 missing。

- [ ] **Step 2: 实现语义比较**

`CapabilityProbe` 只在 `doctor`、`health` 或 `capabilities` 显式调用时请求 `ping`/`help`；绝不在 MCP `tools/list` 期间发 HTTP。比较顺序固定为 action 存在性、合法 object schema、required 增删、property type/enum/range/array bounds 收窄、additionalProperties 收紧、新增 optional 字段、contract version/hash。hash 不同只报告差异，不直接隐藏工具。

- [ ] **Step 3: 验证并提交**

```bash
cd iOSDriver
npx vitest run tests/runtime/capabilityProbe.test.ts tests/runtime/schemaCompatibility.test.ts
git add src/runtime/capabilityProbe.ts src/runtime/schemaCompatibility.ts tests/runtime/capabilityProbe.test.ts tests/runtime/schemaCompatibility.test.ts
git commit -m "feat: add runtime capability and compatibility probe"
```

## Task 8: 将 WorkflowRunner 移入独立 workflows 模块

**Files:**
- Create: `iOSDriver/src/workflows/workflowRunner.ts`
- Create: `iOSDriver/src/workflows/waitAndInspect.ts`
- Create: `iOSDriver/src/workflows/tapAndInspect.ts`
- Create: `iOSDriver/src/workflows/types.ts`
- Create: `iOSDriver/tests/workflows/waitAndInspect.test.ts`
- Create: `iOSDriver/tests/workflows/tapAndInspect.test.ts`

- [ ] **Step 1: 写 fake runtime 测试**

`wait_and_inspect` 成功顺序固定为 `ui.waitAny`、`ui.inspect`；`wait_timeout` 后仍继续 inspect 并返回最新 observation；inspect 失败才终止。`tap_and_inspect` 的 tap 失败短路，wait 超时仍继续 inspect，结果保留 `tap`、`stateAfter` 和完整 `timing`。

```ts
expect(runtime.calls.map((item) => item.action)).toEqual([
  "ui.waitAny",
  "ui.inspect"
]);
expect(result.wait.code).toBe("wait_timeout");
expect(result.observation).toBeDefined();
```

- [ ] **Step 2: 实现无 adapter 依赖的 workflow**

Workflow 只依赖 `DriverRuntime.invoke`、HostOperationSpec 输入和总 deadline；不导入 MCP SDK、CLI parser 或 UIKit。每个子 action 传递剩余预算。`tap_and_inspect` 的 `waitForStable`、`stableTimeMs`、`inspectDepth`、`inspectMaxTargets` 只能来自 host contract。`wait_and_inspect` 遇到 `wait_timeout` 时保留 wait 的失败 code 并继续返回 observation，MCP 继续按现有行为渲染为包含失败过程信号的非 tool error 结果；inspect 失败才是 workflow 终态失败。

- [ ] **Step 3: 验证并提交**

```bash
cd iOSDriver
npx vitest run tests/workflows/waitAndInspect.test.ts tests/workflows/tapAndInspect.test.ts
git add src/workflows tests/workflows
git commit -m "refactor: extract workflows from MCP adapter"
```

## Task 9: 重建 MCP adapter、tool mapping 和静态 tools/list

**Files:**
- Create: `iOSDriver/src/adapters/mcp/toolMappings.ts`
- Create: `iOSDriver/src/adapters/mcp/toolCatalog.ts`
- Create: `iOSDriver/src/adapters/mcp/resultRenderer.ts`
- Create: `iOSDriver/src/adapters/mcp/server.ts`
- Create: `iOSDriver/tests/adapters/mcp/toolCatalog.test.ts`
- Create: `iOSDriver/tests/adapters/mcp/resultRenderer.test.ts`
- Create: `iOSDriver/tests/adapters/mcp/server.test.ts`
- Modify: `iOSDriver/src/server.ts`
- Modify: `iOSDriver/src/index.ts`
- Migrate: `iOSDriver/tests/startup.test.ts`, `iOSDriver/tests/server.test.ts`

- [ ] **Step 1: 冻结现有 28 个工具名**

`toolMappings.ts` 只保存历史名称到 device action/host operation 的映射，不复制 schema 字段：

```ts
expect(STATIC_TOOL_NAMES).toEqual([
  "health_check", "check_capabilities", "call_action", "app_logs_mark",
  "app_logs_read", "ui_topViewHierarchy", "ui_inspect", "ui_control_sendAction",
  "ui_input", "ui_tap", "ui_screenshot", "ui_keyboard_dismiss", "ui_scroll",
  "ui_navigation_back", "ui_navigation_tapBarButton", "ui_waitAny",
  "ui_scrollToElement", "ui_alert_respond", "ui_controllers", "ui_swipe",
  "ui_longPress", "ui_tabBar_selectTab", "ui_datePicker_setDate",
  "ui_picker_selectRow", "ui_webView_eval", "wait_and_inspect", "ui_wait",
  "ui_tap_and_inspect"
]);
```

测试 App 不在线时 `tools/list` 仍返回完整稳定集合，且不调用 `help`/`ping`，不设置 `listChanged`，不因模块未注册删除工具。

- [ ] **Step 2: 运行红测试**

```bash
cd iOSDriver
npx vitest run tests/adapters/mcp/toolCatalog.test.ts tests/adapters/mcp/server.test.ts tests/startup.test.ts
```

- [ ] **Step 3: 实现 adapter 与渲染**

`toolCatalog.ts` 从 generated DeviceActionContract、HostOperationSpec 和显式 mapping 生成 schema/description。`server.ts` 只绑定 MCP SDK `tools/list`/`tools/call`；adapter 不把 MCP 类型泄漏给 runtime。`resultRenderer.ts` 把 `InvocationResult` JSON 转 text，把 image artifact 转 MCP image content，根据稳定错误 code 设置 `isError`。

`health_check`/`check_capabilities` 调 CapabilityProbe；`call_action` 可直接调用任意 action，不以公共静态合同作为准入门槛。若当前 help metadata 已知，则用它选择 timeout/idempotency；未知扩展 action 按 `sideEffecting`、不重试的保守策略调用，由 App 的 `unknown_action` 决定是否存在。不为未纳入公共合同的 action 自动生成工具。Workflow mapping 调独立 WorkflowRunner。`nextSteps` 使用显式 host/workflow 规则，不拼接完整错误 message。

- [ ] **Step 4: 验证并提交**

```bash
npm test -- tests/adapters/mcp tests/startup.test.ts tests/server.test.ts
git add src/adapters/mcp src/server.ts src/index.ts tests/adapters/mcp tests/startup.test.ts tests/server.test.ts
git commit -m "refactor: make MCP a static contract adapter"
```

## Task 10: 实现 CLI adapter、配置初始化和 exit code

**Files:**
- Create: `iOSDriver/src/adapters/cli/config.ts`
- Create: `iOSDriver/src/adapters/cli/commands.ts`
- Create: `iOSDriver/src/adapters/cli/output.ts`
- Create: `iOSDriver/src/adapters/cli/main.ts`
- Create: `iOSDriver/tests/adapters/cli/config.test.ts`
- Create: `iOSDriver/tests/adapters/cli/commands.test.ts`
- Modify: `iOSDriver/src/index.ts`
- Modify: `iOSDriver/package.json`

- [ ] **Step 1: 写 CLI 红测试**

固定命令：

```bash
iosdriver init
iosdriver doctor
iosdriver call <action> --data '{}'
iosdriver mcp
```

测试配置优先级为“命令行参数 > 环境变量 > 配置文件 > 默认值”。继续兼容现有 `$IOS_EXPLORE_BASE_URL` 和 `$IOS_EXPLORE_REQUEST_TIMEOUT_MS`；配置路径为 `$IOSDRIVER_CONFIG`，未设置时 `$XDG_CONFIG_HOME/iosdriver/config.json`，再回退 `~/.config/iosdriver/config.json`。`init` 幂等、原子替换、保留未知字段和已有用户值，只打印使用 `iosdriver mcp` 的 MCP 配置片段，不修改 MCP 客户端私有配置。不得保存当前未启用的 auth token。

测试 stdout/stderr 分离、`call --data @file`、image artifact 的 `--output <path>`、未指定 output 时只打印 metadata；`mcp` stdout 只能有 MCP stdio 帧。exit code 固定为：成功 0、App 业务/workflow 失败 1、配置错误 2、transport/HTTP/protocol 失败 3。

- [ ] **Step 2: 实现依赖注入的 CLI**

`config.ts` 解析 immutable config；`commands.ts` 实现 init/doctor/call/mcp，doctor 检查 Node 版本、配置、endpoint、端口代理可达性、ping、help 和合同兼容性，但不得启动、停止或管理 `iproxy`/XcodeBuildMCP/设备；`output.ts` 负责 JSON/human 输出；`main.ts` 只负责 argv、exit code、SIGINT 和 stderr 日志。CLI 不复制 per-action handler。

`package.json` 增加 bin：

```json
"bin": {
  "iosdriver": "./dist/adapters/cli/main.js",
  "ios-explore-mcp-server": "./dist/index.js"
}
```

保留 `ios-explore-mcp-server` 兼容别名；`src/index.ts` 作为 legacy entry 无参数直接进入 MCP stdio，不能因为引入子命令而改成显示 CLI help。`iosdriver mcp` 启动同一个 `src/adapters/mcp/server.ts`，不能让 Node process 自动创建 `iproxy`。

- [ ] **Step 3: 验证并提交**

```bash
cd iOSDriver
npx vitest run tests/adapters/cli/config.test.ts tests/adapters/cli/commands.test.ts
npm run typecheck
git add src/adapters/cli src/index.ts package.json tests/adapters/cli
git commit -m "feat: add iosdriver CLI adapter"
```

## Task 11: 删除 staticTools 重复职责并补齐公共兼容回归

**Files:**
- Delete: `iOSDriver/src/staticTools.ts`
- Modify: `iOSDriver/src/iosExploreClient.ts` only as deprecated facade or delete after import audit
- Modify: `iOSDriver/src/types.ts` and `iOSDriver/src/result.ts` to remove duplicated contract/runtime types
- Create: `iOSDriver/tests/compatibility/publicSurface.test.ts`
- Migrate/delete: `iOSDriver/tests/staticTools.test.ts`

- [ ] **Step 1: 写公共表面测试**

测试固定 28 个 MCP 工具名、generated schema 来源、workflow output 字段、screenshot image content、App offline `tools/list`、`POST /` request body `{ action, data }`、HTTP 400/500 transport 与 HTTP 200 business envelope 的差异，以及 `call_action` 的 extension/private action 调用路径。

- [ ] **Step 2: 迁移后再删除旧实现**

只有在新 adapter/runtime/workflow 测试通过后，才删除 static schema、transport、error enrichment 和 workflow 业务代码。runtime 类型只保留 `InvocationResult`/`DriverError` 等运行时职责；MCP 类型只能出现在 adapter。保留外部可能依赖的 `IOSExploreClient` deprecated facade 时，确保它委托 `DriverRuntime` 且不重复实现 retry/JSON parse。

- [ ] **Step 3: 完整 Node 门禁并提交**

```bash
cd iOSDriver
npm run contracts:check
npm run typecheck
npm test
git add -A
git commit -m "refactor: remove duplicated static MCP implementation"
```

Expected: `staticTools.ts` 不存在，28 个公共工具和兼容测试通过。

## Task 12: 真实 App、文档和 skill 验收

**Files:**
- Modify: `docs/cli/README.md`
- Modify: `docs/architecture/index.md`
- Create: `docs/generated/contracts.md` only via generator
- Create: `docs/skills/examples/contract-runtime.md`
- Modify only if needed: affected `.codex/skills/*/SKILL.md` and matching `agents/openai.yaml`
- Modify: `docs/superpowers/specs/2026-07-24-iosdriver-contract-runtime-refactor-design.md` only if implementation reveals an approved invariant is false

- [ ] **Step 1: 更新文档事实**

`docs/cli/README.md` 必须说明 contracts 目录、两个合同命名空间、generated outputs、`contracts:check`、`iosdriver init/doctor/call/mcp`、配置优先级、exit code、retry/idempotency、artifact 输出、capability unknown/partial 语义和 host runtime 不管理外部生命周期。“未来演进”表继续保留完整 JSON Schema、可选 `DeviceSession`/`ProxyManager`、extension tool discovery、stream/file artifact、protocol v2 的触发条件、方向、成本和兼容要求。

保留 HTTP 示例：

```bash
curl -X POST http://localhost:38321/ -d '{"action":"ping"}'
```

成功 envelope 仍为 `{"code":"ok","data":{"pong":true}}`。文档中的工具名、字段和错误摘要链接到 generated fragment，不手写第三份 schema。

- [ ] **Step 2: 运行真实 App 集成验证**

按仓库现有模拟器/真机 runbook 执行：`ping`、`help`、`capabilities`，至少一个 UIKit read action，`ui.inspect` → `ui.tap` 或 `ui.control.sendAction`，screenshot image artifact，`app.logs.mark`/`app.logs.read`，以及未注册 UIKit/Diagnostics 时 partial/not_registered 状态。真机连接仍由现有 runbook/外部工具负责，不能由新 runtime 自动管理。

- [ ] **Step 3: skill 边界检查**

仓库具体示例写入 `docs/skills/examples/contract-runtime.md`。通用 skill 正文只能保留跨 App 稳定工作流、参数语义、失败分诊和终止条件；不得写仓库名、App 名、绝对路径、bundle ID、设备 ID、账号或历史验收结果。只对实际修改的 skill 运行 `quick_validate.py`，同步检查 `.claude/skills` 和 `.trae/skills` 是 `.codex/skills` 的快捷方式。

- [ ] **Step 4: 全量门禁**

```bash
cd iOSDriver
npm run contracts:check
npm run typecheck
npm test
cd ..
swift build
swift test
rg -n "import UIKit" Sources/iOSExploreServer Sources/iOSExploreServer/Generated
rg -n "@modelcontextprotocol" iOSDriver/src/runtime iOSDriver/src/workflows
rg -n "iproxy|xcodebuild|devicectl" iOSDriver/src/runtime iOSDriver/src/workflows
rg -n "child_process|spawn\(|exec\(" iOSDriver/src/adapters/cli
```

Expected：合同 drift、Node typecheck/test、Swift build/test 通过；core/runtime/workflow 不依赖越界模块，CLI 不启动或管理外部进程。若全量存在无关既有失败，记录精确测试名和输出，并补跑受影响 target 的定向测试，不能把定向通过说成全量通过。

- [ ] **Step 5: 提交文档和验收结果**

```bash
git add docs .codex/skills
git commit -m "docs: document contract runtime boundaries and verification"
git status --short
git log --oneline -12
```

最终报告必须说明本次目标、按模块/文件改动、HTTP/MCP/CLI 对外效果、使用/验证命令、未实现能力和平台限制。

## 最终验收门禁

- [ ] `contracts:check` 在干净工作树通过，重复生成字节一致。
- [ ] 27 个 device action 和 5 个 host operation 都有唯一、可校验合同。
- [ ] Swift generated metadata 不 import UIKit，core public boundary 无 UIKit 类型。
- [ ] `help` 返回 protocol/contract version、hash 和当前 Router 注册快照；extension 不改变公共 hash。
- [ ] App 仍只处理 `POST /` 和 `{ action, data }`，HTTP 通信失败与 HTTP 200 业务失败区分不变。
- [ ] MCP `tools/list` 不发 HTTP、不依赖 App 在线，28 个工具名和 mapping 稳定。
- [ ] `DriverRuntime` 不启动、停止或管理 `iproxy`、XcodeBuildMCP、设备生命周期。
- [ ] 仅明确 `readOnly`/`idempotent` 且未收到 App response 的 transport failure 可 retry 一次。
- [ ] Capability 报告区分 reachable、unknown、partial/not_registered 和 schema breaking/additive。
- [ ] Workflow 保留 wait timeout 后 inspect、tap failure short-circuit、timing 和错误终态。
- [ ] Artifact 统一解码、MIME/大小校验并按 adapter 输出，日志不泄露大 payload。
- [ ] CLI init 幂等保留未知配置，doctor/call/mcp 的 stdout、stderr、exit code 有测试。
- [ ] 未来演进项继续记录：完整 JSON Schema、可选 DeviceSession/ProxyManager、extension tool discovery、stream/file artifact、protocol v2。
