# ui.* 命令调用契约改进（agent / MCP / Skill 侧）

> 2026-07-05 · spec
> 范围：补齐 `ui.*` 命令在调用方契约与 cell 定位信息上的三处空缺，让 MCP server 封装者、Skill 编写者、agent 自动化脚本能"一次读对、不用试错"。
> 同主题的调用方侧经验总结见 [docs/uikit/agent-command-protocol.md](../../../uikit/agent-command-protocol.md)。

## 1. 背景与问题

2026-07-05 用 `ui.tap` 点 SPMExample 菜单第三项「日志诊断测试」时，agent 思考链异常冗长（近 20 步），且前两次落点错成"弹窗测试 cell"。复盘发现根因有两层：

- **调用方层（agent 自身责任）**：把 `ui.topViewHierarchy` 返回的 `UITableView.subviews` 数组顺序当成 `indexPath` 顺序。UITableView 有 cell 复用机制，subviews 数组顺序与 `indexPath` 数据顺序无关。
- **库契约层（库可改进的责任）**：库在 cell 场景没给调用方足够信息直接锁定目标，迫使调用方靠 path+frame 间接推断，间接推断恰好是误判高发区。

本文聚焦后者——**库契约层补什么能免调用方误判**。

## 2. 目标与非目标

**目标：**

- 调用方读完 `ui.topViewHierarchy` 就能直接选定目标 cell，无需靠 subviews 顺序或 y 坐标猜 indexPath。
- 调用方读完 `ui.viewTargets` 就能直接区分无 `accessibilityIdentifier` 的 cell，无需再钻 topViewHierarchy 四级子节点读标题。
- 调用方拿到 `ui.tap` schema 即知"必须先 `ui.viewTargets` 再 tap"的两步契约，无需靠报错试错。

**非目标：**

- 不改 `ui.tap` 的执行语义、route 派发、陈旧防护。
- 不改 `ui.viewTargets` 的 canonical-only 口径（`UITableViewCell` 仍不进 targets 列表）。
- 不改 `iOSExploreServer` core 协议层。

## 3. 三条改进（按价值排序）

### 改进 1：`ui.topViewHierarchy` 给 cell 节点带 `indexPath`

**痛点**：调用方读层次结构时，`UITableViewCell` 节点没有 `indexPath` 字段，必须靠 subviews 顺序或 y 坐标猜哪一个是哪一项。两者都不可靠。

**方案**：`UIViewHierarchyCollector` 收集到 `UITableViewCell` / `UICollectionViewCell` 节点时，调用 `tableView.indexPath(for: cell)` 拿到 `IndexPath`，序列化为 `{ "section": N, "item": M }` 加进节点输出。

**收益**：调用方读层次时一眼看到 `indexPath`，直接按 indexPath 选 cell，**根治本次误判**。

**风险**：`indexPath(for:)` 在 cell 正在动画 / 不在 visible 区域时可能返回 nil；nil 时不写 `indexPath` 字段（语义保持"无 indexPath 信息"），不报错。

### 改进 2：`ui.viewTargets` 给 cell / list 节点带 `primaryText` / `cellTitle`

**痛点**：`ui.viewTargets` 默认 `includeStaticText=false`，cell 的标题文本不在响应里；调用方拿到的是无 text、无 id 的 `UIListContentView`，无法直接区分三项 cell。

**方案**：`UIViewTargetsCollector` 收集到 `UITableViewCell` / `UICollectionViewCell` 子树内目标（如 `UIListContentView`）时，回溯其父 cell，从 cell 的 `textLabel` / `UIListContentView` 内第一个 `UILabel` 抽出主标题，写入 target 的 `primaryText` 字段（不破坏现有 `text`/`title`/`semanticText` 语义——`primaryText` 是新字段，专门给"父 cell 的主标题"用）。

**收益**：调用方调 `ui.viewTargets` 直接拿到 cell 标题，免钻 topViewHierarchy 四级子节点。

**风险**：cell 标题抽取口径需谨慎（如 `UICollectionViewListCell` 用 `UIListContentView`，老式 cell 用 `textLabel`）；抽取失败时 `primaryText=null`，不报错。

### 改进 3：`ui.tap` 的 description 显式写明两步契约

**痛点**：当前 `ui.tap.inputSchema` 对 `viewSnapshotID` 的描述只是"ui.viewTargets 签发的结构化 target 指纹快照标识"，没说"调用前必须先 `ui.viewTargets`"。agent 只能靠 `viewSnapshotID is required` 报错才意识到。

**方案**：把 `ui.tap` / `ui.control.sendAction` / `ui.input` 的 `action` description 在 `UIKitCommandRegistrar` 注册处补成完整的两步流程说明，例如：

> `ui.tap`：在 view 层次或目标列表已发现的目标上执行默认激活。**调用前必须先调 `ui.viewTargets` 或 `ui.topViewHierarchy`，并把同响应返回的 `viewSnapshotID` 原样传入本命令。**

可选：新增 `ui.tapByPath`（吃 path、内部自取最新快照、一步到位），降低两步契约丢失概率。是否做此项需评估陈旧防护绕过的风险（自取快照绕过了调用方主动刷新的语义），倾向于**不做**——两步契约本身是对的，留在 description 写清楚即可。

**收益**：调用方读 help / schema 即知流程，不用试错。

**风险**：description 变长，但 help 输出仍可读；无运行时风险。

## 4. 实施顺序

- 改进 1（topViewHierarchy 加 indexPath）**最关键**，先做。完成后用 SPMExample 菜单验证：读层次即可知 cell.item，不再靠 y 排序。
- 改进 2（viewTargets 加 primaryText）次之。
- 改进 3（description 写明两步契约）最后做，纯文档改动。

## 5. 验证

- 改进 1 完成后，agent 重跑"进入日志诊断测试"流程：发 `ui.topViewHierarchy` → 直接读到 cell.indexPath=2 → 选定 cell → 发 `ui.viewTargets` → `ui.tap`，思考链应从 ~20 步降到 ~5 步，且不再出现"靠 y 排序猜"或"靠 subviews 顺序猜"的中间推理。
- 改进 2 完成后，agent 调 `ui.viewTargets` 应能在响应里直接读到三项 cell 的 `primaryText`，区分无需钻层次。
- 改进 3 完成后，`help` 输出的 `ui.tap` description 应包含"必须先调 ui.viewTargets"字样。

## 6. 不属于本文档范围

- **调用方侧经验沉淀**（标准 curl 时序模板、字段名速查、SPMExample 菜单 cell 与 path 的实测对应表、cell 复用导致 subviews 顺序 ≠ indexPath 顺序的成因解释）见 [docs/uikit/agent-command-protocol.md](../../../uikit/agent-command-protocol.md)。该文档面向 MCP / Skill / agent 调用方，本 spec 只跟踪库侧改进。
- **UITableViewCell cell selection 触发机制**（`didSelectRow` 私有入口、gesture adapter 路径）是另一条独立 spec，见 [2026-07-05-uitableviewcell-tap-selection-design.md](./2026-07-05-uitableviewcell-tap-selection-design.md)。
