---
paths:
  - "Sources/iOSExploreServer/**/*.swift"
---

# iOSExploreServer 库源码规则

- **只 `import Foundation` / `Network`，禁止 `import UIKit`。** 需要 UIKit 的能力（UIDevice 等）由 App 层注册额外 handler 注入，不进库。
- **Swift 6.2 严格并发**：跨边界模型 `Sendable`；共享可变状态用 `actor`；闭包 `@Sendable`；连接处理 `Task` 捕获 actor/@Sendable 闭包，不捕获 `self`。
- **唯一命令端点 `POST /` + JSON envelope**。新增能力 = 注册新 `action`，不改协议/传输/envelope 格式。
- 改完**先跑 `swift test`** 再说完成（含 `IntegrationTests`，端口 38399，`@Suite(.serialized)` 串行）。
- 新增 `.swift` 文件会被 SPM target 与 framework 同步组**自动收录**，无需改 `Package.swift`/`project.pbxproj`。
- 库源码须同时兼容 SPM（Swift 6.2）与 framework 工程（`SWIFT_VERSION=5.0`）：**避免 Swift-6-only 语法**（if/else 表达式、typed throws 等）。
- 改 `HTTPParser.parseRequest` 的定界逻辑要同步检查 `HTTPListener.handle` 的累积循环依赖（parser 必须对 partial body 严格返回 nil）。
