# 综合命令覆盖率测试报告

**测试时间**: 2026/7/13 23:23:41

## 📊 总体情况

| 指标 | 数值 |
|------|------|
| 命令覆盖率 | **30/32 (93.75%)** |
| 目标 | 90% (29/32) |
| 状态 | ✅ 已达成 |
| 总测试数 | 30 |
| 成功率 | 73.33% |

## ✅ 已测试命令 (30)

1. `app.logs.mark` - 1/1 通过
2. `app.logs.read` - 1/1 通过
3. `debug.emitAppLog` - 1/1 通过
4. `debug.emitLogger` - 1/1 通过
5. `debug.emitNSLog` - 1/1 通过
6. `debug.emitOSLog` - 1/1 通过
7. `debug.emitStderr` - 1/1 通过
8. `debug.emitStdout` - 1/1 通过
9. `debug.probe` - 1/1 通过
10. `device` - 1/1 通过
11. `echo` - 1/1 通过
12. `greet` - 1/1 通过
13. `help` - 1/1 通过
14. `info` - 1/1 通过
15. `ping` - 1/1 通过
16. `ui.alert.respond` - 0/1 通过
17. `ui.control.sendAction` - 0/1 通过
18. `ui.controllers` - 1/1 通过
19. `ui.input` - 0/1 通过
20. `ui.inspect` - 1/1 通过
21. `ui.keyboard.dismiss` - 1/1 通过
22. `ui.longPress` - 1/1 通过
23. `ui.navigation.back` - 0/1 通过
24. `ui.screenshot` - 1/1 通过
25. `ui.scroll` - 0/1 通过
26. `ui.swipe` - 0/1 通过
27. `ui.tap` - 0/1 通过
28. `ui.topViewHierarchy` - 1/1 通过
29. `ui.wait` - 1/1 通过
30. `ui.waitAny` - 0/1 通过

## ⚡ 性能数据（前 10 最快）

| 命令 | 平均 (ms) |
|------|----------|
| `info` | 2.0 |
| `debug.emitNSLog` | 2.0 |
| `debug.emitOSLog` | 2.0 |
| `app.logs.mark` | 2.0 |
| `ui.scroll` | 2.0 |
| `ui.tap` | 2.7 |
| `ui.navigation.back` | 2.9 |
| `greet` | 3.0 |
| `device` | 3.0 |
| `debug.probe` | 3.0 |

