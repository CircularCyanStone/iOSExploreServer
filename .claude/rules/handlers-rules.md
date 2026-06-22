---
paths:
  - "Sources/iOSExploreServer/Handlers/**/*.swift"
---

# Handler 规则

- 命令实现 `Command` 协议:`var action`/`var description`/`var parameters`/`func handle(_:) async throws -> ExploreResult`。`parameters` 默认空,声明参数的命令才填。
- 注册方式(二选一,均同步):
  - 协议对象(首选):`server.register(MyCommand())` 或 `router.register(MyCommand())`。
  - 闭包便捷入口:`server.register(action: "name", description: "...", parameters: [...]) { req in ... }`。
- 返回 `.success(JSON)` 或 `.failure(code: ExploreError, message: String)`;**不要向外 rethrow**——`Router` 已捕获异常并转为 `.internalError`。
- 参数校验由 `Router` 统一做(按 `parameters` 校验必填 + 类型,不过返回 `.invalidData`);handler 内无需重复校验,只管业务。
- 取入参用 `req.data["key"]?.stringValue` / `.doubleValue` / `.boolValue`。
- **禁止依赖 UIKit**。需要 UIKit 信息(如 `UIDevice`)时,在 App 层(`SPMExample`)注册单独 handler,handler 内用 `await MainActor.run { ... }` 取值后返回。
- 新内置命令:实现 `Command` struct,在 `BuiltinHandlers.registerAll(into:)` 注册,同步在 `BuiltinHandlersTests` 补测试。
