# iOSExploreUIKit 知识库

`Sources/iOSExploreUIKit/`（UIKit 扩展模块，4 个 `ui.*` 命令）的阅读与参考文档。

core 不依赖 UIKit；所有依赖 UIKit 的命令下沉到本模块，宿主 App **显式** `server.registerUIKitCommands()` 注册。

## 这里的文档

- **[reading-guide.md](./reading-guide.md)** — 阅读指南。回答"代码这么多，从哪看、整个设计长什么样"。给一张全局心智模型 + 一条按依赖排序的阅读路线（约 1500 行精选阅读量，不是全部 3840 行）。**第一次读从这份开始。**
- **[uikit-file-reference.md](./uikit-file-reference.md)** — 文件档案。逐个登记 25 个文件的职责、关键点与依赖关系，当查阅手册或改某个文件时用。

## 4 个命令一览

| action | 作用 | adapter | 执行核心 |
|---|---|---|---|
| `ui.topViewHierarchy` | 完整 view 树结构快照（含文本/颜色/控件状态） | `TopViewHierarchyCommand` | `UIViewHierarchyCollector` |
| `ui.viewTargets` | 扁平轻量可交互目标列表（事件下发前发现） | `ViewTargetsCommand` | `UIViewTargetsCollector` |
| `ui.tap` | 模拟点击（坐标 hit-test / view 定位） | `UITapCommand` | `UIKitActionExecutor` |
| `ui.control.sendAction` | 向 UIControl 发 target-action 事件 | `UIControlSendActionCommand` | `UIKitActionExecutor` |

## 贯穿全模块的两条铁律

1. **typed factory**：UIKit 操作必须先在 Foundation-only typed query（如 `UIViewHierarchyQuery`、`UITapQuery`）里解析+校验，通过后才进入 `@MainActor` 域。UIKit 类型绝不穿过 public 边界。
2. **`#if canImport(UIKit)`**：碰 UIKit 的文件整体包在该指令内；macOS 编译为空壳，UIKit 行为由 iOS framework 测试覆盖。

## 相关文档

- 架构总览（含 UIKit 模块边界）→ `docs/architecture/index.md`
- 历史设计决策 → `docs/superpowers/specs/2026-06-23-uikit-command-extension-architecture-design.md` 等
