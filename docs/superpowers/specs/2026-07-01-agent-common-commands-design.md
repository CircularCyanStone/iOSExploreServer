# Agent 常用 UIKit 命令 v2 设计

- **日期**: 2026-07-01
- **状态**: 交叉评审后修订稿 v2，待用户审阅
- **范围**: 先补 iOS 端常用命令，再做 Mac 侧 MCP server
- **上游设计**: `docs/superpowers/specs/2026-06-30-action-commands-design.md`

## 1. 背景与目标

当前已实现 11 个 action：core 4 个，UIKit 7 个。UIKit 侧已经具备 agent 的基础闭环：

`ui.viewTargets` / `ui.topViewHierarchy` 发现目标 -> `ui.screenshot` 看屏 -> `ui.tap` / `ui.input` / `ui.scroll` / `ui.control.sendAction` 操作。

这轮不急着做 MCP server，而是先补 agent 在真实 App 流程里最容易卡住的常用原子能力：等待、返回、弹窗、键盘、滚到目标。MCP server 后续只负责把这些 action 包装成 tools，不应倒逼 iOS 端仓促新增临时语义。

## 2. 范围

### In scope

- 新增 5 个 UIKit 命令，均放在 `iOSExploreUIKit`，通过 `server.registerUIKitCommands()` 显式注册：
  - `ui.wait`
  - `ui.navigation.back`
  - `ui.alert.respond`
  - `ui.keyboard.dismiss`
  - `ui.scrollToElement`
- 所有命令继续使用 typed `CommandInput`，字段 schema 作为 help/MCP 映射的单一来源。
- 复用现有 Foundation-only parsing、`UIKitContextProvider`、`UIKitLocatorInput`、`UIKitSnapshotStore`、`UIKitCommandError`、`UIKitCommandLogging`。
- 更新 docs 中 UIKit 命令数量和清单，修复 `docs/uikit/README.md` 仍写 4 个命令的漂移。

### Out of scope

- Mac 侧 MCP server 实现。
- 多指手势、拖拽、任意 selector 调用。
- 全量日志流和性能诊断。
- 任意 DOM 自动化框架。`WKWebView` 专项能力留后续 `ui.web.evaluateJavaScript`。
- 截图裁剪、多 scene 选择、坐标系重设计。

## 3. 设计原则

1. **动作语义面向 agent 意图**：例如 `ui.scrollToElement` 表达“找到并滚到目标”，不是要求 agent 自己循环 `ui.scroll` + `ui.viewTargets`。
2. **确定性优先**：默认非动画、有限重试、超时清晰、响应返回实际状态。
3. **失败可恢复**：失败 envelope 要告诉 agent 下一步该重试、重截图、换目标、还是上报不可支持。
4. **不泄露敏感数据**：日志只记录摘要、长度、类型、错误码，不记录完整文本、截图、按钮全文列表之外的大 payload。
5. **不破坏 core 边界**：core 仍只依赖 Foundation + Network；UIKit 能力全部在 `iOSExploreUIKit`。

## 4. 命令总览

| action | 优先级 | 作用 | 主要复用 |
|---|---:|---|---|
| `ui.wait` | P0 | 等 UI 稳定、等待目标/文本出现或消失、等待快照变化 | context、hierarchy/viewTargets collector、snapshot 指纹 |
| `ui.navigation.back` | P0 | 返回上一页 | context、UINavigationController、导航栏按钮 fallback |
| `ui.alert.respond` | P0 | 查询/点击当前 alert 按钮 | context、presented controller |
| `ui.keyboard.dismiss` | P1 | 单独收起键盘 | UIApplication.sendAction / endEditing |
| `ui.scrollToElement` | P1 | 循环滚动直到目标可见 | viewTargets 匹配、UIScrollExecutor |

## 5. 共同实现约束

- 新增命令 adapter 放 `Sources/iOSExploreUIKit/Commands/<Feature>/`。
- 通用辅助放 `Sources/iOSExploreUIKit/Support/` 下按职责拆分，不把复杂逻辑塞进 command adapter。
- typed input 必须是 Foundation-only；UIKit 类型只能出现在 `@MainActor` 执行核心内部。
- 每个命令失败先通过 `UIKitCommandError` 工厂生成业务失败，再转 `ExploreResult`。
- 新增 envelope code 前先检查 `ExploreError`：它是固定 enum，不是自由字符串。只有 agent 恢复策略确实不同的失败才新增 code；否则复用现有 code 并把具体原因写进 message/logMessage。
- 每个命令记录 start / complete / failed 日志，至少包含 action、关键参数摘要、耗时、错误 code。
- 新增 public 类型、关键 internal 类型和生命周期方法写 `///` 中文注释。
- 注册入口 `registerUIKitCommands()` 更新注册数量；help schema、README、UIKit 文档同步更新。

## 6. `ui.wait`

### 目标

给 agent 一个可靠的等待原语，避免点击/输入/滚动后马上截图或查 target 时读到中间态。

### input

`UIWaitInput`：

- `mode`：String enum，必填。
  - `idle`：等待 UI 连续稳定。
  - `targetExists`：等待目标出现。
  - `targetGone`：等待目标消失。
  - `textExists`：等待文本出现。
  - `snapshotChanged`：等待当前页面指纹相对传入 snapshotID 发生变化。
- `timeoutMs`：Int，可选，默认 3000，范围 100...30000。
- `intervalMs`：Int，可选，默认 100，范围 50...1000。
- `stableMs`：Int，可选，默认 300，仅 `idle` 使用，范围 100...5000。
- `accessibilityIdentifier` / `path`：可选，`targetExists` / `targetGone` 使用，二选一。
- `text`：String，可选，`textExists` 使用。按可见文本 contains 匹配，不做正则。
- `snapshotID`：String，可选，`snapshotChanged` 使用。
- `includeHidden`：Bool，可选，默认 false。

### output

```json
{
  "satisfied": true,
  "mode": "targetExists",
  "elapsedMs": 420,
  "attempts": 5,
  "snapshotID": "snap-18",
  "snapshotUnavailableReason": null
}
```

### 行为

- 每轮在 MainActor 取当前 context。
- `idle`：连续采集轻量指纹，连续 `stableMs` 内 digest 不变即成功。
- `targetExists` / `targetGone`：复用定位解析和 resolver，不触发点击。
- `textExists`：新增可复用文本采集 helper，基于 hierarchy/viewTargets 现有遍历与文本提取规则实现 contains 匹配。当前没有“所有可见文本扁平列表”的现成入口：`viewTargets` 只输出 target 摘要字段，且默认不返回可编辑输入内容；`topViewHierarchy` 的文本提取覆盖更广但绑定在层级构建内。
- `snapshotChanged`：从 `UIKitSnapshotStore` 取旧 snapshot，与当前指纹 digest 比较；旧 snapshot 不存在或过期返回 stale 类错误。
- 轮询 deadline 到达时不抛 transport error，返回业务失败 `waitTimeout`，message 写清 mode 和 elapsedMs；命令级 `timeoutNanoseconds` 只做兜底保护。
- `ui.wait` 必须自声明固定命令级超时 `timeoutNanoseconds = 31_000_000_000`（略高于 `timeoutMs` 最大 30000ms）。`ClientSession` 会在 `router.route` 外层先套命令级 `withTimeout`，且 `Router.commandTimeout(for:)` 只能按 action 查表，无法读取 input 动态超时；因此业务轮询 deadline 必须在 adapter/executor 内自管，避免全局 10s 先返回通用 `timeout`。

### 错误

- `invalid_data`：mode 与字段组合非法。
- `waitTimeout`：等待条件未满足。
- `stale_locator`：snapshotID 不存在或过期。
- `hierarchyUnavailable`：无前台 window/root view。

### 日志

- start：mode、timeoutMs、intervalMs、字段摘要。
- complete：mode、elapsedMs、attempts、snapshotID 是否签发。
- failed：code、elapsedMs、attempts。

## 7. `ui.navigation.back`

### 目标

给 agent 一个稳定的“返回上一页”命令，不要求它识别每个页面的返回按钮文案或坐标。

### input

`UINavigationBackInput`：

- `strategy`：String enum，可选，默认 `auto`。
  - `auto`：按优先级自动返回。
  - `navigationController`：只走 `popViewController`。
  - `barButton`：只点导航栏返回按钮。
  - `dismiss`：只 dismiss 当前 presented controller。
- `animated`：Bool，可选，默认 false。
- `waitAfterMs`：Int，可选，默认 300，范围 0...3000。

### output

```json
{
  "performed": true,
  "strategy": "navigationController",
  "topBefore": "DetailViewController",
  "topAfter": "HomeViewController"
}
```

### 行为

- `auto` 顺序：
  1. 如果 top controller 有 presented controller，且当前就是 presented 栈，先 `dismiss(animated:)`。
  2. 如果存在 `UINavigationController` 且 viewControllers 数量 > 1，调用 `popViewController(animated:)`。
  3. best-effort 尝试定位导航栏左侧可交互 back item/button，再走现有 tap/control 能力。导航栏 back button 不保证一定是稳定 `UIControl` path，因此该策略只能作为兜底，不作为主成功路径。
  4. 都不可用则返回 `navigationBackUnavailable`。
- 默认 `animated=false`，便于后续马上 `ui.wait` / `ui.screenshot`。
- `waitAfterMs` 只做短暂 settle，不替代 `ui.wait`。

### 错误

- `navigationBackUnavailable`：没有可返回路径。
- `transitionInProgress`：正在转场，要求 agent 稍后重试或先 `ui.wait`。
- `hierarchyUnavailable`：无前台上下文。

### 日志

- start：strategy、animated。
- complete：命中的 strategy、topBefore/topAfter 类型名。
- failed：code、topBefore 摘要。

## 8. `ui.alert.respond`

### 目标

处理真实 App 流程中频繁出现的确认弹窗、权限说明弹窗和错误提示弹窗。

### input

`UIAlertRespondInput`：

- `buttonTitle`：String，可选。按按钮标题精确匹配。
- `buttonIndex`：Int，可选。0-based。
- `role`：String enum，可选。
  - `default`
  - `cancel`
  - `destructive`
- `dryRun`：Bool，可选，默认 false。为 true 时只返回当前 alert，不点击。
- `waitAfterMs`：Int，可选，默认 200，范围 0...3000。

约束：

- `buttonTitle`、`buttonIndex`、`role` 最多提供一个。
- 三者都不提供且 `dryRun=false` 时，默认选择 `cancel`，如果没有 cancel 则返回 `alertButtonRequired`，不猜默认按钮。

### output

```json
{
  "present": true,
  "title": "确认",
  "message": "是否继续",
  "buttons": [
    {"index": 0, "title": "取消", "role": "cancel"},
    {"index": 1, "title": "继续", "role": "default"}
  ],
  "selectedIndex": 1,
  "selectedTitle": "继续"
}
```

### 行为

- 只支持当前前台 controller 正在 presented 的 `UIAlertController`。
- `dryRun=true` 时不执行 action，供 agent 先观察。
- 点击通过 `UIAlertAction` 的可用公开路径有限：公开 API 可以读取 `UIAlertController.actions`，但没有公开入口直接执行某个 action handler。默认实现路径改为“查询当前 alert + 返回按钮元数据 + 尽量返回可点击 button view path”；直接点击能力必须先做 spike 验证。
- spike 要在 SPMExample 里弹出 `UIAlertController`，验证能否稳定拿到 button view path，并用现有 `ui.tap` 点中。只有 spike 通过，`buttonTitle` / `buttonIndex` / `role` 才允许在同命令内直接点击；否则第一版只返回 alert 查询结果和 path 建议，不伪造成功。
- 不处理系统级权限弹窗的私有 API。若系统弹窗不在 App view hierarchy 中，返回 `alertUnavailable`，由外部工具或人工处理。

### 错误

- `alertUnavailable`：当前没有可处理的 `UIAlertController`。
- `alertButtonNotFound`：指定 title/index/role 不存在。
- `alertButtonRequired`：不允许猜默认按钮。
- `invalid_data`：选择字段组合非法；若 spike 证明存在“有 alert 但公开路径无法安全操作”的独立可恢复分支，再新增 unsupported alert 类型错误码。

### 日志

- start：dryRun、选择字段摘要。
- complete：present、buttonCount、selectedIndex。
- failed：code、buttonCount。

## 9. `ui.keyboard.dismiss`

### 目标

允许 agent 在输入后明确收起键盘，避免键盘遮挡按钮或截图。

### input

`UIKeyboardDismissInput`：

- `strategy`：String enum，可选，默认 `auto`。
  - `auto`
  - `resignFirstResponder`
  - `endEditing`
- `waitAfterMs`：Int，可选，默认 200，范围 0...3000。

### output

```json
{
  "dismissed": true,
  "strategy": "endEditing",
  "firstResponderBefore": "UITextField",
  "firstResponderAfter": null
}
```

### 行为

- `auto` 优先向当前 first responder 发送 resign，再 fallback 到 keyWindow `endEditing(true)`。
- 不强制判断键盘系统动画是否结束；需要稳定画面时 agent 再调用 `ui.wait`。
- 如果本来没有 first responder，返回 `dismissed=false` 且 `firstResponderBefore=null`，不作为失败。

### 错误

- `hierarchyUnavailable`：无前台 window。
- `keyboardDismissFailed`：尝试后 first responder 未变化。

### 日志

- start：strategy。
- complete：dismissed、firstResponder 类型变化。
- failed：code。

## 10. `ui.scrollToElement`

### 目标

把“滚到某个目标可见”封装成单个命令，减少 agent 自己循环滚动、截图、查 target 的成本。

### input

`UIScrollToElementInput`：

- `match`：String enum，必填。
  - `accessibilityIdentifier`
  - `text`
- `value`：String，必填。
- `containerAccessibilityIdentifier` / `containerPath`：可选，限定滚动容器，二选一。
- `direction`：String enum，可选，默认 `down`，可选 `up` / `down` / `left` / `right`。
- `stepAmount`：Double，可选，pt，默认可见尺寸 0.7 倍，必须 > 0。
- `maxScrolls`：Int，可选，默认 8，范围 1...50。
- `includeHidden`：Bool，可选，默认 false。
- `snapshotID`：String，可选，仅当 `containerPath` 提供时用于陈旧校验。

### output

```json
{
  "found": true,
  "scrolls": 3,
  "target": {
    "path": "root/0/2/4",
    "type": "UILabel",
    "text": "订单详情",
    "frame": {"x": 16, "y": 320, "width": 120, "height": 24}
  },
  "container": {
    "path": "root/0/1",
    "type": "UITableView",
    "offsetBefore": {"x": 0, "y": 0},
    "offsetAfter": {"x": 0, "y": 1480}
  },
  "snapshotID": "snap-22",
  "snapshotUnavailableReason": null
}
```

### 行为

- 每轮先采集可见 targets，按 `match/value` 查找目标。
- 找到目标且 frame 与当前 window 有可见交集即成功。
- 未找到则按 direction/stepAmount 调用 scroll 共享原语做一次滚动。
- 每次滚动后短暂 yield，再进入下一轮。
- 达到边界或 `maxScrolls` 后仍找不到，返回 target-not-found 语义的业务失败，message/logMessage 写清 scroll 次数与 reachedExtent。
- 成功后签发新的 snapshotID，方便 agent 后续按 target path 调 `ui.tap`。
- 默认不支持 `WKWebView` 内部 DOM，只看 native view hierarchy。

### scroll 原语抽取

`UIScrollExecutor.execute(input:context:)` 当前是“定位 -> nearest scrollView -> 陈旧校验 -> 算 delta -> setContentOffset -> reachedExtent”的同步整体方法，不适合被 `ui.scrollToElement` 每轮整体调用；直接复制其 private 逻辑又会让边界判断分叉。

实现本命令前必须先抽取共享原语，例如：

- `UIScrollResolver`：按可选容器 locator 找 scrollView，复用“排除 UITextView”和 foremost scrollView 规则。
- `UIScrollGeometry`：计算默认步长、direction delta、`adjustedContentInset` 边界、`reachedExtent`。
- `UIScrollStepResult`：统一 offsetBefore/offsetAfter/reachedExtent/adjustedContentInset 响应字段。

`ui.scroll` 与 `ui.scrollToElement` 都调用这些原语；`ui.scroll` 仍保持单步命令，`ui.scrollToElement` 只负责循环采集、匹配和终止条件。

### 错误

- `target_not_found`：滚动结束仍未找到。不要新增独立 `targetNotFoundAfterScroll` code，具体 scroll 次数与 reachedExtent 放 message/logMessage。
- `scrollContainerUnavailable`：找不到滚动容器。
- `stale_locator`：containerPath + snapshotID 陈旧。
- `invalid_data`：match/value 或容器字段组合非法。

### 日志

- start：match 类型、value 长度、direction、maxScrolls、container 摘要。
- per-attempt debug：attempt、offset、found count，不记录完整文本列表。
- complete：found、scrolls、target path、snapshotID 是否签发。
- failed：code、scrolls、reachedExtent。

## 11. 错误码策略

新增错误工厂都放在 `UIKitCommandError`，但 envelope code 必须来自 core `ExploreError` enum。新增 code 只保留 agent 需要不同恢复策略的场景。

建议新增 `ExploreError` case：

- `waitTimeout = "wait_timeout"`：等待条件未满足；若实现时决定复用现有 `timeout`，必须在实现计划里说明 MCP/agent 如何区分 wait 业务超时与命令级兜底超时。
- `navigationBackUnavailable = "navigation_back_unavailable"`：没有可返回路径。
- `alertUnavailable = "alert_unavailable"`：当前没有可处理 alert。
- `alertButtonNotFound = "alert_button_not_found"`：指定 title/index/role 不存在。
- `alertButtonRequired = "alert_button_required"`：调用方未指定按钮，且不能安全默认选择。
- `keyboardDismissFailed = "keyboard_dismiss_failed"`：尝试后 first responder 未变化。

暂不新增：

- `targetNotFoundAfterScroll`：复用/新增通用 `target_not_found` 工厂更合理，scroll 次数放 message/logMessage。
- `unsupportedAlertType`：先由 alert spike 决定。第一版可复用 `alert_unavailable` 或 `invalid_data`；只有确实存在“有 alert 但公开路径不支持”的可恢复分支，才新增独立 code。

若已有语义可复用，优先复用：

- `invalid_data`
- `hierarchyUnavailable`
- `stale_locator`
- `transitionInProgress`
- `scrollContainerUnavailable`

现有不一致也要在实现前处理：`ExploreError` 已有 `stale_locator`，但当前 `UIKitCommandError.staleLocator` 返回的是 `.invalidData`。本轮新增命令依赖 snapshot 恢复语义，实施计划应先统一 stale 工厂的 code，或明确继续用 `invalid_data` 的理由。

## 12. 测试策略

### macOS `swift test`

覆盖 Foundation-only 部分：

- 每个新 input model 的 schema 字段、默认值、未知字段拒绝、互斥字段校验。
- 错误工厂 code/message/logMessage 契约。
- `help` 中新增命令 schema 出现且字段与解析一致。
- docs 里命令数量与注册数量的轻量一致性测试，如已有类似测试则扩展。

### iOS framework tests

覆盖 UIKit 行为：

- `ui.wait`：target 出现/消失、timeout、idle 稳定。
- `ui.navigation.back`：navigation stack pop、无可返回路径。
- `ui.alert.respond`：dryRun 列按钮、按 index/title 选择、按钮不存在。
- `ui.keyboard.dismiss`：有 first responder、无 first responder。
- `ui.scrollToElement`：列表中向下找到目标、达到底部仍找不到、容器限定。
- `ui.alert.respond` 先做 spike 测试：验证 alert button view path 是否可稳定返回并被 `ui.tap` 触发；未通过时只实现 query/path 建议，不实现直接点击。

### 集成验证

- `swift test`
- `xcodebuild -project iOSExploreServer/iOSExploreServer.xcodeproj -scheme iOSExploreServer -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build`
- 若需要跑 iOS framework 测试，先用 `xcrun simctl list devices available` 确认本机存在的 simulator 名称，再指定 `-destination`；不要在实现计划里写死某个可能不存在的设备名。
- 更新 README/docs 后跑 `git diff --check`。

## 13. 文档更新要求

实现同一轮必须更新：

- `README.md` 命令清单和总数。
- `AGENTS.md` UIKit 模块边界与命令清单。
- `docs/agent_instructions.md` 同步根指令。
- `docs/uikit/README.md`，当前仍写 4 个命令，需改为实际数量。
- `docs/uikit/reading-guide.md` 和 `docs/uikit/uikit-file-reference.md` 新增文件档案。

## 14. 后续路线

第一批 5 个命令落地后，再根据真实 agent 流程补第二批：

1. `ui.picker.select`
2. `ui.device.info`
3. `ui.app.state`
4. `ui.web.evaluateJavaScript`
5. `ui.logs.recent`

MCP server 放在第一批命令稳定之后做：读取 `help`，把 action/inputSchema 映射为 MCP tools，并处理 `ui.screenshot` 的 image content 映射。

建议实施顺序按风险从低到高，而不是按 P0/P1：

1. `ui.keyboard.dismiss`
2. `ui.navigation.back`
3. `ui.wait`
4. `ui.scrollToElement`
5. `ui.alert.respond`（spike 先行）

## 15. 自查

- 无未定稿语句。
- 第一批只包含 5 个命令，未把 MCP server 混入实现范围。
- 每个命令都有 input、output、行为、错误、日志。
- 已吸收交叉评审：`ui.wait` 双层超时、scroll 原语抽取、alert 点击 spike、文本采集 helper、错误码收敛。
- 保持 core 不依赖 UIKit。
- 复用现有 typed input、locator、snapshot、logging、error factory 边界。
