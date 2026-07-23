# iOSExploreDiagnostics 日志模块使用说明

这份文档写给接入 `iOSExploreDiagnostics` 的 App 开发者。它解释这个模块能读哪些日志、怎么打开、怎么用 HTTP 命令验证，以及哪些情况读不到。

## 这个模块解决什么问题

`iOSExploreDiagnostics` 是 Debug 环境里的 App 内日志查询模块。Mac 侧 Agent 发 HTTP 命令到 App 进程后，经常需要回答一个问题：

> 命令已经发出去了，App 里面到底发生了什么？

注册 Diagnostics 后，Agent 可以用：

- `app.logs.mark`：先记一个检查点。
- `app.logs.read`：再从这个检查点之后读取 App 进程内已经捕获到的日志。

这些日志只存在 App 当前进程的内存 store 里，用来辅助开发和调试。它不是线上日志 SDK，不负责上传日志，也不应该进 Release 上架产物。

## 最小接入方式

宿主 App 需要显式注册 Diagnostics 命令。最直接、最推荐的接入方式就是在代码里写清楚要打开哪些日志：

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

如果不想接管 stdout/stderr/NSLog/os_log，只想先看 iOSExplore 自己和宿主主动写入的日志，就把四个 capture 都写成 `false`：

```swift
#if DEBUG
server.registerDiagnosticsCommands(.init(
    captureStdout: false,
    captureStderr: false,
    captureNSLog: false,
    captureOSLog: false
))
#endif
```

四个 capture 都为 `false` 时，只启用两类低风险日志：

- `explore`：iOSExploreServer 自己的内部日志，例如命令注册、请求路由、命令开始和结束。
- `bridge`：宿主 App 主动调用 `ESAppLogger.emit(...)` 写入的业务日志。

需要排查 `print`、stderr、`NSLog`、`os_log` 或 Swift `Logger` 时，再按需打开对应开关。

## 每种日志来源是什么意思

`app.logs.read` 返回的每条日志都有 `source` 字段。这个字段表示“这条日志是从哪条路径进入 Diagnostics 的”。

| source | 开发者平时怎么产生 | 是否默认开启 | 打开方式 | 读到后的典型用途 |
| --- | --- | --- | --- | --- |
| `explore` | iOSExploreServer 内部自己写的日志 | 是 | `captureExploreLogs: true`，默认就是 true | 看 HTTP 请求有没有进来、命令有没有注册、执行是成功还是失败 |
| `bridge` | 宿主 App 调用 `ESAppLogger.emit(...)` | 是 | `enableBridge: true`，默认就是 true | App 自己在关键业务点主动打日志，最稳定、最推荐 |
| `stdout` | `print(...)`、`FileHandle.standardOutput.write(...)`、部分 C stdout 输出 | 否 | `captureStdout: true` | 看开发临时 `print` 是否真的执行 |
| `stderr` | `FileHandle.standardError.write(...)`、`fprintf(stderr, ...)`、`fputs(..., stderr)` | 否 | `captureStderr: true` | 看错误输出，返回 level 固定为 `error` |
| `nslog` | `NSLog(...)` | 否 | `captureNSLog: true` | 看老代码、Objective-C 代码或第三方调试代码里的 `NSLog` |
| `oslog` | `os_log(...)` 和 Swift `Logger` | 否 | `captureOSLog: true` | 看使用 Apple 系统日志 API 写出的日志 |

## stdout 和 stderr 到底是什么

`stdout` 和 `stderr` 可以理解为当前 App 进程里的两根“文字输出管道”。

- `stdout` 常用于普通输出。Swift 的 `print(...)` 大多会走这里。
- `stderr` 常用于错误输出。C 的 `fprintf(stderr, ...)` 会走这里。

Diagnostics 打开 `captureStdout` 或 `captureStderr` 后，会在 Debug 环境里临时接管这两根管道，把写进去的文本按行复制到 `ESAppLogStore`，然后 `app.logs.read` 就能读到。

实际效果：

- `stdout` 进入 store 后是 `source:"stdout"`，`level:"info"`。
- `stderr` 进入 store 后是 `source:"stderr"`，`level:"error"`。
- 文本按行记录；没有换行的尾部文本会在停止 capture 或测试 reset 时 flush。
- 默认会 tee 回原始标准流，也就是尽量保留原本控制台还能看到输出的行为。

限制：

- 只有打开开关后写入的内容才会进入 store。
- 只能捕获当前 App 进程的 stdout/stderr，不会捕获别的 App、系统进程或 Mac 侧命令行输出。
- 这是进程级接管，所以默认关闭，避免示例 App 或业务 App 在不知情时改变标准流行为。

## NSLog 到底是什么，本模块做了什么

`NSLog(...)` 是 Foundation 提供的老式日志 API。很多 Objective-C 代码、老项目或第三方库还会用它。

Diagnostics 打开 `captureNSLog` 后，会同时启用两条路径：

- 可控路径：如果 `NSLog` 最终写到了 stderr，`ESStdIOCapture` 会识别这种行，并写成 `source:"nslog"`。Swift `NSLog(...)` 在当前 macOS SPM 测试中走的是这条路径。
- 增强路径：通过 fishhook 重绑定当前进程里的 `NSLog`/`NSLogv`，先把格式化后的文本写入 `ESAppLogStore`，再调用原始 `NSLog`/`NSLogv` 保留系统控制台输出。这个做法与 DoKit 的 NSLog 查看插件一致，主要覆盖 Objective-C/C 调用点。

实际效果：

- Example App 里的 `debug.emitNSLog` 调用 `NSLog("%@", message)`。
- 开启 `captureNSLog` 后，Agent 可以用 `app.logs.read` 加 `sources:["nslog"]` 读到这条文本。
- 返回的 level 目前固定为 `info`，category 为 `nslog`。

限制：

- fishhook 是当前进程内的全局符号重绑定，只在 Debug Diagnostics 注册且 `captureNSLog: true` 时启用；Swift Foundation overlay 不保证经过可被 fishhook 改写的 C 符号。
- hook 安装成功后不反复卸载；Runtime 重置或关闭 capture 时只移除 active store，后续 `NSLog` 会继续走原始系统输出但不会写入 Diagnostics。
- 如果 stderr 行识别和 fishhook 都不可用，capture 状态会是 `unavailable`，不是“日志一定没发生”。

## os_log 和 Swift Logger 到底是什么，本模块做了什么

`os_log(...)` 和 Swift 的 `Logger` 都是 Apple 推荐的系统日志 API。它们不是简单写到 stdout/stderr，而是写进 Apple Unified Logging。

可以把 Apple Unified Logging 理解成系统给当前 App 维护的一套日志库。日志里通常会带：

- `subsystem`：哪个模块或 App 写的。
- `category`：这个模块里的分类。
- `level`：debug、info、error、fault 等等级。
- `message`：日志正文。

Diagnostics 打开 `captureOSLog` 后，会通过 Apple 提供的 `OSLogStore(scope: .currentProcessIdentifier)` 读取“当前 App 进程”里新增的 os_log / Swift Logger entry，然后写入 `ESAppLogStore`，让 Agent 可以用 HTTP 读到。

实际效果：

- Example App 里的 `debug.emitOSLog` 调用 `os_log(...)`。
- Example App 里的 `debug.emitLogger` 调用 Swift `Logger`。
- 开启 `captureOSLog` 后，这两类日志都会以 `source:"oslog"` 返回。
- `os_log` / `Logger` 的 subsystem 和 category 会进入 metadata，方便排查是哪块代码写的。

限制：

- 依赖系统是否允许当前进程读取 `OSLogStore`。当前实现要求 iOS 15 或 macOS 12 及以上。
- `OSLogStore` 不是同步 stdout 管道，日志进入系统 store 可能有短暂延迟；`app.logs.read` 会主动 flush 一次，但真实设备上仍建议用 mark + token + 分页读取。
- 只能读取当前 App 进程允许读到的记录，不保证读取系统全部日志，也不读取其他 App 的日志。
- 这不是线上日志收集，不做持久化和上传；App 重启后旧的内存 cursor 不能继续使用。

## 为什么仍然说“不是自动抓所有 App 日志”

这里的“所有 App 日志”容易误解。一个真实 App 里可能有很多日志路径：

- 有些写到 `print`。
- 有些写到 stderr。
- 有些写到 `NSLog`。
- 有些写到 `os_log` 或 Swift `Logger`。
- 有些第三方 SDK 自己写文件。
- 有些直接上传到自己的日志平台。
- 有些只是内存埋点，根本不落本地文本。

Diagnostics 当前覆盖的是前五类里可被当前进程读到的部分。它不会扫描你的业务对象，不会读取第三方 SDK 私有日志文件，不会从线上日志平台拉数据，也不会读取其他进程。

最稳定的方式仍然是：在关键业务点主动调用 `ESAppLogger.emit(...)`。这条路径由宿主 App 自己决定写什么，进入 `source:"bridge"`，不会依赖系统日志实现。

## 推荐的使用策略

开发阶段建议按这个顺序使用：

1. 先看 `explore`：确认 HTTP 请求有没有进 App，命令是否注册，命令是否执行失败。
2. 关键业务点加 `ESAppLogger.emit(...)`：让 Agent 能看到明确的业务状态。
3. 临时排查 `print` 时打开 `captureStdout`。
4. 临时排查错误输出时打开 `captureStderr`。
5. 项目里有老 Objective-C 或第三方 `NSLog` 时打开 `captureNSLog`。
6. 项目使用 `os_log` 或 Swift `Logger` 时打开 `captureOSLog`。

真实业务 App 不一定要全部打开。stdout/stderr 是进程级资源，系统日志读取也可能比较吵；你可以先只开 `explore` / `bridge`，需要排查某一类输出时再把对应 capture 改成 true。

## Example App 如何打开

`Examples/SPMExample` 现在直接在 `ViewController` 代码里配置 Diagnostics：

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

也就是说，直接运行 `SPMExample` Debug target 时：

- Server 会自动启动。
- stdout capture 会打开。
- stderr capture 会打开。
- NSLog capture 会打开。
- os_log / Swift Logger capture 会打开。

配置位置是：

```text
Examples/SPMExample/SPMExample/ViewController.swift
server.registerDiagnosticsCommands(.init(...))
```

Debug 验证命令：

| action | 做什么 | 需要哪个 capture |
| --- | --- | --- |
| `debug.emitStdout` | 向 stdout 写一行 message | `captureStdout` |
| `debug.emitStderr` | 向 stderr 写一行 message | `captureStderr` |
| `debug.emitNSLog` | 调用 `NSLog("%@", message)` | `captureNSLog` |
| `debug.emitOSLog` | 调用 `os_log(...)` | `captureOSLog` |
| `debug.emitLogger` | 调用 Swift `Logger` | `captureOSLog` |

## curl 验证流程

以下命令假设 Example App 已启动并监听 `38321`。模拟器可以直接 curl `localhost:38321`；真机需要先用 `iproxy` 转发。

1. 确认 server 可用：

```bash
curl -s -X POST http://localhost:38321/ \
  -d '{"action":"ping"}'
```

期望返回：

```json
{"code":"ok","data":{"pong":true}}
```

2. 建立日志检查点：

```bash
curl -s -X POST http://localhost:38321/ \
  -d '{"action":"app.logs.mark"}'
```

响应里保存 `data.cursor`。后续读取时把它放到 `after`，表示“只读检查点之后发生的日志”。

3. 触发 stdout：

```bash
curl -s -X POST http://localhost:38321/ \
  -d '{"action":"debug.emitStdout","data":{"message":"token-stdout-001"}}'
```

4. 读取 stdout：

```bash
curl -s -X POST http://localhost:38321/ \
  -d '{"action":"app.logs.read","data":{"after":{"captureSessionID":"替换为 mark 返回的 captureSessionID","id":替换为 mark 返回的 id},"sources":["stdout"],"limit":100}}'
```

期望在 `entries` 中看到：

```json
{
  "source": "stdout",
  "level": "info",
  "category": "stdio",
  "message": "token-stdout-001"
}
```

5. 触发 stderr：

```bash
curl -s -X POST http://localhost:38321/ \
  -d '{"action":"debug.emitStderr","data":{"message":"token-stderr-001"}}'
```

读取时把 `sources` 换成 `["stderr"]`。期望看到 `source:"stderr"`、`level:"error"`。

6. 触发 NSLog：

```bash
curl -s -X POST http://localhost:38321/ \
  -d '{"action":"debug.emitNSLog","data":{"message":"token-nslog-001"}}'
```

读取时把 `sources` 换成 `["nslog"]`。期望看到 `source:"nslog"`，message 里包含 `token-nslog-001`。

7. 触发 os_log 和 Swift Logger：

```bash
curl -s -X POST http://localhost:38321/ \
  -d '{"action":"debug.emitOSLog","data":{"message":"token-oslog-001"}}'

curl -s -X POST http://localhost:38321/ \
  -d '{"action":"debug.emitLogger","data":{"message":"token-logger-001"}}'
```

读取时使用 `sources:["oslog"]`。如果输出很多，可以加 `minimumLevel:"error"`：

```bash
curl -s -X POST http://localhost:38321/ \
  -d '{"action":"app.logs.read","data":{"after":{"captureSessionID":"替换为 mark 返回的 captureSessionID","id":替换为 mark 返回的 id},"sources":["oslog"],"minimumLevel":"error","limit":500}}'
```

期望看到两条 `source:"oslog"` 日志，message 分别包含 `token-oslog-001` 和 `token-logger-001`。

## app.logs.read 参数怎么用

`app.logs.read` 支持这些参数：

| 参数 | 含义 |
| --- | --- |
| `after` | 上一次 `app.logs.mark` 或 `app.logs.read` 返回的 cursor；用于增量读取 |
| `limit` | 最多返回多少条，范围 1...500，默认 100 |
| `sources` | 来源过滤，例如 `["stdout"]`、`["stderr"]`、`["nslog"]`、`["oslog"]` |
| `minimumLevel` | 最低等级过滤，例如 `error` 表示只看 error/fault 等级 |

返回里的关键字段：

| 字段 | 含义 |
| --- | --- |
| `entries` | 本次返回的日志列表 |
| `nextCursor` | 下一次读取应该传的 cursor |
| `capturedThrough` | 本次读取时 store 已经捕获到的最新位置 |
| `hasMore` | 是否还有更多日志可以继续分页读取 |
| `gap` | 如果 cursor 太旧、日志已被 ring buffer 覆盖，这里说明丢失范围 |
| `capture` | 每个来源当前是 enabled、notCaptured 还是 unavailable |

## capture 状态怎么看

`app.logs.mark` 和 `app.logs.read` 都会返回 `capture`。它用来区分三种情况：

| state | 意思 | 开发者该怎么判断 |
| --- | --- | --- |
| `enabled` | 这个来源已经安装并正在写入 store | 可以继续用对应 `sources` 读取 |
| `notCaptured` | 配置没打开，或 Release 下不可用 | 不是失败；需要打开对应配置再启动 App |
| `unavailable` | 配置打开了，但系统或安装步骤不允许 | 看 `reason`，例如 OS 版本不支持或 fd 接管失败 |

如果 `entries` 为空，先看 `capture`：

- `state:"notCaptured"`：说明你没打开开关。
- `state:"unavailable"`：说明开关打开了，但当前系统不允许或安装失败。
- `state:"enabled"`：说明来源可用，再检查是否用了 mark 之后的 token、是否 source 过滤写错、是否需要分页。

## Release 行为

Diagnostics 是 Debug-only 能力。非 Debug 构建里：

- `registerDiagnosticsCommands` 返回 disabled。
- stdout/stderr/NSLog/os_log/Logger capture 不会安装。
- 这些能力不会改变 Release 上架产物的运行行为。

## 常见问题

### 为什么 `print` 没读到？

检查三件事：

1. App 是否用 Debug 配置启动。
2. `registerDiagnosticsCommands(.init(...))` 里是否写了 `captureStdout: true`。
3. 是否在 `app.logs.mark` 之后才触发 `print`。

### 为什么 stderr 没读到？

确认打开的是 `captureStderr`，读取时 `sources` 写的是 `["stderr"]`。stderr 返回 level 是 `error`，如果你设置了更高的 `minimumLevel`，可能会被过滤掉。

### 为什么 NSLog 还会和 stderr 或系统日志有关？

Diagnostics 会安装 fishhook 增强 Objective-C/C `NSLog` 覆盖；但原始 `NSLog` 仍会被调用，系统之后可能继续把同一条文本写到 stderr 或 Apple Unified Logging。Swift Foundation overlay 不保证命中 fishhook，因此 stderr 行识别仍是本模块对 Swift `NSLog` 的可控路径。

### 为什么 os_log / Logger 不是立刻出现？

它们写进 Apple 系统日志，不是直接写入 stdout/stderr。系统日志落盘和查询会有短暂延迟。`app.logs.read` 会主动刷新一次，但真实设备上仍建议用唯一 token、`limit:500` 和分页读取。

### 为什么不要默认全开？

因为 stdout/stderr 是进程级输出管道，接管它们可能影响开发者原本观察控制台输出的方式。系统日志也可能很吵，默认全开会让 Agent 读到很多无关记录。这个模块的目标是 Debug 下按需诊断，不是一直运行的日志平台。
