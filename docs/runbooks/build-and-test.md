# 构建与测试

## SPM 库（主）

```bash
swift build                              # 构建
swift test                               # 全量测试（当前 60 个，含端到端、UI 层级模型、control action 和 tap 参数解析）
swift test --enable-code-coverage        # 带覆盖率（当前 89.91%）
swift test --filter Integration          # 只跑端到端集成测试
```

- 集成测试在测试进程内起真实 `ExploreServer` + 用 `NWConnection` 走 loopback 验证往返，**模拟器/CI/本机都能跑**，无需真机。
- 集成测试用端口 **38399**，且用 `@Suite(.serialized)` 串行（4 个测试共用端口，不能并行）。
- UIKit 层级模型、筛选逻辑、control action 和 tap 参数解析是 Foundation-only，可由 macOS `swift test --filter UIKitViewHierarchyTests` / `swift test --filter UIKitControlActionTests` / `swift test --filter UIKitTapTests` 覆盖；真实 UIKit 采集器、`sendActions(for:)` 和 `hitTest` 点击流程需要 framework/iOS 构建或 App 运行验证。

## framework 工程（手动编 `.framework`）

```bash
xcodebuild -project iOSExploreServer/iOSExploreServer.xcodeproj \
           -scheme iOSExploreServer \
           -sdk iphonesimulator \
           -destination 'generic/platform=iOS Simulator' build
```

- 该工程的 `PBXFileSystemSynchronizedRootGroup` 指向根 `Sources/iOSExploreServer/`，与 SPM 共享源码。
- `BUILD_LIBRARY_FOR_DISTRIBUTION=NO`：Swift 6.2 工具链下，library-evolution 的 `.swiftinterface` 会因 `nonisolated(nonsending)` 在 `SwiftVerifyEmittedModuleInterface` 失败，故关闭。代价：不再生成跨 Xcode 版本的稳定 interface，对"手动编译嵌入同版本 Xcode 项目"无影响。

## SPMExample 测试 App

Xcode 打开 `Examples/SPMExample/SPMExample.xcodeproj` → 选真机或模拟器 → Run。
App 启动后默认「○ 已停止」，点「启动 Server」开始监听 `:38321`。

## 真机端到端验证（完整 USB 链路）

1. 真机连数据线 → 信任此电脑。
2. Xcode 选真机 → Run SPMExample → App 内点「启动 Server」（状态变 `● 监听中 :38321`）。
3. Mac 终端：`./scripts/proxy.sh`（前台，保持运行）。
4. **另开一个终端**：
   ```bash
   curl -X POST http://localhost:38321/ -d '{"action":"ping"}'
   curl -X POST http://localhost:38321/ -d '{"action":"info"}'
curl -X POST http://localhost:38321/ -d '{"action":"greet","data":{"name":"Claude"}}'
curl -X POST http://localhost:38321/ -d '{"action":"device"}'
curl -X POST http://localhost:38321/ -d '{"action":"ui.topViewHierarchy","data":{"maxDepth":2}}'
curl -X POST http://localhost:38321/ -d '{"action":"ui.control.sendAction","data":{"accessibilityIdentifier":"mine.header.avatar","event":"touchUpInside"}}'
curl -X POST http://localhost:38321/ -d '{"action":"ui.tap","data":{"accessibilityIdentifier":"mine.header.avatar"}}'
```
5. App 日志面板应实时显示每个请求；curl 输出应为 envelope JSON。

> 已在 iPhone12,1 / iOS 26.5 验证通过（见 `.git/sdd/progress.md`）。

## 模拟器快速验证（不用 iproxy）

模拟器与 Mac 共享网络栈，Mac 可直接打模拟器里的 Server：
```bash
curl -X POST http://127.0.0.1:38321/ -d '{"action":"ping"}'
```
前提：模拟器 App 已点「启动 Server」。
