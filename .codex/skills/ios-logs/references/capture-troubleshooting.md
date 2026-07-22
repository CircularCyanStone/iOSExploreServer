# 捕获来源与平台排障

仅在需要启用或排查 `stdout`、`stderr`、`nslog`、`oslog` 时读取本文。日常命令链和业务日志优先使用正文中的 `explore` 与 `bridge`。

## 开启捕获

在宿主 Debug 集成中显式选择需要的来源：

```swift
#if DEBUG
server.registerDiagnosticsCommands(.init(
    captureStdout: true,
    captureStderr: true,
    captureNSLog: true,
    captureOSLog: true
))
#endif
```

四个开关默认关闭，因为标准流接管和系统日志轮询会改变进程行为或增加开销。只开启当前任务需要的来源，并在修改配置后重启 App。`captureExploreLogs` 与 `enableBridge` 默认开启。

## 来源差异

### stdout 与 stderr

- `stdout` 捕获 `print(...)` 和当前进程标准输出，写入后等级为 `info`。
- `stderr` 捕获当前进程标准错误，写入后等级为 `error`。
- 两者通过进程级 fd 接管实现；安装失败时返回 `unavailable` 和具体 `reason`。
- 捕获按行写入。没有换行的尾部文本可能要到 capture 停止时才 flush，不适合作为即时断言。

### NSLog

`NSLog` 在不同系统环境中可能进入 stderr，也可能进入 Apple Unified Logging。Diagnostics 同时提供 stderr 行识别和 `OSLogStore` 读取路径，只要其中一条路径安装成功，`nslog` 的状态就可能是 `enabled`。

不要根据日志格式假定它来自哪条底层路径，也不要假定同一条 NSLog 必然同时出现在 `nslog` 与 `oslog`。按返回 entry 的 `source` 判断即可。

### os_log 与 Swift Logger

`oslog` 通过当前进程范围的 `OSLogStore` 轮询读取，需要 iOS 15+ 或 macOS 12+。即使系统版本满足，沙箱或系统策略仍可能使它返回 `unavailable`。

Unified Logging 写入和轮询是异步的。`app_logs_read` 只请求后台刷新，不同步等待系统读取完成，以免阻塞命令。因此在 `capture.oslog.state == "enabled"` 且首次结果为空时：

1. 保留原始 mark cursor。
2. 短暂等待后用同一 `after` 重读。
3. 检查 `hasMore` 并继续分页。
4. 仍为空时记录“当前捕获范围未观察到”，不要把平台推断写成固定事实。

## 排障顺序

1. 读取 `capture.state` 和 `reason`。
2. 确认开关在动作发生前已经启用，并且 App 已重启。
3. 确认 source 过滤使用 `stdout`、`stderr`、`nslog` 或 `oslog`。
4. 确认 mark 在动作之前，read 传入同一 session 的 cursor。
5. 对 oslog 处理异步刷新和分页。
6. 来源仍不可用时，改用 `ExploreAppLog.emit(...)` 提供高信号 `bridge` 日志，或切换到系统级日志工具。

## 平台判断原则

不要维护“模拟器必定可用”“真机更完整”或按某次验收写死的矩阵。系统版本、权限、沙箱和日志量都会影响捕获；每次运行都以 `app_logs_mark/read` 返回的三态快照为事实来源。
