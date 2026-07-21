# 排障手册

## `iproxy` 一直显示 `waiting for connection`

**这是正常的，不是故障。** `iproxy` 在 Mac 监听 38321，**被动等待 `curl` 来连**——它不是在等设备。`curl` 一连 `localhost:38321`，iproxy 才把连接通过 USB 转发到设备。

解决：**另开一个终端**跑 `curl`。运行 `iproxy 38321 38321` 的终端保持前台不要关。

确认两端就绪：
```bash
idevice_id -l                       # 应输出设备 UDID（空=设备没连/没信任）
lsof -iTCP:38321 -sTCP:LISTEN -n -P # 应看到 iproxy 在监听 *:38321
```

## curl 连不上 / 超时 / 连接被拒

按顺序排查：

1. **设备 App 是否点了「启动 Server」**？状态必须是 `● 监听中 :38321`。没启动则设备 :38321 无人监听，curl 会超时。
2. **iproxy 是否在跑**？`lsof -iTCP:38321` 看有没有 iproxy 进程。
3. **设备是否连接且被信任**？`idevice_id -l` 有 UDID；首次连需在手机点「信任」。
4. **端口是否被占用**？`lsof -iTCP:38321` 若被别的进程占，停止冲突进程，或同时修改 `ExploreServer(port:)` 和 `iproxy <mac-port> <device-port>` 的端口。

## 设备返回错误 envelope

- `{"code":"unknown_action",...}` → action 名拼错或没注册。检查 `register(action:)` 拼写。
- `{"code":"bad_request",...}` → body 非合法 JSON 或缺 `action` 字段。检查 curl 的 `-d` JSON。
- `{"code":"internal_error",...}` → handler 抛异常。看 App 控制台日志定位。
- `HTTP/1.1 503 Service Unavailable` → 活跃连接数达到 server 上限。确认 Mac 侧没有悬挂的 curl/MCP 连接，或等待已有请求结束后重试。
- `message` 包含 `command timed out` → handler 执行超过命令超时。检查是否在 handler 内做了截图、UI tree 遍历或其他耗时操作；这类能力后续应做限频/分页/缓存。

## 打开组件内部日志

库默认不输出内部日志。调试时在 App 启动阶段开启：

```swift
ExploreLogging.setEnabled(true)
ExploreLogging.setMinimumLevel(.debug)
```

日志使用 Apple Unified Logging，subsystem 为 `iOSExploreServer`。常用 category：

- `server`：`ExploreServer` 初始化、启动、停止、命令注册。
- `listener`：`NWListener` ready/waiting/failed/cancelled、session 接入/关闭、读取失败、请求过大。
- `http`：HTTP 方法/路径校验、body 解析失败、action 收到、响应状态。
- `router`：action 注册、路由命中、参数校验失败、handler 抛错。
- `command`：内置命令执行。

查看方式：Xcode 控制台或 macOS Console 选择设备进程后，按 `subsystem:iOSExploreServer`
过滤；需要更细时再加 category。

## `info` 的 device 字段为什么没有具体机型

库内 `info` 只用 `ProcessInfo`/`Bundle`（不依赖 UIKit），返回 `system`/`app`/`bundle`。具体设备机型（如 "iPhone11"）需要 UIKit 的 `UIDevice` 或 `sysctl`，由 App 层注册额外 handler（如 SPMExample 的 `device`）注入。

> 注意 `UIDevice.current.model` 返回 "iPhone"（类型），`.name` 在 iOS 16+ 受隐私限制可能返回通用名——这是系统行为，非 bug。

## framework 工程编译失败（`SwiftVerifyEmittedModuleInterface`）

症状：`xcodebuild` 在 module-interface 验证阶段失败，提到 `nonisolated(nonsending)`。
原因：`BUILD_LIBRARY_FOR_DISTRIBUTION=YES` + Swift 6.2 工具链不兼容。
解决：framework target 设 `BUILD_LIBRARY_FOR_DISTRIBUTION=NO`（已设）。详见 `docs/runbooks/build-and-test.md`。

## 集成测试端口冲突 / flaky

症状：`IntegrationTests` 偶发 "no handler for ..." 或连接被拒。
原因：并行 bind 会争用端口；即使 suite 串行，`NWListener.cancel()` 也会异步释放 socket。
解决：保持 `@Suite(.serialized)`，并在复用端口前调用测试内部 `await server.stopAndWait()`，不要只依赖退避重试。

## 后台不工作

`NWListener` 在 App 进入后台后可能被系统挂起。MVP 约定：**App 保持前台**。测试时不要切到后台。

## 本地网络权限弹窗

走 Wi-Fi（同网段）访问会触发 `NSLocalNetworkUsageDescription` 权限弹窗（Info.plist 已预留文案）；经 USB/iproxy 通常**不触发**。若走 Wi-Fi 遇到拒绝，检查 Info.plist 该 key 是否存在。
