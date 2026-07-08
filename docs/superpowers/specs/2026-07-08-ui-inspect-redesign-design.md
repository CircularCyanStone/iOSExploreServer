# ui.inspect 重新设计（原 ui.viewTargets）

> 日期：2026-07-08
> 状态：设计已确认（含评审修正），待写实现计划
> 相关问题：`docs/investigations/mcp-spim-example-e2e-issues.md` P9（viewTargets 不收集 cell 内 UILabel）
> 触发场景：2026-04-28 端到端测试"点击滚动测试 cell"时，viewTargets 无法按文字定位 cell

## 修订记录

- **v1**（2026-07-08）：初版设计
- **v2**（2026-07-08）：根据 subagent 源码评审修正 3 处实现硬伤 + 补全遗漏：
  - ① **maxTargets 截断矛盾**（原 §5 自相矛盾）→ 改为"截断只数 full 节点，minimal 不占配额"
  - ② **not_actionable 无实现路径**（原 §3.7）→ 补 `isPathSigned` 方法 + core `ExploreError` 加 case + control.sendAction 同处理
  - ③ **summary 值类型字段无法 null**（原 §3.2 低估）→ 补 `toJSON` 按 `isMinimal` 分档，模型字段不改 Optional
  - 补：5 处运行时用户可见字符串改名、`UIKitFingerprintCollector`/wait 重采链路、`matchesIdentifier` 语义、collector 日志、candidate 死字段、`inspectOptions` 字段名
- **v3**（2026-07-08）：根据 v2 二次评审补 3 处非阻塞微调 + 2 处矛盾记录：① §5 增补 `maxVisitedNodes` 防 minimal 深树失控；② §3.7 明确 `isPathSigned` 三态语义（unknown/expired id 返回 true 交 isStale 裁决）；③ §4.1 补第 6 处字符串（UIKitCommandFields L58）+ `UIKitCommandError.notActionable` 工厂；④ §3.3 修正心智模型（full 静态节点也可能 actions=[]）；⑤ §5 记录 matchesWholeTable 截断误报边界

## 1. 背景与问题

### 1.1 直接症状

在 SPMExample 主页调 `ui.viewTargets`，主菜单 `root/5` 下 4 个 `UIListContentView` cell 的 `text` / `accessibilityLabel` / `semanticText` **全部为 null**。agent 无法通过"滚动测试"这种自然语言文本反查到目标 cell 的 path。`ui.scrollToElement {"match":"text","value":"滚动测试"}` 也因此无法定位（P1 同源）。

### 1.2 根因

`UIViewTargetsModels.shouldInclude`（L137-145）是严格的**白名单**口径，只放行三类节点：

```swift
if candidate.isControl { return true }
if candidate.isScrollView { return true }
if candidate.hasGestureRecognizers { return true }
return false
```

cell 标题文字落在子 `UILabel` 上，UILabel 不是 control、不是 scrollView、通常无 gesture，被 `return false` 滤掉。注释（L129-131）明确写"`includeStaticText`/`includeContainers`/`includeDisabled` 保留 schema 兼容，但 canonical-only 规则下不再让静态/容器 view 进入 targets"——即这三个入参被故意降级为**死字段**，传不传都不生效（实测 `includeStaticText=true/false` 输出完全一致）。

### 1.3 隐藏的更深层问题：层级断裂

白名单过滤不仅丢了文字，还让输出**层级断裂**。当前 viewTargets 输出 `root/5/0/1`（cell 内容容器），但它的父 `root/5/0`（UITableViewCell）、子 `root/5/0/1/0`（UILabel）都不在输出里。agent 看到 path 只能靠数字推断父子关系，看不到树结构——这比"cell 没文字"更根本。

### 1.4 当前两极分化

- `ui.viewTargets`：太轻——没文字、层级断裂，无法按自然语言定位
- `ui.topViewHierarchy`：太重——全量节点 + appearance/bounds/state 重字段，token 爆炸

agent 缺中间形态：**层级完整 + 轻字段 + 带文字 + 可操作标注**。

## 2. 设计目标

把 `ui.viewTargets` 重新定位为 **"当前页面探索主入口"**，一次调用同时满足：
1. **看结构**——理解页面层级（cell 在 table 里、label 在 cell 里）
2. **找目标**——按文字/类型定位要操作的节点
3. **拿 path**——给 `ui.tap` / `ui.control.sendAction` / `ui.input` 用

## 3. 方案详述

### 3.1 命名：`ui.viewTargets` → `ui.inspect`

动词风格，与 `ui.tap` / `ui.scroll` 一致；"检视"语义涵盖看结构 + 找目标 + 识别。与 `ui.topViewHierarchy`（深度诊断、重字段）形成清晰分工。

### 3.2 节点输出：全节点 + full/minimal 两档

collect 递归**遍历全节点**（不再用 `shouldInclude` 决定收不收），但每个节点按"有没有识别信息 / 可不可操作"分两档收集字段：

| 档位 | 判定（任一为 true） | 收集字段 | fingerprint | 可 tap |
|---|---|---|---|---|
| **full** | `isControl` / `isScrollView` / `hasGestureRecognizers` / `hasStaticText` / `hasAccessibilityLabel` / `hasAccessibilityIdentifier` | 完整：path + type + frame + text + a11y + actions + indexPath | 签发 | 是 |
| **minimal** | 以上全 false | 仅 path + type | 不签发 | 否（强制 `actions=[]`） |

判定用的字段 `UIViewTargetCandidate` 已全部具备（含 rollup 用的 `isInControlSubtree`）。

**rollup 例外（控件内嵌展示节点不独立 full）**：`hasStaticText` 的节点若同时 `isInControlSubtree`（自身非 `UIControl`、祖先链含 `UIControl`，典型如按钮内部渲染 title 的 `UIButtonLabel`），**不作为独立 full target**——其文本已通过父 control 的 `semanticText`（buttonTitle 等）汇总给父 target，独立签发只会让 agent tap 到返回 `unsupported_target` 的死节点，破坏"签发=可操作"不变式。该节点 rollup 到父 control，不进 targets、不签发 fingerprint。

**控件子树整棵剪枝（实现细节，Task 6）**：实际实现中，`UIControl` 子树内**所有非 full 节点**（含 rolled-up 展示节点 + 内部结构节点如 background）整棵剪枝（`guard !isInControlSubtree else { return .none }`），既不作为 full 也不作为 minimal 输出。理由：控件是原子操作单元，内部渲染细节（label/background）对 agent 理解页面结构无价值，输出只增加噪音；且 rollup 节点若作为 minimal 输出会破坏 §3.6"rollup 节点不进返回集合"不变式。这是 rollup 例外在 minimal 层的延伸。`collect(view:)` 返回 `CollectionTruncation` 枚举，`.none` 表示本枝未截断（含 hidden 剪枝、control 子树剪枝、自然到叶、maxDepth 到顶），`.maxTargets`/`.maxVisitedNodes` 向上传播供顶层设 `truncationReason`。cell 子树不受影响（见下）。

cell 子树不受 rollup 影响：`UITableViewCell`/`UICollectionViewCell` **不是** `UIControl`，cell 内 label 的 `isInControlSubtree=false`，仍按 `hasStaticText` 进 full（spec §3.4 核心：cell 内 UILabel 可被 agent 直接 tap）。独立 label（不在 control/cell 子树，如页面标题）祖先无 `UIControl`，同样仍 full。

**模型表达（评审硬伤 ③ 修正）**：`UIViewTargetSummary` 现有 `frame`/`state`/`role` 是非 Optional 值类型，结构上不能为 null。处理方式：
- **模型字段不改 Optional**（避免波及所有构造点和测试）
- 给 `UIViewTargetSummary` 加 `isMinimal: Bool` 标记
- `toJSON()` 按 `isMinimal` 分档：minimal 只输出 `{path, type}`（frame/state/role/text/a11y/actions/indexPath 在 JSON 中**缺席**，不输出为 null）；full 输出全部字段

agent 看到的 minimal 节点就是 `{path, type}` 两个键，干净。

### 3.3 minimal 节点强制 `availableActions=[]`

cell 内的 `_UISystemBackgroundView` 在 cell 子树里，按 `cellAncestor` 规则（`UIKitActionCapabilityResolver` L61-63）实际能触发 cell 选中（capability 给 `['tap']`）。但它无识别价值，若让它保持 `['tap']` 又归 minimal（不签 fingerprint），会出现"声明可点但 tap 报 path missing"的矛盾。

因此 **minimal 节点的 `availableActions` 强制为 `[]`，覆盖 capability 结果**（在 collector `summary(for:)` 的 minimal 分支直接给 `UIKitActionAvailability(actions: [])`，不调 capability resolver）。agent 心智模型（注意：full 节点也可能 `actions=[]`）：
- `actions` 非空 → 可直接 tap（full 节点，已签 fingerprint）
- `actions=[]` → 该节点不可直接 tap。分两种：minimal 结构节点（未签 fingerprint，tap 返回 `not_actionable`）；或 full 但无默认激活路由的静态节点（如页面标题 label——有文字进 full，但 capability 为空，tap 走 `isPathSigned=true` → execute → `unsupported_target`）
- 要操作始终找 `actions` 非空的目标

### 3.4 cell 内 UILabel 自动可 tap（复用现有 cellAncestor 机制）

`UIKitActionCapabilityResolver` L61-63 已实现：cell 子树内任何 view（含 UILabel）都声明 `tap`，走 cellSelection adapter 触发 `didSelectRow`。改版后 cell 内 UILabel 进 full（有文字），其 `availableActions` 自动是 `['tap']`，**agent 直接 tap label 即选中 cell**，无需"上溯找 cell 容器"。

> **既有风险备注**：`UIGestureTargetExecutor.executeCellSelection` 标了 `[SPIKE]`，依赖 runtime 私有 ivar 派发 didSelectRow。这是既有设计风险，非本次引入；若某 iOS 版本私有 ivar 漂移，cell 内 label tap 会 fallthrough 到 `unsupported_target`。本次不处理，记录在案。

### 3.5 fingerprint 签发范围：只签 full

collector 当前只为最终返回的 target 签发 fingerprint（`UIViewTargetsCollector.collect` L52-67）。改版后：**只为 full 节点签发**，minimal 节点不签发。这保持"签发集合 = 可操作集合"，且 minimal 节点不消耗 fingerprint 容量。

### 3.6 不变式变化

| | 旧 | 新 |
|---|---|---|
| 返回集合 | = 签发集合 = 可操作集合 | ⊇ 签发集合 = 可操作集合 |
| 含义 | 只返回 canonical | 返回全节点（含 minimal 结构节点），minimal 仅供看结构 |

minimal 节点出现在返回里（维持层级），但不可操作。

**rollup 节点（按钮内 label）不签发**：控件内嵌展示节点（hasStaticText + isInControlSubtree）rollup 到父 control，既不进返回集合也不签发 fingerprint——它们不是独立 target。full 节点里"纯展示但有识别信息"的（独立 label、仅 `accessibilityIdentifier` 的 view）仍签发，这是为让 agent 识别/定位；但其 tap 可能返回 `unsupported_target`（如无默认激活路由的静态标题 label）。agent 心智模型：要操作始终找 `availableActions` 非空的目标（§3.3）。

### 3.7 minimal 节点 tap/control 的错误处理（评审硬伤 ② 修正）

**现状**：executor `validateViewSnapshot`（`UIKitActionExecutor.swift` L97-112）→ `UIKitSnapshotStore.isStale`。`isStale` 只返回 `Bool`，path 不在指纹表时返回 `true` → 抛 `staleLocator` → envelope `stale_locator`。

**问题**：`isStale` 不区分"path 从未签发（=minimal，应报 not_actionable）"和"签发过但过期/变化（=stale_locator）"。

**实现路径**（不改 `isStale` 现有签名，避免波及调用方）：
1. `UIKitSnapshotStore` 新增 `isPathSigned(viewSnapshotID:path:) -> Bool`——查询该 path 是否在指纹表内（纯读，不改 LRU/TTL）。**三态语义（关键）**：unknown/expired snapshotID（entries 无该 id）→ 返回 **true**（视为"可能签发过，交 `isStale` 裁决 `stale_locator`"，引导 agent 重新 inspect）；snapshotID 有效但 path 不在指纹表 → 返回 **false**（`not_actionable`）。即只有"id 有效 + path 确实未签发"才判 not_actionable，避免传错/过期 id 误报 not_actionable 误导 agent 去找别的目标。
2. executor（`ui.tap` **和** `ui.control.sendAction`，都走 `validateViewSnapshot`）在 freshness 校验前先查 `isPathSigned`：
   - `false` → 抛新错误码 `not_actionable`（"该节点不可操作，availableActions 为空，请在 ui.inspect 结果里找 availableActions 非空的目标"）
   - `true` → 走 `isStale` 查 freshness，陈旧则 `stale_locator`
3. core `Sources/iOSExploreServer/Models.swift` 的 `ExploreError`（L145 附近）新增 `not_actionable` case——它是通用业务码（"目标不可操作"），非 UIKit 专属，放 core 符合"core 不依赖 UIKit"原则

### 3.8 schema 清理：删除三个死字段 + 连带清理

`includeStaticText` / `includeContainers` / `includeDisabled` 在 canonical-only 规则下早已不生效。改版后"全节点输出"完全取代了它们的语义，应从 `UIViewTargetsInput` 与 inputSchema 中删除。

**连带清理**（评审发现）：
- `UIViewTargetsCollector.swift` L24 的**日志插值**硬编码了 `includeDisabled=\(...) includeStaticText=\(...) includeContainers=\(...)`，删字段后编译失败，同步改为记录 `fullCount`/`minimalCount`
- `UIViewTargetCandidate` 的 `isEnabled`（L177）和 `hasSubviews`（L189）在 `isFull` 六条规则里都不被读，变纯死字段，按 AGENTS.md「开发期不留妥协设计」一并删除

保留：`includeHidden`（仍控制隐藏剪枝）、`maxDepth`、`maxTargets`、`accessibilityIdentifier`、`accessibilityIdentifierPrefix`、`textLimit`。

### 3.9 静态工具清理：废弃 observe，简化 wait_and_observe

- **废弃 `observe`**：它内部就是调 viewTargets，改名后 `ui_inspect` 动态工具已可直接用，observe 是多余封装层。从 `MCPServer/src/staticTools.ts` 移除。
- **`wait_and_observe` → `wait_and_inspect`**：保留"wait 条件命中后自动 inspect"的组合便利语义，仅把内部 `ui.viewTargets` 调用改为 `ui.inspect`、名字同步更新。不并入 `ui.wait`——组合工具仍有独立价值。
- **`wait_and_observe` schema 的 `viewTargetsOptions` 嵌套字段名 → `inspectOptions`**（description 同步更新），保持命名一致。

### 3.10 matchesIdentifier 语义（评审 N2，新增）

全节点输出下，`accessibilityIdentifier` 筛选的语义需要明确：**identifier 筛选只作用于 full 节点的输出与签发；minimal 结构节点不受筛选**（用于维持层级完整）。

即：当 agent 传 `accessibilityIdentifier` 筛选时，不匹配的 full 节点不输出；但 minimal 结构节点照常输出（维持树结构），只是它们本来就没有 a11y。这避免了"带筛选查询时层级断裂"（否则又回到 §1.3 问题）。

## 4. 影响面

### 4.1 需要改

| 模块 | 改动 |
|---|---|
| `Sources/iOSExploreServer/Models.swift`（**core**） | `ExploreError` 新增 `not_actionable` case（评审硬伤 ②） |
| `UIViewTargetsModels.swift` | `shouldInclude` 改为 `isFull` 判定；删三个死字段 + candidate 死字段（isEnabled/hasSubviews）；`UIViewTargetSummary` 加 `isMinimal` 标记 |
| `UIViewTargetsCollector.swift` | collect 全节点输出、分档签发（只签 full）；summary 分 full/minimal 两档（minimal 强制 `actions=[]`）；L24 日志改 fullCount/minimalCount；`matchesIdentifier` 语义按 §3.10 |
| `UIViewTargetSummary.toJSON` | 按 `isMinimal` 分档输出（评审硬伤 ③） |
| `ViewTargetsCommand.swift` | action 名 `ui.viewTargets` → `ui.inspect` |
| `UIKitActionExecutor.swift` | tap/control 在 freshness 前先查 `isPathSigned`，false 抛 `not_actionable`（评审硬伤 ②） |
| `UIKitSnapshotStore.swift` | 新增 `isPathSigned(viewSnapshotID:path:)` 方法（不改 `isStale` 签名） |
| `UIKitFingerprintCollector.swift` | `shouldInclude` → `isFull` 改名连带（`collectMatching` 筛选语义同步）；验证 `ui.wait(snapshotChanged)` 重采仍正确比对 |
| `UIKitCommandRegistrar.swift` | 注册名同步 |
| **6 处运行时用户可见字符串**（agent/MCP 实际读得到）| `UIKitCommandError.swift` L41 staleLocator message "call ui.viewTargets first..." → "ui.inspect"；`UIKitCommandFields.swift` L58 path description（含 "ui.viewTargets"）+ L69 viewSnapshotID description；`UIWaitModels.swift` L60 viewSnapshotID description；`UITapModels.swift` L32 extensionMessage；`UIControlSendActionModels.swift` L63 extensionMessage |
| `UIKitCommandError.swift` | 新增 `notActionable` 工厂方法（与 `staleLocator` 工厂同模式，code 用 core 新增的 `not_actionable`） |
| `MCPServer/src/staticTools.ts` | 废弃 observe；wait_and_observe → wait_and_inspect；viewTargetsOptions → inspectOptions |
| 测试 | 所有 viewTargets 测试改 inspect；新增 full/minimal 判定、minimal tap/control 返回 not_actionable、截断只数 full、snapshotChanged 重采、cell 内 label 可 tap 的回归 |
| 文档 | `AGENTS.md` 命令清单、`docs/uikit/*`、`MCPServer/README.md`、`MCPServer/docs/local-mcp-test.md` |

### 4.2 不需要改（已确认解耦或自带支持）

| 模块 | 原因 |
|---|---|
| `UIKitActionCapabilityResolver` | cellAncestor 机制已让 cell 子树 UILabel 声明 tap，改版后自动生效 |
| `UIKitInternalUtils.explore_cellAncestor` | 已存在且覆盖 UILabel（评审断言 1 验证） |
| `UIScrollToElementExecutor` | `findTargetDepthFirst` 独立搜 UILabel.text，不读 viewTargets 输出，完全解耦 |
| `UIKitContextProvider` | rootView = topViewController.view 边界不变 |
| `ui.topViewHierarchy` | 定位保持"完整视图树诊断 + 重字段"，不动 |

## 5. 边界与降级

- **maxTargets 截断（评审硬伤 ① 修正）**：全节点输出后 target 数增加（主页约 90-140 节点，视 App 状态；其中 full 约 24、minimal 约 70-110）。**截断只数 full 节点，minimal 不占配额**——DFS 递归时 minimal 节点照常收集输出，但不递增 full 计数；只有 full 节点触发 `maxTargets` 检查。这保证"所有 full 节点都在返回集合内"（minimal 不会挤掉深层可操作 full），且 minimal 即便因 maxTargets 截断未返回也不影响"签发 ⊆ 可操作"一致性。
- **minimal 节点上限（防深树失控）**：maxDepth 默认无限、includeHidden 只剪隐藏子树，嵌套深容器（多层 stackView）可产生上千 minimal。新增 `maxVisitedNodes` 上限（独立于 maxTargets），DFS 访问节点数触顶即停，防递归过久/token 膨胀。
- **fingerprint 容量**：单快照上限 512。只签 full，full 约 24 个远低于上限。触顶时 `viewSnapshotID=null`（不阻断，仅丢陈旧防护）。
- **matchesWholeTable 截断边界（已知限制）**：`ui.wait(snapshotChanged)` 全表相等比较，但重采（`collectMatching`）不遵循 maxTargets 截断。full 数超 maxTargets 时 stored（截断）≠ current（全量）→ 误报"已变化"。默认 full≈24 不触发；极端深树触发属已知限制。
- **UIImageView**：本次无 a11y 的 UIImageView 归 minimal。若后续需识别图片内容，加 `hasImage` 规则。YAGNI，先不做。

## 6. 不在本次范围

- `ui.topViewHierarchy` 的字段/定位调整（保持现状）
- cell 容器文字"回填"（cell 内 UILabel 已是 full 且可 tap，无需额外回填到 UIListContentView）
- `ui.scrollToElement` 改造（已解耦）
- `hasImage` / UIImageView 识别（YAGNI）
- `executeCellSelection` 的 [SPIKE] 私有 ivar 风险（既有，非本次引入）

## 7. 验证计划

1. **单元测试**（macOS `swift test`）：
   - `isFull` 判定覆盖六条规则各分支
   - minimal summary `toJSON` 只含 path+type（评审硬伤 ③）
   - minimal 强制 `actions=[]`
   - fingerprint 只签 full、不签 minimal
   - **截断只数 full**：构造 nodeCount > maxTargets 的树，确认深层 full 不丢、minimal 不占配额（评审硬伤 ①）
   - `isPathSigned` 查询正确（评审硬伤 ②）
2. **iOS framework 测试**（`xcodebuild test`）：
   - cell 内 UILabel 进 full 且 `availableActions=['tap']`
   - minimal 节点 tap / control.sendAction 返回 `not_actionable`
   - **snapshotChanged 改版后仍正确比对**（重采链路）
3. **端到端**（重做 2026-04-28 的点击滚动测试 cell 流程）：
   - `ui_inspect` 能直接看到"📜  滚动测试"文字（在 cell 内 UILabel 上）
   - agent 直接 tap 该 UILabel path → 成功 push 到 ScrollTestViewController
   - 无需退到 `ui.topViewHierarchy` 二次解析
4. **回归**：scrollToElement、wait(snapshotChanged)、control.sendAction 不受影响

## 8. 风险

- **token 增加**：全节点输出使单次响应变大（主页 full 约 24 + minimal 约 70-110）。mitigation：minimal 只 path+type 两键，字段极简；实测确认 agent 上下文可承受。
- **action 改名破坏现有调用**：5 处运行时字符串 + toolName 映射 + 文档/测试。mitigation：开发期无外部兼容承诺，一次性改全；grep 确认无遗漏（评审已列出 5 处字符串）。
- **动 core 库**：`ExploreError` 加 `not_actionable` case 是跨模块改动。mitigation：`not_actionable` 是通用业务码，放 core 符合"core 不依赖 UIKit"；core 测试同步补。
- **minimal 强制 actions=[] 与 capability 不一致**：cell 内 background 实际可 tap（cellAncestor）但 viewTargets 显示 `[]`。mitigation：agent 不会点无文字的 background，点 UILabel（full+可 tap）是更自然路径；"actions 非空才可点"对 agent 更清晰。
- **executeCellSelection [SPIKE]**：依赖私有 ivar，iOS 版本漂移会让 cell 内 label tap 退化为 unsupported_target。既有风险，本次不处理。
