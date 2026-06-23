# UIKit 命令扩展架构设计

## 背景与目标

`iOSExploreServer` 的长期主路径是“查询 App 当前状态，再下发命令并根据结果继续决策”。现有 `ui.topViewHierarchy`、`ui.viewTargets`、`ui.tap` 和 `ui.control.sendAction` 已验证这条路径，但它们仍位于 core target 中，且各自直接处理 UIKit 上下文、目标定位、错误和日志。

本设计的目标不是为现有四个 action 重新命名或扩张功能，而是建立稳定边界，使后续输入、滚动、截图、键盘、等待与有限手势能力可以增加为独立命令，而不再重写页面查询、定位、MainActor 调度和执行诊断。

本次设计确认以下原则：

- `iOSExploreServer` 保持只依赖 `Foundation` 与 `Network`。
- UIKit 能力作为独立可选模块，由宿主显式注册。
- 保持四个既有 action 的名称、已有必填参数、成功 envelope 与既有操作语义。
- 当前不实现鉴权、授权 UI、风险拦截、插件卸载或泛型 capability 平台；只保留未来接入位置。
- 新增命令不是本次重构的验收条件。模块边界通过契约测试与现有命令迁移验证，而不是为了测试架构额外堆功能。

## 当前问题与依据

1. `Package.swift` 只有一个 target，`ExploreServer.init` 在 `#if canImport(UIKit)` 下自动注册 UIKit 命令。core 因而感知 UIKit 的存在，不能满足严格的模块边界。
2. `UIKitViewLookup` 已正确复用 window、顶部控制器、identifier/path 查找与祖先判断，但 `ui.topViewHierarchy`、`ui.viewTargets`、`ui.tap`、`ui.control.sendAction` 仍各自获取上下文、映射错误并记录日志。未来增加命令会复制这些路径。
3. UIKit 命令依赖同一 target 内部的 `ExploreLogger` 与 `ExploreServerError`。拆成 target 后，不能通过将所有 internal 类型公开来解决，否则会把 core 内部实现泄漏为扩展 API。
4. `ui.viewTargets` 的 `suggestedActions` 按 role 推断，对 label、container、普通 view 等给出 `tap`，但当前 `ui.tap` 只稳定支持 `UIControl` 的 `touchUpInside` fallback。发现能力与真实可执行能力不一致。
5. `accessibilityIdentifier` 当前和展示文本一起受 `textLimit` 截断。截断后的 identifier 可能无法传回命令精确定位，违反 locator 契约。
6. `path` 是 `subviews` 下标链，只在当前页面结构未变化时有效；现在只能靠文档要求调用方立即使用，不能识别陈旧 path。

## 模块结构

```text
宿主 App / SPMExample
  ├─ import iOSExploreServer
  ├─ import iOSExploreUIKit
  └─ server.registerUIKitCommands()
           │
           ▼
iOSExploreUIKit
  ├─ UIKitCommandRegistrar
  ├─ Context
  ├─ Query
  ├─ Locator
  ├─ Action
  └─ Commands
           │
           ▼
iOSExploreServer
  ├─ HTTP / Router / Command / Models
  ├─ 通用命令失败与扩展日志接口
  └─ Foundation 内置命令
           │
           ▼
Foundation + Network
```

SPM 提供两个 library product：`iOSExploreServer` 与 `iOSExploreUIKit`。后者依赖前者。建议源码布局如下：

```text
Sources/
  iOSExploreServer/
    HTTP、Router、Command、Models、日志、通用错误、BuiltinHandlers
  iOSExploreUIKit/
    UIKitCommandRegistrar.swift
    Context/
    Query/
    Locator/
    Action/
    Commands/
      ViewHierarchy/
      ViewTargets/
      Tap/
      ControlAction/
```

所有现有 UIKit 文件（包括 Foundation-only 的 UIKit 领域模型）迁入 `iOSExploreUIKit`。该 target 仍允许在 macOS 构建：真实 UIKit 访问继续放在 `#if canImport(UIKit)` 中，纯 Foundation 模型和解析测试仍可由 `swift test` 覆盖。core target 不再出现 `UIKit` import 或 `canImport(UIKit)` 分支。

framework 工程同步新增 `iOSExploreUIKit.framework` target。两个 target 分别以 filesystem-synchronized root group 指向两个 `Sources/` 目录，UIKit framework 显式依赖并链接 core framework。两个 target 均保持 `SWIFT_VERSION = 5.0` 与 `BUILD_LIBRARY_FOR_DISTRIBUTION = NO`，避免 SPM Swift 6.2 源码与 framework 工程漂移。手动集成 framework 的宿主必须链接两个 framework。

## 注册与扩展 API

core 初始化时只同步注册 `ping`、`echo`、`info`、`help`。UIKit product 在 UIKit 可用平台提供唯一宿主入口：

```swift
import iOSExploreUIKit

let server = ExploreServer()
server.registerUIKitCommands()
```

`registerUIKitCommands()` 是同步、无配置、初始化期调用一次的 API。实现仅通过已公开的 `ExploreServer.register(_:)` 注册命令，不公开 `Router`，不引入插件生命周期、动态卸载或命令组配置。重复注册沿用 Router 现有的同 action 覆盖语义，但文档要求宿主只调用一次。

未引入或未调用注册入口时，server 可正常启动，`help` 不列 UIKit action。SPMExample 显式依赖并 import UIKit product；自定义 `greet`、`device` handler 不受影响。

## UIKit 领域边界

### Context

`UIKitContextProvider` 是所有真实 UIKit 读取和操作的唯一入口，运行在 `MainActor`，负责选择 foreground scene/window、root controller、top controller 和 top root view。

它返回只在当前调用内有效的内部 `UIKitContext`。其中的 `UIView`、`UIWindow`、`UIViewController` 不得进入 `Sendable` 模型、snapshot 缓存或 HTTP 响应。Context 同时生成 scene 标识、window 类型、root/top controller 类型等无敏感诊断摘要。未来多窗口支持通过可选 context selector 增加，默认 active-window 行为保持不变。

`UIKitQueryService`、`UIKitLocatorResolver` 的真实 view resolve 路径和 `UIKitActionExecutor` 均由 `@MainActor` 隔离；Command adapter 在 Router 的异步任务中通过 `await` 调用它们。adapter 负责记录进入 MainActor 前后的 action、耗时与失败码，不能把 UIKit 对象带回非隔离域。`UIKitSnapshotStore` 也归属 MainActor，避免为 UIKit 查询版本引入第二个共享锁或 `@unchecked Sendable` 边界。

### Locator

统一使用 `UIKitLocator`，由现有 `UIKitViewLookupTarget` 演进而来：

- `accessibilityIdentifier(String)`：完整、实时、唯一匹配；优先的稳定语义 locator。
- `path([Int])`：`root/0/2/1` 结构 locator；仅适合一次查询后的短生命周期。
- `windowPoint(x:y:)`：坐标 locator，仅供交互操作使用，不混入 view 查询。

后续可以增加 accessibility label、文本、role 或相对位置 locator，但当前不实现。`UIKitLocatorResolver` 只负责参数解析与实时 resolve，返回唯一目标、未找到、歧义或陈旧快照；它不触发 UI 事件，也不决定动作是否支持。

### Query

`UIKitQueryService` 承载 `ui.topViewHierarchy` 和 `ui.viewTargets`。两者的职责保持：前者用于完整结构和视觉验收，后者用于低 payload 的交互目标发现。采集器读取 UIKit 后立即转换为值类型，Foundation builder 继续负责 JSON、过滤和文本裁剪。

Query 与 Action 不得分别按 role 推断动作。两者共享 `UIKitActionCapabilityResolver`：它接收已提取的目标值描述和当前状态，输出真实可用的 `UIKitActionAvailability`。Query 把它序列化为 `availableActions`；Executor 在派发前用同一规则复核，避免 label、普通 view 或 gesture view 被错误宣传为可 tap。

`ui.viewTargets` 保持既有 `screen`、`targetCount`、`targets` 等字段，并追加：

- `snapshotID`：不透明、短 TTL 的查询版本标识。
- `availableActions`：当前 executor 实际能执行的动作，而不是仅凭 role 推断的建议。

`ui.topViewHierarchy` 也返回 `snapshotID`，使其已返回的 `path` 可进入同一陈旧检测流程；它不返回 `availableActions`。`availableActions` 只属于 `ui.viewTargets.targets`。

`accessibilityIdentifier` 是 locator，必须完整返回，不能受 `textLimit` 截断。title、label、placeholder、value 等展示文本继续裁剪；日志仅记录长度、数量和必要摘要。

`UIKitSnapshotStore` 只保存值类型记录：context fingerprint 与 `path -> target fingerprint`（类型、完整 identifier 的不可逆摘要、role 与必要状态）。绝不保存 `UIView`。默认最多保留 8 个快照、每个快照最多 512 个目标指纹、TTL 为 10 秒；先清理过期条目，再按最近最少使用淘汰。超过单快照指纹上限时查询仍成功，但 `snapshotID` 返回 `null`，调用方只能使用 identifier 或原有的即时 path 行为。

当执行命令携带 `snapshotID + path` 时，resolver 比较实时上下文与目标指纹；不匹配时保持既有 envelope 协议，返回 `invalid_data` 和固定语义消息“locator is stale; re-query”。未带 `snapshotID` 时保留现有 path 行为。identifier 始终实时解析，snapshot 只参与诊断。该校验只验证结构身份，不保证 frame、z-order 或 hit-test 结果；`ui.tap` 仍必须做实时 hit-test。

快照校验是尽力避免陈旧结构误操作，不承诺把动态 UIKit 树变成事务；调用方始终优先 identifier。

### Action

`UIKitActionExecutor` 接收已解析的 `UIKitActionPlan`，一次性完成 Context 获取、locator resolve、快照校验、可执行性检查、动作派发、结果和耗时日志。命令 adapter 不得直接遍历 UIKit view。

第一阶段 executor 只迁移现有动作：

- `tap`：保留 hit-test 和 `UIControl.sendActions(for: .touchUpInside)` fallback；不伪造私有 API 的系统触摸。
- `controlEvent`：保留指定 `UIControl.Event` 的 `sendActions(for:)` 行为。

`availableActions` 必须由 executor 能力和实时目标状态生成。可被查询到不表示一定可 tap；例如带 gesture recognizer 的普通 view 可作为发现结果，但在没有公开且稳定的执行方式时不得宣称可执行 tap。

未来 `input`、`scroll`、`focus`、`dismissKeyboard`、`screenshot` 只需各自增加 query/action plan 与 executor 分支，复用 Context、Locator、snapshot、日志和 error 映射。不要预先定义覆盖所有 UIKit 行为的泛型 action 协议树。

### Command adapter

每个 `Command` 仅完成四件事：解析 `ExploreRequest.data` 为领域 query/plan；调用 QueryService 或 ActionExecutor；将值结果转为既有 action 的 JSON；记录 action 级开始、完成、失败。它不持有 UIView，也不包含 target 遍历、hit-test 或事件派发逻辑。

现有 action 的参数和语义保持如下：

- `ui.topViewHierarchy` 与 `ui.viewTargets`：保持读操作和既有字段；只追加 `snapshotID`、`availableActions` 等兼容字段。
- `ui.tap`：仍支持 identifier/path 或 window x/y；可选接收 `snapshotID`，且维持现有 `dispatchMode`。
- `ui.control.sendAction`：仍支持 identifier/path 加 event；可选接收 `snapshotID`。

## 错误与日志

独立模块后，core 的传输错误不应继续含 UIKit 专用工厂，也不应为了复用把整个 internal `ExploreServerError` 公开。core 应公开最小的扩展支撑 API：

- 一个通用、值类型、可 `Sendable` 的 `ExploreCommandFailure`，承载 envelope code、对外 message 和内部 log message；它是扩展 command 失败的唯一 core 映射入口。
- 一个受控的扩展日志 API，允许扩展以字符串 category（如 `uikit.query`、`uikit.locator`、`uikit.action`）向现有 `ExploreLogging` sink 写入记录。

UIKit target 自己定义 `UIKitCommandError` factory，集中构造“上下文不可用、未找到、歧义、目标不支持、命中不一致、陈旧 locator”等语义，再映射为 `ExploreCommandFailure`。这样每个错误出口仍先经 typed factory，HTTP/envelope 保持统一，而 core 不持有 UIKit 失败细节。实施时应同步把现有“所有错误必须由 `ExploreServerError` 工厂创建”的项目规则改为“每个模块必须有唯一 typed error factory，并映射为 core command failure”，避免规则与模块边界冲突。由于当前 `ExploreError` 没有 `stale_locator`，本次不扩展 error-code 枚举，避免在模块拆分时改变既有 envelope code 契约。

各层的必需日志点：

- registrar：注册开始、命令数量、每个 action、完成。
- context：MainActor 查询开始、选中 scene/window、不可用原因。
- query：筛选条件、访问节点数、target 数、snapshot ID 摘要、耗时。
- resolver：locator kind、是否携带 snapshot、唯一/未找到/歧义/陈旧结果；不记录完整 identifier。
- executor：动作类型、目标类型、dispatch mode、执行前后状态、耗时、失败码。
- adapter：请求 payload key 数、响应结果与 error code。

日志不得记录 auth token、输入文本全文、完整 identifier、截图内容或大块 payload。

## 迁移顺序

1. 建立两个 SPM products/targets 与两个 framework targets；移动 UIKit 文件；移除 core 的 UIKit 自动注册。
2. 引入显式 `registerUIKitCommands()`；更新 SPMExample、framework 链接、测试 import，以及 `docs/architecture/index.md`、`docs/tools/network-tools.md`、`docs/runbooks/build-and-test.md` 和根 `AGENTS.md` 的模块/构建说明。
3. 将 Context、Locator、Query、Action 目录和内部服务落位；先以现有实现迁移，确保四个 action 行为不变。
4. 抽出 core 扩展日志/通用 command failure，以及 UIKit typed error factory；删除 core 中 UIKit 专用错误工厂。
5. 修正 identifier 截断；将 role 推断的 `suggestedActions` 迁为真实 `availableActions`。为兼容可暂时保留旧字段，并明确它不是执行保证。
6. 将 snapshotID、有限缓存和陈旧 path 检测作为独立子阶段实现；先验证 Context/Locator/Executor 迁移不改变既有动作，再加入这一正确性增强。旧调用方不传 snapshotID 时不改变行为。
7. 完成验证和文档更新后，再单独规划第一个新命令；不在本次重构里混入输入、滚动或截图实现。

## 测试与验证

macOS `swift test` 必须继续覆盖所有 Foundation-only 的 UIKit 领域模型：locator/path 解析、query 过滤、文本裁剪、target JSON、action-plan 解析、snapshot fingerprint 与过期判断、`availableActions` 映射。

iOS/Xcode 测试必须新增真实 UIKit 覆盖：多 scene/window 选择、collector、identifier/path resolve、snapshot 失效、hit-test、UIControl target-action、显式注册以及核心与 UIKit framework 链接。SPMExample 真机/模拟器验证至少覆盖“未注册时 help 无 UIKit action；注册后四个 action 可用；查询后按 identifier 与 path 执行；陈旧 snapshot path 以 `invalid_data` 被拒绝”。

每一步保持现有 `swift test` 通过，并额外构建 framework 工程和 SPMExample。迁移前后用 action-level contract tests 对比现有请求的响应字段与 dispatch mode，避免只因目录调整造成协议漂移。

## 后续命令路线

不在本次实现，但架构应按以下顺序支撑：

1. `ui.input.setText` 与 `ui.input.clear`：最直接完成“查询后输入”的闭环；只支持 `UITextField`/`UITextView`，需明确 first responder 与 editing event 语义。
2. `ui.scroll`：按 scroll-view locator 或目标 view 锚点移动，返回前后 contentOffset 与实际是否移动。
3. `ui.focus` 与 `ui.keyboard.dismiss`：作为输入链路的配套，不把 responder 管理隐藏在 setText 中。
4. `ui.screenshot`：单独作为 capture service，可按 locator 裁剪；不和 query/action 混合，并控制响应体大小。
5. `ui.waitFor`：基于 QueryService 做有限等待，必须和命令超时、取消及日志语义一起设计。
6. `ui.gesture`：最后处理。公开 UIKit 没有稳定的通用系统触摸合成 API；只能在定义清楚的 App 注入测试适配器或可实现控件/滚动语义下提供，不能把现有 control fallback 称为完整手势。

## 不做的事

- 不实现鉴权、权限策略、授权弹窗或风险评分。
- 不引入任意第三个通用插件/能力注册框架。
- 不缓存或跨请求持有 UIKit 对象。
- 不改变现有 action 名、必填字段或把 `ui.tap` 伪装成真实系统触摸。
- 不在重构中顺便增加新的业务命令。

如果部署方式从 USB 转发的本机调试扩展到非受控局域网、远程网络或第三方调用方，必须先重新评估监听绑定范围、鉴权和命令授权边界；在完成该评估前，不得把 UI 突变命令作为通用网络服务开放。
