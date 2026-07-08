# 构建与测试

## SPM 库（主）

```bash
swift build                              # 构建（core + iOSExploreUIKit + iOSExploreDiagnostics）
swift test                               # 全量测试（macOS SPM 当前 225 个，含端到端、UIKit 模型/解析/snapshot store/Diagnostics；iOS framework 下当前 344 个，额外覆盖 UIKit 指纹状态与动作能力）
swift test --enable-code-coverage        # 带覆盖率（当前行覆盖 86.62%）
swift test --filter Integration          # 只跑端到端集成测试
```

- 集成测试在测试进程内起真实 `ExploreServer` + 用 `NWConnection` 走 loopback 验证往返，**模拟器/CI/本机都能跑**，无需真机。
- 集成测试用端口 **38399**，且用 `@Suite(.serialized)` 串行（多个测试共用端口，不能并行）。iOS 模拟器上 `NWListener.cancel()` 释放端口是异步的，串行用例间偶发 `Address already in use`；测试用 `startWithPortRetry` 在端口占用时退避重试，macOS 下首次即成功。
- UIKit 层级模型、筛选逻辑、control/tap 参数解析、snapshot store 是 Foundation-only，可由 macOS `swift test` 覆盖；真实 UIKit 采集器、`sendActions(for:)` 和 `hitTest` 点击流程需要 framework/iOS 构建或 App 运行验证。UIKit 命令的"显式注册正向断言"（`#if canImport(UIKit)`）只在 framework iOS 测试下编译运行。

## framework 工程（手动编 `.framework`）

framework 工程有三个 framework target，与 SPM 共享同一份 `Sources/` 源码：

```bash
# 构建三个 framework（iOSExploreServer + iOSExploreUIKit + iOSExploreDiagnostics）
xcodebuild -project iOSExploreServer/iOSExploreServer.xcodeproj \
           -scheme iOSExploreServer \
           -sdk iphonesimulator \
           -destination 'generic/platform=iOS Simulator' build

# 单独构建 UIKit framework
xcodebuild -project iOSExploreServer/iOSExploreServer.xcodeproj \
           -scheme iOSExploreUIKit \
           -sdk iphonesimulator \
           -destination 'generic/platform=iOS Simulator' build

# framework 测试（含 iOS 正向注册断言，需具体模拟器设备）
xcodebuild -project iOSExploreServer/iOSExploreServer.xcodeproj \
           -scheme iOSExploreServer \
           -sdk iphonesimulator \
           -destination 'platform=iOS Simulator,name=iPhone 17' test
```

- `iOSExploreServer.framework`：`PBXFileSystemSynchronizedRootGroup` 指向 `../Sources/iOSExploreServer/`。
- `iOSExploreUIKit.framework`：指向 `../Sources/iOSExploreUIKit/`，链接并依赖 core framework。测试 target 同时链接两个 framework。
- **core/UIKit 边界**：core framework 不得 `import UIKit`；UIKit framework 只用 core 的 public 缝。
- Debug/Release 均 `SWIFT_VERSION=5.0`、`BUILD_LIBRARY_FOR_DISTRIBUTION=NO`。
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
curl -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}'
# 以下两个动作必填 viewSnapshotID（snap-1 只是占位，实际取上一步 ui.inspect 返回的 data.viewSnapshotID）
curl -X POST http://localhost:38321/ -d '{"action":"ui.control.sendAction","data":{"accessibilityIdentifier":"mine.header.avatar","viewSnapshotID":"snap-1","event":"touchUpInside"}}'
curl -X POST http://localhost:38321/ -d '{"action":"ui.tap","data":{"accessibilityIdentifier":"mine.header.avatar","viewSnapshotID":"snap-1"}}'
curl -X POST http://localhost:38321/ -d '{"action":"app.logs.mark"}'
curl -X POST http://localhost:38321/ -d '{"action":"debug.emitAppLog"}'
curl -X POST http://localhost:38321/ -d '{"action":"app.logs.read","data":{"after":{"captureSessionID":"替换为 mark 返回值","id":0},"sources":["bridge"],"limit":20}}'
```
5. App 日志面板应实时显示每个请求；curl 输出应为 envelope JSON。

Diagnostics 示例 App 在 Debug 构建下已通过 `ViewController.exampleDiagnosticsConfiguration()` 直接打开 stdout/stderr/NSLog/os_log 四个 capture，不再使用环境变量或启动参数控制；Release 构建下四个 capture 全关。Release 构建或未开 capture 时，`app.logs.mark/read` 的 `capture.stdout`、`capture.stderr`、`capture.nslog` 与 `capture.oslog` 会显示 `notCaptured`，但 `explore` 内部日志和 `debug.emitAppLog` 写入的 `bridge` 日志仍可读取。验证进程日志捕获时，直接启动 Debug 构建即可：

```bash
# XcodeBuildMCP 模拟器启动示例；真机同理用 launch_app_device，并在 Mac 侧保留 iproxy。
launch_app_sim(env={"IOS_EXPLORE_AUTOSTART":"1"})  # capture 在 Debug 代码里直配，无需 env

curl -X POST http://localhost:38321/ -d '{"action":"ping"}'
curl -X POST http://localhost:38321/ -d '{"action":"app.logs.mark"}'
curl -X POST http://localhost:38321/ -d '{"action":"debug.emitStdout","data":{"message":"stdout-curl-check-替换为唯一值"}}'
curl -X POST http://localhost:38321/ -d '{"action":"debug.emitStderr","data":{"message":"stderr-curl-check-替换为唯一值"}}'
curl -X POST http://localhost:38321/ -d '{"action":"debug.emitNSLog","data":{"message":"nslog-curl-check-替换为唯一值"}}'
curl -X POST http://localhost:38321/ -d '{"action":"debug.emitOSLog","data":{"message":"oslog-curl-check-替换为唯一值"}}'
curl -X POST http://localhost:38321/ -d '{"action":"debug.emitLogger","data":{"message":"logger-curl-check-替换为唯一值"}}'
curl -X POST http://localhost:38321/ -d '{"action":"app.logs.read","data":{"after":{"captureSessionID":"替换为 mark 返回值","id":0},"sources":["stdout"],"limit":20}}'
curl -X POST http://localhost:38321/ -d '{"action":"app.logs.read","data":{"after":{"captureSessionID":"替换为 mark 返回值","id":0},"sources":["stderr"],"limit":20}}'
curl -X POST http://localhost:38321/ -d '{"action":"app.logs.read","data":{"after":{"captureSessionID":"替换为 mark 返回值","id":0},"sources":["nslog"],"limit":20}}'
curl -X POST http://localhost:38321/ -d '{"action":"app.logs.read","data":{"after":{"captureSessionID":"替换为 mark 返回值","id":0},"sources":["oslog"],"limit":20}}'
```

stdout 结果应为 `source:"stdout"`、`level:"info"`；stderr 结果应为 `source:"stderr"`、`level:"error"`；NSLog 结果应为 `source:"nslog"`；`os_log` 与 Swift `Logger` 结果统一进入 `source:"oslog"`。如果当前 OS 或沙箱不允许 `OSLogStore` 读取当前进程日志，`capture.oslog.state` 会是 `unavailable`，这种情况要按状态排查，不要解释成“没有产生日志”。

> 已在 iPhone12,1 / iOS 26.5 验证通过（见 `.git/sdd/progress.md`）。

## 模拟器快速验证（不用 iproxy）

模拟器与 Mac 共享网络栈，Mac 可直接打模拟器里的 Server：
```bash
curl -X POST http://127.0.0.1:38321/ -d '{"action":"ping"}'
curl -X POST http://127.0.0.1:38321/ -d '{"action":"app.logs.mark"}'
```
前提：模拟器 App 已点「启动 Server」。
