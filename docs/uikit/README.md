# iOSExploreUIKit 知识库

`Sources/iOSExploreUIKit/`（UIKit 扩展模块，14 个 `ui.*` 命令）的阅读与参考文档。

core 不依赖 UIKit；所有依赖 UIKit 的命令下沉到本模块，宿主 App **显式** `server.registerUIKitCommands()` 注册。

## 这里的文档

- **[agent-command-protocol.md](./agent-command-protocol.md)** — **MCP / Skill / agent 自动化脚本构建者必读**。回答"我要从外部调用 `ui.*` 命令，每个命令的前置条件是什么、调用顺序怎么排、`viewSnapshotID` 怎么拿、cell 定位从哪读 indexPath"。记录了调用方实际踩过的坑（viewSnapshotID 字段名写错、subviews 顺序 ≠ indexPath 顺序、session env 不注入进程等）和标准 curl 时序模板。
- **[reading-guide.md](./reading-guide.md)** — 阅读指南。回答"代码这么多，从哪看、整个设计长什么样"。给一张全局心智模型 + 一条按依赖排序的阅读路线（约 1500 行精选阅读量，不是全部 3840 行）。**第一次读从这份开始。**
- **[uikit-file-reference.md](./uikit-file-reference.md)** — 文件档案。逐个登记 61 个文件的职责、关键点与依赖关系，当查阅手册或改某个文件时用。

## 14 个命令一览

| action | 作用 | adapter | 执行核心 |
|---|---|---|---|
| `ui.topViewHierarchy` | 完整 view 树结构快照（含文本/颜色/控件状态） | `TopViewHierarchyCommand` | `UIViewHierarchyCollector` |
| `ui.inspect` | 扁平轻量可交互目标列表（事件下发前发现） | `InspectCommand` | `UIInspectCollector` |
| `ui.tap` | 默认激活动作（按 target 类型路由：button/switch/输入框聚焦） | `UITapCommand` | `UIKitActionExecutor` |
| `ui.control.sendAction` | 向 UIControl 发显式 target-action 事件 | `UIControlSendActionCommand` | `UIKitActionExecutor` |
| `ui.screenshot` | 截屏（可选视觉证据，不再签发 viewSnapshotID） | `ScreenshotCommand` | `UIScreenshotCollector` |
| `ui.input` | 向文本控件注入文本 | `InputCommand` | `UITextInputExecutor` |
| `ui.keyboard.dismiss` | 收起当前 first responder / 键盘 | `KeyboardDismissCommand` | `UIKeyboardDismissExecutor` |
| `ui.scroll` | 在 UIScrollView 上按方向 + 距离滚动 | `ScrollCommand` | `UIScrollExecutor` |
| `ui.navigation.back` | 返回上一页（auto 先 dismiss 再 navigation pop） | `NavigationBackCommand` | `UINavigationBackExecutor` |
| `ui.navigation.tapBarButton` | 触发导航栏 UIBarButtonItem（placement + index） | `UINavigationBarButtonCommand` | `UINavigationBarButtonExecutor` |
| `ui.wait` | 等待 UI 稳定或目标/文本/快照变化 | `WaitCommand` | `UIWaitExecutor` |
| `ui.waitAny` | 一次轮询等待多个条件，第一个命中返回 matchedID/matchedIndex | `WaitAnyCommand` | `UIWaitAnyExecutor` |
| `ui.scrollToElement` | 滚动到指定文本/identifier 元素可见 | `ScrollToElementCommand` | `UIScrollToElementExecutor` |
| `ui.alert.respond` | 查询/响应 UIAlertController（dryRun） | `AlertRespondCommand` | `UIAlertRespondExecutor` |

## 贯穿全模块的两条铁律

1. **typed factory**：UIKit 操作必须先在 Foundation-only typed input（如 `UIViewHierarchyInput`、`UITapInput`）里解析+校验，通过后才进入 `@MainActor` 域。UIKit 类型绝不穿过 public 边界。
2. **`#if canImport(UIKit)`**：碰 UIKit 的文件整体包在该指令内；macOS 编译为空壳，UIKit 行为由 iOS framework 测试覆盖。

## 相关文档

- 架构总览（含 UIKit 模块边界）→ `docs/architecture/index.md`
- 历史设计决策 → `docs/superpowers/specs/2026-06-23-uikit-command-extension-architecture-design.md` 等
