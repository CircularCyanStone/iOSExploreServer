---
paths:
  - "Sources/iOSExploreServer/Handlers/**/*.swift"
---

# Handler 规则

- handler 签名固定：`@Sendable (ExploreRequest) async throws -> ExploreResult`。
- 注册方式：`await router.register(action: "name") { req in ... }`，或内置命令经 `BuiltinHandlers.registerAll(into:)`。
- 返回 `.success(JSON)` 或 `.failure(code: ExploreError, message: String)`；**不要向外 rethrow**——`Router` 已捕获异常并转为 `.internalError`。
- 取入参用 `req.data["key"]?.stringValue` / `.doubleValue` / `.boolValue`（返回 `JSONValue?`，链式取值）。
- **禁止依赖 UIKit**。需要 UIKit 信息（如 `UIDevice`）时，在 App 层（`SPMExample`）注册单独 handler，并在 handler 内用 `await MainActor.run { ... }` 取值后返回。
- 新内置命令加到 `BuiltinHandlers` 并在 `registerAll(into:)` 注册，同步在 `BuiltinHandlersTests` 补测试。
