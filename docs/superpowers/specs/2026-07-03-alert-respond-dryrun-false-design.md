# `ui.alert.respond` dryRun=false 实现方案

> 日期：2026-07-03
>
> 状态：spike 已验证，正式代码已接入 `Swizzler.swift`、`UIAlertAction+Trigger.swift`、`UIAlertController+TriggerAction.swift`、`UIAlertRespondExecutor`、错误码和注册入口；真实示例 App 闭环验证已完成（2026-07-04）：simple/threeButtons/loginInput/actionSheet/nested 五案例 `dryRun=false` 全部 `performed=true dismissed=true`，由系统私有 `_dismissWithAction:` 实现「自动 dismiss + 自动调 handler」（见 §13、§14）。
>
> 背景：本项目定位已明确为 Debug-only 开发工具（见 `AGENTS.md` Always follow 第一条）。此前 `agent-usage-protocol.md §7` / README 6.2 把 `UIAlertAction` handler 不可触发当成"公共 API 硬边界"，是按生产代码标准做的过度保守结论，在 Debug 工具定位下不再成立。本方案修订该结论，给出真正实现 `dryRun=false` 的路线。

## 1. 目标

让 agent 通过 `ui.alert.respond` + `dryRun=false` 配合 `buttonIndex` / `buttonTitle` / `role` 之一，真正触发任意 `UIAlertController` 的指定按钮 handler，并正常关闭 alert。覆盖范围不限于自己 App 的 alert——第三方 SDK 弹的、各种 `preferredStyle`、各种按钮组合都要能处理。

## 2. 核心问题

`UIAlertAction` 的点击 handler 是闭包，`init(title:style:handler:)` 之后被系统藏进私有 ivar。公开 API 既拿不出该闭包，也没有 `perform()` 之类触发方法，`alert.dismiss()` 也不跑 handler。本质问题：**怎么在不真实手指点按的情况下，把这个私有闭包取出来并调用**。Debug-only 定位下，可用 KVC 反射与 method swizzle 解决。

## 3. 两条技术路线（互补）

### 3.1 主线：swizzle `UIAlertAction` 初始化，创建时截获 handler

App 启动时（`registerUIKitCommands` 内）用 method swizzle 替换 `actionWithTitle:style:handler:` 类工厂方法，在调用原始实现后用 `objc_setAssociatedObject` 把 handler 参数绑到 action 实例上。触发时用 `objc_getAssociatedObject` 取出调用。这里不再写成 `initWithTitle:style:handler:`，因为 spike 证明当前 Swift/ObjC runtime 下可 hook 的入口是类工厂方法。

- 优势：不依赖任何私有 ivar（handler 是 init 公开参数，截获时直接拿到），对 iOS 版本漂移几乎免疫（只要 init 签名不变就能截）。
- 劣势：只对 hook 之后创建的 action 有效；hook 前已创建的（启动极早期）action 上没有关联对象。

### 3.2 兜底：KVC 反射现成实例

`UIAlertAction` 内部 ivar 历史上叫过 `_handler`（早期），后改为 `_actionHandler` 指向内部类 `_UIAlertControllerAction` 对象，真闭包再包一层。用 `value(forKey:)` 逐层试探已知路径，取到 block 后用 `@convention(block) (UIAlertAction) -> Void` 桥接调用。

- 优势：对任何已存在 action 实例有效，不依赖创建时机（覆盖 hook 前创建的、第三方 SDK 的）。
- 劣势：ivar 路径随 iOS 版本漂移，当前 iOS 26.x 确切结构须实测；需多路径探测 + 降级。

### 3.3 配合

触发时先试关联对象（主线，快、稳、无私有 API）；取不到再试 KVC（兜底）。两条都走 `#if DEBUG`。

## 4. 架构落点（操作下沉，命令层只调用）

不把 KVC/swizzle 写进 executor。分层：

### 4.1 Swizzler 工具类

`Sources/iOSExploreUIKit/Support/Runtime/Swizzler.swift`（`#if DEBUG`）。

封装通用 method swizzle：`swizzle(class:original:replacement:)`，处理幂等（关联对象标记已 hook）、线程安全（dispatch once 等价）、错误处理。所有 swizzle 走此入口，不散写。

### 4.2 UIAlertAction extension

`Sources/iOSExploreUIKit/Support/Runtime/UIAlertAction+Trigger.swift`（`#if DEBUG`）。

- `static func explore_installHandlerCapture()`：调 Swizzler hook `actionWithTitle:style:handler:` 类工厂方法，把 handler 存关联对象。`registerUIKitCommands` 启动时调一次。
- `func explore_performHandler()`：按"关联对象优先 → KVC 兜底"顺序拿 handler 并调用，ivar 路径探测 / block 桥接 / 签名对齐全封在此。

### 4.3 命令层

`UIAlertRespondExecutor`：`dryRun=false` 时定位 alert → 按 selector 选 action → 对真实展示中的 alert 调 `UIAlertController.explore_dismissWithAction(_:)`，让 UIKit 自己完成关闭与 handler 调用 → 对未 present 的测试对象回退 `action.explore_performHandler()` → 返回 `{ performed, dismissed, button }`。executor 只表达业务流程，不散写私有结构处理；后续 iOS 版本适配只改 Debug runtime extension，命令层和测试不动。

## 5. Debug 隔离

整个 `Support/Runtime/` 子目录 `#if DEBUG` 包裹。非 Debug 编译时代码不存在，extension 方法不存在；executor 的 `dryRun=false` 分支在 `#if DEBUG` 关闭时返回 `alert_release_unsupported`，不 crash。这个错误码表示“构建配置禁止触发”，不同于 `alert_button_required`（多按钮未指定选择器，补参数可解决）。确保误打包进 Release 也没有私有 API 残留。

## 6. 错误码与返回值演进

- 触发成功：`{ performed: true, dismissed: <bool>, button: { index, title, role } }`。`dismissed` 单独给，handler 调用后 alert 是否自动关闭需观察，不假设。
- handler 拿不到 / 调用异常：新错误码 `alert_button_trigger_failed`（与"能力不支持"区分）。
- 未指定按钮且 alert 多按钮：保留 `alert_button_required` 原语义（不猜默认）。
- Debug 关闭 / Release 构建：`dryRun=false` 回退 `alert_release_unsupported`，提示调用方改用 `dryRun=true` 查询或交给宿主自定义 action / 人工处理。

## 7. 实现步骤

1. **spike**：实测 iOS 26.x 下 `UIAlertAction` ivar 结构（KVC 路径），确认 handler 能取出并调用；验证 swizzle init 后关联对象存取可行。在 `AlertTestViewController` 5 个案例上验证。spike 通过才进后续。
2. 建 Swizzler 工具类（`#if DEBUG`）。
3. 建 `UIAlertAction+Trigger` extension（关联对象优先 + KVC 兜底，`#if DEBUG`）。
4. 改 `UIAlertRespondExecutor`：`dryRun=false` 走 extension 触发，错误码按 §6 演进。
5. `registerUIKitCommands` 启动时调 `UIAlertAction.explore_installHandlerCapture()`。
6. 测试：覆盖 5 种 alert 形态、Debug 关闭降级、多版本 ivar 路径探测、swizzle 后正常手指点击仍工作。
7. 文档：修订 `agent-usage-protocol.md §7`、README 6.2、`curl-json-loop-protocol.md` alert 段、`uikit-file-reference.md` 的 `UIAlertRespondExecutor` 条目。历史 specs/plans（`ui.tap` 两个设计稿"不使用私有 API"前提）属存档，不改正文。

## 8. 验证标准

- `AlertTestViewController` 5 个案例（`alert.trigger.simple` / `threeButtons` / `loginInput` / `actionSheet` / `nested`）`dryRun=false` 全部能触发对应 handler 并 dismiss。
- actionSheet 在 iPad popover 场景、嵌套 alert 的第二个、带输入框先填再触发，都覆盖。
- Debug 关闭时 `dryRun=false` 回退 `alert_release_unsupported`，不 crash。
- 构造不经过 hook 代码的 alert（模拟第三方 SDK），KVC 兜底也能触发。

## 9. 风险与适配

- **ivar 漂移**：多路径探测 + 单测覆盖已知版本；新 iOS 出来跑回归，失效就补路径。属工具持续维护项。
- **swizzle 全局副作用**：启动时 hook 一次 + 幂等标记；单测验断言 hook 后正常手指点击仍工作。
- **block 桥接签名**：handler 是 `(UIAlertAction) -> Void`，OC block 签名要对应，spike 阶段验证。

## 10. 相关文件

已有：
- `Sources/iOSExploreUIKit/Commands/Alert/UIAlertRespondCommand.swift` — adapter
- `Sources/iOSExploreUIKit/Support/Action/UIAlertRespondExecutor.swift` — 执行核心（`dryRun=false` 在 Debug 下选择按钮、真实展示 alert 交给 `UIAlertController` runtime 扩展关闭并触发 handler，未 present 测试对象回退直接触发 handler；Release 下回退 `alertRespondDisabledInRelease` / `alert_release_unsupported`）
- `Sources/iOSExploreUIKit/Support/Action/UIAlertInspector.swift` — alert 定位与摘要
- `Sources/iOSExploreUIKit/UIKitCommandError.swift` — 错误工厂
- `Examples/SPMExample/SPMExample/AlertTestViewController.swift` — 5 个 alert 案例（已就位）
- `Tests/iOSExploreServerTests/UIAlertRespondSpikeTests.swift` — 现有 inspector/executor 测试

新增：
- `Sources/iOSExploreUIKit/Support/Runtime/Swizzler.swift`
- `Sources/iOSExploreUIKit/Support/Runtime/UIAlertAction+Trigger.swift`
- `Tests/iOSExploreServerTests/UIAlertActionHandlerSpikeTests.swift`
- `Tests/iOSExploreServerTests/UIAlertActionTriggerTests.swift`

## 11. Spike 结论（2026-07-03）

验证环境：`xcodebuild -project iOSExploreServer/iOSExploreServer.xcodeproj -scheme iOSExploreServer -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:iOSExploreServerTests/UIAlertActionHandlerSpikeTests`；Xcode 使用 iPhoneSimulator SDK 26.2，实际运行目标为 iPhone 17 模拟器 iOS 26.3.1（arm64）。

结论：

- KVC / ivar 路径可用。当前 iOS 26.3.1 下 `UIAlertAction` 直接持有 `action._handler: @? -> __NSMallocBlock__`，`value(forKey: "handler")` 也能取到同一个 block 形态。因此当前兜底路径优先记录为 `handler`（KVC key），对应 ivar 为 `_handler`。
- block 签名验证通过。取到的 block 用 `@convention(block) (UIAlertAction) -> Void` 桥接调用，可以真实执行 handler；临时 spike 覆盖了标准 alert、三按钮 alert、带输入框 alert、actionSheet、嵌套 alert 第一层与第二层，事件流均被写入。
- swizzle 主线可行，但 selector 要修正。当前 Swift/ObjC runtime 中没有可直接 hook 的实例方法 `initWithTitle:style:handler:`；`UIAlertAction(title:style:handler:)` 走类工厂 `actionWithTitle:style:handler:`。用 `method_setImplementation` 替换该类方法，并在 replacement block 调原 IMP 后 `objc_setAssociatedObject` 存 handler，可以在新建 action 后通过关联对象取回 `__NSMallocBlock__` 并调用。
- Swift 桥接注意点：`objc_getAssociatedObject` 返回 Swift `Any`，调用前要先转成 `AnyObject` 再 `unsafeBitCast` 到 `@convention(block)`；否则会触发 Swift 的类型尺寸保护。KVC 返回值同理应在 runtime extension 内收敛为 `AnyObject`。
- 工程化调整：`UIAlertAction+Trigger.explore_installHandlerCapture()` 应 hook `actionWithTitle:style:handler:` 类方法，而不是文档前文中的实例 init selector。`Swizzler` 需要支持类方法替换或提供专门入口；命令层仍只调用 `explore_performHandler()`，不暴露 selector/KVC 细节。

## 12. 代码接入结果（2026-07-03）

已完成的代码接入不是泛指“工程化”，具体包括：

- `Sources/iOSExploreUIKit/Support/Runtime/Swizzler.swift`：提供 Debug-only 的类方法替换入口，集中处理 method replacement，避免每个 executor 自己散写 runtime 操作。
- `Sources/iOSExploreUIKit/Support/Runtime/UIAlertAction+Trigger.swift`：提供 `explore_installHandlerCapture()` 与 `explore_performHandler()`。前者在注册 UIKit 命令时安装一次 handler 捕获；后者按“关联对象优先，KVC key `handler` 兜底”的顺序取 handler，并用 spike 验证过的 block 签名调用。
- `Sources/iOSExploreUIKit/Support/Action/UIAlertRespondExecutor.swift`：`dryRun=true` 仍只查询；`dryRun=false` 在 Debug 下按 `buttonTitle`、`buttonIndex` 或 `role` 选择按钮，真实展示中的 alert 调 `UIAlertController.explore_dismissWithAction(_:)`（系统自动 dismiss + 调 handler），未 present 的 alert 回退 `UIAlertAction.explore_performHandler()`，返回 `{ performed, dismissed, button }`。多按钮但未指定按钮时返回 `alert_button_required`，指定按钮不存在时返回 `alert_button_not_found`，handler 无法触发时返回 `alert_button_trigger_failed`。
- `Sources/iOSExploreUIKit/Support/Runtime/UIAlertController+TriggerAction.swift`：封装系统私有 `_dismissWithAction:` 入口，让系统像真人点按钮一样「自动 dismiss + 自动调 handler」，嵌套 present 也由系统协调。
- `Sources/iOSExploreServer/Models.swift` 与 `Sources/iOSExploreUIKit/UIKitCommandError.swift`：新增 `alert_button_trigger_failed`，用于“按钮找到了，但 handler 取不到或执行失败”的场景。
- `Sources/iOSExploreUIKit/UIKitCommandRegistrar.swift`：`registerUIKitCommands()` 在 Debug 下安装一次 alert action handler 捕获；安装失败只记日志，不阻塞其它 UIKit 命令注册。

已完成的自动化验证：

- `swift test`（macOS SPM，含真实 TCP 端到端）2026-07-04 复核为 `208 tests` 全通过。
- `xcodebuild -project iOSExploreServer/iOSExploreServer.xcodeproj -scheme iOSExploreServer -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' test` 2026-07-04 复核为 `327 tests` 全通过（含 `UIAlertAction` handler 触发、KVC 兜底、`ui.alert.respond` dryRun=false 选择按钮 + 未 present 时 `dismissed=false` 契约）。
- 同上 `-configuration Release build` 通过，确认 Debug-only runtime 隔离：`perform`/`explore_dismissWithAction`/`explore_performHandler` 整套在 `#if DEBUG` 内，Release 二进制无私有 API 残留。

## 13. 真实闭环验证结果（2026-07-04）

真实闭环指：示例 App 弹出 alert → Mac 侧发 `ui.alert.respond dryRun=false` → App 内对应 `UIAlertAction` handler 被调用 → alert 关闭 → 响应 envelope 返回 `{ performed, dismissed, button }`。已覆盖两类环境：iPhone 17 模拟器 iOS 26.3.1（模拟器内 socket 路径）和 iOS 26.5 真机（`devicectl` 安装启动，`--ios-explore-autostart --ios-explore-open-alert-test` / `IOS_EXPLORE_AUTOSTART=1` / `IOS_EXPLORE_OPEN_ALERT_TEST=1` 自动起 server 并进入弹窗测试页，Mac 侧经 `iproxy` + `curl` 访问）。

触发与关闭的最终实现：真实展示中的 alert 走系统私有 `UIAlertController._dismissWithAction:`——系统点击 alert 按钮时的内部入口，由系统本身同时完成「dismiss 当前 alert」与「调用该 action 的 handler」，与真人点按钮完全一致。executor 不手动 dismiss，dismiss、handler、嵌套 present 全交给 UIKit 在同一套点击流程里协调。未 present 的 alert（logic test 构造的对象）回退 `UIAlertAction.explore_performHandler()` 直接调 handler block，`dismissed=false`。封装在 `Sources/iOSExploreUIKit/Support/Runtime/UIAlertController+TriggerAction.swift`，selector 名随 iOS 版本漂移需重新探测。

5 个案例的真实结果（案例间留约 0.6s 等系统 dismiss 转场落地后再触发下一个，避免连续 present 受阻）：

- **simple**（`alert.trigger.simple` → `buttonTitle:"确认"`）：`performed=true`、`dismissed=true`，button `{index:1, role:default, title:"确认"}`。事件流出现 `simple 确认`，UI 快照确认 alert 关闭。
- **threeButtons**（`alert.trigger.threeButtons` → `role:"destructive"`）：`performed=true`、`dismissed=true`，button `{index:0, role:destructive, title:"删除"}`。role 选择器真实路径命中删除按钮。
- **loginInput**（`alert.trigger.loginInput` → 先 `ui.input` 用 `path` 填用户名 `agent`，再 `buttonTitle:"登录"`）：`performed=true`、`dismissed=true`，button `{index:0, role:default, title:"登录"}`。
- **actionSheet**（`alert.trigger.actionSheet` → `buttonTitle:"拍照"`）：`performed=true`、`dismissed=true`，button `{index:0, role:default, title:"拍照"}`。`findAlert` 对 `.actionSheet` 样式同样命中。
- **nested**（`alert.trigger.nested` → 先 `buttonTitle:"继续"`，再 `buttonTitle:"完成"`）：第一层 `performed=true`、`dismissed=true`，系统关闭第一层并由 handler 弹出第二层（`findAlert` 随即命中「步骤 2/2」）；第二层 respond `完成` 同样 `performed=true`、`dismissed=true`。嵌套两层全部正常。

`dismissed` 不再靠同步观测 dismiss 完成判定（实测 `presenter.presentedViewController`、`alert.view.window`、`dismiss` 的 completion 回调在 `perform` 同步流程内都不更新，dismiss 真正落地只发生在 `perform` 返回后的 App 主事件循环）。改为：`_dismissWithAction:` 由系统在点击流程内关闭 alert，`dismissed` 以「已让系统触发关闭」为准返回 true；五个案例实测 alert 确实关闭，与返回值一致。

## 14. 备选方案与注意点

- **为何选 `_dismissWithAction:`**：目标是让系统像真人点按钮一样「自动 dismiss + 自动调 handler」，executor 不手动关闭。三条候选路在 iOS 26.3.1 的验证结果：
  - `_dismissWithAction:`（当前采用）：`perform(_:with:)` 单参数调用，系统自动 dismiss + 调 handler，嵌套也由系统协调，5 案例全过。注意它只在真实 App 工作——xctest 测试 host 里 alert 的 present/dismiss 转场跑不全，该方法在测试 host 里 `fired=0` 伪阴性，不能据此判断。
  - `_performAction:invokeActionBlock:dismissAndPerformActionIfNotAlreadyPerformed:`：用 IMP 直接调用会让 App crash（多 BOOL 参数 ABI / 内部断言），弃用。
  - `sendActions(for:.touchUpInside)` 模拟点击 alert 按钮：iOS 26 把 alert 按钮放在私有 `_UIInterfaceAction*` representation 容器里，普通视图树遍历（含 `alert.view.window` 整棵树）定位不到按钮 view（辅助功能树能看到所以真人能点），无法拿到 sendActions 目标，弃用。
- **`UIAlertAction.explore_performHandler()` 保留作 fallback**：未 present 的 alert（logic test 构造对象）`_dismissWithAction:` 要求 alert 在层级中，故走 `explore_performHandler()` 直接调 handler block，`dismissed=false`。它也仍是「绕过 UIKit 点击流程、直接调私有 handler block」的实现，本身不会触发系统自动 dismiss。
- **`ui.input` 在 alert 内的定位**：填 alert 输入框时，`ui.input` 配合 `viewSnapshotID` 必须用 `path` 定位，传 `accessibilityIdentifier` 会报 `viewSnapshotID is valid only with path`。
- **连续触发多个 alert**：系统 dismiss 转场是异步的，连续 `ui.alert.respond` 或连续 `ui.tap` 触发不同 alert 时，案例间需留约 0.5–0.6s 等当前 alert 关闭落地，否则下一个 `present` 可能受阻、`findAlert` 找不到目标 alert。
