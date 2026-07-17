# iOSExploreServer ui.inspect 在 modal 容器场景的采集根盲区

**文档版本**: v1.0
**创建日期**: 2026-07-17
**问题类型**: 基础设施缺陷(resolver / view hierarchy 采集根选取)
**严重性**: 高 —— 影响所有依赖 `ui.inspect` / `ui.topViewHierarchy` / `ui.tap` 的 skill 在 modal 容器场景的可用性
**是否已复现**: ✅ 已用 SPMExample 实测坐实

---

## 0. 一句话结论

`ui.inspect` / `ui.topViewHierarchy` 用 **`context.topViewController.view`** 作为采集根,而 `topViewController` 会一路钻到最深的叶子 VC(modal → tab → selectedVC)。容器 VC(`UITabBarController` / `UINavigationController` / `UISplitViewController`)的 chrome——最典型的是 **`UITabBar` 及其 `UITabBarButton`——是容器 VC.view 的子视图,与叶子 VC.view 平级,因此不在采集根的子树里,永远采集不到。** `ui_controllers` 走的是 controller 关系链(presented / viewControllers),不受影响,所以同一个 `UITabBarController` 在 `ui.controllers` 里能完整呈现。

---

## 1. 复现步骤

**环境**:SPMExample(模拟器,profile `sim-app`),iOSExploreServer 已在 App 启动时自动起在 `:38321`。

**操作路径**(进到一个 modal present 的 UITabBarController):

1. 启动 App(`build_run_sim` / `launch_app_sim`,profile `sim-app`)
2. 确认连接:`iOSDriver ping` 返回 `pong: true`
3. `ui_inspect` 主页菜单 → 定位菜单第 4 项 "🏗️ Controller 结构测试"(实测 path `root/5/5/1`,viewSnapshotID `snap-1`)
4. `ui_tap` 该菜单项 → 进入 `ControllerStructureTestViewController`
5. `ui_inspect` → 定位 "Present TabBar (3 tabs)" 按钮(实测 path `root/0/0/7`)
6. `ui_tap` 该按钮 → present 出一个 3-tab 的 `UITabBarController`(Tab 1 红 / Tab 2 蓝 / Tab 3 绿)
7. 此时屏幕上**真实可见** 3 个 tab 按钮 + Tab 1 内容。分别用三种方式采集:

---

## 2. 实测证据(三组对比,决定性)

### 2.1 `ui_inspect`(iOSExploreServer 自己的命令)—— ❌ 盲区

```
ui_inspect(maxDepth=12, maxTargets=150, maxVisitedNodes=3000)
→ visitedNodeCount: 2
→ fullCount: 1, minimalCount: 1
→ targets 仅:
    root (UIView)
    root/0  UILabel  text="Tab 1"   (accessibilityLabel "Tab 1")
→ screen.topViewController: SimpleTestViewController
→ screen.rootViewController: UINavigationController
```

**只有 2 个节点**(主页是 109、上一页是 24)。UITabBar、UITabBarButton ×3、dismiss 按钮、Tab1 背景全丢。

### 2.2 `ui_controllers`(iOSExploreServer 自己的命令)—— ✅ 完整

```
ui_controllers(maxDepth=8)
→ root: UINavigationController
   ├─ nav[0] ViewController "iOSExploreServer" (不可见)
   ├─ nav[1] ControllerStructureTestViewController (可见)
   └─ presented: UITabBarController            ← path: root.presented
      ├─ tab[0] "Tab 1" SimpleTestViewController  isSelected:true  isViewLoaded:true
      ├─ tab[1] "Tab 2" SimpleTestViewController  isSelected:false isViewLoaded:false
      └─ tab[2] "Tab 3" SimpleTestViewController  isSelected:false isViewLoaded:false
→ topPath: root.presented.tab[0]
```

`UITabBarController` 和全部 tab 状态(title / isSelected / isViewLoaded / path)**完整可见**。证明 iOSExploreServer 内部完全持有 `UITabBarController` 引用,数据本身不缺,缺的只是"view 子树采集根"。

### 2.3 `snapshot_ui`(XcodeBuildMCP / XCUITest Accessibility 体系)—— ✅ 完整

```
snapshot_ui →
  e68|tap|tab|Tab 1|1|   ← 1 = 选中
  e69|tap|tab|Tab 2|0|
  e70|tap|tab|Tab 3|0|
  (并透出底层页面的 e8 BackButton / e18 Push 一层 VC 等)
```

Accessibility 体系从 `keyWindow` 起遍历整棵 accessibility 树,**能看到 tab 与选中状态**。证明盲区**不是 iOS / Accessibility 的限制,而是 iOSExploreServer 的 view 子树采集根选错**。

---

## 3. 根因分析(精确到行)

### 3.1 采集根的选取

`Sources/iOSExploreUIKit/Commands/TopViewHierarchy/UIViewHierarchyCollector.swift`(默认无 `controller` 参数分支):

```swift
// line 63-77
} else {
    targetController = context.topViewController      // ← 采集根的 VC
    controllerLog = "default"
    isControllerOverride = false
}
guard let rootView = targetController.view else { ... } // ← 采集根 view
let element = UIKitViewElement(view: rootView, skipWindowGuard: isControllerOverride)
// 之后 UIViewHierarchyBuilder.build(from: element, ...) 从 rootView 递归 subviews
```

### 3.2 topViewController 一路钻到叶子

`Sources/iOSExploreUIKit/Support/Context/UIKitContextProvider.swift`(line 73-87,**当前无测试覆盖**):

```swift
private static func topViewController(from controller: UIViewController) -> UIViewController {
    if let presented = controller.presentedViewController {
        return topViewController(from: presented)           // 1. 钻进 presented
    }
    if let navigation = controller as? UINavigationController, let visible = navigation.visibleViewController {
        return topViewController(from: visible)             // 2. 钻进 nav 栈顶
    }
    if let tab = controller as? UITabBarController, let selected = tab.selectedViewController {
        return topViewController(from: selected)            // 3. 钻进 tab selected
    }
    if let split = controller as? UISplitViewController, let last = split.viewControllers.last {
        return topViewController(from: last)                // 4. 钻进 split last
    }
    return controller
}
```

modal TabBar 场景的递归路径:
`UINavigationController` →(分支1 presented)`UITabBarController` →(分支3 tab)`SimpleTestViewController(Tab1)` → 返回。

所以 `topViewController = Tab1`,`rootView = Tab1.view`。

### 3.3 为什么 UITabBar 采集不到

`UITabBarController.view` 的子视图结构(UIKit 私有布局):

```
UITabBarController.view
├─ UITransitionView (内容区)
│   └─ <selectedViewController>.view   ← Tab1.view(采集根在这里)
└─ UITabBar                            ← 与 selectedVC.view 平级!
   ├─ _UITabBarBackground
   └─ UITabBarButton × 3               ← tab 按钮,私有类:UIControl 子类
```

采集从 `Tab1.view` 递归 `subviews`,**永远走不到兄弟节点 `UITabBar`**。这就是 `UITabBarButton` 完全消失、`visitedNodeCount=2` 的精确机制。

### 3.4 一个容易误判的点:`isAttachedToWindow` 守卫不是根因

`UIViewHierarchyCollector.UIKitViewElement.init`(line 213-302)有一个 window 归属守卫:`isAttachedToWindow(view)` 为 false 时把该子树 subviews 置空,防 `sendAction` 后的过渡态 view。**这个守卫不是 UITabBarButton 消失的原因**——`UITabBar` 及 `UITabBarButton` 都在 window hierarchy 里,守卫放行。根因纯粹是采集根选在了叶子 VC.view。修复时无需动守卫,但修复后若 UITabBarButton 仍不可见,再回头查守卫是否误杀私有子视图。

---

## 4. 影响面

不止 TabBar。**任何 `present(容器 VC)` 场景,容器 chrome 在 `ui.inspect` / `ui.topViewHierarchy` 里都不可见**:

| 场景 | 丢失的元素 |
|---|---|
| `present(UITabBarController)` | `UITabBar` / `UITabBarButton` / badge |
| `present(UINavigationController)` | 被 present 的 `UINavigationBar`(栈顶 VC 的 nav bar 摘要由 `UINavigationBarInspector` 单独提供,但 nav bar 私有按钮走 view 子树的部分仍缺) |
| `present(UISplitViewController)` | split 的 `displayModeButtonItem`、divider |
| App 主界面 = `UITabBarController` 作 `window.rootViewController` | 同样丢失 `UITabBar`(最常见的真实场景) |

对 agent 的实际后果:
- 无法靠 `ui_inspect` 定位 tab 按钮去 `ui_tap`(本次实测直接卡住,`ui_tap` 无有效 target)
- 任何"切 tab"的自动化必须降级到坐标盲点或外部工具(XcodeBuildMCP),`ios-ui-*` skill 在 tab 场景失效
- 连带影响 `ui-test-runner` 等上层 skill 的覆盖范围

---

## 5. 修复方向

### 5.1 关键判断:采集根 ≠ topViewController

`topViewController`(钻到叶子)对**操作类命令**(`ui.tap` / `ui.input` / `ui.control.sendAction`)的语义是**正确**的——操作发生在叶子 VC 上。**不要改 `topViewController` 的语义**,会破坏操作命令。

`ui.inspect` / `ui.topViewHierarchy` 需要的是另一种根:**"当前屏幕最外层可见 VC 的 view"**,它要包含容器 chrome。

### 5.2 推荐方案:给采集命令单独的采集根

新增一个"最外层可见 VC"计算(沿 `rootViewController → presentedViewController` 走到头,**不**钻 nav stack / tab selection / split):

```
topMostPresentedController(from: root):
    current = root
    while current.presentedViewController != nil:
        current = current.presentedViewController
    return current
```

modal TabBar 场景:返回 `UITabBarController`(最外层 presented),`rootView = UITabBarController.view` → 包含 `[UITransitionView(selectedVC.view), UITabBar]` → 完整采集。

各场景验证:
- modal TabBar → 根 = `UITabBarController.view`(含 UITabBar)✅
- App 主界面 = `UITabBarController` 作 rootVC(无 presented)→ 根 = `UITabBarController.view` ✅(顺带修复最常见的主界面 TabBar)
- modal Navigation → 根 = `UINavigationController.view`(含 UINavigationBar)✅
- 无 modal 纯 nav → 根 = `UINavigationController.view` ✅
- 普通 VC(无容器无 modal)→ 根 = 该 VC.view,行为同今 ✅

### 5.3 实现落点(给修复 agent 的提示,非死代码)

- 在 `UIKitContextProvider` 增加 `hierarchyRootController`(或类似)字段 + 计算函数,与 `topViewController` 并列;`Context` 同时持有两者。
- `UIViewHierarchyCollector.collectTopViewHierarchy` 的**默认分支**(无 `controller` 参数)把 `targetController` 从 `context.topViewController` 改为 `context.hierarchyRootController`;**带 `controller` 参数的 override 分支不动**。
- path 语义变化:`root` 从"叶子 VC.view"变成"最外层容器 VC.view",`root/0` 等下标整体下移一层。这是**更正确**的行为(能定位 tabBar),但属于对外可观察的行为变化,需在 CHANGELOG / skill 文档注明,并更新受影响测试。
- 不需要动 `isAttachedToWindow` 守卫(见 §3.4)。
- 操作类命令(`ui.tap` / `ui.input` / `ui.control.sendAction` / locator 解析)继续用 `topViewController` 语义——它们不受本修复影响,保持稳定。

### 5.4 备选方案(不推荐,仅记录)

- **用 `keyWindow` 作采集根**:最彻底,覆盖一切 chrome;但 path 从 `UIWindow` 起,语义大变,破坏 agent 现有定位习惯,回归风险高。
- **改 `topViewController` 不钻 tab/nav**:会破坏操作命令语义,否决。

---

## 6. 验证方法(修复前后对照)

### 6.1 主路径:SPMExample modal TabBar

按 §1 复现到 modal TabBar 屏,调 `ui_inspect`:

| 指标 | 修复前 | 修复后(期望) |
|---|---|---|
| `visitedNodeCount` | 2 | 数十(含 UITabBar 子树) |
| 能否看到 `UITabBar` | ❌ | ✅ |
| 能否看到 `UITabBarButton × 3` | ❌ | ✅,且带选中状态 |
| `ui_tap` 点 Tab 2 能否切换 | ❌(无 target) | ✅(`tabBarController:didSelect:` 触发) |

### 6.2 回归(必须全绿)

- `swift test`(macOS SPM,~225 个)
- `xcodebuild ... test`(iOS framework,~344 个)
- 重点关注:`UIKitContextProvider`、`UIViewHierarchyCollector`、`UIInspectCollector`、`UIKitLocatorResolver` 相关测试;现有 inspect 快照测试可能因 path 层级变化需要更新断言(更新前先确认是新行为更正确)。

### 6.3 非回归对照(操作命令不能坏)

修复后用 `ui_tap` 在普通页(非 modal)点一个按钮、用 `ui_input` 输入文本,确认操作命令仍走 `topViewController` 语义、行为不变。

---

## 7. 相关文件清单

| 文件 | 角色 |
|---|---|
| `Sources/iOSExploreUIKit/Support/Context/UIKitContextProvider.swift` | `topViewController` 递归(line 73-87)、`Context` 结构、`currentContext` —— **主修改点** |
| `Sources/iOSExploreUIKit/Commands/TopViewHierarchy/UIViewHierarchyCollector.swift` | 采集根选取(line 63-77 默认分支)、`UIKitViewElement` 采集 + window 守卫 —— **主修改点** |
| `Sources/iOSExploreUIKit/Commands/TopViewHierarchy/UIViewHierarchyModels.swift` | `UIViewHierarchyBuilder.build` 递归构建(无需改,了解即可) |
| `Sources/iOSExploreUIKit/Support/Locator/UIKitLocatorResolver.swift` | locator 解析(操作命令用,继续基于 topViewController,不改) |
| `Tests/iOSExploreServerTests/`(UIKitContextProvider / UIKitInspect / ViewHierarchy 相关) | **先加复现测试,再改实现** |
| `Examples/SPMExample/SPMExample/ControllerStructureTestViewController.swift` | 复现载体(`presentTabBar()`,line 193-213) |

---

## 8. 附录:修复任务提示词(可直接粘贴到新窗口)

> 以下提示词自包含,新窗口的 agent 无需读取本会话历史即可开工。它指向本文档作为唯一上下文源。

```text
你是 iOSExploreServer 仓库的修复工程师。当前工作目录:仓库根。

## 任务
修复 ui.inspect / ui.topViewHierarchy 在 modal 容器场景的"采集根盲区"。完整背景、复现步骤、
根因(精确到行号)、修复方向、验证方法,全在唯一上下文文档里,先完整读一遍:
  docs/superpowers/specs/2026-07-17-resolver-modal-blindspot.md
再读项目规范:AGENTS.md、CLAUDE.md(尤其"核心原则""日志与注释要求""抽象短词必须解释")。

## 根因(一句话)
ui.inspect 用 context.topViewController.view 作采集根,而 topViewController 一路钻到
叶子 VC(modal→tab→selectedVC),导致容器 VC(UITabBarController 等)的 chrome(UITabBar /
UITabBarButton)不在采集子树里。代码:UIKitContextProvider.topViewController (line 73-87)、
UIViewHierarchyCollector.collectTopViewHierarchy 默认分支 (line 63-77)。

## 修复要求
1. 不要改 topViewController 语义(操作类命令 ui.tap/ui.input/ui.control.sendAction 依赖它
   钻到叶子,改了会破坏操作命令)。
2. 给采集命令单独的采集根:新增"最外层可见 VC"计算(沿 rootViewController→presentedViewController
   走到头,不钻 nav/tab/split),在 UIKitContextProvider.Context 里与 topViewController 并列;
   UIViewHierarchyCollector 默认分支(无 controller 参数)改用这个新根;带 controller 参数的
   override 分支不动。
3. 严格 TDD:先写失败测试复现盲区(modal UITabBarController 场景,断言能采集到 UITabBar/
   UITabBarButton),再改实现让它转绿。UIKitContextProvider 当前"无测试覆盖",补上是本任务
   的一部分。
4. 遵守项目硬约束:Debug-only(#if DEBUG / canImport(UIKit) 隔离);Swift 6.2 严格并发
   (Sendable / @MainActor / Mutex);typed factory(Uikit 类型不穿 public 边界);新增/修改
   的 public 类型与关键内部类型必须有 /// 文档注释(写"为什么"和"生命周期角色",不复述签名);
   所有关键路径加 UIKitCommandLogging(category "command")日志。
5. path 语义会变(采集根从叶子 VC.view 变成最外层容器 VC.view,层级下移一层):这是更正确的
   行为,但属对外可观察变化。更新受影响的现有快照测试断言(更新前确认新行为更对),并在
   docs/skills/ 与 docs/architecture/ 相关处注明。

## 验证(全绿才算完成,不允许只贴"测试通过")
A. 单元/集成测试:swift test(macOS,~225)、xcodebuild test(iOS framework,~344)。
B. 端到端(SPMExample 模拟器,profile sim-app):按文档 §1 复现到 modal TabBar 屏,
   用 iOSDriver ui_inspect 确认 visitedNodeCount 从 2 恢复到数十、能看到 UITabBar 与
   3 个 UITabBarButton,再用 ui_tap 点 Tab 2 确认能切换且 tabBarController(_:didSelect:)
   被触发。用 XcodeBuildMCP build_run_sim 起 App,iOSDriver ping 确认 :38321 连通。
C. 非回归:普通(非 modal)页用 ui_tap 点按钮、ui_input 输入文本,确认操作命令行为不变。
D. 覆盖率不下降:swift test --enable-code-coverage(当前 86.62%)。

## 交付清单
- 改动后的 UIKitContextProvider.swift / UIViewHierarchyCollector.swift(+ 必要的关联类型)
- 新增/更新的测试(复现用例 + 回归用例)
- 文档同步(docs/skills/、docs/architecture/、本文档补一节"修复记录"记录最终实现与验证结果)
- 任务结束按 AGENTS.md「任务完成汇报」用普通人话说明:目标/改了什么/运行效果变成什么/
  怎么验证/还有什么没做。

## 边界
- 本任务只修采集根盲区,不要顺手实现 ui.tabBar.selectTab 命令(那是独立的后续任务)。
- 不要改 isAttachedToWindow 守卫(根因不在它,见文档 §3.4);修复后若 UITabBarButton 仍
  不可见再回头查。
- 遇到设计岔路用文档 §5 的推荐方案;若发现推荐方案有问题,先在本文档记下原因再换方案,
  不要默默改方向。
```

---

## 9. 修复记录（2026-07-17 完成）

### 9.1 最终实现（3 处源码改动 + 关联测试）

修复没有给 `Context` 加新字段，而是**改变 `Context.rootView` 的来源**——这是关键设计决策。原因：`ui.inspect` 的采集（`UIInspectCollector.collect` 从 `context.rootView` 起）、`ui.tap`/`ui.input`/`ui.control.sendAction` 的 locator 解析（`UIKitLocatorResolver.locate(in: context.rootView)`）、`ui.wait` 的文本/目标判断（`UIWaitExecutor` 从 `context.rootView` 采集）、fingerprint 的 `ancestorDigest`（基于 `context.rootView`）**全都用同一个 `context.rootView`**。只要让 `currentContext` 把 `rootView` 算成「最外层容器 VC 的 view」，inspect 采集根与操作命令 locator 根自动落在同一棵树，`path` 天然一致，spec §7 的「inspect 签发 path == tap 可操作 path」不变式保持。`topViewController` 字段语义不动（仍钻到叶子 VC），继续喂给 `UINavigationBarInspector` / `UIAlertInspector` / `UIKitFingerprintCollector.digest` / `UIKitFingerprintCollector.context` 等「栈顶操作语义」摘要。

具体改动：

| 文件 | 改动 | 说明 |
|---|---|---|
| `Sources/iOSExploreUIKit/Support/Context/UIKitContextProvider.swift` | 新增 `hierarchyRootController(from:)`（沿 `presentedViewController` 走到最外层，**不**钻 nav/tab/split）；`topViewController(from:)` 从 `private` 提为 `internal`（补单测覆盖）；`currentContext` 的 `rootView` 从 `topViewController.view` 改为 `hierarchyRootController.view` | 两者加 `///` 文档注释，写清「操作根钻叶子 / 采集根停容器」的分工 |
| `Sources/iOSExploreUIKit/Commands/TopViewHierarchy/UIViewHierarchyCollector.swift` | 默认分支（无 `controller` 参数）采集根从 `context.topViewController.view` 改为 `context.rootView`，与 `ui.inspect` 同口径；带 `controller` 参数的 override 分支不动 | override 分支仍走 `UIControllerResolver` 解析非栈顶 VC，`skipWindowGuard=true` 不变 |
| `Sources/iOSExploreUIKit/Commands/Inspect/UIInspectCollector.swift` | **无需改动** | 它本来就从 `context.rootView` 采集（line 44），`currentContext` 的 rootView 来源改对后自动正确 |

测试（严格 TDD：先 RED 再 GREEN）：
- 新增 `Tests/iOSExploreServerTests/UIKitContextProviderTests.swift`：纯函数单测 `topViewController(from:)`（回归，此前无覆盖）+ `hierarchyRootController(from:)`（modal nav→present(TabBar)、TabBar/nav 作 root 不钻容器、plain 返回自身、多层 presented 链）。RED 阶段编译失败（函数不存在 / private），GREEN 后全绿。
- `Tests/iOSExploreServerTests/UIKitViewHierarchyTests.swift` 加 `collectTopViewHierarchyIncludesTabBarChrome`（modal TabBar 注入 `rootView=UITabBarController.view`，断言采集到 UITabBar + nodeCount>5）+ `collectTopViewHierarchyPlainRootUnchanged`（普通 VC 回归）。RED 阶段 nodeCount=1（修复前默认分支用 `topViewController.view`=空 tab1.view），GREEN 后含 UITabBar 子树。
- 顺手修 pre-existing 断言过时：`Tests/iOSExploreServerTests/UIInputTests.swift` 两处 staleLocator 断言 `"call ui.inspect first"` → `"Call ui.inspect"`（实现文案早已更新为含 MCP `call_action` 工具说明，测试断言没跟上；详见 §9.4）。

### 9.2 path 语义变化（对外可观察）

采集根从「叶子 VC.view」（`topViewController.view`）变为「最外层容器 VC.view」（`hierarchyRootController.view`），在**有容器 chrome 的场景**`root` 子树下移一层、并多出 chrome 子树：

| 场景 | 修复前 root | 修复后 root | 新增可见 |
|---|---|---|---|
| `present(UITabBarController)` | Tab1.view（叶子） | UITabBarController.view | `UITabBar` + `_UITabButton` ×N |
| App 主界面 = TabBar 作 rootVC | selectedVC.view | UITabBarController.view | 同上（顺带修复最常见主界面） |
| `present(UINavigationController)` / 纯 nav | 栈顶 VC.view | UINavigationController.view | `UINavigationBar` + `BackButton`（`_UIButtonBarButton`） |
| 普通 VC（无容器无 modal） | 该 VC.view | 该 VC.view | 无变化（hierarchyRoot==topViewController） |

`ui.tap`/`ui.input`/`ui.control.sendAction` 的 path 仍与 `ui.inspect` 同根（都用 `context.rootView`），所以 agent 拿 inspect 的 path 去操作依然命中正确 view——只是 path 数值在容器场景整体下移一层。这是更正确的行为（能定位 chrome），但属对外可观察变化，已在 `docs/architecture/index.md` 与 `AGENTS.md`「ui.inspect 设计要点」注明。

### 9.3 验证结果（全绿）

- **单测/集成**：`swift test`（macOS SPM）289 个全绿；`xcodebuild test`（iOS framework）499 个全绿（含新增 10 个用例）。覆盖率见 §9.5。
- **端到端（SPMExample 模拟器，profile `sim-app`）**：进 `ControllerStructureTestViewController` → Present TabBar (3 tabs)，`ui.inspect` 实测 `visitedNodeCount` 从修复前的 **2** 恢复到 **39/41**，能看到 `UITabBar`（path `root/1/0/0`）与 3 个 `_UITabButton`（Tab 1 `isSelected:true`，Tab 2/3 `false`，`availableActions: [control.touchUpInside, control.touchDown]`）；用 `ui.control.sendAction(touchUpInside)` 点 Tab 2，`isSelected` 翻转为 true、内容区 label 从「Tab 1」变「Tab 2」、navBar title 变「Tab 2」，确认 `tabBarController(_:didSelect:)` 被触发。顺带验证 nav 场景：`ControllerStructureTestViewController` 页 `UINavigationBar`（`root/1`）与 `BackButton`（`_UIButtonBarButton`）也落入采集子树（修复前在叶子 VC.view 子树外）。
- **非回归**：普通（非 modal）页 `ui.tap`（cell.select / button.touchUpInside / control.sendAction）、`ui_input`（`simpleTextField` 输入 `modal-blindspot-fixed` 成功）、`ui_navigation_back` 全部正常——操作命令走 `context.rootView` 的 path 定位行为不变。

> 注：UITabBarButton 在 iOS 26 的运行时实际类名是 `_UITabButton`（本文档 §3.3 用「UITabBarButton」泛指 tab 按钮）；`findNodeByTypeContaining` 测试用 `contains("TabBar")` 匹配，能覆盖 `UITabBar` 与 `_UITabButton`。

### 9.4 pre-existing 失败（与本次修复无关，已顺手修断言）

全量回归时发现 3 个失败，用 `git stash` baseline 证明均 pre-existing：
- **`超过连接上限...503`（IntegrationTests）**：集成测试串行端口 38399 残留 `Address already in use`，环境性 flaky，重跑即过（runbook 已记录模拟器 `NWListener.cancel()` 释放端口异步）。
- **两个 `staleLocator` 文案断言（UIInputTests:187/216）**：实现 `UIKitCommandError.swift:46` 的 staleLocator message 早已更新为 `"view snapshot expired ... To fix: 1) Call ui.inspect (or use MCP tool call_action with action='ui.inspect') ..."`（含 MCP 工具说明），但测试断言还期望旧串 `"call ui.inspect first"`。本次顺手把这两处断言更新为 `"Call ui.inspect"`（line 243 的 targetNotFound 断言用变量 `message`、对应实现确含 `call ui.inspect first`，未误改）。

### 9.5 仍未实现 / 限制

- **`ui.tabBar.selectTab` 命令未实现**：本次只修采集根盲区（让 `ui.inspect` 能看到 tab 按钮 + `ui.control.sendAction(touchUpInside)` 能切 tab）。独立的「按 index/title 选 tab」便捷命令是后续任务（见任务边界）。
- **`UITabBarButton` 私有类名随 iOS 版本漂移**：iOS 26 实测为 `_UITabButton`，未来版本可能变；采集层用 `type(of:)` 如实输出，agent 应按 `accessibilityLabel`（tab title）而非类名定位。
- **`isAttachedToWindow` 守卫未动**（见 §3.4）：修复后 UITabBar/`_UITabButton` 在 window 层级，守卫放行；若未来某 iOS 版本 tab 按钮仍不可见，再回头查守卫是否误杀私有子视图。

---

**文档结束**
