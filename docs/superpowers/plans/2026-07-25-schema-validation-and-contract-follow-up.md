# Schema Validation and Contract Follow-up

- 日期：2026-07-25
- 状态：待实施
- 背景设计：[`2026-07-24-iosdriver-contract-runtime-refactor-design.md`](../specs/2026-07-24-iosdriver-contract-runtime-refactor-design.md)
- 原始实施计划：[`2026-07-24-iosdriver-contract-runtime-refactor.md`](2026-07-24-iosdriver-contract-runtime-refactor.md)
- 当前合同版本：`1.0.0`
- 当前合同 hash：`sha256:f1ca3ffa43d7418af9be345ce7daf5dcb5906e1ab6c6a764ee2faa151421d84b`

## 1. 文档目的

本文记录 2026-07-25 重构复查后的 schema 校验结论、尚未实现的合同能力、平台验证限制和下一轮建议实施顺序。它是一份跨电脑继续开发的交接文件，不是新的 wire contract；当前 action、字段、默认值和错误码仍以 `contracts/`、生成产物、Swift 实现和测试为准。

本文所述状态包含编写时本地工作区中的未提交修改。切换电脑前应确认这些修改已经提交并同步；不能只根据本文的合同 hash 推断所有源码修复都已进入 Git 历史。

## 2. Schema 校验现状与结论

### 2.1 Schema 定义只有一个事实源

Device action 和 host operation 的 schema 只应在 `contracts/` 中维护。生成器将合同投影为：

- `Sources/*/Generated/*ActionContracts.swift`：Swift `CommandContract`、`CommandInputSchema` 和 generated fields；
- `iOSDriver/src/generated/`：TypeScript device action contracts、host operation specs 和 bundle metadata；
- `docs/generated/contracts.md`：生成文档。

因此，“多个地方执行校验”不等于“维护了多份 schema”。不得在 Swift、MCP adapter、CLI adapter、README 或 skill 中再手写一份字段表。

### 2.2 当前存在五类检查

| 位置 | 检查对象 | 是否应保留 |
| --- | --- | --- |
| `iOSDriver/src/contracts/generator/validateBundle.ts` | 合同文件、引用和扩展关键字是否合法 | 保留；这是构建期合同检查，不处理请求 |
| `iOSDriver/src/runtime/hostOperationInput.ts` | Mac 侧 `health`、`call_action`、`wait_and_inspect` 等 host operation 输入 | 保留；这些操作不会进入 Swift |
| `Sources/iOSExploreServer/CommandInputDecoder.swift` 和 `CommandField` | App device action 的顶层未知字段、标量类型、必填、默认值、enum 和范围 | 保留；调用方可以绕过 iOSDriver 直接请求 App |
| 各命令的 `CommandInput.parse(from:)` | 嵌套对象、复杂数组、跨字段关系和领域语义 | 部分保留；只应保留类型转换和合同无法表达的领域规则 |
| `iOSDriver/src/runtime/schemaCompatibility.ts` 及跨语言测试 | canonical contract 与 App `help` 投影是否一致 | 保留；用于发现生成产物或运行时 metadata 漂移 |

Host operation 在 TypeScript 校验、device action 在 Swift 校验，是不同执行边界上的必要校验，不应为了追求“只有一个 validator”而删除其中一层。`call_action.data` 和直接 device action payload 在 host 侧保持 opaque，由 Swift 作为权威执行端校验，这是有意设计。

### 2.3 当前不合理的重复

Swift 内部仍有 schema 语义和手写 parser 同时维护的问题：

1. `CommandInputSchema.constraints` 当前只参与 `toJSON()`，`CommandInput.parse(from:)` 不会通用执行 `exactlyOneOf`、`oneOf` 等跨字段约束。
2. `CommandFieldSchema.extraSchema` 能携带 `items`、嵌套 `properties`、`minItems`、`maxItems` 等结构，但 `CommandInputDecoder.readRaw` 只记录字段已读取，不解释这些约束。
3. `x-iosExplore-constraints.exactlyOneOf` 和 `mutuallyExclusive` 是结构化、可执行约束，但目前仍主要依赖各命令手写实现。
4. `x-iosExplore-constraints.note` 是说明性规则，不能通过解析自然语言执行；例如 `ui.waitAny.conditions[].id` 唯一性仍需要领域 parser，除非未来增加明确的结构化关键字。

这类重复是不理想的。新增或修改复杂字段时，开发者可能只改合同或只改 parser，造成 `help` 声明和 App 实际接受行为不一致。2026-07-25 的复查已实际发现并修复两个此类问题：

- `ui.waitAny` 曾把嵌套可选字符串的错误 JSON 类型当作字段缺失；
- `app.logs.read.after.id` 曾允许超大有限 `Double` 进入 `UInt64` 转换路径，存在运行时 trap 风险。

当前测试已覆盖这两个具体问题，但没有从结构上消除未来漂移。

### 2.4 总体判断

当前设计可作为受测试保护的过渡状态，但不应视为 schema 执行的最终实现：

- 合理：合同只有一个事实源；Mac 和 App 分别在自己的信任边界校验输入；构建期和兼容性检查独立存在。
- 不合理：Swift 对合同已经能够表达的嵌套结构和跨字段规则仍需要手写第二遍。
- 目标：Swift 自动执行 generated schema 的受控子集，typed parser 只做 Swift 类型转换和 UIKit/业务领域规则。

## 3. P1：实现 Foundation-only Swift Schema 子集执行器

### 3.1 目标运行链路

```text
contracts/
  -> generated CommandInputSchema
  -> Foundation-only wire schema validation
  -> typed CommandInput conversion
  -> UIKit / Diagnostics / Core handler domain validation
```

执行器应位于 `Sources/iOSExploreServer/`，不能依赖 UIKit。推荐让它直接解释 `CommandInputSchema.toJSON()` 产生的 `JSON`，从而使 `help` 暴露的结构与运行时执行结构来自同一对象。可选择新增 `CommandSchemaValidator.swift`，或为 `CommandInputSchema` 增加明确的 `validate(data:)` API。

`AnyCommand` 应在调用 `Input.parse(from:)` 前执行 generated `contract.inputSchema` 校验。校验失败继续映射为 HTTP 200 的 `invalid_data` envelope，不改变现有 endpoint 或通信失败/业务失败分层。

### 3.2 首期支持范围

只实现项目实际使用的受控子集，不实现任意 JSON Schema 方言：

- `type`，包括 nullable type 数组；
- `required`、`additionalProperties`；
- `enum`；
- `minimum`、`maximum`；
- `minItems`、`maxItems`、`uniqueItems`；
- 递归 `properties` 和 `items`；
- `oneOf`、`allOf`、`not`；
- 结构化 `x-iosExplore-constraints.exactlyOneOf`；
- 结构化 `x-iosExplore-constraints.mutuallyExclusive`。

`description`、`default`、`x-iosExplore-propertyOrder` 和 `x-iosExplore-constraints.note` 是 annotation，不应被当作可执行规则。默认值仍由 typed `CommandField` 在读取阶段填充。

对于 JSON integer，必须继续使用 JSON safe integer 和 `Double.isFinite`/精确整数判断，不能先做可能 trap 的 Swift 整数转换。对于字段“是否出现”的判断，必须在测试中固定 null、空字符串、数值 `0` 和布尔 `false` 的语义，不能直接套用 JavaScript truthy 规则。

### 3.3 迁移策略

1. 先为 schema validator 编写每个关键字的正反单元测试，包括嵌套 object/array、nullable、组合约束和错误路径。
2. 把 validator 接入 `AnyCommand`，暂时保留现有手写校验，增加“通用校验结果与 parser 结果一致”的回归测试。
3. 逐个审计使用 `readRaw` 的路径：
   - `ui.waitAny.conditions`；
   - `ui.webView.eval.arguments`；
   - `ui.control.sendAction.value`；
   - `app.logs.read.after`。
4. 仅删除 schema 已完整表达且通用执行器已覆盖的手写结构校验；保留以下领域规则：
   - locator path 文法和非空值语义；
   - wait mode 与对应字段的条件关系；
   - `conditions[].id` 按 id 唯一，而非完整对象 `uniqueItems`；
   - 日期字符串解释和日期分量组合；
   - UIKit control 类型与 `value` 的对应关系；
   - snapshot 生命周期、view 状态和 UIKit 对象关系。
5. 删除或改写 `CommandInput.swift`、`CommandInputSchema.swift` 中“constraints 只输出、不执行”的 F-25 注释，避免完成实现后文档继续声明旧行为。

### 3.4 验收标准

- 直接向 App `POST /` 发送错误的嵌套类型、数组长度、未知嵌套字段和跨字段组合时，稳定返回 `invalid_data`。
- 所有 `contracts/` 中结构化且声明为可执行的约束都有至少一个 accept 和 reject 测试。
- `CommandInput.parse` 不再重复实现 schema 已经完整表达的普通结构规则。
- `swift test`、`npm run contracts:check` 和 `npm test` 全部通过。
- Core 仍不 import UIKit，新增类型满足 Swift 6.2 `Sendable`/严格并发要求。

## 4. P1：明确错误合同的语义范围

当前多数 UIKit/Diagnostics action 的 `errors` 列表较宽，但设计没有足够精确地说明列表包含哪一层错误：

- handler 直接产生的 App envelope code；
- router/session/timeout 等所有 App envelope code；
- host transport/protocol 错误；
- workflow 或 artifact 错误；
- 成功 `data` 内部携带的业务状态码。

在语义明确前，不应批量缩减现有列表。2026-07-25 只补充了能够确定缺失的 `workflow_timeout` 和 `artifact_decode_failed`。

建议决策：

- DeviceActionContract `errors` 只声明通过该 action 的 HTTP 200 失败 envelope 可观察到的稳定 code，并明确是否包含 router 公共错误。
- HostOperationSpec `errors` 声明该 operation 可能返回的 transport、protocol、appEnvelope、workflow 和 artifact 错误并集。
- `errors.json` 继续只保存错误码的机器语义和来源，不保存动态 message。
- MCP `isError`、CLI exit code 和 guidance 仍属于 adapter 投影策略，不进入 wire error contract。

需要增加静态测试：合同引用的 error 必须存在于 error index；runtime/workflow 中显式构造的稳定错误必须被相应 operation 声明；成功数据内的状态字段不得误列为 envelope error。

## 5. P2：补齐成功结果合同

当前 `result` 只声明 `{ "kind": "json" }`、`image` 或 `text`，没有描述 JSON 成功数据的字段、可空性和范围。因此目前只能检查 result kind，不能对成功数据结构做生成、兼容性比较或 adapter 解码约束。

建议单独设计，例如给 `ResultSpec` 增加可选 `schema` 或引用共享 result definition。该变更会扩大合同模型、生成器、Swift metadata、TypeScript 类型和兼容性比较范围，不应与 Swift 输入 validator 混在同一个提交中。

实施前需决定：

- envelope 外层与 action `data` schema 的所有权；
- image artifact 是描述 base64 wire data，还是描述 host 解码后的 artifact；
- `help` 是否输出完整 result schema；
- result schema 变化对应的 contractVersion 规则；
- 动态 UIKit snapshot 和日志 entry 是否使用稳定子集或完整结构。

## 6. P0：确认 1.0.0 是否已经对外发布

现有设计规定：修改默认值、必填字段、enum、范围、错误码含义或结果结构需要 major 版本。2026-07-25 修复为 `app.logs.read.after.id` 增加最大值，并补充了 host operation 错误声明，但当前仍保持 `contractVersion: 1.0.0`。

当前仓库没有 Git tag。若 1.0.0 尚未作为稳定合同对外分发，可以把这些修改视为首次发布前的修正，并在内容稳定后再打 tag。若 1.0.0 已被外部客户端使用，则发布这些范围/错误语义变化前必须按现有规则提升 major 版本；不能只依赖 contract hash 代替版本升级。

切换电脑后应先确认发布事实，再进行其他合同修改。

## 7. P2：补充真实 App 端到端验证

当前验证包含 Swift 单元/集成测试、Node 测试和 transport 模拟，但尚未启动模拟器或真机 App 执行完整 HTTP 链路。仍需在 Debug App 中验证：

1. `ping` 和 `help` 的版本/hash/schema metadata；
2. 绕过 iOSDriver 直接发送非法 device action，确认 Swift 返回 `invalid_data`；
3. CLI `doctor`/`call` 和 MCP capability probe；
4. UIKit、Diagnostics 扩展显式注册后的 action 集；
5. 截图 artifact 解码和实际响应大小限制；
6. 真机场景下的 `iproxy` 连接，但不得把设备 ID 写入通用文档或 skill。

该项目仍是 Debug-only。真实 App 验证不能改变 Core 不依赖 UIKit、单一 `POST /` endpoint、HTTP/业务失败分层等硬规则。

## 8. 已完成修复，下一轮不要重复实现

截至本文编写时，以下问题已在当前工作区修复并有测试：

- host operation 使用 generated `HOST_OPERATION_SPECS` 做统一输入校验；
- Swift schema 生成保留 canonical property 声明顺序；
- contract hash 对 schema property 顺序敏感，对普通对象键顺序稳定；
- schema compatibility 按 Swift `help` 实际投影比较 nullable、顺序和组合约束；
- capability probe 清理旧策略并使用 generation 防止旧请求覆盖新结果；
- HTTP response 默认限制为 8 MiB，并检查声明长度和流式实际长度；
- artifact 解码失败不再把原始无效/超大图片数据放入错误；
- `ui.waitAny` 嵌套字符串类型和 `app.logs.read.after.id` 安全整数问题已修复；
- 新 CLI MCP 入口和 legacy 入口都有启动测试。

编写本文前最近一次验证结果：

- `cd iOSDriver && npm run contracts:check`：通过；
- `cd iOSDriver && npm test`：24 个测试文件、166 个测试通过；
- `swift build`：通过；
- `swift test`：13 个 suite、321 个测试通过；
- `git diff --check`：通过。

这些结果不替代切换电脑后的重新验证。同步分支后应先运行 `git status`、合同漂移检查和定向测试，再开始后续修改。

## 9. 建议实施顺序

1. P0：确认 `1.0.0` 是否已发布，决定是否需要 major bump。
2. P1：实现 Foundation-only Swift schema 子集执行器并接入 `AnyCommand`。
3. P1：定义 error list 的精确语义，再审计和缩减/补充各合同。
4. P2：单独设计并实现 result schema。
5. P2：运行模拟器和真机端到端验证，记录可复现命令和结果。

每一步都应独立提交。涉及 `contracts/` 时必须重新生成产物并运行 `cd iOSDriver && npm run contracts:check`；涉及 Swift 输入行为时先跑相关定向测试，完成后再运行 `swift test`。
