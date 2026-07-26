# 构建与测试

按改动影响范围选择验证；不要为了文档或只读任务机械跑全量测试。

## Swift Package

```bash
swift build
swift test
swift test --enable-code-coverage
swift test --filter Integration
```

说明：

- `swift build` 覆盖 core、UIKit 扩展和 Diagnostics 扩展的 SPM 编译。
- macOS `swift test` 覆盖 core、Foundation-only typed input、解析、snapshot store、Diagnostics 可测逻辑和 loopback 集成测试。
- 集成测试在测试进程内启动真实 `ExploreServer`，通过 loopback 验证 HTTP 往返，不需要真机。
- 涉及真实 UIKit 采集、target-action、fingerprint 状态和 framework 注册断言时，需要 iOS framework 测试或真实 App 验证。

## 按改动范围选择验证

| 改动范围 | 首选验证 | 覆盖边界 |
| --- | --- | --- |
| command parser / schema / `CommandInput` model / JSON 值转换 | 定向 `swift test --filter <相关测试名>` | 覆盖跨边界 Sendable 值、字段校验、错误码和 help metadata；不证明真实 `UIView` 行为 |
| UIKit collector / context provider / locator resolver / executor / registrar | iOS framework 定向测试或对应 scheme 的 `xcodebuild ... test` | 覆盖 `@MainActor` 上的真实 UIKit 对象采集、解析、陈旧检测和显式注册 |
| 真实执行行为：`sendActions(for:)`、alert 响应、navigation、scroll、keyboard、WKWebView JS | SPMExample 模拟器闭环；涉及 USB/设备差异时再跑真机闭环 | 覆盖 App 运行时转场、键盘、滚动、alert dismissal、WebView 加载和 HTTP action 往返 |
| 纯文档、README、注释 | `rg` / 链接或路径检查 | 不运行 Swift 测试；只验证文档中命令名、字段名和交叉引用没有明显漂移 |

## Framework 工程

三个 framework target 与 SPM 共享 `Sources/`：

- `iOSExploreServer.framework`
- `iOSExploreUIKit.framework`
- `iOSExploreDiagnostics.framework`

构建：

```bash
xcodebuild -project iOSExploreServer/iOSExploreServer.xcodeproj \
  -scheme iOSExploreServer \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' build
```

测试需要指定当前机器存在的模拟器名称：

```bash
xcodebuild -project iOSExploreServer/iOSExploreServer.xcodeproj \
  -scheme iOSExploreServer \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=<simulator-name>' test
```

不要在通用文档中固化某台机器的模拟器 ID、真机 UDID 或一次性系统版本。

## iOSDriver

```bash
cd iOSDriver
npm install
npm run contracts:check
npm run typecheck
npm test
npm run build
```

合同源变更时：

```bash
cd iOSDriver
npm run contracts:generate
npm run contracts:check
```

`npm test` 会先 build，再运行 vitest。真实 App 端到端 MCP smoke：

```bash
cd iOSDriver
npm run build
node scripts/mcp-inspector.mjs
```

## App 端到端

模拟器与 Mac 共享 localhost。Debug App 启动并调用 `server.start()` 后：

```bash
curl -s -X POST http://localhost:38321/ -d '{"action":"ping"}'
curl -s -X POST http://localhost:38321/ -d '{"action":"help"}'
curl -s -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}'
```

真机需要先通过 USB 转发：

```bash
iproxy 38321 38321
lsof -iTCP:38321 -sTCP:LISTEN
curl -s -X POST http://localhost:38321/ -d '{"action":"ping"}'
```

`lsof` 的 COMMAND 必须是 `iproxy`。如果是其他进程，先清理端口占用。

## UIKit 操作 smoke

交互命令必须先用 `ui.inspect` 取得当前 `viewSnapshotID` 和目标 `path` 或 `accessibilityIdentifier`：

```bash
curl -s -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}'
curl -s -X POST http://localhost:38321/ \
  -d '{"action":"ui.tap","data":{"path":"<path-from-inspect>","viewSnapshotID":"<snapshot-id>"}}'
```

`ui.topViewHierarchy` 和 `ui.screenshot` 不签发 `viewSnapshotID`，不能作为 `ui.tap` / `ui.control.sendAction` 的 freshness 来源。

## Diagnostics smoke

宿主注册 Diagnostics 后：

```bash
curl -s -X POST http://localhost:38321/ -d '{"action":"app.logs.mark"}'
curl -s -X POST http://localhost:38321/ -d '{"action":"ping"}'
curl -s -X POST http://localhost:38321/ \
  -d '{"action":"app.logs.read","data":{"after":{"captureSessionID":"<from-mark>","id":0},"limit":50}}'
```

stdout/stderr/NSLog/os_log 捕获默认关闭，只有宿主 Debug 配置显式打开后才会进入 `app.logs.read`。`capture.oslog.state="unavailable"` 表示系统或沙箱不允许读取当前进程 unified logging，不等于没有产生日志。
