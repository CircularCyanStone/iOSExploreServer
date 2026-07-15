# 复杂真实场景压力测试报告

**日期**：2026-07-15
**被测对象**：iOSExploreServer（iOS App 内嵌 HTTP 调试库，监听 localhost:38321）+ iOSDriver MCP（Mac 侧，把 App 的 `ui.*` 命令暴露给 agent）+ SPMExample 示例 App
**目标**：**发现问题**，不验证功能。命令能正常工作 = 没发现，不写进结果。
**环境**：iPhone 17 模拟器（065CC8DB-8978-46C5-82D6-C96625B608D8），profile `sim-app`，`IOS_EXPLORE_SHOW_LOGIN=1`，预置账号 test/123456。
**关联台账**：[findings-log.md](./findings-log.md)（本轮新增 F-16~F-39，更新 F-01/02/03/04/07）

---

## 1. 方法论：两阶段编排（非全程并行的原因）

用户的原始方案是「并行派 4-5 个 subagent 做动态测试」。执行前按 `dispatching-parallel-agents` skill 核查，确认**动态测试无法并行**：

- 运行时只有 **1 个模拟器、1 个 App 实例、1 个固定端口 38321**（多 App 实例无法共存），UI 状态（登录会话/当前页/firstResponder）全局共享。
- 多个 subagent 同时发 `ui.tap`/`ui.inspect` 会互相踩：A 在登录页 inspect 时 B 点了退出 → A 拿到首页 snapshot；A 填密码时 B inspect → 读到 A 的密码。
- HTTP 单连接虽串行执行命令（台账 F-11 验证），但只保证命令不交错，**不保证 UI 状态隔离**。

因此采用**两阶段**：

| 阶段 | subagent | 是否碰模拟器 | 覆盖侧重点 |
|---|---|---|---|
| 阶段 1（真并行） | S1 安全审计 / S2 skill↔库一致性 / S3 错误+边界 / S4 可重复性+动态假设 | ❌ 全部纯静态读源码 | 1 安全代码层、2 skill一致性、5 边界、6 错误一致性、8 可重复性 + 为 3/4/7 产出假设 |
| 阶段 2（独占串行） | D1 动态验证（1 个） | ✅ 独占模拟器 | 3 动态结构、4 异步时序、7 复杂层级 + 动态确认 1/5/6 关键点 |

合并 5 份产出 → 去重统一编号 → 按归属（库bug / skill-库不一致 / 示例App / 设计特性）和级别排序。

---

## 2. 覆盖的 8 大侧重点

| # | 侧重点 | 覆盖方式 | 产出 |
|---|---|---|---|
| 1 | 安全/隐私 | S1 代码审计 + D1 动态确认 | F-01 确认、**F-16 新 P0**、F-17 新 |
| 2 | skill↔库一致性 | S2 全量比对 | F-02 根因修正、**F-32~F-39**（3 条 P1） |
| 3 | 动态结构定位 | S4 假设 + D1 验证 | D-07 推翻（库正确），含同文本 cell 边界缺口 |
| 4 | 异步时序/竞态 | S4 假设 + D1 验证 | **C-01 双登录确认**、**D-02 alert 丢失确认**、D-03 部分 |
| 5 | 边界/异常输入 | S3 代码 + D1 动态 | F-04 结案、注入式无防护（预期） |
| 6 | 错误一致性 | S3 全局梳理 | F-03 精确化、F-23 根因 |
| 7 | 复杂层级 | S4 假设 + D1 验证 | D-09/D-10 推翻（库正确） |
| 8 | 环境/可重复性 | S4 代码确认 | F-05/07/09 再确认、F-28~F-30 新 |

---

## 3. 发现汇总

**本轮净增 24 条**（F-16~F-39）+ 更新 5 条已知（F-01/02/03/04/07）。**5 个动态假设被推翻**（验证库设计正确）。

| 编号 | 级别 | 归属 | 标题 | 确认度 |
|---|---|---|---|---|
| **F-16** | **P0** | 库 bug | `ui.topViewHierarchy` 经 `text.value` 泄露密码明文（非编辑态、默认参数） | ✅ 动态确认 100% |
| **F-01** | **P0** | 库 bug | `ui.inspect` 编辑态 UIFieldEditor 子节点泄露密码 | ✅ 动态确认 100%（仍未修复） |
| F-17 | P1 | 示例App | AuthService 预置密码明文进 os_log，LogRedactor 脱敏不掉 | ✅ 代码确认 |
| F-18 | P1 | 库 bug | `ui.tap` 用 `sendActions` 不校验 `isEnabled`，禁用态按钮仍触发 | ✅ 动态确认 |
| F-19 | P1 | 示例App | 登录/注册/重置按钮 action 无防抖，`isEnabled` 在 async Task 内才置位 | ✅ 动态确认（双登录铁证） |
| F-20 | P1 | 示例App | 注册 in-flight 时 `navigation.back` 打断，成功 alert 丢失 | ✅ 动态确认 |
| F-32 | P1 | skill↔库 | ios-automation 映射表列不存在的 `ui_tap`/`ui_input` 工具 | ✅ |
| F-33 | P1 | skill↔库 | list-interaction 全文用错 `ui.swipe` 参数名（混入 XcodeBuildMCP 的 `withinElementRef`） | ✅ 最严重 |
| F-34 | P1 | skill↔库 | form-filling `submit` 默认值文档写 false，实际 true | ✅ |
| F-03 | P2 | 库 bug | `ui.input` 目标未找到用 `invalid_data`（全库唯一离群，code 与 message 自相矛盾） | ✅ 精确化 |
| F-23 | P2 | 库 bug | `inputRejected` message 不告知被拒字符、无恢复指引（F-04 根因） | ✅ |
| F-24 | P2 | 设计风险 | semanticDigest 不含展示文本，异步文本变化不触发 stale（agent 基于过期文本决策） | ✅ 深化 F-07 |
| F-21 | P2 | 示例App | `present(alert)` 前未检查 `presentedViewController` | ✅ 代码确认 |
| F-35 | P2 | skill↔库 | 三个 skill 写 Snapshot TTL 60s，实际 120s | ✅ |
| F-36 | P2 | skill↔库 | form-filling 声称支持 `\n` 多行，与 F-04 矛盾 | ✅ |
| F-37 | P2 | skill↔库 | navigation「back 无参数」，实际有 strategy/animated/waitAfterMs，且自相矛盾 | ✅ |
| F-38 | P2 | skill↔库 | form-filling 把 `ui.control.sendAction` 当核心命令，但它是 F-02 缺失工具，未提兜底 | ✅ |
| F-39 | P2 | skill↔库 | alert-handling「destructive role 偶发失败」疑虚构（缺独立证据） | ⚠️ 待确认 |
| F-25 | P3 | 设计 | `exactlyOneOf` 约束只在 Schema 输出层生效，运行时不强制（靠手写兜底） | ✅ |
| F-26 | P3 | 设计 | bool 严格拒数字，但 `control.sendAction` 的 switch value 接受 0/1 | ✅ |
| F-27 | P3 | 设计/示例App | 边界输入（注入式/超长/零宽）无防护——UITextField 预期，但生产化拼 SQL 有注入风险 | ✅ |
| F-28 | P3 | 示例App | SceneDelegate 从 UserDefaults 读登录开关，跨启动持久 | ✅ |
| F-29 | P3 | 示例App | `AuthService.simulateFailureRate` 是 public 可变属性 | ✅ |
| F-30 | P3 | 示例App | SwipeTest「删除」swipe action 是空日志，无真重排（测试床缺口） | ✅ |
| F-40~F-45 | P3 | skill 文档 | 覆盖率数字自相矛盾、报告路径错、过时 env、iOS 14 vs 26.2、响应漏字段等 | ✅ |

**被推翻的动态假设（库设计正确，非 bug）**：D-04（wait 无假阳性）、D-07（cell 回收后 snapshot 正确判 stale）、D-09（键盘弹起态不影响 tap）、D-10（ui.controllers 真实反映栈）、D-11（snapshotChanged 稳定页无假阳性）。

---

## 4. P0 安全（必须优先修）

### F-16【P0·库bug】`ui.topViewHierarchy` 经 `text.value` 泄露密码明文 — 新发现，比 F-01 更严重

- **现象**：任何 `isSecureTextEntry=true` 的 UITextField，`ui.topViewHierarchy` 返回节点里 `accessibilityValue` 正确显示圆点 `"••••••"`，但同节点的 `text.value` 字段返回**明文密码**。**非编辑态、默认参数（detailLevel=appearance）就触发**，无需 firstResponder、无需子节点绕过。在 LoginVC 和 InputTestVC 两处均复现 → 泛化到所有 secure UITextField。
- **复现**：
  ```
  call_action ui.input(login_password_field, "123456")  → masked "••••••"
  ui.topViewHierarchy(detailLevel:"appearance")
  → login_password_field 节点: accessibilityValue="••••••", text.value="123456"
  ```
- **证据**（真实返回 JSON）：
  ```json
  {
    "accessibilityIdentifier": "login_password_field",
    "accessibilityValue": "••••••",
    "text": { "value": "123456", "fontName": ".SFUI-Regular", "fontSize": 17 },
    "type": "UITextField"
  }
  ```
- **根因**：`Sources/iOSExploreUIKit/Commands/TopViewHierarchy/UIViewHierarchyCollector.swift:328-335` 的 `textInfo(from:)` 对 UITextField 直接 `textField.text`，未检查 `isSecureTextEntry`。UIKit 中 `UITextField.text` 总是返回明文（`isSecureTextEntry` 只控制圆点渲染，不改 `.text`）。`accessibilityValue` 走 UIKit 的 secure 脱敏路径（圆点），但 `text.value` 绕过了。
- **修复方向**：`UIViewHierarchyCollector.swift:329` 改为 `value: textField.isSecureTextEntry ? nil : textField.text`，与 `UIInspectCollector.textualValue`（:488 `guard !textField.isSecureTextEntry else { return nil }`）口径对齐。**一行修复**。

### F-01【P0·库bug】`ui.inspect` 编辑态 UIFieldEditor 子节点泄露密码 — 确认仍未修复

- **现象**：secure UITextField 成为 firstResponder 后，`ui.inspect`（宽过滤）返回的 targets 含一个 `type:"UIFieldEditor"` 子节点，其 `value`/`semanticText` 为明文密码，`semanticTextSource:"accessibilityValue"`。
- **复现**：
  ```
  call_action ui.tap(login_password_field)  → isFirstResponder:true
  call_action ui.input(login_password_field, "123456")
  call_action ui.inspect(maxTargets:30)
  → root/0/0/2/2 type=UIFieldEditor value="123456" semanticText="123456"
  ```
- **证据**：
  ```json
  { "path": "root/0/0/2/2", "type": "UIFieldEditor",
    "value": "123456", "semanticText": "123456",
    "semanticTextSource": "accessibilityValue", "availableActions": ["input"] }
  ```
- **根因**：`UIInspectCollector.swift:525-532`（value 字段）只对 `UITextField`/`UITextView` 本体返回 nil，UIFieldEditor 都不是 → 走 `view.accessibilityValue` 返回明文；`:403-441`（semanticText）同理。`UIKitInternalUtils.swift` 只有 `explore_controlAncestor`，**没有 secure 祖先链检查**。textField 本体 `textualValue`（:488）有保护，但不覆盖子节点。
- **修复方向**：在 `UIKitInternalUtils.swift` 新增 `explore_secureTextEntryAncestor`（仿 `explore_controlAncestor` 向上找 `isSecureTextEntry==true` 的 UITextField 祖先），`UIInspectCollector` 三处取值（value/semanticText/textualValue）开头加 `if view.explore_secureTextEntryAncestor != nil { return nil }`。建议与 F-16 用同一套机制统一修复，避免两条路径保护口径分叉。

### 泄露路径全景

| 路径 | 泄露 | 说明 |
|---|---|---|
| `ui.input` 返回 masked | ❌ 否 | `"••••••"` |
| `ui.screenshot` 视觉 | ❌ 否 | UIKit 渲染圆点 |
| `accessibilityValue`（inspect/topViewHierarchy） | ❌ 否 | 正确掩码 |
| **`ui.topViewHierarchy` 的 `text.value`** | ✅ **是** | 非编辑态明文（F-16） |
| **`ui.inspect` 的 UIFieldEditor `value`** | ✅ **是** | 编辑态明文（F-01） |

> 即：ui.input 和截图两条主路径安全，但 ui.inspect（编辑态）和 ui.topViewHierarchy（任意态）两条观察路径都泄露。agent 一次 topViewHierarchy 就能读到用户密码，无需任何特殊操作。

---

## 5. P1（功能错误 / skill-库断点）

### F-18 + F-19【P1·库bug + 示例App】双登录竞态 — 日志铁证

- **现象**：登录页填好 test/123456 后，两个并行 `ui.tap(login_button)` 都返回 `activated:true`，`loginButtonTapped()` 被调用**两次**，产生两次登录请求、`HomeViewController.viewDidLoad` 触发两次（第二次 `setViewControllers` 覆盖第一次）。
- **根因（双因素）**：
  - **F-19（示例App）**：`LoginViewController.swift:213-228` 的 `loginButtonTapped()` 是 fire-and-forget——`loginButton.isEnabled = false` 在 `Task { @MainActor in updateLoadingState(...) }` 体内，该 Task 异步调度，两个同步 `sendActions` 都在 Task 执行前完成 → 按钮在两个 tap 到达时仍 enabled。无同步重入守卫（`guard !isLoading`）。
  - **F-18（库bug）**：`UIKitActionExecutor.swift:207-222` 用 `control.sendActions(for: .touchUpInside)` 实现 tap，**不校验 `isEnabled`**（UIKit 中 `isEnabled` 只拦截真实触摸追踪，不拦截编程式 sendActions）。即使按钮已禁用（loading 中），tap 仍能触发 → 放大了竞态窗口。
- **证据**（app.logs.read 日志）：
  ```
  🔵 登录按钮点击  ×2
  📤 开始登录请求: username=test  ×2
  ✅ 登录成功: username=test  ×2
  🔵 HomeViewController viewDidLoad  ×2
  ```
- **修复方向**：
  - F-19：`loginButtonTapped()` 开头加同步 `guard !isLoading else { return }; isLoading = true`，或把 `loginButton.isEnabled = false` 移到 Task 外同步执行。注册/重置页同构，一并改。
  - F-18：`UIKitActionExecutor.executeTap` 的 `.controlTouchUpInside` 分支前加 `if let c = located.view as? UIControl, !c.isEnabled { 返回 activated:false, reason:"disabled" 或抛 disabled }`，与人类触摸语义对齐。
  - **两者都修才能根治**：只修 F-19 仍可能在 isEnabled 置 false 后的瞬间被 F-18 绕过；只修 F-18 仍可能在两个 tap 都在 Task 调度前到达时双触发。

### F-20【P1·示例App】注册 in-flight 时 navigation.back 打断，成功 alert 丢失

- **现象**：注册页填合法数据 → tap register_button（触发 1.5s 异步）→ 立即 `ui.navigation.back` pop 回登录页 → 等 2.5s → 注册实际成功，但**成功 alert 从未出现**。
- **根因**：`RegisterViewController.swift:285-297` 的 `showSuccessAndNavigateToLogin()` 调 `self.present(alert)`，但此时 `self`（RegisterVC）已被 pop，`view.window == nil`。iOS `present()` 在此情况下只打印 console warning（"whose view is not in the window hierarchy"），不 crash 也不显示。ResetPasswordVC 同构。
- **复现**：
  ```
  call_action ui.tap(register_button)  → activated
  ui.navigation.back(strategy:"navigationController")  → pop to LoginVC
  [wait 2.5s]
  ui.inspect → topVC: LoginViewController, alert.available: false
  ```
- **修复方向**：注册/重置回调里 `present` 前检查 `self.view.window != nil`（或 `self.navigationController != nil`），已离屏时改用其他反馈（如在 LoginVC 上 present，或 delegate/通知）。

### F-17【P1·示例App】预置密码明文进 os_log，LogRedactor 脱敏不掉

- **现象**：`AuthService.swift:31` `logger.info("🔐 AuthService 初始化完成，预置测试账号: test/123456")`。SPMExample 在 DEBUG 全开捕获（`AppDelegate.swift:169-174` captureOSLog:true），该日志经 `app.logs.read` 返回明文 `123456`。`LogRedactor` 的正则只认 `password=xxx`/`"password":"xxx"`/`Authorization: Bearer xxx` 等 key 前缀格式，裸值 `test/123456` 不匹配 → 原样返回。
- **对照**：`AuthService.swift:73` 的 `token=\(token)` 命中 regex 被脱敏为 `token=[REDACTED]` —— 但这依赖日志格式巧合，脆弱。
- **修复方向**：示例 App 删 `AuthService.swift:31` 的明文密码（改为「预置测试账号: test」）；库文档明确 LogRedactor 只覆盖 key=value/JSON key 格式，宿主不应 log 裸敏感值。

### F-32 / F-33 / F-34【P1·skill↔库不一致】

- **F-33（最严重）**：`.claude/skills/ios-list-interaction/skill.md` 全文（L160/168/184/296/337/434）的 swipe 示例用 `"withinElementRef"`，L429 还从 inspect 返回取 `.elementRef`。但 `ui.swipe` 真实参数是 `direction/distance/accessibilityIdentifier/path/viewSnapshotID/cellAccessibilityIdentifier/cellPath/actionTitle`（`UISwipeModels.swift:26-48`）。`withinElementRef`/`elementRef` 是 **XcodeBuildMCP** 的参数名，iOSExploreServer 根本没有，inspect 也不返回 elementRef。**整个 skill 的滚动/cell swipe 示例按字面执行必然 `invalid_data`**（两个 MCP server 概念混淆）。
- **F-32**：`.claude/skills/ios-automation/skill.md:219,221` MCP 工具映射表列「点击→`mcp__iOSDriver__ui_tap`」「输入→`mcp__iOSDriver__ui_input`」，但这俩工具不存在（F-02），文档未提必须 `call_action` 兜底。
- **F-34**：`.claude/skills/ios-form-filling/skill.md:409` 写 `submit` 默认 false，实际 `UIInputModels.swift:87` 默认 true（写完 resignFirstResponder）。agent 以为不传 submit 就不收键盘，实际默认收键盘，改变 firstResponder 链。
- **修复方向**：skill 文档全面校正参数名/默认值/工具可用性，对 F-02 的三个命令统一标注「用 call_action 兜底」。

---

## 6. P2（一致性 / 健壮性）

| 编号 | 归属 | 要点 | 修复方向 |
|---|---|---|---|
| **F-03** | 库 bug | `ui.input` 目标未找到用 `invalid_data`，是 tap/control/scroll/scrollToElement/swipe/longPress 6 个命令里**唯一**离群点（其余都用 `target_not_found`），且 `code=invalid_data` 与 `message="input target not_found"` 自相矛盾、无恢复指引 | `UITextInputExecutor.swift:40` 改用 `UIKitCommandError.targetNotFound`，与 tap 同款 message+指引 |
| **F-23** | 库 bug | `inputRejected` message 只给「rejected or altered by delegate」，不区分 UITextField 拒换行/delegate shouldChangeCharactersIn 返回 false/formatter 改写三种失败，不告知被拒字符 | message 补失败原因（如 `newline not allowed in UITextField; use UITextView for multiline`） |
| **F-24** | 设计风险 | `UIKitTargetSemanticDigest.swift:43-77` 证实 digest 不含 UILabel/UITextField/UITextView 展示文本 → 异步文本变化（"加载中"→"已完成"）不触发 stale，agent 基于过期文本 tap 但校验放行；双标：开发者设了 accessibilityValue 又会过度保护（连续 append 误报 stale） | stale_locator 恢复指引/inspect 响应补「snapshot 不跟踪文本变化，文本敏感决策应重新 inspect」 |
| F-21 | 示例App | Register/Reset/Home 的 `present(alert)` 前无 `presentedViewController == nil` 判断 | 加判断 |
| F-35 | skill↔库 | form-filling/list-interaction 写 TTL 60s，实际 120s（`UIKitSnapshotStore.swift:194`） | 改 120s |
| F-36 | skill↔库 | form-filling Example 3 演示 `\n` 多行输入，与 F-04（UITextField 拒换行）矛盾 | 区分 UITextField/UITextView |
| F-37 | skill↔库 | navigation「back 无参数」，实际有 strategy/animated/waitAfterMs；且文档说「不能 dismiss 模态」但 `strategy:"dismiss"` 恰恰就是 dismiss | 补参数、删错误结论 |
| F-38 | skill↔库 | form-filling 把 `ui.control.sendAction` 当控件交互核心，但它是 F-02 缺失工具，未提兜底 | 标注 call_action |
| F-39 | skill↔库（待确认） | alert-handling 称「destructive role 偶发失败（1/42）」并给三层 fallback，但 `UIAlertRespondCommand.swift` 无对应缺陷分支 | 核对 `docs/alert-test-complete-report.json` 是否真有该失败记录，若无可删 |

---

## 7. 重要修正与结案

### F-02 根因被推翻（方向对、位置定错）

- **原台账结论**：「动态工具生成器无法处理 JSON Schema oneOf」。
- **S2 逐文件核实**：`iOSDriver/src/` **没有任何代码过滤 oneOf**。`schemaMapper.ts:43` 明写「App 端的 oneOf（identifier/path 二选一）仍由 inputSchema.oneOf 表达」原样透传；`toolRegistry.ts:51-79` 对每个 command 都映射成工具，还为 `ui.input` 专门追加描述（L68-70）；`toolName.ts:13-15` 仅做字符替换无过滤；`index.ts:9` fixedToolNames 不含这三个、不会冲突跳过。
- **真正结论**：iOSDriver **生成并返回了** ui_tap/ui_input/ui_control_sendAction 三个工具（含 oneOf inputSchema），但 **MCP 客户端（Claude Code）在 ListTools 时没把它们暴露给 agent**。过滤发生在 server↔agent 之间（客户端侧），**不在被测代码库内**。
- **修复方向**：iOSDriver 在 `schemaMapper.ts` 把顶层 `oneOf` 改写为客户端能消化的形式（拍平成 properties + required 互斥提示），或确认客户端 oneOf 支持后排查其他原因。

### F-04 结案：UITextView 接受换行（动态确认）

- **代码证据**：`UITextInputExecutor.swift:92` UITextField 与 UITextView 走同一 `insertText` 调用；`:95-96` 比对逻辑对 UITextView 放行换行（`insertText("\n")` 真正插入 → finalText 含 `\n` → 匹配 → 成功）。
- **动态确认**：`"line1\nline2\nline3"` 输入 UITextView 返回 `code:"ok"`，finalText 含换行；UITextField 同输入返回 `input_rejected`。
- **结论**：拒换行是 UITextField 的 UIKit 固有行为（return 键触发 action 而非插入），非库主动拒绝。findings-log「UITextView 待验证」可关闭。仅需在 F-23 的 message 和文档里标注此差异。

### F-03 / F-07 精确化与深化

- F-03：S3 grep 全库 6 个命令的 notFound 码，确认 ui.input 是唯一离群点，且 code/message 自相矛盾（见 P2 表）。
- F-07：S3+S4 双重确认指纹字段（`UIKitFingerprintCollector.swift:34-91` 含 path/viewType/identifierHash/isEnabled/isSelected/isHidden/alpha/isUserInteractionEnabled/ancestorDigest/semanticDigest，**不含 frame、不含 label/text 自由文本**）。D1 动态验证 D-06（导航后旧 snap 正确判 stale）通过 → context 比对（ObjectIdentifier(window)+ObjectIdentifier(topVC)）有效。

---

## 8. 已推翻的假设（库设计正确，记录以免重复探测）

| 假设 | 验证 | 结论 |
|---|---|---|
| D-04 wait targetExists 在转场动画中途假阳性 | 登录后立即 wait home_username_label，elapsedMs:1597ms（匹配 1.5s 延迟），attempts:31 | ✅ **无假阳性**，setViewControllers 动画不致误判 |
| D-07 cell 回收后旧 path 命中错位 cell | ScrollTest 30 cell 滚动 3 屏，旧 path tap 返回 `stale_locator` | ✅ **正确拦截**（注：cell 有唯一 identifier；同文本无 identifier 的边界未测，见限制） |
| D-09 键盘弹起态致 rootView 错乱/tap 偏移 | username_field 弹键盘后 rootView 仍 LoginVC.view，password_field 仍可准确 tap | ✅ **无影响**（resolver 全程用 path/identifier 不用坐标） |
| D-10 ui.controllers 报告栈与实际不一致 | ScrollTestVC stack=[ViewController,ScrollTestVC]，pop 后=[ViewController] | ✅ **真实一致** |
| D-11 snapshotChanged 在稳定页首轮误判 | Home inspect → wait snapshotChanged(timeoutMs:2000)，超时返回，attempts:20 | ✅ **无假阳性** |
| D-05 path 受 sibling 显隐影响漂移 | errorLabel 显隐后 login_button path 仍 root/0/0/4 | ✅ **库 path 稳定**（真实 subviews 索引），风险仅在 agent 误用 targets 数组下标 |

> **正面结论**：snapshot 校验（stale/not_actionable 三态）、wait 机制、path/identifier 定位、ui.controllers、键盘态处理 —— 这些核心机制在动态验证下**全部表现正确**。findings-log 的 F-07/F-08/F-10~F-15 正面项得到运行时佐证。

---

## 9. 边界输入动态验证

在真实 `login_username_field`（UITextField）测试：

| 输入 | 结果 | 存储值 |
|---|---|---|
| `<script>alert(1)</script>` | ok | 原样，无转义 |
| `{{7*7}}` | ok | 原样，无求值 |
| `' OR 1=1--` | ok | 原样 |
| `../../../etc/passwd` | ok | 原样 |
| `👨‍👩‍👧‍👦`（家庭 emoji ZWJ） | ok | 正确 |
| `a​b​c`（零宽 U+200B） | ok | len=5 正确 |
| 1000 个 `A` | ok | len=1000，**无长度上限** |
| `col1\tcol2` | ok | 正确 |
| `line1\nline2` | **input_rejected** | — |

- **结论**：无注入/转义防护是 UITextField 的预期行为（非 HTML 渲染）。当前 AuthService 内存实现无 SQL 风险，但**生产化时若这些值直接拼 SQL，`' OR 1=1--` 是真实注入向量**（F-27）。超长无上限是性能隐患。
- 呼应 S3 ✅：源码无字符串拼接 SQL/HTML 路径，identifier 精确 `==` 匹配，无注入风险。

---

## 10. 归属分布与修复优先级

```
库 bug        : F-16(P0) F-01(P0) F-18(P1) F-03(P2) F-23(P2) F-24(P2设计) F-25(P3) F-26(P3)
skill↔库不一致: F-32/33/34(P1) F-35/36/37/38(P2) F-39(P2待确认) F-40~45(P3)  + F-02根因修正
示例App       : F-17/19/20(P1) F-21(P2) F-27/28/29/30(P3)
设计特性/正面 : D-04/05/07/09/10/11 推翻（库正确）
```

**修复优先级建议**：

1. **P0 安全（立即）**：F-16（一行修复，影响所有密码框，默认参数即触发）+ F-01（secure 祖先链 helper，与 F-16 共用机制）。
2. **P1 库**：F-18（tap 校验 isEnabled）。
3. **P1 示例App**：F-19（按钮 action 同步防抖）、F-20（回调 present 前检查 window）、F-17（删明文密码日志）。
4. **P1 skill 文档**：F-33（swipe 参数名整体校正）、F-32/F-34（工具映射/默认值）。F-02 根因定位后，统一为三个命令标注 call_action 兜底。
5. **P2**：F-03/F-23（错误码与 message 一致化）、F-24（文档补 snapshot 文本限制）、其余 skill 文档校正。
6. **P3**：按需。

---

## 11. 未覆盖 / 限制

- **D-07 同文本 cell 漂移边界未测**：ScrollTest 30 cell 都有唯一 identifier（scroll.target.N），无法测「文本完全相同且无 identifier」时指纹是否漏检。需构造同文本 cell 测试页。且 SwipeTest「删除」是空操作（F-30），无真 cell 增删重排场景。
- **UITextView 的 F-16/F-01 未验**：UITextView 通常不用于密码，优先级低。
- **D-03 真正双 present 未复现**：HTTP 单连接串行 + snapshot stale 检查使 Home 双击退出的「第二个 present 实际执行」极难触发；代码缺陷（F-21）存在，但运行时被 UIKit + snapshot 双重拦截。
- **F-39 待确认**：alert-handling「destructive 偶发失败」需核对 `docs/alert-test-complete-report.json` 是否真有该失败记录。

---

## 附录：执行消耗

- 阶段 1：4 个静态 subagent 并行（S1 安全 445s/22 tools，S2 一致性 442s/30 tools，S3 错误边界 557s/35 tools，S4 假设 635s/23 tools）。
- 阶段 2：1 个动态 subagent 独占模拟器串行（D1，1245s/72 tools，12 类探测）。
- 主编排者上下文只用于派发/合并/写报告，未亲自跑任何 UI 命令（符合「编排者不亲自探测」）。
