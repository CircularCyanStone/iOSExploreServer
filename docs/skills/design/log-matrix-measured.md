# 实测日志矩阵(2026-07-16)

> 本文记录 iOSExploreDiagnostics `app.logs.read` 在模拟器和真机上对 6 个 `source` 的实测可用性,供 `ios-logs` skill 及后续真机补测引用。数据来源:用 `curl` 直接驱动 `Examples/SPMExample`(已开启 `DiagnosticsConfiguration` 全部 4 个 capture 开关:`captureStdout` / `captureStderr` / `captureNSLog` / `captureOSLog`)。

## 矩阵

| source | 模拟器 capture.state | 模拟器可读 | 真机 capture.state | 真机可读 |
|---|---|---|---|---|
| explore | enabled | 是(50 条,本仓库自身生命周期日志:`http` / `listener` / `router` / `command`) | enabled | 是(50+ 条 `hasMore=true`,同模拟器,`http` / `listener` / `router` / `command` 全覆盖) |
| bridge | enabled | 是(3 条,宿主 App 经 `UIKitCommandLogging` 上报的桥接事件,如 `spm.example.nslog` / `spm.example.stdio`) | enabled | 是(3 条,`spm.example.nslog` + `spm.example.stdio` ×2,与模拟器一致) |
| stdout | enabled | 是(`m-stdout-token-CX3`,category=`stdio`,level=`info`) | enabled | 是(`d-stdout-token-C3`,category=`stdio`,level=`info`,bytes=18) |
| stderr | enabled | 是(`m-stderr-token-DX4`,category=`stdio`,level=`error`) | enabled | 是(`d-stderr-token-D4`,category=`stdio`,level=`error`,bytes=18) |
| nslog | enabled | 是(`2026-07-16 09:45:48.981 SPMExample[66464:4655547] m-nslog-token-BX2`,完整 NSLog 行) | enabled | 是(`2026-07-16 15:12:53.138 SPMExample[36246:7951908] d-nslog-token-B2`,完整 NSLog 行,PID 为真机进程) |
| oslog | enabled | 是(`m-oslog-token-AX1` 与 `m-logger-token-EX5`,subsystem=`com.coo.SPMExample`;另含 NSLog 镜像条目 `m-nslog-token-BX2`) | enabled | 是(`d-oslog-token-A1` 与 `d-logger-token-E5`,subsystem=`com.coo.SPMExample`,category=`diagnostics`;**NSLog 镜像条目真机显示为 `<private>`**(见下文差异说明);另含 `iOSExploreServer` subsystem 的生命周期日志) |

图例:`enabled` = `app.logs.mark` / `app.logs.read` 响应中该 source 的 `capture.state` 字段值。

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

- **设备**:"李奇奇的iPhone",CoreDevice ID `3AC0C7D6-22F6-572B-8368-4047A14BAB52`,USB UDID `00008030-001045C136D1402E`(两者同一台,AGENTS.md 坑 #1),iOS 26.5,state=connected。
- **网络路径**:真机 38321 必须经 `iproxy` USB 转发(`./scripts/proxy.sh --daemon`),Mac 侧再 `curl http://localhost:38321/`。与模拟器的关键差别:`lsof -iTCP:38321` 的 COMMAND 列必须是 `iproxy`(PID 由 `proxy.sh` 管理),**不能**是 `SPMExampl`——后者是模拟器 App 残留成的 Mac 进程占住 38321(AGENTS.md 坑 #4),会导致 curl 打到旧模拟器 binary 而非真机。实测前先 `xcrun simctl terminate 065CC8DB-8978-46C5-82D6-C96625B608D8 com.coo.SPMExample` 清模拟器残留,再起 iproxy。
- **profile**:XcodeBuildMCP `device-app`(SPMExample.xcodeproj,scheme SPMExample,configuration Debug,deviceId `3AC0C7D6`,bundleId `com.coo.SPMExample`,platform iOS)。`build_run_device()` 一条龙完成构建+install+launch,SPMExample 在 DEBUG `viewDidAppear` 自动 `server.start()`,不需要 `launchArgs` / `env`(AGENTS.md 坑 #3 不适用本场景)。
- **触发序列**(每个 source 各发一条独立 token,与模拟器区分用 `d-` 前缀):
  - `debug.emitOSLog` → `d-oslog-token-A1`
  - `debug.emitNSLog` → `d-nslog-token-B2`
  - `debug.emitStdout` → `d-stdout-token-C3`
  - `debug.emitStderr` → `d-stderr-token-D4`
  - `debug.emitLogger`(Swift `Logger`) → `d-logger-token-E5`
- **每个 source 的 capture.state**:6 个 source(`explore` / `bridge` / `stdout` / `stderr` / `nslog` / `oslog`)在 `app.logs.mark` 与每次 `app.logs.read` 的 `data.capture` 中均返回 `state=enabled`,**无 `notCaptured` 或 `unavailable`**。包括 `oslog`。
- **token 匹配**:5 条 emit 的 token 全部在对应 source 的 read 响应中找到。`stdout` / `stderr` 各命中 1 条(18 字节,`category=stdio`);`nslog` 命中 1 条(完整带时间戳与真机 PID `36246` 的 NSLog 行);`oslog` 命中 `d-oslog-token-A1` 与 `d-logger-token-E5` 两条原始 os_log 记录(`category=diagnostics`,subsystem `com.coo.SPMExample`),另含 `iOSExploreServer` subsystem 的生命周期日志(`listener` / `http` / `router` / `command`);`explore` 与 `bridge` 同模拟器,分别是本仓库生命周期日志与宿主桥接事件。
- **oslog 真机可用性(关键数据点)**:iOS 26.5 真机上 `oslog` 的 `capture.state` 返回 `enabled`,`OSLogStore` 进程级读取工作正常,未出现 spec §7 担心的 `unavailable`。这**不推翻** spec §7"不能写死平台断言"的设计——它验证了"在当前 iOS 26.5 + Debug 配置 + 这台设备上 oslog 可用"这一个数据点;其他 iOS 版本、Release 配置、不同 entitlement 或系统策略下仍可能返回 `unavailable`,所以代码必须保留运行时探测而非写死 `if device == sim`。本实测为该设计提供了真机侧的正面样本。
- **NSLog 镜像真机差异(privacy 脱敏)**:模拟器 `oslog` source 能看到 NSLog 镜像条目的明文(`m-nslog-token-BX2`);**真机 `oslog` source 里的 NSLog 镜像条目显示为 `<private>`**(本次实测 id=237,`category=""`,`subsystem=""`,`message="<private>"`)。这是 `os_log` 默认 `.privacy(auto)` 在真机上更严格的体现——真机会对未显式 `.public` 的字符串参数做脱敏,模拟器则默认明文。NSLog 原文在 `nslog` source 仍是完整明文(不受影响)。agent 在真机 `oslog` source 看到 `<private>` 不要误判为捕获失败,应去 `nslog` / `stdout` / `stderr` source 找明文。
- **os_log 写入延迟**:emit 后 `sleep 2` 再读 `oslog`,首次读即有完整数据,本次未见明显延迟(与模拟器一致)。`ios-logs` skill 仍应在首次 `oslog` 读空时建议等 1–2 秒重读。
- **captureSessionID**:`2C0B0649-1205-4059-AB68-8FCA3023240A`;mark cursor `id=144`。所有 read 响应在 `data.capture` 中均回传当前 6 个 source 的 state 快照,可作自检字段使用。

### 真机与模拟器对比小结

- **capture.state**:6 个 source 在两端**全部 `enabled`**,无差异。
- **可读性**:6 个 source 在两端**全部可读**,token 全部命中。
- **唯一实质差异**:NSLog 镜像在 `oslog` source 的呈现——模拟器明文,真机 `<private>`(os_log privacy 策略)。这不影响 `nslog` source 本身的明文读取。
- **结论**:`iOSExploreDiagnostics` 的日志捕获在真机和模拟器上行为一致可用;`ios-logs` skill 的真机流程(iproxy + curl)与模拟器流程(curl 直连)产出等价数据,无需为真机做特殊 source 降级。唯一要注意的是真机 `oslog` 的 `<private>` 脱敏,但裸文本日志走 `nslog` / `stdio` 不受影响。
