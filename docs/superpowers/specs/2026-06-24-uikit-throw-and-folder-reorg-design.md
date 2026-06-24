# UIKit 模块 throw 化 + 文件夹重组设计

- 日期：2026-06-24
- 范围：`Sources/iOSExploreUIKit/`（UIKit 扩展模块，4 个 `ui.*` 命令）
- 不涉及 core（`Sources/iOSExploreServer/`）任何 public 协议或行为变更

## 背景与动机

UIKit 模块当前用一组自定义 Result 风格枚举在内部传递失败：

- `UIKitContextProvider.ContextResult`（`.success(Context)` / `.failure(String)`）
- `UIKitLocatorResolver.LocateResult`（`.found(LocatedView)` / `.notFound` / `.ambiguous(count)`）
- `UIKitSnapshotStore` 校验返回的 `valid / stale` 枚举

每个调用点都要写一段 `switch … case .failure / .notFound / .ambiguous …` 然后手动构造 `UIKitCommandError`、记日志、`return error.result`。`UIKitActionExecutor` 内部因此堆叠了 6 处以上几乎同构的 switch+return，可读性差，且每处都要重复「构造错误 → 记日志 → 返回」三行。

同时模块按 9 个顶层文件夹组织，4 个 `*Command` 与辅助类型（Context / Locator / Action / Snapshot / Utils）平铺在同一层，读者无法一眼分辨「哪些是命令、哪些是辅助」。

本设计做两件事：

1. **throw 化**：删除上述自定义 Result 枚举，UIKit 内部执行核心全程 `throws`，失败 `throw UIKitCommandError`，边界转换集中在 handler 顶层。
2. **文件夹重组**：顶层 `Commands/` 收 4 个命令及其紧密配套，`Support/` 收横切辅助，让「命令 vs 辅助」边界一眼可分。

## 关键约束（决定 throw 化形态）

命令 handler 协议（core，不改）：

```swift
func handle(_ request: ExploreRequest) async throws -> ExploreResult
```

handler 可以 throw，但 `Router.route` 会把 **thrown 的 error 一律转成 `.failure(code: internal_error)`**（`ExploreServerError.handlerThrown`），丢失 `hierarchy_unavailable` / `target_not_found` / `invalid_data` 等业务码。只有 handler **返回** `ExploreResult.failure(code, message)` 才保留业务码（HTTP 200 envelope）。

**结论**：UIKit 的业务错误码必须以 `ExploreResult.failure` 从 handler 返回，**不能一路 throw 到 Router**。因此 throw 化的正确形态是——UIKit 内部全程 `throws UIKitCommandError`，handler 顶层 `catch` 后转 `error.result`。

## 设计一：throw 化

### 错误载体

`UIKitCommandError` 增加 `Error` 协议（现已是 `Sendable & Equatable`），成为 UIKit 内部唯一可抛出的业务错误类型：

```swift
struct UIKitCommandError: Error, Sendable, Equatable {
    let failure: ExploreCommandFailure
    var result: ExploreResult { failure.result }
    // 13 个工厂方法（hierarchyUnavailable / targetNotFound / staleLocator / …）签名不变
}
```

每个工厂方法仍自封装 `code` + 对外 `message` + 内部 `logMessage`（含 action / target / reason 完整上下文），抛出点一行即可。

### 删除的自定义 Result 枚举

| 枚举 | 位置 | 替代 |
|---|---|---|
| `ContextResult` | `UIKitContextProvider` | `currentContext(action:) throws`，失败直接 throw `hierarchyUnavailable` |
| `LocateResult` | `UIKitLocatorResolver` | `locate(...) throws`，notFound/ambiguous 直接 throw 对应错误 |
| `UIKitSnapshotValidation`（`valid/stale`） | `UIKitSnapshotStore` | 删枚举；改 `isStale(...) -> Bool`，executor 在 true 时 throw `staleLocator` |

### 执行核心签名变更（B2：对外 `throws -> JSONValue`）

执行核心不再碰 `ExploreResult`——成功返回纯 JSON，失败 throw：

| 类型 | 现状 | 改为 |
|---|---|---|
| `UIKitContextProvider` | `currentContext() -> ContextResult` | `currentContext(action:) throws -> Context` |
| `UIKitLocatorResolver` | `locate(...) -> LocateResult` | `locate(...) throws -> LocatedView` |
| `UIKitSnapshotStore` | `validation(snapshotID:path:context:current:) -> UIKitSnapshotValidation`（public） | `isStale(snapshotID:path:context:current:) -> Bool`（public） |
| `UIKitActionExecutor` | `execute(_:) -> ExploreResult` / `execute(_:context:) -> ExploreResult` | `execute(_:) throws -> JSONValue` / `execute(_:context:) throws -> JSONValue` |
| `UIViewHierarchyCollector` | `collectTopViewHierarchy(query:) -> ExploreResult` | `collectTopViewHierarchy(query:) throws -> JSONValue` |
| `UIViewTargetsCollector` | `collect(query:) -> ExploreResult` | `collect(query:) throws -> JSONValue` |

效果：`executeTap` / `executeControlEvent` 内部从「locate 的 found/notFound/ambiguous switch + context 的 success/failure switch + freshness 的 stale/valid switch」塌缩成线性 `try` 链，例如：

```swift
let context  = try UIKitContextProvider.currentContext(action: controlAction)
let located  = try UIKitLocatorResolver.locate(locator: locator, in: context.rootView)   // 复用值直接拿到
if case .path = locator, let snapshotID {
    try validateFreshness(located: located, snapshotID: snapshotID, context: context, action: controlAction)
}
let control  = try requireControl(from: located)   // 内部 throw controlTargetNotControl
…
return json
```

`validateFreshness` 由「返回 `ExploreResult?`」改为 `throws`（stale 时 throw `staleLocator`，正常时直接返回）。

### 边界转换集中在 handler 顶层

每个 command 的 `handle` 统一 catch，业务码走 `e.result`（不丢），日志在顶层一处记：

```swift
func handle(_ request: ExploreRequest) async throws -> ExploreResult {
    UIKitCommandLogging.info("command", "command \(action) start payloadKeys=\(request.data.storage.count)")
    do {
        let query = try UITapQuery.parse(from: request.data)            // throws QueryParseError
        let plan  = UIKitActionPlan.tap(locator: query.target.locator, snapshotID: query.snapshotID)
        let json  = try await UIKitActionExecutor.execute(plan)          // throws UIKitCommandError
        UIKitCommandLogging.info("command", "command \(action) completed …")
        return .success(json)
    } catch let e as UIKitCommandError {
        UIKitCommandLogging.error("command", e.failure.logMessage)
        return e.result
    } catch let p as QueryParseError {
        let e = UIKitCommandError.invalidData(action: action, message: p.message)
        UIKitCommandLogging.error("command", e.failure.logMessage)
        return e.result
    }
}
```

`QueryParseError`（Foundation-only，typed query 解析）保持单独 catch 转 `invalidData`——它是 parse 阶段错误，不属于执行核心，不并入 `UIKitCommandError`。

### `currentContext` 加 `action` 参数

`hierarchyUnavailable(action:reason:)` 需要 action 做日志关联，而 `currentContext` 是通用方法。让调用方传入自己的 action：executor 传 `actionName(for: plan)`（tap→`ui.tap`，control→`ui.control.sendAction`），两个 collector 传各自 `actionName`。失败时 `currentContext` 内部直接 throw 完整的 `hierarchyUnavailable`，顶层 catch 无需二次包装。

## 设计二：文件夹重组（Commands/ + Support/）

```
Sources/iOSExploreUIKit/
  Commands/                              ← 4 个 ui 命令 + 紧密配套
    TopViewHierarchy/
      TopViewHierarchyCommand.swift
      UIViewHierarchyModels.swift
      UIViewHierarchyCollector.swift
    ViewTargets/
      ViewTargetsCommand.swift
      UIViewTargetsModels.swift
      UIViewTargetsCollector.swift
    Tap/
      UITapCommand.swift
      UITapModels.swift
    ControlAction/
      UIControlSendActionCommand.swift
      UIControlSendActionModels.swift
  Support/                               ← 横切辅助类型
    Context/
      UIKitContextProvider.swift
    Locator/
      UIKitLocator.swift
      UIKitLocatorResolver.swift
      UIKitViewLookupModels.swift        ← UIKitViewLookupTarget（identifier/path 定位模型），主要消费者是 UIKitLocator
    Action/
      UIKitActionExecutor.swift          ← tap + control 共用执行核心
      UIKitActionCapabilityResolver.swift
      UIKitActionKind.swift
      UIKitActionPlan.swift
    Snapshot/
      UIKitFingerprintCollector.swift
      UIKitSnapshotStore.swift
      UIKitSnapshotResponse.swift
    Parsing/
      QueryDecoder.swift
      QueryParseError.swift
      UIKitQueryNumber.swift
  UIKitCommandRegistrar.swift            ← 根：注册入口
  UIKitCommandError.swift                ← 根：错误工厂（被所有层用）
  UIKitCommandLogging.swift              ← 根：日志入口（被所有层用）
```

### 归属原则

- **collector 跟命令走**：`UIViewHierarchyCollector` 只服务 `ui.topViewHierarchy`、`UIViewTargetsCollector` 只服务 `ui.viewTargets`，紧耦合，进 `Commands/X/`。
- **`UIKitActionExecutor` 进 `Support/Action/`**：tap + control **共用**执行核心，不属于任一单一命令。
- **`UIKitViewLookupModels` 进 `Support/Locator/`**：其 `UIKitViewLookupTarget` 表达「按 identifier/path 定位 view」语义，主要消费者是 `UIKitLocator`；其中的 `UIControlSendActionTarget` typealias 专属于 control 命令，实现时可作为可选内聚优化移到 `ControlAction/UIControlSendActionModels.swift`（非必须）。
- **根目录 3 个文件保持根级**：`UIKitCommandRegistrar` / `UIKitCommandError` / `UIKitCommandLogging` 被所有层依赖，是模块级横切，一眼可见。
- **`Utils/` → `Support/Parsing/`**：语义化命名；`QueryDecoder` / `QueryParseError` / `UIKitQueryNumber` 是通用 JSON→typed query 解析工具。

### 工程影响

- framework 工程 target 用 `PBXFileSystemSynchronizedRootGroup` 指向 `Sources/iOSExploreUIKit/`，**移动文件自动同步，无需手改 `.pbxproj`**。
- SPM 同一 target，模块内 `import` 不变（无显式 import 语句变化）。
- `docs/uikit/uikit-file-reference.md`（逐文件登记）与新 `reading-guide.md` 路径需同步更新。

## 影响面与测试

- **源文件改动**：UIKit 模块约 15 个文件（3 个 collector/executor 的签名 + handler 顶层 catch + 删除的枚举 + 目录移动）。
- **测试改动**：
  - 执行核心对外从 `-> ExploreResult` 改为 `throws -> JSONValue`，测试断言从「拿 `ExploreResult` 断言 `.failure(code:)`」改为「`XCTAssertThrowsError` 断言 `error.failure.code`」；成功路径直接断言 JSON 字段（更干净）。
  - `UIKitContextProvider.currentContext` 签名变（加 `action`、throws），`UIKitTestHost` 与相关测试同步。
  - `UIKitSnapshotStore.validation` → `isStale`，store 测试同步。
- **public API 变更**：`UIKitSnapshotStore.validation`（两个 overload）与 `UIKitSnapshotValidation` 是 `public`，改 `isStale` 并删除 `UIKitSnapshotValidation` 属 public 签名变更。UIKit 模块当前仅被自家 App（`Examples/SPMExample`）与测试消费、无第三方依赖，可接受；需同步更新这些消费点。
- **日志点不丢**：每个失败分支的 `logMessage` 由工厂保留，顶层 catch 统一记 `error.failure.logMessage`（含 action/target/reason）；start/complete 的 info 日志保留。
- **验证命令**：`swift test`（SPM，macOS）与 `xcodebuild -project iOSExploreServer/iOSExploreServer.xcodeproj -scheme iOSExploreServer -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' test`（framework，含 iOS 正向注册断言）都要绿。

## 不做的事（YAGNI）

- 不改 core 的 `Command` 协议、`Router`、`ExploreResult`、`ExploreCommandFailure`。
- 不把 `QueryParseError` 并入 `UIKitCommandError`（它是 typed query 解析错误，与 UIKit 执行错误职责不同）。
- 不为 throw 引入新的中间 Error 类型——复用现有 `UIKitCommandError` 工厂，零新增错误类型。
- 不改命令的对外行为、JSON 结构、错误码语义（纯重构 + 错误传递机制现代化）。
- 不强制移动 `UIControlSendActionTarget` typealias（可选内聚优化，非本次目标）。

## 实施顺序建议（供 writing-plans 细化）

1. `UIKitCommandError: Error` + executor/collector 签名改 `throws -> JSONValue`，handler 顶层 catch（throw 化主体）。
2. 删除 `ContextResult` / `LocateResult` / snapshot `valid-stale` 枚举，调用点改线性 `try`。
3. 移动文件到 `Commands/` + `Support/`（纯目录调整，编译应仍绿）。
4. 同步测试断言方式。
5. 更新 `docs/uikit/` 文件档案与阅读指南路径。
