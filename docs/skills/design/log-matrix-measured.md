# 实测日志矩阵(2026-07-16)

> 本文记录 iOSExploreDiagnostics `app.logs.read` 在模拟器和真机上对 6 个 `source` 的实测可用性,供 `ios-logs` skill 及后续真机补测引用。数据来源:用 `curl` 直接驱动 `Examples/SPMExample`(已开启 `DiagnosticsConfiguration` 全部 4 个 capture 开关:`captureStdout` / `captureStderr` / `captureNSLog` / `captureOSLog`)。

## 矩阵

| source | 模拟器 capture.state | 模拟器可读 | 真机 capture.state | 真机可读 |
|---|---|---|---|---|
| explore | enabled | 是(50 条,本仓库自身生命周期日志:`http` / `listener` / `router` / `command`) | 待补 | 待补 |
| bridge | enabled | 是(3 条,宿主 App 经 `UIKitCommandLogging` 上报的桥接事件,如 `spm.example.nslog` / `spm.example.stdio`) | 待补 | 待补 |
| stdout | enabled | 是(`m-stdout-token-CX3`,category=`stdio`,level=`info`) | 待补 | 待补 |
| stderr | enabled | 是(`m-stderr-token-DX4`,category=`stdio`,level=`error`) | 待补 | 待补 |
| nslog | enabled | 是(`2026-07-16 09:45:48.981 SPMExample[66464:4655547] m-nslog-token-BX2`,完整 NSLog 行) | 待补 | 待补 |
| oslog | enabled | 是(`m-oslog-token-AX1` 与 `m-logger-token-EX5`,subsystem=`com.coo.SPMExample`;另含 NSLog 镜像条目 `m-nslog-token-BX2`) | 待补 | 待补 |

图例:`enabled` = `app.logs.mark` / `app.logs.read` 响应中该 source 的 `capture.state` 字段值;`待补` = 本次未在真机实测,等用户授权设备后补。

## 实测说明

### 模拟器

- **设备**:iPhone 17 模拟器(`com.apple.CoreSimulator.SimDeviceType.iPhone-17`),UDID `065CC8DB-8978-46C5-82D6-C96625B608D8`,运行时 `com.apple.CoreSimulator.SimRuntime.iOS-26-3`(iOS 26.3),state=Booted。
- **网络路径**:模拟器与 Mac 共享 localhost,直接 `curl http://localhost:38321/`,无需 `iproxy`。`lsof -iTCP:38321` 显示监听进程 COMMAND 为 `SPMExampl`(模拟器 App 是宿主 Mac 进程,这是正常预期,不是残留)。
- **profile**:XcodeBuildMCP `sim-app`(SPMExample.xcodeproj,scheme SPMExample,bundleId `com.coo.SPMExample`)。
- **触发序列**(每个 source 各发一条独立 token):
  - `debug.emitOSLog` → `m-oslog-token-AX1`
  - `debug.emitNSLog` → `m-nslog-token-BX2`
  - `debug.emitStdout` → `m-stdout-token-CX3`
  - `debug.emitStderr` → `m-stderr-token-DX4`
  - `debug.emitLogger`(Swift `Logger`) → `m-logger-token-EX5`
- **每个 source 的 capture.state**:6 个 source(`explore` / `bridge` / `stdout` / `stderr` / `nslog` / `oslog`)在 `app.logs.mark` 与每次 `app.logs.read` 的 `data.capture` 中均返回 `state=enabled`,无 `notCaptured` 或 `unavailable`。
- **token 匹配**:5 条 emit 的 token 全部在对应 source 的 read 响应中找到。`stdout` / `stderr` 各命中 1 条;`nslog` 命中 1 条(NSLog 完整带时间戳与 PID 的行);`oslog` 命中 3 条(`emitOSLog` 与 `emitLogger` 的原始 os_log 记录,以及 NSLog 镜像过来的同文本条目)。
- **os_log 写入延迟**:实测中 emit 后 `sleep 2` 再读 `oslog`,首次读即有完整数据,本次未见明显延迟。但 OSLogStore 在某些机型 / 系统负载下存在亚秒到秒级延迟的已知特性;`ios-logs` skill 仍应在首次 `oslog` 读空时建议等 1–2 秒重读一次,再判定为"无日志"。
- **NSLog 镜像**:实测 `m-nslog-token-BX2` 同时出现在 `nslog` source(NSLog 行格式)和 `oslog` source(无 `subsystem` / `category` 的裸条目),印证 NSLog 底层会写入 os_log 的系统行为。这是 iOS 系统行为而非本仓库代码的额外拷贝,agent 在 `oslog` source 看到 NSLog 文本不要误判为重复捕获。
- **captureSessionID**:`BADDCCA2-E745-4E19-BE4D-B2C0C9EBAA10`;mark cursor `id=247923`。所有 read 响应在 `data.capture` 中均回传当前 6 个 source 的 state 快照,可作自检字段使用。

### 真机

- **本次未实测**。约束原因:本机当前仅有一台通过 USB 连接的 iOS 真机,属他人设备,未获用户授权部署 SPMExample(含 Debug-only HTTP server 与私有 API 调用)。
- **待补流程**(用户授权设备后执行):
  1. 在 XcodeBuildMCP 中切到 `device-app` profile,`build_run_device()` + `launch_app_device()`。
  2. `./scripts/proxy.sh --daemon` 启动 iproxy(USB UDID 见 `list_devices`)。
  3. `lsof -iTCP:38321` 确认 COMMAND 列是 `iproxy` 而非残留的 `SPMExampl`(AGENTS.md 坑 #4)。
  4. 重跑上方"触发序列"与各 source 的 `app.logs.read`,把 `capture.state` 与 token 命中情况填到本表"真机"列。
- **预期关注点**:真机上 `oslog` 的 `capture.state` 有可能因 `OSLogStore` 进程级读取限制在不同 iOS 版本下返回 `unavailable`(AGENTS.md 已注明),这正是 spec §7"不能写死平台断言"的根因;补测时需重点确认。
