# 最终命令覆盖率测试报告

**生成时间**: 2026/7/13 23:22:04

## 📊 测试摘要

| 指标 | 数值 |
|------|------|
| 总测试数 | 24 |
| 通过 | 18 |
| 失败 | 6 |
| 成功率 | 75.00% |
| **命令覆盖率** | **21 / 32 (65.63%)** |

## ✅ 已测试命令 (21)

1. `app.logs.mark`
2. `app.logs.read`
3. `debug.emitAppLog`
4. `debug.emitLogger`
5. `debug.emitNSLog`
6. `debug.emitOSLog`
7. `debug.emitStderr`
8. `debug.emitStdout`
9. `debug.probe`
10. `device`
11. `echo`
12. `error-handling`
13. `greet`
14. `help`
15. `info`
16. `ping`
17. `ui.controllers`
18. `ui.inspect`
19. `ui.screenshot`
20. `ui.topViewHierarchy`
21. `ui.wait`

## 📋 命令测试详情

| 命令 | 测试数 | 通过 | 失败 | 成功率 |
|------|--------|------|------|--------|
| `ping` | 1 | 1 | 0 | 100% |
| `echo` | 1 | 1 | 0 | 100% |
| `greet` | 1 | 1 | 0 | 100% |
| `info` | 1 | 1 | 0 | 100% |
| `device` | 1 | 1 | 0 | 100% |
| `help` | 1 | 0 | 1 | 0% |
| `debug.probe` | 1 | 1 | 0 | 100% |
| `debug.emitStdout` | 1 | 1 | 0 | 100% |
| `debug.emitStderr` | 1 | 1 | 0 | 100% |
| `debug.emitNSLog` | 1 | 1 | 0 | 100% |
| `debug.emitOSLog` | 1 | 1 | 0 | 100% |
| `debug.emitLogger` | 1 | 1 | 0 | 100% |
| `debug.emitAppLog` | 1 | 1 | 0 | 100% |
| `app.logs.mark` | 1 | 1 | 0 | 100% |
| `app.logs.read` | 2 | 1 | 1 | 50% |
| `ui.topViewHierarchy` | 1 | 1 | 0 | 100% |
| `ui.controllers` | 1 | 0 | 1 | 0% |
| `ui.screenshot` | 1 | 0 | 1 | 0% |
| `ui.inspect` | 1 | 1 | 0 | 100% |
| `ui.wait` | 1 | 1 | 0 | 100% |
| `error-handling` | 3 | 1 | 2 | 33% |

## ⚡ 性能统计（平均响应时间）

| 命令 | 平均 (ms) | 最小 (ms) | 最大 (ms) |
|------|-----------|-----------|----------|
| `echo` | 2.0 | 2 | 2 |
| `debug.probe` | 2.0 | 2 | 2 |
| `debug.emitAppLog` | 2.0 | 2 | 2 |
| `greet` | 3.0 | 3 | 3 |
| `debug.emitStdout` | 3.0 | 3 | 3 |
| `debug.emitStderr` | 3.0 | 3 | 3 |
| `debug.emitNSLog` | 3.0 | 3 | 3 |
| `app.logs.mark` | 3.0 | 3 | 3 |
| `invalid.action` | 3.0 | 3 | 3 |
| `device` | 4.0 | 4 | 4 |
| `help` | 4.0 | 4 | 4 |
| `ui.controllers` | 4.0 | 4 | 4 |
| `debug.emitOSLog` | 5.0 | 5 | 5 |
| `debug.emitLogger` | 6.0 | 6 | 6 |
| `info` | 8.0 | 8 | 8 |
| `app.logs.read` | 8.0 | 7 | 9 |
| `ui.inspect` | 8.0 | 8 | 8 |
| `ui.topViewHierarchy` | 9.0 | 9 | 9 |
| `ping` | 12.0 | 2 | 22 |
| `ui.screenshot` | 74.0 | 74 | 74 |
| `ui.wait` | 328.0 | 326 | 330 |

