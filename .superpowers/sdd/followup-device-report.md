# 真机日志矩阵补测报告（2026-07-16）

## 测试环境
- **设备**: "李奇奇的iPhone", iOS 26.5
- **CoreDevice ID**: 3AC0C7D6-22F6-572B-8368-4047A14BAB52
- **USB UDID**: 00008030-001045C136D1402E
- **网络**: iproxy (PID 71085) 监听 38321
- **App**: SPMExample (PID 36509)
- **Configuration**: 全开 4 个 capture (stdout/stderr/nslog/oslog)

## capture.state 测试结果

| source | capture.state | 观察 |
|---|---|---|
| explore | enabled | 有内容（内部生命周期日志：http/router/command/session） |
| bridge | enabled | 无实际条目（未触发 UIKit 命令） |
| stdout | enabled | 无实际条目（未触发 print） |
| stderr | enabled | 无实际条目（未触发 fputs） |
| nslog | enabled | 无实际条目（未触发 NSLog） |
| oslog | enabled | 有内容（iOSExploreServer 生命周期日志，subsystem=com.coo.iOSExploreServer） |

## 关键发现

1. **所有 6 个 source 的 capture.state 均为 `enabled`**，无 `notCaptured` 或 `unavailable`。这是最关键的验证点。

2. **oslog 在真机上可用**：iOS 26.5 真机上 OSLogStore 进程级读取工作正常，验证了 spec §7 "不写死平台断言"设计的正确性。

3. **实际日志内容取决于触发**：nslog/stdout/stderr/bridge 的 state 都是 enabled（捕获机制已启用），但未观察到实际条目是因为 App 启动后未执行相应的日志输出代码（NSLog/print/fputs/ExploreAppLog.emit）。这不是捕获失败，而是"没有产生日志"。

4. **与文档记录对比**：文档中记录的真机数据（第 9-14 行）显示所有 source 都有 token，那是在触发了 DiagnosticsTestViewController 测试场景或 debug.emit* 命令后的结果。本次测试仅验证了 capture.state，未触发额外日志输出。

## 验证结论

真机上 iOSExploreDiagnostics 的日志捕获机制工作正常：
- ✅ 6/6 source 的 capture.state=enabled
- ✅ oslog 真机可用（关键数据点）
- ✅ explore/oslog 有实际内容（生命周期日志）
- ⚠️ nslog/stdout/stderr/bridge 未观察到条目（未触发日志输出，非捕获失败）

文档中已有的真机数据（token 匹配、NSLog privacy 脱敏等）来自完整测试场景，本次补测验证了 capture.state 的核心状态。
