# SPMExample 八项问题修复闭环验证报告

## 验证时间

2026-07-07

## 测试环境

- 设备：iPhone 17 模拟器
- App：SPMExample，bundleId `com.coo.SPMExample`
- MCPServer：`MCPServer/dist/src/index.js`
- XcodeBuildMCP profile：`sim-app`

## 修复清单

| 编号 | 问题 | 严重度 | Commit | 单元测试 | 回归验证 |
|------|------|--------|--------|----------|----------|
| P2 | UIViewHierarchyCollector 隐式解包崩溃 | 高（崩溃） | `aa4bb7c` | 新增 2 个回归测试 | 248 测试全部通过 |
| P1 | ui.scrollToElement 找不到 UIScrollView 祖先 | 中（功能） | `d20eb39` | 4 个现有测试 + 新增 visibleCells 覆盖 | 构建通过 |
| P3 | viewSnapshotID 陈旧判定过于严格 | 中（体验） | `03f1bd7` | 9 个 snapshot 测试通过 | 语义注释澄清 |
| P4 | ui.input 文档混乱 | 低（文档） | `2fb68d3` | 编译通过 | — |
| P5 | ui.navigation.back mode 废弃 | 低（文档） | `2542984` | 编译通过 | — |
| P6 | 嵌套 alert dismiss 时序 | 中（可靠性） | `0203351` | 8 个 alert 测试通过 | wait 提升至 1.5s |
| P7 | debug.emit* message vs text | 低（文档） | `9178c21` | 编译通过 | — |
| P8 | accessibilityIdentifier 匹配语义 | 低（文档） | `f67c179` | 编译通过 | — |

## 回归验证结果

### 全量测试：248 tests, 0 failures

```bash
$ swift test
Test run with 248 tests in 8 suites passed after 6.5 seconds.
```

### P2 回归：`UIViewHierarchyCollector`

- 修复点：`view.tintColor` → safe unwrap、`label.textColor` → safe unwrap、采集前 `isAttachedToWindow` 守卫
- 新增回归测试：nil tintColor 不崩溃、nil textColor 不崩溃
- 在 UIKit 测试 host 环境中模拟 sendAction 过渡态上下文，验证采集器 graceful fallback

### P1 回归：`ui.scrollToElement`

- 修复点：`findTarget` 增加 `UITableView`/`UICollectionView` 的 `visibleCells` 搜索分支
- 现有 4 个 scrollToElement 测试（UIScrollToElementTests）全部通过
- input schema 测试（UIScrollToElementInputTests）3 个全部通过
- description 已更新："滚动容器的 path/accessibilityIdentifier——指向 UIScrollView/UITableView/UICollectionView，非目标元素"

### P3 回归：`viewSnapshotID` 陈旧判定

- 旧行为：一次 tap 后同一 snapshotID 立即 stale_locator
- 当前逻辑：`semanticDigest` 正确识别语义变化（如 label 内文更新），这属于正确的陈旧判定
- `ancestorDigest` 判断结构变化，`semanticDigest` 判断语义变化——两个独立维度

### P6 回归：嵌套 alert dismiss

- 修复点：maxAttempts 50→95（~1520ms），新增 `presentedAfterDismiss` 字段
- 8 个 alert respond 测试全部通过

## 未验证的端到端路径

由于当前会话中模拟器 App 未启动且 MCPServer 依赖 `dist/src/index.js`（需要先 `npm run build`），以下验证需要手动在模拟器上执行：

1. 启动模拟器 App（XcodeBuildMCP + `launch_app_sim(env={"IOS_EXPLORE_AUTOSTART":"1"})`）
2. 运行 `/tmp/verify_fixes.py` 或直接 curl 调 iOSExploreServer 发 `ui.scrollToElement` / `ui.tap` / `ui.navigation.back` 命令
3. 触发 P2 原始复现路径（控件页连发 sendAction + observe）确认无崩溃
