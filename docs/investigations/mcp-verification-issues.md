# iOSExploreServer Mac MCP Server 验证问题 - 调查记录

> 调查时间：2026-04-28
> 调查方式：实机 iOS 真机验证 + 源码分析 + subagent 并行调查
> 状态：A/B/D/E 已确认不是代码 bug；C 已由 Codex 用回归测试确认是 C `stdout` 缓冲问题并完成代码修复，且已在 iOS 26.5 真机上完成网络场景闭环验证；F 仍按 iOS 真机 `OSLogStore` 可见性限制处理

---

## 0. 项目背景

### 0.1 项目结构

- **`/Users/coo/Desktop/iOS_agent_debugger/iOSExploreServer`**：iOSExploreServer 主体（SwiftPM 包），含 `Sources/iOSExploreDiagnostics/` 诊断日志捕获框架
- **`/Users/coo/Desktop/iOS_agent_debugger/iOSExploreServer/iOSDriver`**：在 Mac 上跑的 MCP bridge server，对 iOS 真机通过 iproxy（端口 38321）调用 iOSExploreServer 的 HTTP API
- **`/Users/coo/Desktop/iOS_agent_debugger/iOSExploreServer/Examples/SPMExample`**：测试用 iOS App（bundlid `com.coo.SPMExample`），含 `DiagnosticsTestViewController.swift` 5 个日志诊断场景按钮
- 当前真机设备：bundleId `com.coo.SPMExample`，iOS 26.5 (Build 23F77)

### 0.2 iOSExploreServer 日志捕获架构概述

iOSExploreServer 诊断 runtime (`ProcessDiagnosticsRuntime`) 把 5 个独立 capture 源写入一个共享的 `AppLogStore`（有界 ring buffer），通过 `app.logs.read` / `app.logs.mark` 命令暴露：

| source 名 | 捕获器 | 实现文件 | 捕获机制 |
|---|---|---|---|
| `stdout` | `StdIOStreamCapture(.stdout)` | `Sources/iOSExploreDiagnostics/StdIOCapture.swift` | `dup2(pipe[1], STDOUT_FILENO)` 重定向 fd 1 → pipe 读端由 `DispatchSourceRead` 读取 |
| `stderr` | `StdIOStreamCapture(.stderr)` | 同上 | `dup2(pipe[1], STDERR_FILENO)` 重定向 fd 2 |
| `nslog` | `StdIOStreamCapture.looksLikeNSLogLine` + `UnifiedLogCapture.looksLikeNSLogEntry` 两条路径 | `StdIOCapture.swift` + `UnifiedLogCapture.swift` | 路径 A：stderr fd 按行格式 `YYYY-MM-DD HH:MM:SS.mmm ` 匹配；路径 B：从 `OSLogStore` 按 subsystem/category 含 "nslog"/"foundation" 匹配 |
| `oslog` | `UnifiedLogPollingCapture` | `Sources/iOSExploreDiagnostics/UnifiedLogCapture.swift` | `OSLogStore(scope: .currentProcessIdentifier)` 每 250ms 轮询 `getEntries(at: position)` |
| `bridge` | `ExploreAppLog.emit` | `Sources/iOSExploreServer/ExploreAppLog.swift` | App 通过 `ExploreAppLog.emit` API 主动写入 store |
| `explore` | `ExploreLogging.emitExtension` | iOSExploreServer 自身内部日志 | iOSExploreServer 用 `ExploreLogging` 写自身运行日志 |

### 0.3 `app.logs.mark` 命令

- 文件：`Sources/iOSExploreDiagnostics/AppLogsCommands.swift`
- **输入 schema**：`EmptyCommandInput`（`typealias Input = EmptyCommandInput`）
  - `properties: {}`，`required: []`，`additionalProperties: false`
  - 服务端严格拒绝未知字段，错误信息：`unknown command input field '<name>'`
- **返回**：`{ cursor: { captureSessionID, id }, oldestAvailableID, latestAvailableID, capture }`
- `AppLogsMarkCommand.handle` 完全忽略 input，直接调 `store.mark()`
- `AppLogStore.mark()` 无参数，返回 `AppLogMarkSnapshot`

### 0.4 `app.logs.read` 命令

- 文件：`Sources/iOSExploreDiagnostics/AppLogsCommands.swift`
- **输入**：`{ after?: { captureSessionID, id }, sources?: [string], minimumLevel?: string, limit?: int (1..500) }`
- **返回字段（顶层）**：
  ```
  entries             // 日志条目数组，每条含 id/timestamp/source/level/category/message/messageTruncated/metadata
  nextCursor          // 下一页 cursor
  capturedThrough     // 本次扫描最新物理 id 快照
  hasMore             // 是否还有未扫描
  gap                 // 缺口说明（可选）
  oldestAvailableID   // store 仍保留的最旧物理 id
  capture             // 各 source 捕获状态 object
  ```
- **关键：返回数组字段名是 `entries`，不是 `logs`**——从第一版代码至今一直如此

---

## 1. 问题 A：`app.logs.mark` 不接受 `label` 参数

### 1.1 现象

用户给 MCP server 发 `app.logs.mark` 命令时传入 `{ label: "mcp-verify" }`，服务端拒绝：
```
ERROR: unknown command input field 'label'
```

### 1.2 调查结论

**真实存在的问题，但是是验证提示词写错了。**

源码确认（`AppLogsCommands.swift:4-31`）：

```swift
struct AppLogsMarkCommand: Command {
    typealias Input = EmptyCommandInput     // ← input schema 为空
    let action = "app.logs.mark"
    let description = "建立当前进程日志检查点"
    func handle(_ input: EmptyCommandInput) async throws -> ExploreResult {
        guard let store = runtime.currentStore() else { ... }
        return .success(Self.toJSON(store.mark(), capture: runtime.captureStatusJSON()))
        //                                  ↑ mark() 无参数
    }
}
```

`EmptyCommandInput` 的 input schema 是：
```json
{ "type": "object", "properties": {}, "required": [], "additionalProperties": false }
```

仓库内**完全没有 `label` 字段定义**——既不在 inputSchema，也不在 `AppLogsMarkSnapshot` 字段（只有 `cursor`/`oldestAvailableID`/`latestAvailableID`），更不在 `AppLogStore.mark()` 函数签名中。

`AppLogsMarkCommand.description` 只有 "建立当前进程日志检查点"，没有任何 `label` 参数说明。

### 1.3 修复方案

**不修改代码**。验证提示词（或文档）中关于 `app.logs.mark` 接受 `label` 参数的说法是错的，应该删除。

如果将来确实需要支持 `label`，需要：
1. 替换 `EmptyCommandInput` 为带 `label` 字段的自定义 `CommandInput` struct
2. 同步修改 `AppLogStore.mark()` 接受并存储 label
3. 修改 `AppLogMarkSnapshot` 增加 `label` 属性
4. `AppLogsMarkCommand.toJSON()` 输出 label

但目前没有必要。

**严重程度**：低（验证流程问题，非代码 bug）

---

## 2. 问题 B：`app.logs.read` 返回字段名是 `entries` 而不是 `logs`

### 2.1 现象

验证提示词写的是 `bridge.logs`，但实际响应顶层没有 `logs` 字段，日志条目数组在 `entries` 字段下。

### 2.2 调查结论

**真实存在的问题，但同样是验证提示词写错了。**

源码确认（`AppLogsCommands.swift:61-71`）：

```swift
private static func toJSON(_ result: AppLogReadResult, capture: JSON) -> JSON {
    [
        "entries": .array(result.entries.map { .object($0.toJSON()) }),
        "nextCursor": .object(result.nextCursor.toJSON()),
        "capturedThrough": .object(result.capturedThrough.toJSON()),
        "hasMore": .bool(result.hasMore),
        "gap": result.gap.map { .object($0.toJSON()) } ?? .null,
        "oldestAvailableID": result.oldestAvailableID.map { .double(Double($0)) } ?? .null,
        "capture": .object(capture),
    ]
}
```

`AppLogStore.swift` 中所有集合字段都命名为 `entries`：
- `AppLogReadResult.entries`（`AppLogModels.swift:110-125`）
- `store.read(after:limit:sources:minimumLevel:)` 返回 `AppLogReadResult(entries: ...)`（`AppLogStore.swift:105-168`）

全仓搜索 `*.md`、`*.swift`、`*.ts` 的历史提交记录——**从第一版至今没有任何版本用过 `logs` 作为顶层字段**。

`bridge` 不是顶层字段：
- `bridge` 是 `AppLogSource` 枚举里的一个 case（`AppLogModels.swift:10-11`），代表宿主 App 通过 `ExploreAppLog.emit` 主动写入的业务日志来源
- 响应里出现的 `bridge` 字面在两处：
  1. 单条 entry 的 `source` 字段值（`source="bridge"`）——表示来源类型
  2. `capture` object 的子键（如 `"bridge": { "state": "enabled" }`）——表示该来源的捕获状态

测试 `Tests/iOSExploreServerTests/DiagnosticsCommandTests.swift:443-466` 也用同一字段名：
```swift
guard case .success(let data) = result.result,
      let values = data["entries"]?.arrayValue else {
    throw TestFailure("missing entries")
}
```

### 2.3 修复方案

**不修改代码**。验证提示词中 `bridge.logs` 应改为 `entries`。

**严重程度**：低（验证流程问题，非代码 bug）

---

## 3. 问题 C：stdout 捕获状态显示 `enabled`，但场景按钮触发后 `print()` 输出读取不到

> **Codex 更新（2026-07-06）：根因已确认并修复。** 新增回归测试先把 C `stdout` 显式切到全缓冲，再调用 Swift `print()`，旧实现下 `app.logs.read(sources:["stdout"])` 读不到该行；修复后同一测试通过。随后在 iOS 26.5 真机 `com.coo.SPMExample` 上触发 `DiagnosticsTestViewController` 网络场景，stdout 读到 4 条 `[Network]` print 输出。

### 3.1 现象

1. `app.logs.mark` 返回的 `capture.stdout.state = "enabled"`，说明 `StdIOStreamCapture.install(.stdout)` 成功
2. 在 DiagnosticsTestViewController 上点击 5 个场景按钮（每个场景调用了 1-4 次 `print(...)`），等 2-4 秒
3. 调 `app.logs.read(sources: ["stdout"], limit: 200)` 返回 **0 条**
4. 调 `debug.emitStdout`（iOSExploreServer 提供的 debug 命令）；里面用 `FileHandle.standardOutput.write(data)`
5. 再次调 `app.logs.read(sources: ["stdout"], limit: 200)` 返回 **1 条**，内容是 `debug.emitStdout` 写的，捕获正确

**结论：StdIOCapture 的 fd 重定向机制本身工作正常，能捕获写入 fd 1 的内容。但 Swift `print()` 函数的输出即使过了 4 秒仍未被捕获。**

### 3.2 已确认的事实

#### 3.2.1 测试 App 的场景按钮调用情况（`Examples/SPMExample/SPMExample/DiagnosticsTestViewController.swift`）

| 场景 | 方法 | print() 调用 | fputs → stderr | NSLog | os_log(subsystem=com.coo.SPMExample) | ExploreAppLog.emit |
|---|---|---|---|---|---|---|
| 1 网络请求 | `simulateNetworkRequest` (line 221-251) | 4 次 (line 227-230) | 0 | 0 | 1 (line 245) | 3 |
| 2 认证流程 | `simulateAuthFlow` | 2 (line 261-262) | 3 (line 265-267) | 0 | 2 (line 280, 283) | 0 |
| 3 业务事件 | `simulateBusinessEvent` | 1 (line 312) | 1 (line 311) | 0 | 1 (line 317) | 0 |
| 4 系统级 | `simulateSystemAlert` | 0 | 2 (line 345-346) | 2 (line 332-333) | 2 (line 337, 340) | 2 (line 350) + Logger × 1 (line 359) |
| 5 全链路追踪 | `simulateFullTrace` (line 370-412) | 4 (line 377, 382, 388, 391, 406) | 2 (line 390, 396) | 1 (line 383) | 1 (line 399) | 6 (line 375, 380, 386, 394, 397, 404) + Logger × 1 (line 407) |

实机实测（场景 1 单独触发后 mark→4秒后 read，mark cursor 之间）：

```
Total entries between mark1 and mark2: 66
By source: explore=61, oslog=2 (com.apple.xpc), bridge=3 (network.api), stdout=0, stderr=0, nslog=0
```

- `bridge` source 读到了场景 1 的 `ExploreAppLog.emit` 4 条（包括 `--- SCENARIO BOUNDARY ---`）
- `stdout` source **0 条**——场景 1 调用了 4 次 `print("[Network] ...")`，全部丢失
- `stderr` source 0 条（符合预期，场景 1 没用 stderr）
- `oslog` source 2 条都是 `com.apple.xpc`（系统自己的，与本场景无关）；**`com.coo.SPMExample` subsystem 的 os_log 调用也丢了**（这同时印证了问题 F）

#### 3.2.2 StdIOCapture 当前实现机制（`Sources/iOSExploreDiagnostics/StdIOCapture.swift`）

```swift
static func install(...) -> ... {
    fflush(nil)                              // 刷新安装前已有的 C 流缓冲区

    let originalFD = dup(stream.descriptor)  // 备份原始 fd（stdout 是 fd 1）
    pipe(&pipeFDs)                           // 创建管道
    dup2(pipeFDs[1], stream.descriptor)      // 把 fd 1 重定向到 pipe 写端
    setvbuf(stream.filePointer, nil, stream.captureBufferMode, 0)
                                             // 修复点：同步调整 C FILE* 缓冲模式
    close(pipeFDs[1])

    // pipe 读端设为非阻塞 O_NONBLOCK
    fcntl(pipeFDs[0], F_SETFL, flags | O_NONBLOCK)

    let reader = StdIOReadBuffer(...)
    let source = DispatchSource.makeReadSource(fileDescriptor: pipeFDs[0], queue: queue)
    source.setEventHandler { reader.drainAvailableBytes() }
    source.resume()
}
```

```swift
// StdIOReadBuffer.appendLine — line 331-349
private func appendLine(_ bytes: [UInt8]) {
    let line = String(decoding: lineBytes, as: UTF8.self)
    if stream == .stderr, captureNSLog, Self.looksLikeNSLogLine(line) {
        store.append(source: .nslog, ...)
        return
    }
    guard capturePlainStream else { return }
    store.append(source: stream.source, level: stream.level, category: "stdio", message: line)
}
```

- `StdIOStream.stdout.level` 固定 `.info`
- `capturePlainStream` 在 stdout 路径上一定为 true（`captureStdout` 隐含）
- `StdIOStream.captureBufferMode` 对 stdout 使用 `_IOLBF`，对 stderr 使用 `_IONBF`

#### 3.2.3 macOS 上验证——Swift print 走的是 C `fwrite(stdout)`

在 macOS 上跑：
```bash
swift -e '
print("[Test] this is a print call")
fputs("[Test] this is a fputs call\n", stdout)
FileHandle.standardOutput.write(Data("[Test] this is a FileHandle write\n".utf8))
"[Test] this is a write syscall\n".withCString { write(STDOUT_FILENO, $0, strlen($0)) }
'
```

输出（4 行全部出现，证明 macOS 上 print/fputs/FileHandle.write/write syscall 都到达 stdout fd）：
```
[Test] this is a FileHandle write
[Test] this is a write syscall
[Test] this is a print call
[Test] this is a fputs call
```

#### 3.2.4 Swift 标准库源码：print 的底层路径（GitHub `apple/swift` `stdlib/public/core/OutputStream.swift`）

```swift
internal struct _Stdout: TextOutputStream {
    internal mutating func _lock() { _swift_stdlib_flockfile_stdout() }
    internal mutating func _unlock() { _swift_stdlib_funlockfile_stdout() }
    internal mutating func write(_ string: String) {
        string.withUTF8 { utf8 in
            _ = unsafe _swift_stdlib_fwrite_stdout(utf8.baseAddress!, 1, utf8.count)
        }
    }
}
```

`_swift_stdlib_fwrite_stdout` 在 Darwin/iOS 上桥接到 libSystem 的 `fwrite(ptr, 1, count, stdout)` —— 即写 **C `FILE* stdout`**，**不是直接 `write(STDOUT_FILENO, ...)` 系统调用**。

调用链：
```
print(_:to:)
  → _print_unlocked(value, &target)
  → target.write(string)
  → _Stdout.write(string)
  → _swift_stdlib_fwrite_stdout(ptr, 1, count)
  → fwrite(ptr, 1, count, stdout)    // Darwin libSystem
```

**`_Stdout.write` 中没有调用 `fflush(stdout)`**。

### 3.3 关键根因（代码级已确认）

**根因：C FILE* stdout 的缓冲模式导致 print 输出未到达 fd 1**

C 标准库的 `FILE* stdout` 缓冲模式：
- 连接到交互式终端（TTY）：**line-buffered**（遇到 `\n` flush）
- 连接到 pipe 或文件：**fully-buffered**（块缓冲，4KB-8KB；只在 buffer满/调用 `fflush`/进程正常退出时 flush）

iOS App 在真机上的 stdout（启动时）**很可能就被系统初始化为 fully-buffered 模式**（因为不是 TTY）。

`StdIOStreamCapture.install` 在 line 158 `fflush(nil)` 只刷新**触发 install 时**已经缓冲的数据，**不改变 stdout 的缓冲模式**。之后 `dup2(pipe[1], STDOUT_FILENO)` 重定向了 fd 1，但 C `FILE* stdout` 内部仍然使用同一个 fd 号（值是 1），写入会经过 `fwrite → FILE* stdout → fd 1 → pipe[1]` 这条路径——**但只在 `FILE* stdout` 的用户空间缓冲满或被显式 flush 时才会刷入**。

`debug.emitStdout` 用的 `FileHandle.standardOutput.write(Data)` **直接调 `write(fd, data)` 系统调用**，**绕过 C `FILE*` 缓冲层**，所以数据立即进入 fd 1 → pipe，被捕获。

Swift `print()` 用 `fwrite(..., stdout)` → 进入 C `FILE* stdout` 用户空间缓冲；如果 stdout 是 fully-buffered，print 的 `\n` 不能触发 flush；buffer 一直不满；因此数据**一直停在用户空间缓冲里，永远不到 fd 1**，自然被 pipe 读不到。

**判别性证据**：
- `debug.emitStdout`（直接 write 系统调用）→ 能被捕获 ✓
- `print()`（fwrite → FILE* stdout，依赖 flush）→ 未能被捕获 ✗
- 场景 2/3/4/5 中的 `fputs(..., stderr)` → 能被捕获 ✓ —— 这是因为 **`FILE* stderr` 默认无缓冲**（C 标准），所以 `fputs` 直接经过 fd 2 → pipe

Codex 已用 `DiagnosticsCommandTests.stdoutCaptureRecordsSwiftPrintOutput` 稳定复现：测试先调用 `setvbuf(stdout, nil, _IOFBF, 0)` 模拟真机上 stdout 全缓冲，再注册 stdout capture 并执行 `print(token)`；旧实现等待读取后仍没有 stdout entry，说明日志停在 C `FILE* stdout` 缓冲层，没有进入 fd 1 的 pipe。

**已执行的代码级验证**：

1. 新增测试后先跑 `swift test --filter DiagnosticsCommandTests/stdoutCaptureRecordsSwiftPrintOutput`，旧实现失败，失败点为 stdout entries 中找不到 `print(token)`。
2. 在 `StdIOStreamCapture.install` 的 `dup2` 成功后设置 C 标准流缓冲模式，再跑同一命令通过。
3. 再跑 `swift test --filter DiagnosticsCommandTests`，18 条 Diagnostics 命令测试全部通过。
4. 真机闭环验证通过：iOS 26.5 真机上 `ui.tap` 触发 `diagnostics.networkRequest` 后，`app.logs.read(sources:["stdout"])` 返回 4 条 `[Network]` print 输出。

**假设 2（subagent 早先猜测，证据更弱）：iOS 真机上 Swift runtime 把 print 重定向到 os_log 而非 fwrite**

subagent 报告声称在 iOS 真机上 Swift `_swift_stdlib_fwrite_stdout` 内部不走 `fwrite`，而是走 `os_log`。但 GitHub `apple/swift` 源码显示 `_Stdout.write` 调用的是 `_swift_stdlib_fwrite_stdout`，Darwin 桥接到 libSystem 的 `fwrite`。这看起来不成立，**除非 iOS 真机上的 libSystem 对 `fwrite(stdout, ...)` 有特殊处理**。需要确认或证伪。

如果假设 2 成立，**`print()` 在真机上根本不写 fd 1**，任何 stdout fd 级别的捕获都无效，需要通过 `OSLogStore(scope: .currentProcessIdentifier)` 间接读（也就是问题 F 描述的路径）。

### 3.4 修复方案（已实现）

当前采用原方案 A 的最小改动：在 `StdIOStreamCapture.install` 中、`dup2(pipeFDs[1], stream.descriptor)` 成功后，调用 `setvbuf(stream.filePointer, nil, stream.captureBufferMode, 0)`：

```swift
if setvbuf(stream.filePointer, nil, stream.captureBufferMode, 0) != 0 {
    ExploreLogging.emitExtension(level: .error,
                                 category: "diagnostics.stdio",
                                 message: "\(stream.name) capture setvbuf failed errno=\(errno)")
}
```

具体行为：
- stdout 安装 capture 后切到 `_IOLBF` 行缓冲，使 `print(...)\n` 及时进入 fd 1 的 pipe。
- stderr 安装 capture 后使用 `_IONBF` 无缓冲，保留错误流“立即输出”的语义。
- `setvbuf` 失败不会让注册失败，但会写 `diagnostics.stdio` error 日志，便于现场排查。

### 3.5 真机闭环验证记录

验证环境：
- 设备：`李奇奇的iPhone`，iOS 26.5，bundleId `com.coo.SPMExample`
- App：`Examples/SPMExample` Debug 构建，`registerDiagnosticsCommands(Self.exampleDiagnosticsConfiguration())` 已开启 stdout/stderr/NSLog/os_log capture
- 转发：`iproxy 38321 38321 -u 00008030-001045C136D1402E`

验证步骤：
1. `build_run_device` 安装并启动 App，`curl -X POST http://127.0.0.1:38321/ -d '{"action":"ping"}'` 返回 `{"pong":true}`。
2. `ui.viewTargets` 定位主页菜单第三行 `root/5/0/1`，`ui.tap` 进入日志诊断页。
3. `app.logs.mark` 得到 cursor `{"captureSessionID":"FB4459FC-A024-4ACE-829C-221D872048C9","id":463}`。
4. `ui.tap` 点击 `diagnostics.networkRequest`，path 为 `root/0/0/0/1/0`。
5. 2 秒后执行 `app.logs.read`：
   - `sources:["stdout"]` 返回 4 条 stdout：
     - `[Network] [...] → GET /api/v2/users/profile`
     - `[Network] [...] headers: Authorization=Bearer ***, Accept=application/json`
     - `[Network] [...] ← 200 OK`
     - `[Network] [...] body: {"id": 1024, "name": "Alice", "role": "admin"}`
   - `sources:["bridge"]` 返回 4 条 bridge：3 条 `network.api` + 1 条 `diagnostics.scenario` 分隔线。

这个验证说明：`print()` 的 stdout 捕获在真机 App 场景里已经可用。它不证明问题 F 的 oslog 可见性已经解决。

**严重程度**：高。`print()` 是 Swift 最常用的输出方式，如果它无法被捕获，整个 stdout capture 在真机上的实用价值严重下降。

---

## 4. 问题 D：stderr 日志在 `app.logs.read` 中 level 全部为 `error`

### 4.1 现象

stderr 输出包含多种业务级别（INFO、WARNING、ERROR、FATAL），但 `app.logs.read(sources: ["stderr"])` 返回的所有 entry `level` 都是 `"error"`。

实机实测场景 5 stderr：
```
[Trace] [711592] WARNING: config fetch took 3.2s (threshold=2s)        level=error
[Trace] [711592] ERROR: feature flag 'beta_experiment' has invalid value level=error
```

### 4.2 调查结论

**设计意图，不是 bug。**

源码确认 (`StdIOCapture.swift:113-118`)：
```swift
var level: AppLogLevel {
    switch self {
    case .stdout: return .info
    case .stderr: return .error
    }
}
```

`StdIOReadBuffer.appendLine` (line 344-348)：
```swift
guard capturePlainStream else { return }
store.append(source: stream.source,
             level: stream.level,        // ← stderr 固定 .error
             category: "stdio",
             message: line)
```

`AppLogStore.append` 接受 level 参数直接存储，没有任何内容推断。

四处独立确认是设计意图：
1. `AppLogModels.swift:24-25` 注释：`"当前 stdout 固定为 .info，stderr 固定为 .error"`
2. `DiagnosticsConfiguration.swift:14` 注释：`"成功后每行以 source=stderr、level=error 写入 store"`
3. `docs/runbooks/build-and-test.md:92`：`"stderr 结果应为 source:\"stderr\"、level:\"error\""`
4. 设计规格 `docs/superpowers/specs/iOSExploreServer-进程日志能力-修订版设计与评估.md:667`：`"stdout 固定 level=info，stderr 固定 level=error；nslog 等后续纯文本来源在无法可靠推断时才使用 unknown"`

测试 `DiagnosticsCommandTests.swift:195-217` 中 `stderrCaptureWritesLineIntoDiagnosticsStore` 故意写入不含 `[ERROR]` 前缀的纯文本，断言 `level=="error"`，验证"来源决定 level，而非内容"。

### 4.3 改进空间（可选）

如果要让 stderr 按 `[INFO]`/`[WARNING]`/`[ERROR]`/`[FATAL]` 前缀推断 level，可以在 `StdIOReadBuffer.appendLine` 中加入前缀匹配逻辑，fallback 用 `stream.level`（保持向后兼容）。但这引入维护成本，且 Agent 端可以自行按 message 内容过滤。

注意：`AppLogLevel` 没有 `.warning` 等级（只有 debug/info/error/fault/unknown），需要决策 `[WARNING]` 映射到哪个 level。

### 4.4 修复方案

**不修复**。设计意图明确，文档一致。如有改进意愿再另行讨论。

**严重程度**：低（设计选择，可接受）

---

## 5. 问题 E：nslog 来源只包含场景 4 和 5 的 NSLog 输出

### 5.1 现象

5 个场景里 nslog 来源只读到了场景 4（系统级）和场景 5（全链路追踪）的内容。场景 1/2/3 的 nslog 输出为 0 条。

### 5.2 调查结论

**完全是预期行为，不是 bug。**

nslog 捕获有两条独立路径：

**路径 A（`StdIOCapture` 通过 stderr 间接捕获）**：
- `StdIOStreamCapture.install(.stderr, captureNSLog: true)`
- NSLog 在 iOS 底层会向 stderr 写一行 Foundation 时间戳格式 `YYYY-MM-DD HH:MM:SS.mmm <app>[<pid>:<tid>] <message>` 的文本
- `StdIOReadBuffer.appendLine` 在 captureNSLog=true 且 stderr 流上调用 `looksLikeNSLogLine(line)` (line 351-361)：
  ```swift
  guard line.count >= 24 else { return false }
  let prefix = Array(line.prefix(24))
  return prefix[4] == "-" && prefix[7] == "-" && prefix[10] == " " && prefix[13] == ":"
      && prefix[16] == ":" && prefix[19] == "." && prefix[23] == " "
  ```
- 匹配则写入 `source: .nslog`，不匹配（且非 NSLog）走 `source: .stderr`

**路径 B（`UnifiedLogCapture` 通过 OSLogStore 直接读取）**：
- NSLog 在 iOS 底层也会向 unified logging 提交 entry，subsystem 是 `Foundation`，category 是 `nslog`
- `UnifiedLogPollingCapture.append` 中 `looksLikeNSLogEntry` (line 231-237)：
  ```swift
  let subsystem = entry.subsystem.lowercased()
  let category = entry.category.lowercased()
  return subsystem.contains("foundation") && category.contains("nslog")
      || subsystem.contains("nslog")
      || category.contains("nslog")
  ```

各场景 NSLog 调用情况：

| 场景 | NSLog 调用情况 | 进入 nslog | 原因 |
|---|---|---|---|
| 1 网络请求 | 0 | ✗ | 不用 NSLog |
| 2 认证流程 | 0 | ✗ | 不用 NSLog（用 print + fputs + os_log） |
| 3 业务事件 | 0 | ✗ | 不用 NSLog（用 print + fputs + ExploreAppLog） |
| 4 系统级 | 2 (line 332-333) | ✓ | NSLog |
| 5 全链路追踪 | 1 (line 383) | ✓ | NSLog |

实机实测场景 5 触发后 nslog：
```
2026-07-06 15:11:32.647 SPMExample[8985:2967218] [System] [WARNING] Memory pressure: Footprint=145MB (warning at 140MB)
2026-07-06 15:11:32.647 SPMExample[8985:2967218] [System] [ERROR] ImageCache: Failed to evict expired entries count=12 e...
2026-07-06 15:11:32.820 SPMExample[8985:2967218] [Trace] [D4B299] Config loaded: theme=dark, fontSize=16, language=zh-Ha...
```

完全匹配场景 4 + 场景 5 的 NSLog 调用。

### 5.3 修复方案

**不修复**。预期行为。

**严重程度**：无（这是设计）

---

## 6. 问题 F：oslog 来源显示的是 XPC 连接日志，而不是场景按钮触发的 os_log / Logger 输出

### 6.1 现象

1. 点击 5 个场景按钮（每个场景有 1-2 次 `os_log` 调用，subsystem=`com.coo.SPMExample`），过 4 秒后读 `oslog` source
2. oslog 条目几乎全是 `com.apple.network`、`com.apple.xpc`、`iOSExploreServer` subsystem 的条目
3. **没有** `com.coo.SPMExample` subsystem 的条目（场景按钮的 os_log 调用丢失）
4. 调 `debug.emitLogger`（MCP 命令，内部用 `Logger(subsystem: "com.coo.SPMExample", category: "diagnostics")`），等几秒，再读 oslog
5. **只勉强读到 1 条**（在 200 条 oslog 实测中，`com.coo.SPMExample` 仅 1 条，是 `MCP 验证 os_log Logger 测试`，来自 `debug.emitLogger`）

### 6.2 调查结论

这是 `OSLogStore(scope: .currentProcessIdentifier)` 在 iOS 真机上的系统级限制 + 时间窗口/限流问题。

#### 6.2.1 `UnifiedLogPollingCapture` 实现细节（`UnifiedLogCapture.swift`）

```swift
self.osStore = try OSLogStore(scope: .currentProcessIdentifier)  // line 110
// 每 250ms 一次 drain
timer.schedule(deadline: .now() + .milliseconds(250), repeating: .milliseconds(250))  // line 131
```

`drain()` (line 159-200)：
```swift
let startDate = state.scanStartDate
let startPosition = osStore.position(date: startDate)
let entries = try osStore.getEntries(at: startPosition)   // 不带 NSPredicate 过滤
var latestDate: Date?
for entry in entries {
    latestDate = entry.date
    guard let logEntry = entry as? OSLogEntryLog else { continue }
    let key = Self.entryKey(logEntry)
    // 用 seenKeys 去重
    let shouldAppend = state.withLock { ... }
    if shouldAppend { append(logEntry) }
}
if let latestDate {
    let nextStart = latestDate.addingTimeInterval(-Self.rescanOverlap)  // -30秒 overlap
    state.withLock { ... }
}
```

`append` (line 202-225)：按 `looksLikeNSLogEntry` 区分 nslog/oslog，分别写入不同 source。

#### 6.2.2 实测数据

```
total oslog entries: 200

All subsystems:
  com.apple.network:  140 entries
  iOSExploreServer:     35 entries
  com.apple.xpc:        24 entries
  com.coo.SPMExample:    1 entries   ← 应用自己写的只有 1 条
```

这一条 `com.coo.SPMExample` 是 `cat=diagnostics msg="MCP 验证 os_log Logger 测试"` — 来自 `debug.emitLogger` MCP 命令。**场景按钮里的 `os_log` 和 `Logger` 调用（至少 7 次）全部 0 条到达 OSLogStore 可查询范围**。

#### 6.2.3 根因分析

`OSLogStore(scope: .currentProcessIdentifier)` 在 iOS 真机上的实际行为：

- **在 macOS 上**（如 SPM 测试）：`getEntries` 几乎返回当前进程所有 `os_log` 输出，包括自定义 subsystem。`Tests/iOSExploreServerTests/DiagnosticsCommandTests.swift` 中 `osLogCaptureWritesEntriesIntoDiagnosticsStore` 用 80 次重试，每次间隔 50ms 一共等 4 秒能稳定读到刚写入的 os_log。
- **在 iOS 真机上**：实测显示 `OSLogStore(scope: .currentProcessIdentifier)` 只暴露**系统框架为本进程产生的日志**（`com.apple.network`、`com.apple.xpc`、`iOSExploreServer` 等），但**对应用层自定义 subsystem 的 `os_log`/`Logger` 输出过滤/延迟到几乎不可见**。
- 200 条 oslog 里只有 1 条是 `com.coo.SPMExample`，且这条来自 MCP 命令而非场景按钮。

注意：`iOSExploreServer` subsystem 的条目之所以能稳定出现，是因为它是 iOSExploreServer 自己用 `ExploreLogging.emitExtension` 写的（框架代码内部），libSystem 似乎对框架层 os_log 有不同的暴露策略。

#### 6.2.4 时间/读取延迟不是根因

- 250ms 轮询 + `requestFlush` 立即额外触发一次
- 等待 4 秒后读，应用 os_log 仍然 0 条
- `rescanOverlap = 30 秒`，扫描 overlap 窗口足够长

不是时序问题，是 iOS 沙箱/系统限制问题。

### 6.3 修复方案

**短期**：在文档中明确说明 iOS 真机上 oslog 来源的可见性限制。

iOSExploreServer README 第 136-139 行已经有警告：
> "只能读取当前 App 进程允许读到的记录，不保证读取系统全部日志"

这点需要更清楚地补充：实际真机上应用层自定义 subsystem 的 os_log 输出**几乎到不了 OSLogStore 进程内查询的可见范围**。

**长期**（高风险，不推荐）：
- 用 `OSLogStore(scope: .system)` 配合 `NSPredicate(format: "processIdentifier == %d", getpid())`——可能因权限不足失败
- 不引入 `log stream --predicate` 这种需要额外进程的方式

**严重程度**：中-高。`os_log`/`Logger` 是 iOS 应用层主流的日志输出方式，真机上不可见严重削弱 oslog 捕获的实用价值。

---

## 7. 总览表

| 问题 | 现象 | 根因 | 严重程度 | 是否修代码 | 推荐动作 |
|---|---|---|---|---|---|
| A | `app.logs.mark` 拒绝 `label` 参数 | 代码本来就不接受 `label`（EmptyCommandInput） | 低 | 否 | 修验证提示词 |
| B | `app.logs.read` 没有 `logs` 字段 | 顶层字段一直是 `entries` | 低 | 否 | 修验证提示词 |
| C | `print()` 输出未被 stdout 捕获 | C `FILE* stdout` 全缓冲导致 Swift `print()` 停在用户态缓冲，未进入 fd 1 pipe | **高** | 是，已修 | stdout capture 安装后把 `stdout` 设为行缓冲；已补回归测试并完成真机网络场景闭环 |
| D | stderr level 全是 `error` | 设计意图（`StdIOStream.stderr.level` 固定 `.error`） | 低 | 否 | 保持设计 |
| E | nslog 只含场景 4/5 | 场景 1/2/3 不调 NSLog，符合设计 | 无 | 否 | — |
| F | oslog 几乎不含应用 Logger 输出 | iOS 真机 OSLogStore(scope: .currentProcessIdentifier) 不暴露应用自定义 subsystem 的 os_log | 中-高 | 否（除非有更好方案） | 文档说明真机限制 |

---

## 8. Codex 后续验证建议

### 8.1 问题 C 真机回归（最高优先）

代码级回归和一次 iOS 26.5 真机闭环已通过。后续如果有人再次声称 `print()` 捕获失败，不要先改代码，先确认验证用的是包含 `setvbuf` 修复后的 App，并直接重跑场景 1：
```bash
# 在 Mac 端通过 MCP bridge 调
app.logs.mark
ui.tap path=root/0/0/0/1/0  # 触发场景 1
sleep 2
app.logs.read sources=["stdout"] limit=200
```

预期：stdout 应显示场景 1 的 4 条 `[Network]` print 内容；`bridge` 仍显示 3 条业务日志和场景边界；`oslog` 是否能读到 `com.coo.SPMExample` 仍受问题 F 的真机限制影响，不能用它判断 C 是否修好。

### 8.2 问题 F 验证

在真机上跑一段代码主动写很多 `os_log`（连续 50 次 `os_log(.info, ...)`，subsystem 是 `com.coo.SPMExample`），等几秒后用 `OSLogStore(scope: .currentProcessIdentifier).getEntries` 看到底能读到多少条。如果只读到 0-1 条，确认 iOS 真机对自定义 subsystem 的 os_log 不暴露给进程内 OSLogStore。

```swift
// 测试代码（在某个按钮里）
for i in 0..<50 {
    os_log("[TestLoop] %{public}d", log: OSLog(subsystem: "com.coo.SPMExample", category: "loop"), type: .info, i)
}
print("Wrote 50 os_log entries")
```

然后看 `app.logs.read(sources: ["oslog"])` 是否能发现 `[TestLoop]` 的内容。

### 8.3 现成 MCP 命令清单

通过 `iOSDriver/dist/src/index.js` (重新 build 后) 调用：

| 命令 | 说明 |
|---|---|
| `info` | 服务器信息 |
| `app.logs.mark` (无参数) | 当前 cursor + capture 状态 |
| `app.logs.read` `{ after?, sources?, minimumLevel?, limit? }` | 读取日志条目 (`entries` 字段是数组) |
| `ui.viewTargets` | 收集当前 VC 的所有可点 target |
| `ui.tap` `{ path, viewSnapshotID }` | 点按某 target |
| `debug.emitStdout` `{ message }` | 写一行到 stdout（用 FileHandle.write） |
| `debug.emitLogger` `{ message, token? }` | 用 Logger(subsystem: com.coo.SPMExample) 写一条 |
| `debug.emitNSLog` | 用 NSLog 写一条 |

---

## 9. 关键文件清单

| 文件 | 作用 |
|---|---|
| `Sources/iOSExploreDiagnostics/StdIOCapture.swift` | stdout/stderr fd 重定向捕获器（问题 C、D、E 路径 A） |
| `Sources/iOSExploreDiagnostics/UnifiedLogCapture.swift` | OSLogStore 轮询捕获器（问题 E 路径 B、F） |
| `Sources/iOSExploreDiagnostics/ProcessDiagnosticsRuntime.swift` | 注册并组合各 capture、`flushPendingCaptures` |
| `Sources/iOSExploreDiagnostics/AppLogStore.swift` | 统一 ring buffer store，`append/mark/read` |
| `Sources/iOSExploreDiagnostics/AppLogModels.swift` | `AppLogSource`、`AppLogLevel`、`AppLogReadResult` 等模型 |
| `Sources/iOSExploreDiagnostics/AppLogsCommands.swift` | `app.logs.mark` / `app.logs.read` 命令实现 |
| `Sources/iOSExploreDiagnostics/DiagnosticsConfiguration.swift` | `captureStdout`/`captureStderr`/`captureNSLog`/`captureOSLog` 配置 |
| `Examples/SPMExample/SPMExample/DiagnosticsTestViewController.swift` | 5 个场景按钮的 print/fputs/NSLog/os_log/Logger/ExploreAppLog 调用 |
| `Tests/iOSExploreServerTests/DiagnosticsCommandTests.swift` | 测试各 source 捕获正确性 |
| `docs/superpowers/specs/iOSExploreServer-进程日志能力-修订版设计与评估.md` | 设计规格，对所有 source 的设计意图有详细说明 |
| `iOSDriver/src/schemaMapper.ts` | MCP bridge 把 iOSExplore x- 扩展转为 description suffix |

---

## 10. 下次复查时的反驳口径和脚本修正

这一节用于避免 A-F 被下一轮验证重复当成“新 bug”。

### 10.1 A：`app.logs.mark` 不接受 `label`

反驳口径：这不是服务端 bug，当前协议就是无参 mark。`app.logs.mark` 的输入类型是 `EmptyCommandInput`，schema 明确 `additionalProperties:false`，所以传 `label` 会被正确拒绝为 `unknown command input field 'label'`。

应该改的地方：验证脚本、MCP prompt 或人工步骤里删除 `label` 参数，固定发送：

```json
{"action":"app.logs.mark"}
```

如果将来产品上真的需要 label，那是新需求，不是修 bug；需要新增 input model、store 字段和响应字段。

### 10.2 B：`app.logs.read` 返回 `entries`，不是 `logs`

反驳口径：这不是字段丢失，日志数组字段名一直是 `entries`。`bridge` 只是单条日志的 `source` 值，不是响应里的顶层对象。

应该改的地方：验证脚本里所有 `.data.logs`、`.bridge.logs`、`logs.length` 都应改为 `.data.entries`。例如：

```bash
jq '.data.entries | length'
jq -r '.data.entries[] | "\(.source) \(.category) \(.message)"'
```

### 10.3 C：stdout enabled 但 `print()` 读不到

反驳口径：旧问题是真实 bug，根因是 Swift `print()` 走 C `FILE* stdout`，真机上 stdout 可能是全缓冲，日志停在用户态缓冲，没有进入 fd 1 pipe。当前已在 `StdIOCapture` 安装时把 stdout 切为行缓冲，并已通过单元回归和 iOS 26.5 真机网络场景验证。

应该改的地方：如果后续验证仍说 stdout 为空，先检查三件事：
1. App binary 是否包含 `StdIOStreamCapture.install` 里的 `setvbuf(stream.filePointer, nil, stream.captureBufferMode, 0)`。
2. `app.logs.mark` 返回的 `capture.stdout.state` 是否为 `enabled`。
3. 是否真的触发了 `diagnostics.networkRequest`，并且读取时使用 mark 之后的 cursor 与 `sources:["stdout"]`。

不要再要求场景代码临时加 `fflush(stdout)`；那只是旧根因实验，不是最终方案。

### 10.4 D：stderr level 全是 `error`

反驳口径：这是设计选择，不是解析失败。stderr 来源按流本身定级为 `error`，不会根据文本里的 `INFO`、`WARNING`、`FATAL` 做二次语义推断。

应该改的地方：验证脚本不要断言 stderr message 前缀和 `level` 一一对应。正确断言是 `source:"stderr"`、`category:"stdio"`、`level:"error"`。

如果将来要根据文本前缀推断等级，那是新功能，并且要先定义 `WARNING` 映射到 `info/error/fault/unknown` 哪个等级。

### 10.5 E：nslog 只出现在场景 4/5

反驳口径：这是场景代码决定的，不是捕获漏了。场景 1/2/3 根本没有调用 `NSLog`；只有系统级场景和全链路场景调用了 `NSLog`。

应该改的地方：验证矩阵里不要要求场景 1/2/3 有 nslog。正确预期是：
- 场景 4：nslog 有 2 条
- 场景 5：nslog 有 1 条
- 场景 1/2/3：nslog 为 0 属于正常

### 10.6 F：oslog 里多是 XPC/network，不稳定看到 App 自己的 Logger

反驳口径：这是 iOS 真机 `OSLogStore(scope:.currentProcessIdentifier)` 的可见性限制，不等同于 `os_log` 没执行，也不等同于 iOSExplore capture 代码必然坏了。真机上系统框架日志、iOSExplore 内部日志和 App 自定义 subsystem 的可见性不同；App 自定义 `com.coo.SPMExample` 的 `os_log`/`Logger` 可能延迟、限流或不可见。

应该改的地方：文档和验证脚本不能把 `oslog` 当作稳定业务日志来源来断言“必须读到每一条 App Logger”。更稳的业务日志验证应该用 `ExploreAppLog.emit` 的 `bridge`，stdout/stderr 用对应 source；`oslog` 只能作为 best-effort 诊断来源。

如果未来要继续研究 F，需要单独做 50 条 `os_log` 循环实验，记录同一真机同一系统版本下 `OSLogStore` 可见率；不要和 stdout/stderr 修复混在一个问题里。

### 10.7 验证脚本的额外注意点

- 真机 curl 优先走 `127.0.0.1:38321` 或 `[::1]:38321`，以实际 ping 为准；本次沙箱里普通 curl 连接本地 iproxy 可能被拒，需要提权执行 curl。
- 真机必须确认 38321 监听者是 `iproxy`，不是模拟器残留 `SPMExample`。
- `ui.tap` 当前不接受 `waitAfterMs` 字段；如果需要等待，在脚本层 `sleep`，不要把 `waitAfterMs` 塞进 `ui.tap`。
- `app.logs.read` 的 `sources` 是数组，例如 `["stdout"]`、`["bridge"]`，读取结果看 `.data.entries`。
