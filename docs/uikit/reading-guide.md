# iOSExploreUIKit 阅读指南

> 这份文档专门解决一个问题：**"代码很多，我不知道从哪看、整个设计长什么样"**。
> 它是一张地图 + 一条推荐阅读路线，不是逐行讲解。
> 逐文件的完整档案见 [uikit-file-reference.md](./uikit-file-reference.md)。

## 先建立全局心智模型（不读代码也能看懂）

`iOSExploreUIKit` 是挂在 `iOSExploreServer`（core）上的一个**可选扩展模块**。它把所有依赖 UIKit 的命令（`ui.*`）从 core 里剥离出来，使 core 能在 macOS 上 `swift test`、且永远不 `import UIKit`。

整个模块只做一件事：**把"Mac 发来的 JSON 命令"翻译成"在 iPhone 当前页面上对真实 `UIView` 的读/写操作"**。

它由 **14 个对外命令**和一组**内部基础设施**组成：

| 命令 | 一句话作用 |
|---|---|
| `ui.topViewHierarchy` | 返回当前页面 view 树的**完整结构快照**（含文本/颜色/控件状态等验收字段） |
| `ui.inspect` | 返回**扁平的、轻量的可交互目标列表**（事件下发前的目标发现） |
| `ui.tap` | 默认激活动作（按 target 类型路由：button/switch/输入框聚焦） |
| `ui.control.sendAction` | 向 `UIControl` 发送显式 target-action 事件 |
| `ui.screenshot` | 截屏（可选视觉证据，不再签发 viewSnapshotID） |
| `ui.input` | 向文本控件注入文本 |
| `ui.keyboard.dismiss` | 收起当前 first responder / 键盘 |
| `ui.scroll` | 在 `UIScrollView` 上按方向 + 距离滚动 |
| `ui.navigation.back` | 返回上一页（auto 先 dismiss 再 navigation pop） |
| `ui.navigation.tapBarButton` | 触发导航栏 UIBarButtonItem（placement + index） |
| `ui.wait` | 等待 UI 稳定或目标/文本/快照变化 |
| `ui.waitAny` | 一次轮询等待多个条件，第一个命中返回 matchedID/matchedIndex |
| `ui.scrollToElement` | 滚动到包含指定文本/identifier 的元素可见 |
| `ui.alert.respond` | 按明确按钮触发并关闭当前 UIAlertController（查询 alert 结构用 ui.inspect） |

这 14 个命令共享同一套底层能力：**定位（Locator）→ 能力判定（Capability）→ 陈旧防护（Snapshot）→ 执行（Executor）**。理解了这套共享基础设施，各命令的 adapter 都只是薄薄的"解析参数 + 调用"。

## 一张图看懂分层

```
                    ┌─────────────────────────────────────────┐
   Mac curl         │  UIKitCommandRegistrar  (注册入口)        │
  命令 JSON   ──►  │  14 个 Command adapter（解析参数 + 打日志） │
                    └──────────────────┬──────────────────────┘
                                       │  adapter 只解析请求、构造 Plan/Query
                                       │  真正的 UIKit 操作全部下沉 ↓
                    ┌──────────────────▼──────────────────────┐
                    │           共享基础设施（@MainActor）      │
                    ├─────────────────────────────────────────┤
                    │ UIKitContextProvider  取前台 window/顶部 VC │
                    │ UIKitLocatorResolver   locator → 真实 UIView │
                    │ UIKitActionExecutor    tap / sendActions 实际执行 │
                    │ UIKitActionCapabilityResolver  什么 view 能做什么动作 │
                    │ UIKitSnapshotStore     陈旧检测（指纹比对） │
                    │ UIKitFingerprintCollector  从 UIView 抽指纹 │
                    └─────────────────────────────────────────┘
                                       │
              ┌────────────────────────┴───────────────────────┐
              │  两个 Foundation-only 层（macOS 可测，无 UIKit）  │
              ├────────────────────────────────────────────────┤
              │  Models：UIKitLocator / UIViewHierarchyInput …  │
              │  Parsing：UIKitCommandFields / UIKitQueryNumber  │
              └────────────────────────────────────────────────┘
```

**贯穿全模块的两条铁律**（看任何文件都要带着这两点）：

1. **typed input factory**：所有 UIKit 操作必须先在 Foundation-only 的 `CommandInput`（如 `UIViewHierarchyInput`、`UITapInput`）里解析+校验参数，通过后才进入 `@MainActor` 域。UIKit 类型（`UIView`/`UIControl`）**绝不穿过 public 边界**回到非隔离域——跨边界只传 `Sendable` 值（路径、类型名、指纹）。
2. **`#if canImport(UIKit)`**：所有碰 UIKit 的文件整体包在这条指令里。macOS 编译时这些文件变成空壳，所以 macOS 上 `swift test` 只能测到 Foundation-only 层；真实 `UIView` 行为由 iOS framework 测试覆盖。

## 推荐阅读路线（按依赖，从入口往下）

下面这条路线按"从看到命令到执行完"的真实路径走，每一步只读一两个文件，读完后会对模块有完整理解。**预计总阅读量约 1500 行**（不是 3840 行全部）。

### 第 0 步：骨架（5 分钟，~60 行）
先建立整体印象，**不要纠结细节**：
- `UIKitCommandRegistrar.swift`——入口，看 14 个命令怎么被注册。
- `UIKitCommandLogging.swift`（29 行）——日志怎么复用 core 的缝。

> 目标：知道“14 个命令 + 一套日志”。

### 第 1 步：两个查询命令（最容易上手，~750 行）
查询命令是纯读、无副作用，最适合先读：
- `Commands/Inspect/UIInspectModels.swift`（381 行）——**重点读 `UIInspectInput.shouldInclude`**，这是 canonical 目标发现决策核心（含 UIControl 系 + UIScrollView 系 + 挂手势的非 control view；普通 label/container 不进 targets，观察职责在 `ui.topViewHierarchy`），而且全是 Foundation-only 逻辑。
- `Commands/Inspect/UIInspectCollector.swift`（270 行）——看 `collect(view:...)` 递归遍历 + 仅按最终 returned targets 签发 `viewSnapshotID` 的主流程。
- `Commands/Inspect/InspectCommand.swift`（81 行）——最薄的 adapter，看"typed input → 调 collector → 打日志"模板。
- （可选）`Commands/TopViewHierarchy/` 三件套——结构类似，但多了完整树和 `UIViewHierarchyElement` 协议抽象，可略读。

> 目标：吃透"AnyCommand 解析 typed input → adapter 调 MainActor collector → 返回 JSON + viewSnapshotID"这套模板。后两个命令照搬。

### 第 2 步：定位与执行（核心难点，~700 行）
两个交互命令（tap / sendAction）共享同一套执行引擎，**这是模块最值得读的部分**：
- `Support/Locator/UIKitLocator.swift`（78 行）——两种定位语义（identifier / path）收敛成一个枚举。
- `Support/Locator/UIKitLocatorResolver.swift`（143 行）——把 locator 在真实 view 树里解析成 `UIView`（失败 throws，由调用方工厂闭包构造对应错误）。
- `Support/Action/UIKitActionExecutor.swift`——**全模块的执行核心**。重点看 `executeTap` 和 `executeControlEvent`：locate → `viewSnapshotID` 陈旧校验 → 默认激活路由（tap）/ `sendActions(for:)`（control）（全程 throws，失败由 handler 顶层 catch 转 envelope）。
- `Commands/Tap/UITapCommand.swift` + `Commands/ControlAction/UIControlSendActionCommand.swift`（共 ~140 行）——又是薄 adapter，和第 1 步的 adapter 模板一模一样。

> 目标：理解"一个交互命令从参数到真实 `sendActions(for:)` 的完整路径"。

### 第 3 步：陈旧防护（决定正确性，~470 行）
为什么 tap 带了 `viewSnapshotID` 才安全？读这块就懂：
- `Support/Snapshot/UIKitSnapshotStore.swift`——指纹快照存储，**重点看 `isStale` 方法和容量/淘汰策略**。
- `Support/Snapshot/UIKitFingerprintCollector.swift`（114 行）——从 `UIView` 抽指纹（含新增 `semanticDigest`：按钮标题 / a11y label / a11y value / switch isOn / segment index / 默认激活路由的稳定哈希，参与陈旧检测）；注意 identifier 只存哈希、不存原文。

> 目标：理解"path 陈旧问题怎么被解决的"——这是 `ui.inspect` 返回 `viewSnapshotID` 的全部理由。

### 第 4 步：辅助基础设施（按需查，~330 行）
用到时再翻，不必通读：
- `Support/Context/UIKitContextProvider.swift`——怎么找前台 window 和顶部 VC（`currentContext(action:) throws`）。
- `Support/Action/UIKitActionCapabilityResolver.swift`（91 行）——UIControl 各 event 的可用性规则（collector 声明 `availableActions` 时用）。tap 的默认激活路由判定已拆到 `UIKitDefaultActivationResolver`（V1：UIButton/UISwitch/文本输入；UISlider/UISegmentedControl/普通 UIView 无默认激活路由，tap 返回 `unsupported_target`）。
- `UIKitCommandError.swift`——错误工厂（conform `Error`，可被 throw），**查的时候看**，不需要通读。
- `Support/Parsing/`——UIKit 共享 command 字段、定位 input helper 与安全整数转换。

## 三个"如果你只想快速理解"的捷径

- **只想知道命令怎么用** → 只读第 0 步 + 每个 `*Input.inputSchema`；实际对外 JSON 可直接看 `help` 返回的 `inputSchema.properties`。
- **只想理解架构设计** → 读第 0、2、3 步的文件头注释（`///` 块），每个文件的文档注释都写清了"为什么这样设计"。
- **只想改某个命令** → 在 [uikit-file-reference.md](./uikit-file-reference.md) 里找到那个文件，看它依赖谁、被谁调用。

## 模块设计意图（为什么是这样切的）

这几个决策是理解代码的关键，建议带着它们去读：

- **core 不依赖 UIKit** → UIKit 能力做成独立 product，宿主**显式** `registerUIKitCommands()`。core 初始化不自动注册任何 `ui.*`，未注册时 `help` 不含 UIKit action（这是回归保护点）。
- **adapter 薄、executor 厚** → 所有"真实 UIKit 操作"集中在 `@MainActor` 的 executor/collector，adapter 只接收已解析的 typed input。这让执行逻辑可在 iOS 测试里用注入的 view 树驱动（看每个类型有没有 `execute(_:context:)` / `collect(query:context:)` 这种"注入入口"）。
- **availableActions 与可执行性对齐** → `ui.inspect` 声明的 `availableActions` 由 `UIKitActionCapabilityResolver` 给出（UIControl 各 event）；`ui.tap` 的默认激活路由由 `UIKitDefaultActivationResolver` 判定（V1：UIButton/UISwitch/文本输入）。二者口径一致，避免"声明可点但实际点不动"的分叉。
- **定位二选一、identifier 精确不截断** → 历史上有过截断 prefix 的 bug；现在 `identifier` 完整匹配，匹配多个返回 `ambiguous`。

## 下一步

读完这份指南，建议：
1. 按第 0→1→2→3 步打开文件实际走一遍。
2. 遇到具体文件疑问，查 [uikit-file-reference.md](./uikit-file-reference.md)。
3. 想看历史设计决策，读 `docs/superpowers/specs/2026-06-23-uikit-command-extension-architecture-design.md`。
4. 如果你在构建 MCP 服务 / Skill / agent 自动化脚本，**必须先读** [agent-command-protocol.md](./agent-command-protocol.md) —— 里面写明了每个 `ui.*` 命令的前置条件、两步调用时序、`viewSnapshotID` 契约、以及 cell 定位的正确方法（避免"靠 subviews 顺序猜 cell"这类已知陷阱）。
