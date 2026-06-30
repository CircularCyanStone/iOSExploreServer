# 操作三件套命令设计（ui.screenshot / ui.input / ui.scroll）

- **日期**: 2026-06-30
- **状态**: 评审后修订稿 v4。已过 4 路 Claude subagent 深度评审 + codex 完整独立交叉审查（第二轮网络恢复后出完整报告）。codex 独立发现 2 BLOCKER + 4 HIGH（均 subagent 漏、经真实代码验证）：错误码枚举落点、target 嵌套无法表达、UIImage 非 Sendable、adjustedContentInset、body 上限时机、secure inputRejected 泄密；已全部纳入。待用户审阅。
- **作者**: coo (coocy) + Claude
- **上游设计**: `docs/superpowers/specs/2026-06-21-ios-explore-server-design.md`

## 1. 背景与目标

iOSExploreServer 已有 8 个 action（core：`ping`/`echo`/`info`/`help`；UIKit：`ui.topViewHierarchy`/`ui.viewTargets`/`ui.tap`/`ui.control.sendAction`），typed command 模式已成熟。本阶段补齐"让 AI agent 闭环驱动 iPhone UI"的最后三块拼图：

- **看屏**：`ui.screenshot`——agent 是视觉的，没它几乎瞎。
- **输入**：`ui.input`——登录/搜索/表单都卡这。
- **滚动**：`ui.scroll`——列表、下拉刷新、翻页。

终极目标（上游 §14）：Mac 侧 MCP server 把每个 `action` 暴露为一个 MCP tool。

## 2. 范围

### In scope
- `ui.screenshot` / `ui.input` / `ui.scroll` 三个 UIKit 命令（放 `iOSExploreUIKit`，`ui.*` 命名空间）。
- core 两处配套改动：**响应 body 软上限**、**`Command` 协议自声明 timeout**。
- snapshot store TTL 调整；capability resolver 扩展（`.input`/`.scroll`）。
- MCP 适配映射表（文档）。

### Out of scope（明确不做，留 v2）
- `WKWebView` 内滚动 / 地图平移 / `UITextView` 内部长文滚动（非 `UIScrollView` 系；v2 优先走 `evaluateJavaScript("window.scrollBy")`）。
- `scrollToElement`（滚到指定 locator 可见）、独立 `ui.swipe` 命令。
- screenshot 的 `region` 裁剪、延时等待渲染、多 scene 选择。
- Mac 侧 MCP server 本身（本阶段只对齐其映射契约）。

## 3. 评审驱动的关键决策（修正点 + 理由）

本设计经 4 路并行 subagent 深度评审，以下修正均为评审硬结论（多路收敛）：

### 3.1 screenshot 不能用"全屏无损 PNG"（原设计低估体积一个数量级）
- **事实**：真机全屏 PNG 3–10MB，base64 后 3.3–10.7MB（原估 1–4MB 错）。
- **连锁风险**：`commandTimeout=10s`（`ClientSession.swift:36`）几乎必超时；`Task.cancel()` 抢占不了 `@MainActor` 同步渲染 → 超时已响应但渲染仍在主线程白跑到完，4 连接并发雪崩；4 个大响应同存活 ≈ 20MB+ → iOS jetsam。
- **决策**：base64 内联 envelope 路线**保留**（协议统一 + MCP `ImageContent` 原生 base64），但必须：
  1. **默认降采样**：input 加 `maxDimension?`（默认长边 1280px，对齐主流 LLM 视觉输入上限），`UIImage` 缩放后再 PNG 编码 → 典型 <1MB。
  2. **PNG 编码在 MainActor 同步、base64 可后台**（codex 发现修正：`UIImage` 非 Sendable，不能跨 actor；主线程 `drawHierarchy` + `UIImage.pngData()` 同步完成，得 `Data`（Sendable）后 base64 可放后台队列）。
  3. **core 新增响应 body 软上限**（见 §8），超限转 `responseTooLarge` 业务码而非崩溃/超时。
  4. **`Command` 自声明 timeout**（见 §8），screenshot 声明 30s。

### 3.2 screenshot 签发的指纹集必须与 viewTargets 逐字一致（codex 交叉验证修正）
- **事实**（对照真实代码修正原描述）：全树采集 helper **已存在**——`UIKitFingerprintCollector.fingerprints(in:includeHidden:digest:)`（`UIKitFingerprintCollector.swift:292`）递归 rootView 生成 `path → fingerprint` 表，viewTargets/topViewHierarchy 都调它。所以**不是"提取新 helper"**，而是**复用 + 对齐筛选**。
- **真问题**（codex 发现，subagent 全漏）：`fingerprints()` 是**无筛选全树**采集，真实 UI 全树节点数极易超过 `UIKitSnapshotStore.maxFingerprints=512`（`UIKitSnapshotStore.swift:178`）→ `insert` 返回 nil（`UIKitSnapshotStore.swift:233`）→ screenshot 响应 `snapshotID=null` + `snapshotUnavailableReason:"fingerprintLimit"`（复用 `UIKitSnapshotResponse.fields`）→ agent 该轮无陈旧防护（可接受，不阻断功能）。
- **关键约束**：screenshot 签发的指纹集必须与 `ui.viewTargets` 默认采集的指纹集**逐字相同**（同 rootView、同筛选：includeHidden/includeDisabled/includeStaticText/includeContainers/maxDepth），否则"截图拿 snapshotID → tap 带 snapshotID"会 `path missing`（`UIKitSnapshotStore.swift:279`）判 stale。
- **决策**：screenshot collector **直接复用 viewTargets 的同款采集入口**（共享一个 `collectFingerprints(context:)`，而非另走无筛选全树 `fingerprints()`），保证与 viewTargets 同筛选；超 512 时照常返回 `fingerprintLimit`，不阻断。文档与 help 写明此取舍。

### 3.3 input 的 becomeFirstResponder 窗口期 + 委托拦截
- **事实**：`becomeFirstResponder` 后立即 `insertText`，在 inputAccessoryView/IME/密码框上会间歇丢首字符；`shouldChangeCharactersIn` 委托会拒绝/改写 `insertText`。
- **决策**：
  1. `becomeFirstResponder` 后等一帧（`RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))`）+ 断言 `isFirstResponder && selectedTextRange != nil`，否则抛 `becomeFirstResponderFailed`。
  2. 注入后比对 `expectedText` vs `finalText`，不等返回业务码 `inputRejected`（带 expectedText + finalText），让 agent 决策。
  3. `secureTextEntry == true` 时**所有响应（含 inputRejected）不回明文、不回 expectedText**，只返回 `{masked, length}`（codex 发现：inputRejected 带 expectedText 会泄露密码）。
  4. MVP 白名单 `UITextField | UITextView | UISearchTextField`；其他 conform `UITextInput` 的自定义 view 返回 `unsupportedTextInputType`。

### 3.4 scroll 默认 animated:false + reachedExtent 算 adjustedContentInset
- **事实**：`setContentOffset(animated:true)` 期间 offset 持续变，紧接 screenshot 截中间态、`reachedExtent` 是预测值；裸 `contentInset` 下 `offset==contentSize-bounds` 永远 false；浮点 `==` 不可靠。
- **决策**：
  1. **默认 `animated:false`**（agent 场景求确定性），`animated` 可配；false 时 `setContentOffset` 后 `await Task.yield()` 让 layout settle。
  2. `reachedExtent` 用 **`adjustedContentInset`**（codex 发现：含 safe area 合并，非裸 `contentInset`）：`minY = -adjusted.top`，`maxY = max(minY, contentSize.h - bounds.h + adjusted.bottom)`，x 轴同理，**1pt 容差**；响应回传 `adjustedContentInset`。
  3. 响应回传命中的 scrollView `type`/path，供 agent 判断嵌套层是否命中预期。
  4. snapshotID 校验 **target view 的 path**（与 tap 对齐），文档写明。

### 3.5 capability resolver 对 UITextView 失效 + UITextView scroll 矛盾
- **事实**：`UIKitActionCapabilityResolver.resolve()` 有 `guard let control`（`UIKitActionCapabilityResolver.swift:41`），`UITextView` 非 `UIControl` → `.input` 声明永远空集。
- **决策**：为 `UITextInput` 遵循者与 `UIScrollView` 系**各开一条能力发现路径**，不依赖 UIControl guard。`UIKitActionKind` 加 `.input` / `.scroll`。
- **UITextView 矛盾修正**（codex 发现）：`UITextView` 是 `UIScrollView` 子类，简单 `view is UIScrollView` 会错误暴露 `.scroll`。MVP **排除 UITextView scroll**（内部长文滚动留 v2）：resolver 与 executor 都显式 `if view is UITextView { 不声明/拒绝 .scroll }`，与 §11 out-of-scope 一致，消除"既支持 UIScrollView 系又不支持 UITextView 滚动"的矛盾。

### 3.6 snapshot TTL 与 LLM 推理节奏错配
- **事实**：TTL 写死 10s；LLM 单轮推理 3–30s，截图后思考即过期 → stale 拒绝 → 重截图死循环。
- **决策**：TTL **10s → 30s**（`UIKitSnapshotStore.ttlSeconds`）；snapshotID 在 input/scroll 的 schema 里**标可选**（nil 时跳过 stale 校验，现有 `validateFreshness` 已支持）；stale 错误 `message` 写明"请重新调用 ui.screenshot 获取新快照"。

### 3.7 MCP 适配映射必须显式定义
- **事实**：MCP `ImageContent = {type:"image", data:<raw base64>, mimeType:"image/png"}`（裸 base64，非 data URI）；envelope `{code,data}` → MCP `isError` 映射未定义。
- **决策**：见 §9 映射表。

## 4. 一致性基线（三命令共同遵守）

- 放 `iOSExploreUIKit`，typed factory（`Command` + `CommandInput`）、`#if canImport(UIKit)`。
- 入参先 Foundation-only typed input 解析校验（走 core `CommandInputDecoder`，错误统一 `CommandInputParseError` → `invalid_data`），过才进 `@MainActor`。
- 执行核心 `@MainActor` + `throw UIKitCommandError` → adapter 顶层 `catch` 转 envelope（业务码不丢）。
- **独立 executor**（不塞进 `UIKitActionPlan`）：input/scroll 语义与 tap/control 不同（无"事件"概念），各建 `UITextInputExecutor` / `UIScrollExecutor`，与 `UIKitActionExecutor` 并列。
- 错误一律先扩 `UIKitCommandError` 工厂，再生成 envelope code/message/logMessage。
- **snapshotID 二分**：查询类（screenshot/viewTargets/topViewHierarchy）签发（`insert`）；动作类（input/scroll/tap/control）消费（`isStale`），**不签发**。
- 定位字段复用 `UIKitLocatorFields`（identifier/path/snapshotID）。

## 5. ui.screenshot 规格

- **action**: `ui.screenshot`（查询类，签发 snapshot）
- **input**（`UIScreenshotInput`，**非 EmptyCommandInput**）：
  - `maxDimension?`（Int，默认 1280，长边像素上限；1–4096）
  - `snapshotID?` 不消费（screenshot 是签发端）
- **output**：
  ```json
  {
    "image": "<base64 PNG>",
    "format": "png",
    "width": 1170, "height": 2532, "scale": 3,
    "pixelScale": 0.5,
    "snapshotID": "snap-12",
    "snapshotUnavailableReason": null
  }
  ```
  - `pixelScale`：实际下采样比例（=1 表示未缩放），供 Mac 侧坐标映射。
  - `snapshotID` / `snapshotUnavailableReason` 复用 `UIKitSnapshotResponse.fields(for:)`。
- **行为**：
  1. MainActor 复用 `UIKitContextProvider.currentContext(action:)` 取 window（与 tap/scroll 同源，不独立取"最前 window"）。
  2. 若 `transitionCoordinator != nil`（**VC transition** 进行中），返回 `transitionInProgress` 让 agent 重试。注意（codex 发现）：`transitionCoordinator` **不覆盖键盘动画**——键盘弹出/收起中间态是已知限制（§11），v2 用 window/layer animation keys 或键盘通知检测。
  3. `UIGraphicsImageRenderer` + `drawHierarchy(in:afterScreenUpdates:false)` 渲染（MainActor，截当前已渲染帧）。
  4. `UIImage` 按 `maxDimension` 等比缩放。
  5. **PNG 编码在 MainActor 同步做**（`UIImage.pngData()`；codex 发现：`UIImage` 非 Sendable，**不跨 actor 传递**，否则 Swift 6.2 严格并发编不过/需违规 unchecked）。降采样后典型 <150ms，30s timeout 兜底。得到 `Data`（Sendable）后 base64 编码可放后台队列。
  6. **体积前置检查**（codex 发现）：base64 前按 PNG bytes × 4/3 估算，超 `maxResponseBodyBytes` 直接返回 `responseTooLarge`，避免分配峰值（与 §8.1 两层限制呼应）。
  7. 同帧采集可交互目标指纹（复用 viewTargets 同款采集）→ `UIKitSnapshotStore.insert` → 返回 snapshotID。
- **错误**：`renderingFailed`（对齐 `hierarchyUnavailable`，HTTP 200 + internal_error）、`transitionInProgress`、`responseTooLarge`。
- **timeout**：30s。
- **日志**：start（maxDimension）；complete（耗时 ms、imageBytes、width×height、pixelScale、snapshotID）；failed（code）。**不记录 image 内容**。

## 6. ui.input 规格

- **action**: `ui.input`（动作类，消费 snapshot）
- **input**（`UIInputInput`，**扁平字段**，复用 `UIKitLocatorFields`；codex 发现：现有 `CommandField` 无 object decoder，`target` 嵌套对象无法表达）：
  - `accessibilityIdentifier?` / `path?`（二选一，必填一个）
  - `snapshotID?`
  - `text`（String，必填）
  - `mode?`（`replace` 默认 / `append`）
  - `submit?`（Bool，默认 true，是否 resignFirstResponder）
- **output**：
  ```json
  { "type": "UITextField", "locator": "<摘要>", "finalText": "中文🎉" }
  ```
  - `secureTextEntry` 时：`{ "finalTextMasked": "••••", "length": 4 }`。
- **行为**：
  1. resolve locator → `isStale` 防护（snapshotID 非 nil 时）。
  2. 校验目标 ∈ 白名单（UITextField/UITextView/UISearchTextField），否则 `unsupportedTextInputType`。
  3. `becomeFirstResponder()` → 等一帧 → 断言 `isFirstResponder && selectedTextRange != nil`，否则 `becomeFirstResponderFailed`。
  4. `replace` 模式：`selectAll()` + `deleteBackward()`。
  5. `insertText(text)`（一次性整段，触发 `shouldChangeCharactersIn` 委托一次）。
  6. 读 `finalText`（先读再 resign，避免 endEditing 清洗干扰）。
  7. `submit`：`resignFirstResponder()`。
  8. 比对 expectedText vs finalText，不等返回 `inputRejected`。**secureTextEntry 下所有响应（含 inputRejected）只回 `{masked, length}`，不回 expectedText/finalText**（codex 发现：防密码明文经响应/MCP transcript 泄露）。
- **错误**：`unsupportedTextInputType` / `becomeFirstResponderFailed` / `inputRejected` / `staleLocator`（复用）。
- **日志**：start（target 摘要、mode、text 长度非原文）；complete（type、finalText 长度、是否脱敏）；failed（code）。**不记录 text 原文、不记录密码明文**。

## 7. ui.scroll 规格

- **action**: `ui.scroll`（动作类，消费 snapshot）
- **input**（`UIScrollInput`，**扁平字段**）：
  - `direction`（`up`/`down`/`left`/`right`，必填）
  - `amount?`（Double，pt，**必须 >0**；codex 发现：负数反向滚、0 无动作；默认 = 可见区高度 × 0.5）
  - `accessibilityIdentifier?` / `path?`（可选锚定；**都缺时走 keyWindow 最前 scrollView**，需新增 `UIKitLocatorInput.parseOptional(...) -> UIKitViewLookupTarget?`——现有 parse 不允许都缺）
  - `snapshotID?`
  - `animated?`（Bool，默认 false）
- **output**：
  ```json
  {
    "container": "UICollectionView",
    "locator": "<摘要>",
    "offsetBefore": {"x": 0, "y": 0},
    "offsetAfter": {"x": 0, "y": 400},
    "reachedExtent": null
  }
  ```
  - `reachedExtent` ∈ `top`/`bottom`/`left`/`right`/`null`（null = 未到边界）。
- **行为**：
  1. resolve target（可选）→ 找 nearest `UIScrollView` 祖先；无 → `scrollContainerUnavailable`。
  2. `isStale` 防护（校验 target 的 path）。
  3. 算 delta（direction + amount）。
  4. `setContentOffset(targetOffset, animated:)`；false 时 `await Task.yield()`。
  5. 算 `reachedExtent` 用 **`adjustedContentInset`**（codex 发现）：`minY = -adjusted.top`，`maxY = max(minY, contentSize.h - bounds.h + adjusted.bottom)`，x 轴同理，1pt 容差；响应回传 `adjustedContentInset`。
- **边界**：只支持 `UIScrollView` 系，**但显式排除 `UITextView`**（codex 发现：UITextView 是 UIScrollView 子类，`view is UIScrollView` 会误暴露；resolver/executor 都 `if view is UITextView { 拒绝 }`）。不支持 WKWebView 内滚动/地图（v2）。
- **错误**：`scrollContainerUnavailable` / `staleLocator`（复用）。
- **日志**：start（direction、amount、target 摘要、animated）；complete（container 类型、offsetBefore/After、reachedExtent）；failed（code）。

## 8. core 改动（两处，谨慎）

### 8.1 响应 body 软上限（两层 + public 暴露）
- **两层限制**（codex 发现：序列化后检查太晚，PNG/base64/JSON 峰值已形成，只能避免发送不能避免分配）：
  1. screenshot collector 在 base64 **之前**按 PNG bytes × 4/3 估算，超限直接返回 `responseTooLarge`（避免分配峰值，见 §5 步骤 6）。
  2. core 在 `send` **之前**对 `serialized()` 总长做最后防线（兜底其他命令的大响应）。
- `maxResponseBodyBytes` 默认 6MB，**必须暴露到 `ExploreServer` public init**（codex 发现：当前 public init 固定 `.default`，`ExploreServer.swift:70-79`，宿主无法按需配置）。
- 超限转 `ExploreServerError.responseTooLarge`（HTTP 200 + envelope code，业务失败语义），记日志，不崩溃不截断。
- 与请求方向 `maxBodyBytes=1MB` 对称但独立配置。

### 8.2 Command 协议自声明 timeout
- `Command` 加 `var timeout: Duration?`（默认 nil = 用全局 `commandTimeout` 10s）；`AnyCommand` 透传该值。
- **传递路径**（codex 交叉验证发现，已对照真实代码修正原描述）：
  - 现状：`withTimeout` 在 `ClientSession.process`（`ClientSession.swift:278`）**包裹整个 `router.route`**，timeout 值须在调用 route **之前**确定；而 `command.timeout` 要 `Router.route` 锁内取到 command 后才知道。**不能**在 `Router.route` 内把 timeout 传给 withTimeout（时序上拿不到）。
  - 改法：`Router` 新增 `func commandTimeout(for action: String) -> Duration?`（锁内查 `AnyCommand.timeout`，**不执行 handler**）；`ClientSession.process` 先 `let ns = router.commandTimeout(for: action) ?? configuration.commandTimeoutNanoseconds`，再用该值 `withTimeout` 包裹 `router.route`。两步：先查表拿 timeout，再包裹执行。
- screenshot 声明 30s，其余默认（nil 走全局 10s）。
- 同时修 N1：超时单独 `code:"timeout"`（与 `internal_error` 区分），便于 MCP 层重试决策。

### 8.3 扩展 ExploreError 枚举（BLOCKER：新业务 code 需协议落点）
- **事实**（codex 发现）：`ExploreError` 当前只有 4 case（`unknown_action`/`invalid_data`/`internal_error`/`bad_request`，`Models.swift:134-147`）；现有 `staleLocator` 也映射成 `.invalidData`；契约测试 `ExploreServerErrorContractTests` 还锁定 `commandTimeout`=`.internalError`。
- spec 用了 `timeout`/`response_too_large`/`stale_locator`/`input_rejected`/`transition_in_progress`/`unsupported_text_input_type`/`become_first_responder_failed`/`rendering_failed`/`scroll_container_unavailable` 等 code——**必须先在 `ExploreError` 枚举加对应 case + rawValue**，否则编译不过或语义被塞回 `invalid_data`/`internal_error`，MCP 层（§9）无法按 code 分流重试/恢复。
- 同步更新 `ExploreServerErrorContractTests`（HTTP status ↔ envelope code 映射契约）与 `UIKitCommandError` 工厂；UIKit 侧新 code 复用"业务失败 HTTP 200 + code"约定。

## 9. MCP 适配映射表（Mac 侧实现契约）

| iOSExploreServer | MCP |
|---|---|
| `code:"ok"` + screenshot data | `isError:false`，`content=[{type:"image", data:<base64>, mimeType:"image/png"}]`（字段名对齐 MCP） |
| `code:"ok"` + input/scroll data | `isError:false`，`content=[{type:"text", text: <JSON>}]` |
| `code` ∈ {`invalid_data`,`stale_locator`,`input_rejected`,...} | `isError:true`，`content=[{type:"text", text: message}]`，**message 必须是 LLM 可执行恢复提示** |
| `code:"timeout"` | Mac 层静默重试一次后再上抛 |
| `code:"internal_error"` | `isError:true`（实现 bug 信号） |

**stale_locator 恢复文案**："snapshot expired or target changed; call `ui.screenshot` first, then retry with the new `snapshotID`."

## 10. 测试计划

### macOS SPM 单元（Foundation-only）
- 三命令 Input schema 解析/校验/默认值/非法值：`screenshotCommandSchemaMatchesInputFields`、`inputCommandSchemaMatchesInputFields`、`scrollCommandSchemaMatchesInputFields`（对齐现有 `UIKitCommandInputSchemaTests` 范式）。
- `maxDimension` 范围校验；`mode`/`direction` 枚举；`amount` 数值校验。
- core：`responseTooLarge` envelope 契约、`timeout` code 契约（对齐 `ExploreServerError` 工厂测试范式）。

### iOS framework 测试（@MainActor 真实 UIKit）
- **executor 全部留注入签名**（对齐 `UIKitActionExecutor.execute(_:context:)`），让命令逻辑可测、不依赖 UIKit 派发效果。
- **screenshot**：构造含 label+textField（对比色背景）的 window；解码 base64 回 `UIImage` 断言非 nil + `cgImage.width == returnedWidth` + **像素采样断言非全透明**（防空白位图假通过）；`renderingFailed` 用注入假渲染器测；`transitionInProgress` 用假 transitionCoordinator 测。
- **input**：replace 清空旧值、append 追加、`中文🎉` finalText、`shouldChangeCharacters` 委托改写→`inputRejected`、UILabel→`unsupportedTextInputType`、stale snapshotID 拒绝、`secureTextEntry` 脱敏。
- **scroll**：UICollectionView 超屏数据，`animated:false` 同步断言 offsetAfter.y 增大、reachedExtent（含 inset 容差）；纯 UIView→`scrollContainerUnavailable`。
- **capability 一致性**（防 collector/executor 分叉）：`UITextField` 声明 `.input`、`UIScrollView`/`UICollectionView` 声明 `.scroll`、`UIView`/`UILabel` 不声明、disabled 控件空集；executor 用同一 rawValue 做契约比对。

### 集成（端口 38399 串行）
- 三命令端到端 envelope：screenshot 断言 `data.image` 合法 base64（解码 count > 100）+ width/height/scale 正；input 断言 `finalText == "中文🎉"`；scroll 断言 `offsetAfter.y > offsetBefore.y`。
- screenshot 集成测试**显式抬高 `maxResponseBodyBytes`**（或断言默认下超大图被 `responseTooLarge` 拒，作负向契约）。
- 跨命令 snapshotID 链路：screenshot 签发 → 立即用同 path 调 input（未改视图）不抛 stale。

### 覆盖率
维持 ≥80%（当前 86.62%）。

## 11. 已知边界（v2）

- 非 scrollView 滚动：WKWebView 内（`evaluateJavaScript("window.scrollBy")`，公开可靠，优先）、地图平移、UITextView 内部长文。
- `scrollToElement`、独立 `ui.swipe`。
- screenshot region 裁剪、延时、多 scene。
- 非 iOS 17 的键盘/IME 差异。

## 12. 实现期验证项

- `UIGraphicsImageRenderer` 后台队列编码的线程安全（`UIImage` 跨 actor 传递）。
- 降采样后 base64 实测体积确认 < `maxResponseBodyBytes` 默认值。
- `becomeFirstResponder` 在测试 target（无宿主 App 生命周期）的获焦可靠性；若不可靠，相关断言标注仅在 App/集成环境跑。
- `Command.timeout` 对 `withTimeout` 的传递不破坏现有命令的 10s 默认。

## 13. 文件落位

```
Sources/iOSExploreUIKit/
  Commands/Screenshot/  UIScreenshotCommand + UIScreenshotModels + UIScreenshotCollector
  Commands/Input/       UIInputCommand + UIInputModels
  Commands/Scroll/      UIScrollCommand + UIScrollModels
  Support/Action/       UITextInputExecutor + UIScrollExecutor   （独立 executor，与 UIKitActionExecutor 并列）
  Support/Snapshot/     UIKitFingerprintCollector +collectAll（提取共享 helper）
  UIKitActionCapabilityResolver.swift   ← UITextInput/UIScrollView 能力路径
  UIKitActionKind.swift                  ← + .input / .scroll
  UIKitCommandError.swift                ← 新 case
  UIKitCommandRegistrar.swift            ← 注册 3 个，count 改 7
Sources/iOSExploreServer/
  Command.swift                          ← + var timeout: Duration?
  ExploreServerError.swift               ← + responseTooLarge / timeout
  HTTPListener.swift / ClientSession.swift ← maxResponseBodyBytes + 命令 timeout 传递
```

每个新文件随首个实现补齐类型/关键属性/关键方法 `///` 注释（写"为什么"与生命周期角色），不留 TODO；日志点覆盖 §5–7 列出的 start/complete/failed + 关键步骤，符合 AGENTS.md 日志/注释要求。
