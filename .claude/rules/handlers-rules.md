---
paths:
  - "Sources/iOSExploreServer/Handlers/**/*.swift"
---

# Handler 规则

- 命令实现 typed `Command` 协议:`associatedtype Input: CommandInput`、`var action`、`var description`、`func handle(_ input: Input) async throws -> ExploreResult`。
- 注册方式(二选一,均同步):
  - 协议对象(首选):`server.register(MyCommand())` 或 `router.register(MyCommand())`。
  - 闭包便捷入口:`server.register(action: "name", description: "...", input: MyInput.self) { input in ... }`。
- 返回 `.success(JSON)` 或 `.failure(code: ExploreError, message: String)`;**不要向外 rethrow**——`Router` 已捕获异常并转为 `.internalError`。
- 参数校验由 `CommandInput.parse(from:)` + `CommandInputDecoder.read(_:)` 统一做，失败返回 `.invalidData`;handler 入参已经是 typed input，只管业务。
- 字段声明用 `CommandField` / `CommandFields` 作为 schema 与解析单一来源；不要在 handler 内直接读 `ExploreRequest.data`。
- **禁止依赖 UIKit**。需要 UIKit 信息(如 `UIDevice`)时,在 App 层(`SPMExample`)注册单独 handler,handler 内用 `await MainActor.run { ... }` 取值后返回。
- 新内置命令:实现 `Command` struct,在 `BuiltinHandlers.registerAll(into:)` 注册,同步在 `BuiltinHandlersTests` 补测试。
