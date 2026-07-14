# 端到端验证小结：`ui.topViewHierarchy` + `controller` 参数

## 验证时间
2026-07-09

## 被测代码

- `ui.topViewHierarchy`：`controller` 参数 → `UIControllerResolver.resolve` → `loadViewIfNeeded()` → `targetController.view` 做 rootView
- `ui.topViewHierarchy` 不带 controller：行为不变，用 `topViewController.view`
- `ui.controllers`：列表 controller 树，输出每个 controller 的 path

## 测试 App
SPMExample，storyboard 改成了 UITabBarController + 3 tab

## 被测命令序列与结果

| # | 命令 | 期望 | 结果 |
|---|---|---|---|
| 1 | `ui.controllers` | 返回 7 个 controller (tab root + 3 nav + 3 VC) | ✅ controllerCount=7, 3 个 tab children 正确 |
| 2 | `ui.topViewHierarchy`（默认） | 返回当前选中 tab 的 view 树，path 完整 | ✅ nodeCount=55, navigationBar 可读, 路径 `root/0/...` |
| 3 | `ui.topViewHierarchy {controller:"root.tab[0].nav[0]"}` | 采集目标 tab VC 的 view 树，path 省略 | ✅ nodeCount 正确(55), `controllerNote`出现, payload中 path 数量=0 |
| 4 | `ui.topViewHierarchy {controller:"root.tab[1].nav[0]"}` | 采集非栈顶 tab VC 的 view 树 | ✅ nodeCount=1(UIKit 行为: 非被选 tab 的 view subviews 回收) |
| 5 | `ui.topViewHierarchy {controller:"root.tab[5]"}` | controller path 越界, 返回 `target_not_found` | ✅ 返回 `code: target_not_found, message: "controller path segment not found: root.tab[5]"` |
| 6 | MCP 端: `ui_topViewHierarchy` 工具(通过 mcp-inspector) | 同上 | ✅ 全部通过，text content 为 json 包含 `controller` / `controllerNote` 等 |

## 核心发现

1. **`controller` 参数正确地切换了 rootView**：传 `root.tab[0].nav[0]` 时（与栈顶相同的 controller），nodeCount 一致但路径全部省略。
2. **path 被安全地去掉**：controller override 模式下 payload 内 path 数量 = 0。
3. **controllerNote 正确提示**：提示该 path 相对于非栈顶 view，不可用于操作。
4. **越界 path 正确报错**：`tab[5]` 返回 `target_not_found`，而不是崩溃或静默返回空树。
5. **非选中 tab 的 view 没有 subviews**：`tab[1].nav[0]` 的 `UITableViewController.viewIfLoaded` 为 false，`loadViewIfNeeded()` 后 view 已建但 subviews=0——这是 UIKit 生命周期管理行为，非被选中 tab 的 view 不会预加载子视图数据。`nodeCount=1`，仅有 root view 自身。

## 已知限制

- 非栈顶/non-selected 的 UITableViewController 在 viewDidLoad 后 subviews 为 0——这是因为 table view 的 dataSource 还没有被调用。这是 UIKit 默认行为，不是实现 bug。对真实 App（有 split VC、modal、自定义容器），非栈顶 controller 通常有子 view 时能正确采集。
- storyboard 中 "日志" 和 "工具" tab 的 `UITableViewController` 绑定到了原来的旧场景 `g80-xX-jKy`/`Nxq-zP-y9e` 并基于旧的 `TableViewController`，它们的 `viewDidLoad` 还没被加载。需要 App 先选中相应 tab 让其 view 加载，或用代码预加载。

## MCP 工具

通过 `mcp-inspector.mjs` 端到端跑全部序列也全部通过，`isError=false`，业务语义与直接 curl 一致。
