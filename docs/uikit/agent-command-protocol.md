# iOSExplore `ui.*` 命令调用契约（agent / MCP / Skill 构建者必读）

> 这份文档专门给**调用方**看：MCP server 封装者、Skill 编写者、agent 自动化脚本。
> 它不解释库内部实现，只回答"我要从外部发 curl 调 `ui.*` 命令时，每个命令的前置条件是什么、调用顺序怎么排、哪些坑会把 agent 带偏"。
> 内部实现阅读指南见 [reading-guide.md](./reading-guide.md)。

## 0. 一句话总览

`ui.*` 命令不是孤立的 HTTP 接口，它们之间有**严格的前置/后置关系**。最常见的错误模式是：跳过前置命令、直接发交互命令（`ui.tap` / `ui.control.sendAction` / `ui.input` / `ui.scroll`），结果拿到 `viewSnapshotID is required` 报错，然后开始盲试参数。

正确的心智模型是：

```
[发现阶段]                    [定位 + 陈旧防护阶段]        [执行阶段]
ui.topViewHierarchy  ──┐
ui.viewTargets     ────┼──>  选定 path/identifier  ──>  ui.tap
                       │     + 拿 viewSnapshotID         ui.control.sendAction
                       │                                  ui.input
                       └──>  对照层次结构选目标            ui.scroll
                                                            ui.alert.respond
```

**铁律**：任何 `ui.*` 交互命令执行**之前**，**必须**先在同一个 UI 稳定状态下调用过一次发现命令。`ui.tap` / `ui.control.sendAction` 必须带 `ui.viewTargets` 签发的 `viewSnapshotID`；`ui.input` / `ui.scroll` 只有在 `path` 定位时可选带 `viewSnapshotID` 做陈旧校验，identifier 定位不能带 `viewSnapshotID`。
**铁律二**：执行命令之后如果换了页面、或想点新的目标，**必须重新**调用发现命令；带旧 `viewSnapshotID` 给新页面目标会触发 `stale_locator`。

**两个发现命令怎么选**（决策树）：

| 你要做什么 | 用哪个 | 原因 |
|---|---|---|
| 要执行 `ui.tap` / `ui.control.sendAction`，或给 `ui.input` / `ui.scroll` 的 path 定位做陈旧校验 | `ui.viewTargets` | 它签发 `viewSnapshotID`；`topViewHierarchy` 不签发，不能直接接 tap/control |
| 选 table/collection 的某行 cell | `ui.viewTargets` | cell 子 view 带 `indexPath`，直接按 `indexPath.item` 选行 + 同响应拿 `path` + `viewSnapshotID` 单命令 tap |
| 已知 `accessibilityIdentifier` 想确认 view 是否可达 | `ui.viewTargets` | 轻、扁平；只返回 canonical target |
| 看页面整体结构、容器嵌套 | `ui.topViewHierarchy` | 嵌套 root 树，覆盖全量 view |
| 看 view 颜色 / 字体 / 图片 / 控件状态等验收字段 | `ui.topViewHierarchy` | `detailLevel=appearance/full` 含这些字段 |
| 给定 identifier 反查 + 想要 matches 模式精简输出 | `ui.topViewHierarchy` | 带 identifier 时切 `matches` 模式 |
| 只看 cell 与 indexPath 映射、无后续 tap 意图 | `ui.topViewHierarchy` | cell 节点本身带 indexPath，结构接近视图树，便于排障 |

> 一句话：**`viewTargets` 用于"操作"，`topViewHierarchy` 用于"观察"**。需要 `viewSnapshotID` → viewTargets；需要看完整结构/验收字段 → topViewHierarchy。

下表是各命令的前置/后置关系速查：

| 命令 | 前置发现命令 | 必须从发现命令带上的字段 | 执行后是否换页 / 改视图 |
|---|---|---|---|
| `ui.topViewHierarchy` | 无 | — | 否（纯读） |
| `ui.viewTargets` | 无 | — | 否（纯读，**签发 `viewSnapshotID`**） |
| `ui.tap` | `ui.viewTargets`（强） | `viewSnapshotID` + (`path` 或 `accessibilityIdentifier`) | 是（可能 push / pop / 弹窗） |
| `ui.control.sendAction` | `ui.viewTargets`（强） | `viewSnapshotID` + (`path` 或 `accessibilityIdentifier`) + `event` | 通常否，但 control 状态会变 |
| `ui.input` | `ui.viewTargets`（推荐） | `text` + (`path` 或 `accessibilityIdentifier`)；仅 `path` 可选带 `viewSnapshotID` | 否（仅文本） |
| `ui.scroll` | `ui.viewTargets` | `direction`；定位字段+`viewSnapshotID`（如要滚特定 view） | 否（仅滚动） |
| `ui.scrollToElement` | `ui.topViewHierarchy`（推荐先看一眼） | `value` + `match` | 否（仅滚动） |
| `ui.screenshot` | 无 | — | 否（纯读） |
| `ui.alert.respond` dryRun=true | 无（不过通常先 `ui.topViewHierarchy` 看是否真的弹了 alert） | — | 否（dryRun=true 纯查询） |
| `ui.alert.respond` dryRun=false | 是（必须先有 dryRun=true 看清楚按钮） | `buttonTitle` / `buttonIndex` / `role` 之一 | 是（关闭 alert） |
| `ui.navigation.back` | 无（但建议先 `ui.topViewHierarchy` 确认 `backAvailable`） | — | 是 |
| `ui.navigation.tapBarButton` | `ui.topViewHierarchy`（看 `navigationBar.rightItems/leftItems`） | `placement` + `index` | 是 |
| `ui.keyboard.dismiss` | 无 | — | 否 |
| `ui.wait` | 无（它就是用来等发现的） | `mode` + 条件字段 | 否 |
| `ui.waitAny` | 无 | `conditions` 数组 | 否 |

---

## 1. `viewSnapshotID` 契约（最容易绕弯的点）

### 1.1 它是什么、为什么必须有

`viewSnapshotID` 是 `ui.viewTargets` 响应里**签发**的一个字符串（形如 `snap-9`），代表"那一瞬间 view 树的指纹快照"。后续 `ui.tap` / `ui.control.sendAction` 强制要求带上它；`ui.input` / `ui.scroll` 只有在 `path` 定位时可选带上它。原因在 [reading-guide.md 第 3 步](./reading-guide.md)：执行 click 期间 UI 可能正在异步变化（动画、异步 reload），用旧 path 找当前 view 不一定对，所以要校验"执行时的 view 树指纹 == 发现时的指纹"，否则报 `stale_locator`。

### 1.2 调用方必须记住的三条

1. **`viewSnapshotID` 是 `ui.viewTargets` 响应的字段名**，不是 `snapshotID`、不是 `snapshotId`、也不是 `ui.topViewHierarchy` 的字段。schema 里所有相关字段都叫 `viewSnapshotID`，请求和响应同名。
2. **同一次"发现 → 执行"链路必须用同一份 `viewSnapshotID`**。如果你发了 `ui.viewTargets`、又在中间发了 `ui.topViewHierarchy`，两者签发的快照不一定一致——以**最后一次发现命令**返回的快照为准。安全实践：发现和执行之间不要插入其它会签发新快照的命令。
3. **执行命令一旦换页**（push / pop / 弹 alert / 切 tab），**之前**的 `viewSnapshotID` 失效。下一次交互必须重新 `ui.viewTargets`。

### 1.3 常见报错与对应处理

| 报错 | 原因 | 处理 |
|---|---|---|
| `viewSnapshotID is required` | 没传 `viewSnapshotID` 字段 | 先调 `ui.viewTargets` 拿到，再带上发 `ui.tap` |
| `unknown command input field 'snapshotID'` | 字段名拼错成 `snapshotID` | 改成 `viewSnapshotID` |
| `stale_locator` | 快照已过期（页面变了） | 重新调 `ui.viewTargets` 拿新的 `viewSnapshotID` |
| `unknown command input field 'identifier'` | 把 `accessibilityIdentifier` 写成 `identifier` | 改成 `accessibilityIdentifier` |
| 视图明明在，viewTargets 这次没采到 / targetCount 偏少 | 目标处于 `reloadData` 等瞬时空档，subviews 短暂为空 | 重试一次 `ui.viewTargets` 即可，不需要推理变化。**非 bug**：业务侧高频 reload（如 SPMExample 日志面板每次 server 事件都 reloadData+scrollToRow）会在两次 cell 挂载之间留下"无 cell"瞬间，collector 按调用瞬时状态如实采，自然有时采不到。 |

> 「targetCount 抖动」典型表现：相邻两次 `ui.viewTargets` 调用，targetCount 在两个固定值之间跳（如 11 ↔ 29，差值恰好等于某个 UITableView 的可见行数 + accessory）。subagent 端到端跳转案例里遇到过（2026-07-05），未影响最终 tap——用最后一次干净快照即可。

### 1.4 字段名速查（这几个最容易写错）

| 正确字段名 | 含义 | 容易写错成 |
|---|---|---|
| `viewSnapshotID` | view 指纹快照 ID（viewTargets 签发） | `snapshotID` / `snapshotId` / `viewSnapshotId` |
| `accessibilityIdentifier` | 控件的 a11y 标识 | `identifier` / `accessId` |
| `accessibilityIdentifierPrefix` | a11y 前缀筛选 | `identifierPrefix` |
| `path` | view 在树里的位置，如 `root/5/0/1` | `viewPath` |
| `buttonTitle` | alert 按钮标题（ui.alert.respond） | `title` |
| `buttonIndex` | alert 按钮下标 | `index` |

---

## 2. cell 定位：`UITableView` / `UICollectionView` 的正确打开方式

**这是 agent 最容易错的地方**，反复出现过"把弹窗测试 cell 误判成日志诊断测试 cell"的案例。问题集中在两个误区：

### 2.1 误区一：靠 subviews 物理顺序推断 indexPath

`ui.topViewHierarchy` 返回的 `UITableView` 节点 `subviews` 数组顺序，**不等于** `indexPath` 顺序。UITableView 有 cell 复用机制：visible cells 里 subviews 的物理顺序受复用、Auto Layout、以及 cell 出现时机影响，**可能完全和数据顺序不一致**。

**真实案例**（2026-07-05，SPMExample 菜单）：

menu 列表数据顺序是：`[弹窗测试, 控件测试, 日志诊断测试]`。但 `ui.topViewHierarchy` 返回的 subviews 顺序却是：

```
root/5/0  → indexPath.item 2  日志诊断测试  (y=388, 最下面)
root/5/1  → indexPath.item 1  控件测试      (y=324, 中间)
root/5/2  → indexPath.item 0  弹窗测试      (y=260, 最上面)
```

**错误推理**：看到 `root/5/0` 就以为是"第一项 = 弹窗测试"，结果点了 `root/5/0`，实际激活了 `indexPath.item=2` 的"日志诊断测试"。

### 2.2 误区二：靠 y 坐标推断 indexPath 顺序

y 坐标只代表**视觉位置**，和 `indexPath` 没有强对应关系。在普通列表里通常 `y 越小 indexPath 越小`，但遇到倒序 layout、section 分隔、header、transform 等情况不可靠。

### 2.3 正确做法

两个发现命令都已给 cell 相关节点带上 `indexPath: {section, item}` 字段：

- `ui.topViewHierarchy` 把 `indexPath` 挂在 `UITableViewCell` / `UICollectionViewCell` 节点本身（如 `root/5/0`）。
- `ui.viewTargets` 把 `indexPath` 挂在 cell 的 canonical target 子 view 上（如 `UIListContentView`、cell accessory button，path 形如 `root/5/0/1`）。

按以下优先级**唯一确定**目标 cell，**不要靠 subviews 顺序或 y 坐标猜**：

1. **首选 `accessibilityIdentifier`**：调用方（App 开发者）给每个可点击 cell 设 `accessibilityIdentifier`，例如 `menu.diagnostics`。`ui.tap` 直接带这个 id 即可，完全免 path 推理。SPMExample 当前没给菜单 cell 设 id，这是值得做的改进。
2. **次选 `indexPath` 字段**：在 `ui.viewTargets` 响应里按 `indexPath.item` 直接选行——同响应里的 `path` 与 `viewSnapshotID` 一并用于 tap，**单命令完成发现 + 定位 + 签发**，无需再走 topViewHierarchy。例如要选"日志诊断测试"（menuItems 第 3 项，indexPath.item=2），在 targets 里找 `indexPath.item==2` 的那条，拿它的 path 和 viewSnapshotID 直接 tap。
   - 若只看 cell 与 indexPath 映射、无 tap 意图，`ui.topViewHierarchy` 的 cell 节点也带 indexPath，结构更接近视图树，方便排障。
3. **`ui.tap` 返回里的 `indexPath` 是执行后权威**：点完一个 cell，响应里有 `indexPath: {item, section}`，可与 menuItems 数组 1:1 对应校验"点对了"。
4. **section + item 显式定位**：`ui.scrollToElement` + `match: "text"` 可以把目标 cell 滚到可见，但仍需先确认文本。

### 2.4 库改进记录

第 2.3 节的 `indexPath` 字段支持由两次提交完成：

1. **`ui.topViewHierarchy` 给 `UITableViewCell` / `UICollectionViewCell` 节点加 `indexPath`**（daf0a58，2026-07-05）：调用方读层次时直接拿到 indexPath。
2. **`ui.viewTargets` 给 canonical target（cell 子 view）加 `indexPath`**（本次提交）：调用方在发现阶段就能按 indexPath 选行，不用再两步走 `topViewHierarchy` + `viewTargets`。cell 子 view 通过向上找最近祖先 cell 反查 `tableView.indexPath(for:)` / `collectionView.indexPath(for:)` 公有 API。

> 历史设计记录见 [docs/superpowers/specs/2026-07-05-uitableviewcell-tap-selection-design.md](../superpowers/specs/2026-07-05-uitableviewcell-tap-selection-design.md)。

---

## 3. 标准 curl 时序模板

### 3.1 模板 A：点击一个有 `accessibilityIdentifier` 的目标

```
# 1) 发现有 viewSnapshotID
curl -X POST http://localhost:38321/ -d '{"action":"ui.viewTargets","data":{}}'
#  → 响应 data.viewSnapshotID = "snap-9", targets[*].accessibilityIdentifier="example.gestureTap"

# 2) 用 id + viewSnapshotID 点击
curl -X POST http://localhost:38321/ -d '{
  "action":"ui.tap",
  "data":{"accessibilityIdentifier":"example.gestureTap","viewSnapshotID":"snap-9"}
}'
```

### 3.2 模板 B：点击一个无 id 的 cell（如 SPMExample 菜单）

`ui.viewTargets` 已给 cell 子 view 挂 `indexPath`，发现 + 定位 + 签发可在同一次调用里完成，无需再先调 `ui.topViewHierarchy`：

```
# 1) 调 viewTargets 一次拿到 indexPath + path + viewSnapshotID
curl -X POST http://localhost:38321/ -d '{"action":"ui.viewTargets","data":{}}'
#  → targets 里找 indexPath.item==2 的那条（"日志诊断测试"是 menuItems[2]）
#    path="root/5/0/1" indexPath={item:2,section:0} viewSnapshotID="snap-9"

# 2) 用 cell 子 view 的 path + viewSnapshotID 点击
curl -X POST http://localhost:38321/ -d '{
  "action":"ui.tap",
  "data":{"path":"root/5/0/1","viewSnapshotID":"snap-9"}
}'
#  → 响应 data.indexPath = {item:2, section:0}；与第 1 步一致即点对了
```

只读排障（无 tap 意图、只想看 cell 与 indexPath 映射或视图结构）用 `ui.topViewHierarchy`：

```
curl -X POST http://localhost:38321/ -d '{"action":"ui.topViewHierarchy","data":{"maxDepth":25}}'
#  → UITableViewCell 节点 root/5/0 直接带 indexPath={item:2,section:0}
```

### 3.3 模板 C：alert 应答（dryRun 先看后点）

```
# 1) 触发弹窗（业务侧动作，或调 ui.tap 点触发按钮）

# 2) 查询 alert 按钮列表
curl -X POST http://localhost:38321/ -d '{"action":"ui.alert.respond","data":{"dryRun":true}}'
#  → 响应 data.buttons 数组，每个按钮有 title/index/role

# 3) 选定一个按钮，dryRun=false 真正触发
curl -X POST http://localhost:38321/ -d '{
  "action":"ui.alert.respond",
  "data":{"dryRun":false,"buttonTitle":"确定"}
}'
#  → data.status = "performed" / "dismissed" / "button"
```

### 3.4 模板 D：执行后换页，再次交互的标准流程

```
# 1) 上一次 ui.tap 让页面 push 到新 VC

# 2) 等页面稳定
curl -X POST http://localhost:38321/ -d '{"action":"ui.wait","data":{"mode":"idle","timeoutMs":3000}}'

# 3) 重新发现（旧 viewSnapshotID 已失效）
curl -X POST http://localhost:38321/ -d '{"action":"ui.viewTargets","data":{}}'
#  → 新 viewSnapshotID = "snap-10"

# 4) 继续交互
curl -X POST http://localhost:38321/ -d '{
  "action":"ui.tap",
  "data":{"accessibilityIdentifier":"<newId>","viewSnapshotID":"snap-10"}
}'
```

---

## 4. 调用方常踩的坑汇总

| 行为 | 结果 | 正确做法 |
|---|---|---|
| 跳过 `ui.viewTargets`，直接 `ui.tap` 不带 `viewSnapshotID` | `viewSnapshotID is required` | 先 viewTargets |
| 字段名写成 `snapshotID` / `identifier` / `viewPath` | `unknown command input field` | 用 `viewSnapshotID` / `accessibilityIdentifier` / `path` |
| `build_run_sim` 后直接 curl 38321 没反应 | server 因 autostart 关闭而未起 | 调 `launch_app_sim(env={"IOS_EXPLORE_AUTOSTART":"1"})` 重启 App（详见 AGENTS.md 「四个必须记住的差异」） |
| 点击 cell 后旧 `viewSnapshotID` 还在用 | `stale_locator` | 重新 viewTargets |
| 用 subviews 数组顺序当 indexPath 顺序 | 点错 cell（本次案例） | 见 §2.3，靠 `accessibilityIdentifier` / cell 标题 / 返回的 indexPath |
| `ui.alert.respond` 直接 dryRun=false 但不知道按钮 | `unknown button` 或点错按钮 | 先 dryRun=true 列按钮，再 dryRun=false 精确点 |
| 一上来只发 `ui.topViewHierarchy` 想 tap | 没有 viewSnapshotID 字段，topViewHierarchy 不签发 | tap 前必须单独发 `ui.viewTargets` |

---

## 5. SPMExample 真实闭环补充约定

调用 `Examples/SPMExample` 做 agent 验证时，**自动启动 server 的开关必须通过 `launch_app_sim` / `launch_app_device` 的 `env` 或 `launchArgs`**，**不能**写进 session defaults 的 `env`（`build_run_*` 不把 session env 注入到 App 进程）。已实测打通的流程见 `AGENTS.md` 的「XcodeBuildMCP 运行配置」节「四个必须记住的差异」第 3 点。这套环境变量属于长期测试约定，不要清理，复用即可。

**示例 App 当前 cell 无 `accessibilityIdentifier`**，这是 §2.4 库改进未实施之前，调用方必须按下表钻 topViewHierarchy 子节点确认菜单项（数据按 `indexPath` 不是按 subviews 顺序）：

| menuItems 下标 | 标题 | 在 topViewHierarchy 里的常见 path（仅参考，运行时以实际响应为准） |
|---|---|---|
| 0 | 弹窗测试 | `root/5/2/0`（视觉最上面，y 最小） |
| 1 | 控件测试 | `root/5/1/0`（视觉中间） |
| 2 | 日志诊断测试 | `root/5/0/0`（视觉最下面，y 最大） |

**不要**靠 path 字面值（`root/5/0` vs `root/5/2`）记忆顺序，运行时以实际响应的 `text.value` 和 `indexPath` 为唯一权威。
