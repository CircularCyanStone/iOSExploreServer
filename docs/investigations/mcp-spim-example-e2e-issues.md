# SPMExample MCP 端到端测试问题 - 2026-04-28

> 测试时间：2026-04-28
> 测试方式：通过 MCP 协议（stdio）调用 `MCPServer/dist/src/index.js`，对 `Examples/SPMExample` 在 iPhone 17 模拟器上跑整套端到端
> 测试覆盖：基础命令、主页、弹窗测试页（5 种 alert）、控件测试页（6 类控件）、日志诊断页（5 场景 + 6 来源 + 6 emit）、wait/observe、scroll、screenshot、navigation、call_action、refresh_tools
> 总工具数：34（5 固定 + 29 动态）
> 健康检查：`{ ok: true, dynamicToolCount: 29, conflicts: [] }`
> 测试期 App 崩溃次数：1 次（见 P2）

## 已确认问题

### P1. `ui.scrollToElement` 找不到 UIScrollView 祖先

**严重度**：中（功能不可用）

**复现**：
- 在主页 menuTableView（`availableActions: ["scroll"]`）上，调用：
  ```json
  // 不带 path
  {"match":"text","value":"日志诊断"}
  // 带 path 指向 menuTableView
  {"path":"root/5","match":"text","value":"日志诊断"}
  ```
- 两者均返回：
  ```json
  {
    "source": "ios_envelope",
    "message": "no UIScrollView ancestor (UITextView excluded)",
    "code": "scroll_container_unavailable",
    "action": "ui.scrollToElement"
  }
  ```

**矛盾点**：
- `ui.viewTargets` 返回的 `root/5` 明确标注 `availableActions: ["scroll"]`
- `ui.scroll` 在同一 `path: "root/5"` 上工作正常（offset 0→50）
- 但 `ui.scrollToElement` 既不接受 `viewSnapshotID`（schema 已声明不接受），也找不到 UIScrollView 祖先

**推断**：
- 实现可能默认从 window 视角自上而下搜索"包含 text 的 view"，再从该 view 上溯 UIScrollView 祖先
- 当通过 `path` 指定 scrollView 容器自身时，可能没用上 path 而是仍走"全局搜 text"分支，找不到目标文本对应的元素
- 或：path 被当作"目标 view 的 path"（UILabel/UIButton）而不是 scrollView 容器的 path，于是从 scrollView 自身上溯时父链没有更外层 scrollView

**建议**：
- 让 `path` 同时支持"目标 view path"和"scrollView 容器 path"（或新增 `containerPath`）
- 当 `match=text` 时，应允许指定在哪个 scrollView 内搜索目标 cell
- 在 description 里明确 `path` 指的是目标 view 还是 scrollView 容器

**已修复**：`d20eb39` — findTarget 增加 UITableView/UICollectionView 的 visibleCells 搜索分支；模型注释和字段 description 明确 path/accessibilityIdentifier 指向滚动容器自身。当容器是 UITableView/UICollectionView 时，visibleCells 内的子 view 会被额外搜索。

### P2. `UIViewHierarchyCollector` 隐式解包崩溃

**严重度**：高（App 完全崩溃，需要重启）

**复现路径**：
- 进入控件测试页 → 对 6 类控件连发 6 次 `ui.control.sendAction`（含 UISegmentedControl value=2、UIStepper value=5） → 之后任何 observe 命令导致 App hang
- 重启 App 后查崩溃日志：
  ```
  iOSExploreUIKit/UIViewHierarchyCollector.swift:117
  Fatal error: Unexpectedly found nil while implicitly unwrapping an Optional value
  ```

**推断**：
- 第 117 行某 Optional 被强制解包为 nil
- 触发可能与 `UIStepper`/`UISegmentedControl` 的 `sendAction` 后状态变化导致层级采集时某 superview/window 临时为 nil 有关
- 也可能与 first responder 切换、keyboard 状态切换相关

**建议**：
- 排查 `Sources/iOSExploreUIKit/UIViewHierarchyCollector.swift:117`，把 implicitly unwrapped optional 改成 safe unwrap + graceful fallback
- 在层级采集前增加"view 是否仍在 window 层级中"的守卫

**已修复**：`aa4bb7c` — `view.tintColor?.hierarchyHexString`（safe unwrap）+ `label.textColor?.hierarchyHexString` + 采集前 `isAttachedToWindow` 守卫跳过已脱离 window 的过渡子树。新增 2 个回归测试（nil tintColor / nil textColor 不崩溃）。

### P3. `viewSnapshotID` 陈旧判定过于严格

**严重度**：中（脚本化操作不友好）

**复现**：
- `observe` 拿到 `snap-5` → 用 `snap-5` 触发一次 `ui.tap` 成功 → 紧接着第二次 `ui.tap` 用同一个 `snap-5`，立即报：
  ```json
  {
    "source": "ios_envelope",
    "message": "view snapshot expired or target changed; call ui.viewTargets first, then retry with the new viewSnapshotID",
    "code": "stale_locator"
  }
  ```
- 中间未做任何导航/页面切换，仅一次同页 tap 后即失效

**矛盾点**：
- 一次 tap 通常不会改变 view tree 结构（如 gesture label 内文变化），但仍强制签发新 snapshot
- 对自动化脚本不友好：每次操作前必须 observe，调用链变成 observe-tap-observe-tap-observe-tap...

**建议**：
- 区分"结构变化"和"内容变化"：仅结构变化时才使旧 snapshot 失效
- 或增加 `force: true` 参数允许在已知无结构变化时跳过检查
- 或允许 snapshotID 在"同次 observe 窗口"内多次复用，直到下一次 observe 显式刷新

**已评审**：`03f1bd7` — 理论上当前 fingerprint 比对已包含 `semanticDigest`（语义摘要）与 `ancestorDigest`（结构摘要）两个独立维度，前者判断内容变化，后者判断结构变化。tap 操作触发 gesture label 内文更新会使 semanticDigest 变化，这属于正确的陈旧判定。增加注释明确独立字段的用途。

### P4. `ui.input` 不支持 `accessibilityIdentifier` 定位

**严重度**：低（有 workaround：用 `path`）

**复现**：
- 在控件测试页，对 `test.textfield` UITextField 调用：
  ```json
  {"accessibilityIdentifier":"test.textfield","text":"Hello-MCP","viewSnapshotID":"snap-X"}
  ```
- 返回：
  ```json
  {
    "source": "ios_envelope",
    "message": "viewSnapshotID is valid only with path",
    "code": "invalid_data",
    "action": "ui.input"
  }
  ```
- 即：传了 `viewSnapshotID` 时强制要求 `path`，但 schema oneOf 表明 identifier 与 path 二选一

**矛盾点**：
- schema 声明 `accessibilityIdentifier` 与 `path` 二选一
- 但同时又有 `x-iosExplore-constraints: ["viewSnapshotID is valid only with path"]`
- 这两条结合后的实际语义是"用 identifier 时不允许传 viewSnapshotID"，但描述没有把这点写清楚
- 然而 schema 又把 viewSnapshotID 列为可选字段，造成使用者无所适从

**建议**：
- 让 `ui.input` 在用 `accessibilityIdentifier` 定位时也支持 `viewSnapshotID` 防陈旧校验，与 `ui.tap` 行为一致
- 或在 description 顶部明确写出约束："当用 accessibilityIdentifier 时不接受 viewSnapshotID；用 path 时必须搭配 viewSnapshotID"

**已修复**：`2fb68d3` — 模型注释 + constraints 文案明确 viewSnapshotID 仅支持 path；identifier 定位不带结构路径无法做指纹校验，与 ui.tap 不同（tap 的 viewSnapshotID 是 required 且 LRU 缓存额外支持 identifier）。

### P5. `ui.navigation.back` 不接受 `mode` 参数

**严重度**：低（不带参数可工作）

**复现**：
- 调用 `{"mode":"auto"}` 返回：
  ```json
  {
    "source": "ios_envelope",
    "message": "unknown command input field 'mode'",
    "code": "invalid_data",
    "action": "ui.navigation.back"
  }
  ```
- 调用 `{}` 工作正常，返回 `{performed: true, strategy: "navigationController", topAfter/topBefore}`

**矛盾点**：
- 文档/示例中提到 `mode: auto/dismiss/pop`，但实际不接受
- 输出里有 `strategy` 字段（实际生效的策略），但没有输入 `mode` 选项

**建议**：
- 如果"auto/dismiss/pop"是真意图，补全 inputSchema 的 mode enum
- 否则更新文档/示例，去掉 mode 参数

**已修复**：`2542984` — description 和模型注释明确 strategy 三个值（auto / navigationController / dismiss），注明"旧文档 mode 字段已废弃"。

### P6. 嵌套 alert dismiss 后短期读回旧 alert 信息

**严重度**：中（自动化脚本误判风险）

**复现**：
- 嵌套 alert：第 1 层"步骤 1 / 2"含继续/取消按钮 → `ui.alert.respond(dryRun=false, buttonIndex=0)` dismiss 成功
- 紧接着（无 sleep）调用 `ui.alert.respond(dryRun=true)` 查询，返回的 title 仍是 **"步骤 1 / 2"**、buttons 仍是 `[继续, 取消]`
- 加 `sleep 1.5` 后再查询，才返回"步骤 2 / 2"、buttons `[完成]`

**推断**：
- dismiss 完成回调与第二层 present 之间有 300-500ms 窗口
- 此窗口内 `ui.alert.respond` 读到的是刚被 dismiss 的 controller 的 stale 引用，或者读到了 UIAlertController 内部的"presented but not yet visible"过渡状态
- 已确认 P6 与 commit `9042c7e fix(uikit/alert): T2-AlertDismiss — 补全 alert.respond dismiss 后 RunLoop 等待` 的修复主题相关，现有 `dismissWaitMs: 800` 似乎仍不足以覆盖更深嵌套场景

**建议**：
- 在 `ui.alert.respond` 处理 dismiss 后增加 RunLoop spin 直到 `presentedViewController` 真正切换
- 或在 dismiss 后强制透传更长 `dismissWaitMs`（≥1500ms）默认值，覆盖嵌套场景
- 至少在返回结果里增加 `presentedAfterDismiss` 字段，让调用方能判断当前呈现的是新 alert 还是没 alert

**已修复**：`0203351` — maxAttempts 从 50（~800ms）提升到 95（~1520ms）；新增 `presentedAfterDismiss` 布尔字段。

### P7. `debug.emit*` 命名字段混乱：`message` vs `text`

**严重度**：低（schema 已明确，但容易误用）

**复现**：
- 6 个 `debug.emit*` 工具：debug_emitAppLog / emitLogger / emitNSLog / emitOSLog / emitStdout / emitStderr
- 初次按 iOS 通用语义传 `{"text": "..."}` → 全部报 `unknown command input field 'text'`
- 正确字段是 `{"message": "..."}`，搭配可选 `token`

**矛盾点**：
- 其他工具（如 `ui.input`）用 `text` 描述"要输入的文本"
- 而 `debug.emit*` 用 `message` 描述同一概念
- 两种命名混合使用，调用方必须查 schema 才能确定

**建议**：
- 统一字段命名（推荐保留 `message`，因为 NSLogger/stderr 的输入语义更接近 logger message 而非 UI text）
- 或在 description 顶部明确："字段名为 message，**不是** text"，避免误用
- 或让 schemaMapper 在工具描述里自动追加"Known field names: ..."提示

**已修复**：`9178c21` — ExampleStdIOMessageInput 的 messageField description 增加"（注意字段名是 message 不是 text）"提示 + 注释解释命名差异背景。

### P8. `ui.viewTargets` 的 `accessibilityIdentifier` 精确匹配语义未文档化

**严重度**：低（有 prefix 替代）

**复现**：
- 调用 `{"accessibilityIdentifier":"test"}` 返回 `targetCount: 0`（期望：返回所有 `test.button/switch/slider/segmented/stepper/textfield`）
- 改用 `{"accessibilityIdentifierPrefix":"test"}` 也返回 0（但主页确实没有 `test.` 前缀的控件，需在控件测试页测试）
- 在控件测试页同样用 `{"accessibilityIdentifier":"test"}` 仍 `targetCount: 0`

**推断**：
- `accessibilityIdentifier` 是严格相等匹配，不接受前缀/子串
- 但 schema description 仅写"按 accessibilityIdentifier 精确定位目标 view"——这点其实已经写明"精确"二字
- 但 prefix 字段的语义和"精确"identifier 的关系没有对照表

**建议**：
- 在 description 增加 example："identifier='test.button'（精确等价）vs identifierPrefix='test.'（前缀匹配多个）"
- 或对 identifier 也支持自动前缀 fallback（不推荐，会破坏语义清晰度）

**已修复**：`f67c179` — UIKitFilterFields.accessibilityIdentifier 和 identifierPrefix 的 description 增加完整示例 + 精确/前缀对照说明。

## 修复概要

| 编号 | 严重度 | 修复 | Commit | 验证方式 |
|------|--------|------|--------|----------|
| P2 | 高（崩溃） | safe unwrap + window 守卫 | `aa4bb7c` | 现有 248 测试全部通过；新增 2 个回归测试 |
| P1 | 中（功能） | visibleCells 搜索 | `d20eb39` | scrollToElement 4 个测试通过 |
| P3 | 中（体验） | 语义注释澄清 | `03f1bd7` | snapshot 9 个测试全部通过 |
| P4 | 低（文档） | constraints 文案 | `2fb68d3` | input input schema 测试通过 |
| P5 | 低（文档） | description 更新 | `2542984` | navigation back input 测试通过 |
| P6 | 中（可靠性） | wait 提升 + 新增字段 | `0203351` | alert respond 8 个测试通过 |
| P7 | 低（文档） | description 提示 | `9178c21` | 编译通过 |
| P8 | 低（文档） | 示例说明 | `f67c179` | 编译通过 |

## 额外观察（非问题，但值得记录）

### O1. `greet` 命令的 data 嵌套

- 动态帮助里 `greet` 的 schema 要求 `name` 字段直接放在 args 顶层，不包 `data`
- 但 `call_action` 兜底工具的 schema 是 `{action, data}`——两种调用方式语义不一致
- 推测：动态工具直接对应 iOSExplore action，参数直接平铺；`call_action` 是包装层，需把 args 包成 data 转交
- 不算 bug，但建议在文档里明确"动态工具的 args 直接平铺，call_action 的 args 必须包 data"

### O2. UITextField 注入后 `text` 字段为 null

- 通过 `ui.input` 注入文本后，`ui.viewTargets` 返回的该 textField：
  - `text: null`
  - `value: null`
  - `semanticText: "Hello-MCP"`（来源 `accessibilityValue`）
- 即：textField 的"用户输入文本"被映射到了 `semanticText`，而 `text` 字段保留给 label 语义
- 这是合理的 schema 设计选择，但容易让初次使用者误判"注入失败"
- 建议：在 ui.input description 里加一句"注入后用 semanticText 字段验证"

### O3. `ui.scroll` 用 `amount` 而不是 `distance`

- schema 实际字段是 `amount`（"滚动距离(pt), 必须 > 0; 缺省 = 可见区 × 0.5"）
- 但常见英文直觉会用 `distance` —— 当前已正常报错"unknown command input field 'distance'"并提示正确字段
- 不算 bug，仅风格建议：考虑接受 `distance` 作为 `amount` 的别名

### O4. `observe` 与 `ui.viewTargets` 行为重叠

- `observe` 默认模式 = viewTargets，返回完全一致结构
- `observe` 额外支持 `mode=topViewHierarchy`（返回完整层级树）
- `ui_viewTargets` 工具单独存在，但 `observe` 已能取代
- 推测：`ui_viewTargets` 是底层工具，`observe` 是封装"常用观察入口"的语义糖
- 不算 bug，是设计选择

## 测试环境

- 设备：iPhone 17 模拟器（ID `065CC8DB-8978-46C5-82D6-C96625B608D8`）
- App：SPMExample，bundleId `com.coo.SPMExample`，启动 env `IOS_EXPLORE_AUTOSTART=1`
- MCPServer：`MCPServer/dist/src/index.js`，stdio JSON-RPC，baseURL `http://localhost:38321/`
- XcodeBuildMCP profile：`sim-app`
- 测试日期：2026-04-28

## 下一步建议

1. **优先修 P2**（崩溃）：直接定位 `UIViewHierarchyCollector.swift:117` 的 implicitly unwrapped optional
2. **修 P1**：让 `ui.scrollToElement` 接受 scrollView 容器 path，或新增 `containerPath`
3. **修 P3**：放宽 snapshot 陈旧判定，加 `force: true` 或区分结构/内容变化
4. **修 P6**：增加 dismiss 后的 RunLoop spin 等待，覆盖嵌套 alert 场景（与 T2-AlertDismiss commit 关联）
5. P4 / P5 / P7 / P8：均为文档/语义清晰度问题，可在下个文档迭代中补全
