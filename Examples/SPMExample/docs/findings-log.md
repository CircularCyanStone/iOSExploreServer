# iOSExploreServer / iOSDriver 发现台账

> 持续累积的问题与验证记录。每条带状态、级别、复现、根因、建议。新会话测试前**先读此文件**，避免重复发现。
>
> **级别**：P0 安全/数据损坏 · P1 功能错误/skill-库断点 · P2 一致性/健壮性 · P3 文档/示例
> **状态**：🔴 待修复 · 🟠 待确认/改进 · ✅ 已修复 · 🟢 设计特性(记录) · ⭐ 正面验证

---

## 🔴 待修复

### F-01【P0·安全】密码明文经 UIFieldEditor 子节点泄露
- **场景**：注册/登录/重置页密码框（isSecureTextEntry）**编辑态**
- **现象**：`ui.tap(password_field)` 成为 firstResponder 后，`ui.inspect`（宽过滤）会输出密码框内部子节点 `UIFieldEditor`，其 `value` / `semanticText`(source=accessibilityValue) 为**密码明文**。password_field 本身 text=null（正确），ui.input 返回 masked（正确），但子节点绕过了保护。
- **复现**：
  1. `ui.tap(register_password_field)` → isFirstResponder:true
  2. `ui.input(register_password_field,"CCC_pass123")` → masked
  3. `ui.inspect(maxTargets:15)` → 子节点 `path:"root/0/0/3/2" type:"UIFieldEditor" value:"CCC_pass123"`
- **根因**：ui.inspect 序列化 target 时未对"祖先链含 isSecureTextEntry UITextField"的子节点屏蔽 value
- **建议**：序列化时，若节点祖先链含 isSecureTextEntry==true 的 UITextField，屏蔽该节点 text/value/semanticText（与 textField.text=null 对齐），或将 UIFieldEditor 降级为 minimal。建议与 F-16 用同一套 `explore_secureTextEntryAncestor` 祖先链 helper 统一修复
- **2026-07-15 动态确认**：100% 复现。`root/0/0/2/2 type=UIFieldEditor value="123456" semanticText="123456"`。三处取值点定位：`UIInspectCollector.swift:525-532`(value)、`:403-441`(semanticText)、`textualValue`(:488) 只护 textField 本体不护子节点；`UIKitInternalUtils.swift` 无 secure 祖先链检查
- **状态**：🔴 待修复（动态确认）

---

## 🟠 待确认/改进

### F-03【P2·一致性】tap 与 input "目标找不到" 错误码不统一
- **现象**：`ui.tap(不存在identifier)` → `code:"target_not_found"` + 恢复指引；`ui.input(不存在identifier)` → `code:"invalid_data"` + message:"input target not_found"（无指引）
- **根因**：input 复用了通用 invalid_data 码，未对"目标不存在"单列
- **建议**：input 也用 target_not_found + 同款恢复指引，invalid_data 留给参数格式错误。改 `UITextInputExecutor.swift:40` 复用 `UIKitCommandError.targetNotFound`
- **2026-07-15 精确化**：grep 全库确认 ui.input 是 tap/control.sendAction/scroll/scrollToElement/swipe/longPress **6 个命令里唯一**用 invalid_data 表达"目标未找到"的离群点，且 `code=invalid_data` 与 `message="input target not_found"` 自相矛盾。ambiguous 用 invalid_data 是全库一致惯例（无需改）
- **状态**：🟠 待改进

### F-04【P2·健壮性】ui.input 拒绝换行符且原因不明
- **现象**：含 `\n` 返回 `input_rejected: text input was rejected or altered by delegate`；`\t`/emoji/中文/超长均 OK
- **根因**：UITextField.insertText("\n") 被 UIKit 拒绝（return 键触发 action 而非插入换行，UITextField 与 UITextView 固有差异）
- **建议**：错误 message 补充被拒字符（"newline not allowed in UITextField, use UITextView"）；文档标注
- **2026-07-15 结案**：UITextView 代码上**接受**换行（`UITextInputExecutor.swift:92`+:95-96 决定性证据；动态确认 `"line1\nline2\nline3"` → code:ok finalText 含换行）。拒换行仅是 UITextField 的 UIKit 固有行为（return 键触发 action 而非插入），非库主动拒绝。message 改进见新发现 F-23
- **状态**：✅ 结案（仅需 F-23 改 message + 文档标注 UITextField/UITextView 差异）

### F-05【P3·文档/示例】AuthService 内存单例，重启丢状态
- **现象**：注册/重置的账号在 build_run/launch 重启后失效，test 密码回到 123456
- **影响**：跨 build 端到端用例失效（如 e2e 注册用户重装后没了）；测试不可重复
- **建议**：示例 README 标注"内存单例重启重置"；测试用例每次自建账号或固定预置 test/123456
- **状态**：🟠 待文档

---

## 🔴 2026-07-15 复杂场景探测新增（F-16~F-45）

> 两阶段编排（4 静态并行 + 1 动态独占串行）产出。详见 [complex-scenario-probe-report-2026-07-15.md](./complex-scenario-probe-report-2026-07-15.md)。

### ✅ 同日修复（2026-07-15，3 subagent 按文件域隔离并行）

| 编号 | 修复 | 验证 |
|---|---|---|
| F-16 | `UIViewHierarchyCollector.swift:328` secure 屏蔽 text.value | ✅ xcodebuild 489 |
| F-01 | `UIKitInternalUtils.swift:75-98` 新增 `explore_secureTextEntryAncestor` + `UIInspectCollector.swift` 三处检查（:404/:487/:537，与 F-16 共用 helper） | ✅ xcodebuild 489 |
| F-18 | `UIKitActionExecutor.swift:214-226` tap 前校验 isEnabled → activated:false/disabled | ✅ xcodebuild 489 |
| F-03 | `UITextInputExecutor.swift:36-48` notFound 改 targetNotFound + 恢复指引 | ✅ swift 289 |
| F-23 | `UIKitCommandError.swift:499-514` inputRejected 加 `singleLineField` 参数 + 换行提示 | ✅ swift 289 |
| F-24 | `UIKitCommandError.swift:42-43` stale_locator message 补文本追踪限制 | ✅ swift 289 |
| F-17 | `AuthService.swift:31` 删明文密码 | ✅ build SPMExample |
| F-19 | Login/Register/ResetVC 同步 `guard !isLoading` + isLoading 收敛进 updateLoadingState | ✅ build SPMExample |
| F-20 | Register/ResetVC 新增 `presenterForAlert()` 离屏时回退到 keyWindow rootVC 链顶端 | ✅ build SPMExample |
| F-21 | Home/Register/ResetVC present 前 `presentedViewController == nil` 检查 | ✅ build SPMExample |
| F-32~F-38 | 5 个 skill 文档校正（swipe 参数/工具映射/submit 默认值/TTL 120s/\n 限制/navigation.back strategy/call_action 兜底） | ✅ 对照源码 |

**测试总计**：`swift test` 289 passed / `xcodebuild test`（iOS framework）489 passed，0 failed。示例App build SUCCEEDED 0 警告。新增测试文件：`UISecureTextLeakTests`（F-16/F-01，含 helper 直测 + scrollSubtree/labelSubtree 模拟 UIFieldEditor）、`UIKitActionExecutorTests`（F-18）、`UIInputTests`（F-03）、`UIKitCommandErrorTests`（F-23/F-24）。

**未修（有意）**：F-02（根因在 MCP 客户端侧、不在被测库内，需改 `iOSDriver/src/schemaMapper.ts`）、F-25/F-26/F-27/F-28/F-29（设计特性/记录项）、F-30（补 SwipeTest 真删除测试床，待定）、F-39（destructive 偶发失败待核 alert 报告）、F-40~F-45 零碎项（部分已随 skill 校正处理）。

### F-16【P0·安全·库bug】ui.topViewHierarchy 经 text.value 泄露密码明文（非编辑态、默认参数）— 比 F-01 更严重
- 任何 isSecureTextEntry UITextField，ui.topViewHierarchy 节点 accessibilityValue="••••••" 正确，但 text.value=明文。**非编辑态、detailLevel=appearance 默认即触发**。LoginVC + InputTestVC 两处复现，泛化所有 secure UITextField
- 根因：`UIViewHierarchyCollector.swift:328-335` textInfo 直接 `textField.text`，未检查 isSecureTextEntry（UITextField.text 总返回明文）
- 建议：`:329` 改 `value: textField.isSecureTextEntry ? nil : textField.text`（一行，与 UIInspectCollector.textualValue:488 对齐）
- 状态：🔴 待修复（动态确认 100%）

### F-17【P1·示例App】预置密码明文进 os_log，LogRedactor 脱敏不掉
- `AuthService.swift:31` `logger.info("...预置测试账号: test/123456")`，DEBUG 全开捕获 → app.logs.read 返回明文。LogRedactor 正则只认 key=value 格式，裸值不匹配（token=xxx 格式则被脱敏，依赖巧合）
- 建议：删明文密码；库文档明确 LogRedactor 只覆盖 key=value/JSON key 格式
- 状态：🔴 待修复

### F-18【P1·库bug】ui.tap 用 sendActions 不校验 isEnabled，禁用态按钮仍触发
- `UIKitActionExecutor.swift:207-222` executeTap 的 .controlTouchUpInside 分支直接 sendActions(for:)，无 isEnabled 守卫。UIKit 中 isEnabled 只拦截真实触摸追踪，不拦截编程式 sendActions
- 影响：App loading 时 loginButton.isEnabled=false 的防重入被绕过（与 F-19 联动致双登录）
- 建议：分支前判断 `if let c = located.view as? UIControl, !c.isEnabled { 返回 activated:false/disabled }`
- 状态：🔴 待修复

### F-19【P1·示例App】登录/注册/重置按钮 action 无防抖，isEnabled 在 async Task 内才置位
- `LoginViewController.swift:213-228` loginButtonTapped 是 fire-and-forget，isEnabled=false 在 `Task {@MainActor in updateLoadingState}` 体内异步调度，两个同步 sendActions 都在 Task 前完成。无 `guard !isLoading`。注册/重置页同构
- 动态确认：并行双 tap → loginButtonTapped×2、登录请求×2、HomeVC viewDidLoad×2（日志铁证）
- 建议：action 开头加同步 `guard !isLoading else { return }; isLoading = true`，或 isEnabled=false 移到 Task 外
- 状态：🔴 待修复（与 F-18 共同修才能根治）

### F-20【P1·示例App】注册 in-flight 时 navigation.back 打断，成功 alert 丢失
- `RegisterViewController.swift:285-297` showSuccessAndNavigateToLogin 的 `self.present(alert)` 在 self 已 pop、view.window==nil 时静默失败（仅 console warning）。ResetPasswordVC 同构
- 动态确认：tap register → 立刻 navigation.back → 等 2.5s → alert.available=false（注册实际成功但无反馈）
- 建议：present 前检查 self.view.window != nil，离屏改其他反馈（delegate/通知）
- 状态：🔴 待修复

### F-21【P2·示例App】present(alert) 前未检查 presentedViewController
- Register/Reset/Home 的 present(alert) 无 `presentedViewController==nil` 判断，叠加 F-18 可能重复 present
- 状态：🟠 待改进（D-03 动态未复现双 alert，被 UIKit+snapshot 拦截，但代码缺陷在）

### F-23【P2·库bug】inputRejected message 不告知被拒字符、无恢复指引（F-04 根因）
- `UIKitCommandError.swift:487-491` 只给 "rejected or altered by delegate"，不区分 UITextField 拒换行 / delegate shouldChangeCharactersIn 返回 false / formatter 改写
- 建议：message 补失败原因（如 "newline not allowed in UITextField; use UITextView for multiline"）
- 状态：🟠 待改进

### F-24【P2·设计风险·深化 F-07】semanticDigest 不含展示文本，异步文本变化不触发 stale
- `UIKitTargetSemanticDigest.swift:43-77` digest 不含 UILabel/UITextField/UITextView 文本 → "加载中"→"已完成" 不触发 stale，agent 基于过期文本 tap 但校验放行。双标：开发者设 accessibilityValue 又会过度保护（连续 append 误报 stale）
- 建议：stale_locator 恢复指引/inspect 响应补"snapshot 不跟踪文本变化，文本敏感决策应重新 inspect"
- 状态：🟠 待改进（文档增强）

### F-25【P3·设计】exactlyOneOf 约束只在 Schema 输出层生效，运行时不强制
- `CommandInputSchema.swift:158-186` constraints 只在 toJSON() 生成 schema 时消费；`CommandInput.parse` 无约束评估。当前 tap/input/controlSendAction 靠 `UIKitViewLookupTarget.parse` 手写互斥兜底，未来易漏
- **2026-07-15 已标注**：`CommandInputSchema.swift` + `CommandInput.swift` 加「设计特性 F-25」注释，明确「仅 schema 层声明、运行时不强制，使用命令必须手写互斥校验」，防重复当 bug
- 状态：✅ 已标注（记录，当前无实际 bug）

### F-26【P3·设计】bool 严格拒数字，但 control.sendAction 的 switch value 接受 0/1
- `CommandFields.bool`（CommandField.swift:170-182）只认 JSON bool；`UIKitActionExecutor.switchBoolValue`（:432-443）对 UISwitch 接受 number 0/1。已文档化特例，但 agent 可能误推广
- **2026-07-15 已标注**：`CommandField.swift`(bool) + `UIKitActionExecutor.swift`(switchBoolValue) 加「设计特性 F-26」注释，说明「bool 严格拒数字，UISwitch value 接受 0/1 是唯一特例，勿推广」
- 状态：✅ 已标注（记录）

### F-27【P3·设计/示例App】边界输入无注入防护（UITextField 预期；生产化拼 SQL 有风险）
- 动态确认：`<script>`/`{{7*7}}`/`' OR 1=1--`/`../../../etc/passwd`/超长1000/零宽U+200B/emoji 全部 ok 原样存储无转义。UITextField 预期（非 HTML）。当前 AuthService 内存实现无 SQL 风险，但生产化拼 SQL 时 `' OR 1=1--` 是真实注入向量；超长无上限是性能隐患
- **2026-07-15 已标注**：`UITextInputExecutor.swift` + `UIInputModels.swift` 加「设计特性 F-27」注释，说明「文本字面量存储无注入防护，宿主拼 SQL/HTML 须自行参数化」
- 状态：✅ 已标注（记录，生产化注意）

### F-28【P3·示例App·可重复性】SceneDelegate 从 UserDefaults 读登录开关，跨启动持久
- `SceneDelegate.swift:22` `UserDefaults.standard.bool(forKey:"ios_explore_show_login")`，一旦置 true 后续每次 launch 都进登录流程，跨重启存活，源码只读不写
- **2026-07-15 已标注**：`:21-29` 加注释说明此 key 跨启动持久、源码只读不写、仅测试工程用，集成真实项目时删除 UserDefaults 读取
- 状态：✅ 已标注

### F-29【P3·示例App】AuthService.simulateFailureRate 是 public 可变属性（默认 0）
- `AuthService.swift:25` `var simulateFailureRate: Double = 0.0` 非 private，外部可设，潜在非确定状态旋钮
- **2026-07-15 已修**：grep 确认无外部写入 → 改 `private(set)` + 调试旋钮注释
- 状态：✅ 已修复

### F-30【P3·示例App·测试床缺口】SwipeTest「删除」swipe action 是空日志，无真重排
- `SwipeTestViewController.swift:243-257` delete handler 仅 log+completion(true)，无 deleteRows/数据变更；numberOfRowsInSection 硬编码 5。整个 SPMExample 无任何真 insertRows/deleteRows 列表 → 无法端到端验证"cell 增删后旧 snapshot 误中错位 cell"
- **2026-07-15 已补测试床**：`:89-94` 新增 `items: [Int]` 数据源，numberOfRowsInSection/cellForRowAt 数据驱动，delete handler 改 `items.remove` + `tableView.deleteRows(.automatic)` + 越界防御。现在 cell 增删重排可端到端测（D-07 同文本 cell 漂移边界前提）
- 状态：✅ 已补测试床

### F-32【P1·skill↔库不一致】ios-automation MCP 工具映射表列不存在的 ui_tap/ui_input
- `.claude/skills/ios-automation/skill.md:219,221` 列 mcp__iOSDriver__ui_tap/ui_input，但工具不存在（F-02），未提 call_action 兜底
- 状态：🟠 待改进

### F-33【P1·skill↔库不一致·最严重】list-interaction 全文用错 ui.swipe 参数名（混入 XcodeBuildMCP）
- `.claude/skills/ios-list-interaction/skill.md` L160/168/184/296/337/434 所有 swipe 示例用 `withinElementRef`，L429 取 `.elementRef`。实际 ui.swipe 参数是 direction/distance/accessibilityIdentifier/path/viewSnapshotID/cellAccessibilityIdentifier/cellPath/actionTitle（`UISwipeModels.swift:26-48`）。withinElementRef/elementRef 是 **XcodeBuildMCP** 的参数，iOSExploreServer 没有，inspect 也不返回 elementRef → 整个 skill 滚动/swipe 示例必然 invalid_data（两个 MCP server 概念混淆）
- 状态：🔴 待修复

### F-34【P1·skill↔库不一致】form-filling submit 默认值文档写 false，实际 true
- `.claude/skills/ios-form-filling/skill.md:409` 写 default:false，实际 `UIInputModels.swift:87` `submit:Bool=true`。agent 以为不传就不收键盘，实际默认收
- 状态：🟠 待改进

### F-35【P2·skill↔库】三个 skill 写 Snapshot TTL 60s，实际 120s
- form-filling:512/621、list-interaction:535 写 60s；`UIKitSnapshotStore.swift:194` `ttlSeconds=120`
- 状态：🟠 待改进

### F-36【P2·skill↔库】form-filling 声称支持 \n 多行输入，与 F-04 矛盾
- form-filling:68 + Example 3(L216-229) 演示向输入框填 "Line 1\nLine 2"；实际 UITextField 拒换行（F-04）。未区分 UITextField/UITextView
- 状态：🟠 待改进

### F-37【P2·skill↔库】navigation「back 无参数」，实际有 strategy/animated/waitAfterMs，且自相矛盾
- navigation:442-455 说"No parameters required"，Response 只列 {performed,topBefore,topAfter}；实际 `UINavigationBackModels.swift:27-48` 三参数。L665 又说"不能 dismiss 模态"但 strategy:"dismiss" 就是 dismiss
- 状态：🟠 待改进

### F-38【P2·skill↔库】form-filling 把 ui.control.sendAction 当核心命令，但它是 F-02 缺失工具，未提兜底
- form-filling:71-125,435-462 UISwitch/UISlider/Stepper/Segmented 全依赖 ui.control.sendAction，文档通篇未提 call_action 兜底
- 状态：🟠 待改进

### F-39【P2·skill↔库·已核对】alert-handling「destructive role 偶发失败」**虚构，已删**
- alert-handling 原 L401-431/L580/L616 称"destructive role lookup occasionally fails (1 of 42)"并给三层 fallback
- **核对结论：虚构**。`docs/alert-test-complete-report.json`（与 `reports/2026-07-13-14-skills-creation-project/` 下副本完全一致）42 条 `detailed_results` 里**唯一失败**是 test #42「Error: Invalid button index」——传 index=99 期望 `invalid_button_index` 实得 `alert_button_not_found`（错误码命名不一致，与 role 查找无关）。42 条用例无任何 role/destructive 相关测试名；`scenarios_tested` 里"Role-Based Response"整体标 PASS，仅附手写备注"Role 'destructive' failed - needs investigation"，不对应任何失败用例
- **源码佐证**：`UIAlertRespondExecutor.selectAction`（`Sources/iOSExploreUIKit/Support/Action/UIAlertRespondExecutor.swift:84-89`）对 cancel/default/destructive 三种 role 统一走 `$0.role == parsedRole` 等值匹配，无 destructive 特殊分支，结构上不可能比其他 role 更易失败
- **已改**：`.claude/skills/ios-alert-handling/skill.md` 删除「Known Issue + 三层 fallback」段、简化 Best Practice #2（去 retry 循环）、Limitations 去掉 destructive 条目、Test Coverage 失败归因改为 invalid button index、Production Readiness 去 destructive 表述。保留 97%/42 数据（报告 summary 确如此），仅纠正失败归因
- 状态：✅ 已核对（虚构，skill 段已删，附证据来源）

### F-40~F-45【P3·skill 文档】零碎问题汇总
- F-40 覆盖率数字自相矛盾/无源（form-filling description "200+ scenarios" vs Test Coverage "Total Tests:10"；automation "96.3%"、navigation/list "100%" 引 final-two-commands 报告名不匹配）
- F-41 测试报告相对路径在 skill 目录下无法解析（docs/xxx-report.json 实际在仓库根/reports/）
- F-42 过时 env IOS_EXPLORE_AUTOSTART=1（automation:285，实际 DEBUG 自动 start）
- F-43 form-filling "iOS 14.0+" 与部署目标 26.2 不符
- F-44 navigation.back 响应漏 strategy 字段（实测有）
- F-45 list-interaction scrollToElement 返回字段名（targetPath/targetType/container）待核对 executor
- 状态：🟠 待改进

### 推翻的动态假设（库设计正确，记录防重复探测）
- D-04 wait targetExists 无假阳性（elapsedMs 匹配 1.5s 登录延迟）
- D-05/D-07 path 是真实 subviews 索引稳定；cell 回收后旧 path 正确判 stale_locator（同文本无 identifier 边界未测，见 F-30）
- D-09 键盘弹起态不影响 tap（resolver 用 path/identifier 不用坐标）
- D-10 ui.controllers 真实反映导航栈
- D-11 snapshotChanged 稳定页无假阳性（超时返回）

## ✅ 已修复

### F-02【P1·skill↔库一致性】ui.tap/ui.input/ui.control.sendAction oneOf 拍平
- **原问题**：App server 注册的 ui.tap/ui.input/ui.control.sendAction 三个命令的参数定义使用了 JSON Schema oneOf（identifier/path 二选一），早期 MCP 客户端可能无法处理导致工具不可用
- **修复**：`iOSDriver/src/schemaMapper.ts:56-90` 实现 `flattenTopLevelComposition` 函数，自动拍平顶层 oneOf/anyOf/allOf：
  - 删除顶层 oneOf 关键字
  - 合并各分支的 properties 到顶层
  - 在各替代字段的 description 追加"⚠️ 与 X 二选一(互斥)"提示
  - 在工具 description 追加"accessibilityIdentifier / path 二选一(互斥:必须且只能提供其中一个)"说明
- **验证**：2026-07-15 实测 `mcp__iOSDriver__ui_tap` 工具存在且可调用，schema 无 oneOf 关键字，正确标记 viewSnapshotID 为 required
- **状态**：✅ 已修复

### F-06【P2】semanticText 对 accessibilityIdentifier 截断
- **现象**：长 identifier（如 register_confirm_password_field 28字符）被 textLimit 截断为 "register_confirm_password"，但 semanticTextSource 仍标注 accessibilityIdentifier（误导）
- **修复**：UIInspectCollector.swift:403 移除 identifier 截断，只对 label/text/title 截断
- **验证**：285 SPM + 344 framework 测试通过，新增 2 个回归测试
- **状态**：✅ 已修复（注意：accessibilityLabel 截断仍保留，属预期）

---

## 🟢 设计特性（记录，非 bug）

### F-07 viewSnapshotID 陈旧校验机制
- TTL 120s + 结构性变化检测；**不捕获 text 内容变化、不捕获 frame 位移**
- 错误码：`stale_locator`（过期）vs `not_actionable`（inspect 窄过滤致目标变 minimal）
- 含义：agent 可复用 snapshot 跨多次 input（2分钟内），但 inspect 时操作目标必须是 full target
- **2026-07-15 深化（关联新发现 F-24）**：`UIKitTargetSemanticDigest.swift:43-77` 证实 digest 不含 UILabel/UITextField/UITextView 展示文本 → 异步文本变化（"加载中"→"已完成"）不触发 stale，agent 基于过期文本 tap 但校验放行；双标：开发者设 accessibilityValue 又会过度保护（连续 append 误报 stale）。动态 D-04/D-06/D-11 确认 TTL/context 比对本身正确（ObjectIdentifier(window)+topVC）。指纹全量字段见 `UIKitFingerprintCollector.swift:34-91`（含 isEnabled/isHidden/alpha，不含 frame/text）

### F-08 path 是 subviews 真实索引（稳定），但 includeHidden:false 致 targets 序列不连续
- 定位应优先用 accessibilityIdentifier，不用 path/数组下标

### F-09 日志环形缓冲 2000 条，溢出 bufferOverrun
- app.logs.read 的 gap 字段会警告 lostIDRange；长会话需缩短 mark 间隔

---

## ⭐ 正面验证（值得保持的设计）

### F-10 alert 字段设计优秀
- 顶层独立结构 {available,title,message,buttons[{index,role,title,availableActions}],textFields}；availableActions 引导用 ui.alert.respond 而非 tap；navigationBar.available=false 语义清晰

### F-11 并发 ui.input 无错位
- 同消息并行 4 个 input（不同字段），文本正确落位（HTTP 单连接串行化）

### F-12 输入边界健壮（除换行符）
- 超长 ~2900 字符、emoji、family emoji(ZWJ)、中文、tab、引号 均正确

### F-13 ui.swipe 自适应三策略
- TableView swipeActions / UISwipeGestureRecognizer / UIPanGestureRecognizer，route 字段标注；actionTitle 精确定位

### F-14 ui.longPress 对无手势 view 返回 unsupported_target
- 错误码清晰，不误触

### F-15 ui.tap 激活路由区分类型
- UIButton→control.touchUpInside；UITextField→input.focus（isFirstResponder 反馈）

---

## 待探测（2026-07-15 更新）

> 本轮已覆盖大部分，详见 [complex-scenario-probe-report-2026-07-15.md](./complex-scenario-probe-report-2026-07-15.md)。剩余：

- ✅ ~~动态列表定位~~：D-07 已验，cell 回收后 snapshot 正确判 stale（同文本无 identifier 边界未测，需 F-30 补测试床）
- ✅ ~~wait 假阳性~~：D-04 已推翻，无假阳性
- ✅ ~~异步打断~~：F-19 双登录确认、F-20 注册 alert 丢失确认、F-21/D-03 alert 叠加部分
- ✅ ~~截图/日志隐私~~：截图视觉安全（✅）；日志 → F-16（topViewHierarchy 泄露）/F-17（os_log 明文）确认
- ✅ ~~复杂层级~~：D-09 键盘态推翻、D-10 controllers 真实、D-11 snapshotChanged 推翻
- ✅ ~~注入式字符串~~：F-27 已验，UITextField 预期无防护
- ✅ ~~skill 流程实测~~：F-32~F-39 静态全量比对完成
- ⏳ **仍待探测**：
  - 同文本 cell（无 identifier）滚动复用时指纹是否漏检——F-30 测试床已补，待端到端验证
  - UITextView 的 F-16/F-01（UITextView 通常非密码框，优先级低）
  - F-02 端到端验证（需重启 iOSDriver + 重开 Claude Code 会话，确认 ui_tap 工具出现在列表）
