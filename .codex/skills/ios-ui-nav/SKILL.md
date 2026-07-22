---
name: ios-ui-nav
description: iOS App 屏幕导航、返回或 dismiss、导航栏按钮、UITabBarController 切换与 controller 层级检查。用于 push 后验证、pop/modal 返回、left/right bar button、按 index/title 选择 tab、排查 navigation/tab/split/presented 树；UIAlertController 按钮不适用。触发词包括 navigation、back、dismiss、modal、tab bar、controller tree、ui_navigation_back、ui_navigation_tapBarButton、ui_tabBar_selectTab、ui_controllers。
---

# iOS 导航与 controller 层级

把“发出导航动作”和“确认到达目标页”分开判断。优先使用组合工具得到动作后的新观察；导航命令成功只表示动作已发出或 controller 状态已设置。

## 进入下一屏

1. `ui_inspect` 获取当前 `viewSnapshotID` 和目标。
2. 使用 `ui_tap_and_inspect`，从返回的 `stateAfter.navigationBar`、`stateAfter.targets` 或 alert 判断结果。
3. 若目标页异步加载，转到 `ios-ui-wait` 等待业务终态。

不要只比较 controller 类名：同一 controller 可切换编辑态而不换类；也不要只看 tap 成功。

## 返回或 dismiss

`ui_navigation_back` 的 `strategy`：

- `auto`（默认）：先 dismiss 当前 presented controller；不可 dismiss 时再 pop navigation stack。
- `dismiss`：只关闭 modal。
- `navigationController`：只 pop，要求 navigation stack 至少两层。

`animated` 默认 `false`；`waitAfterMs` 范围 `0...3000`，默认 `300`。成功返回 `performed/strategy/topBefore/topAfter`，其中 `strategy` 是实际执行的路径。

失败 `navigation_back_unavailable` 表示当前既没有可 dismiss 的 presented controller，也没有可 pop 的栈层。不要循环重试；重新 inspect/controller tree 选择其他导航入口。

## 导航栏按钮

先从 `ui_inspect.navigationBar.leftItems/rightItems` 读取现场按钮，再调用 `ui_navigation_tapBarButton`。

合法定位方式：

- `placement + index`：按某侧下标定位。
- `accessibilityIdentifier`：全局搜索左右两侧。
- `placement + accessibilityIdentifier`：限定一侧搜索。
- `title` 只做二次确认，不单独定位。

`waitAfterMs` 默认 `300`。成功返回实际 `placement/index/title/accessibilityIdentifier/topBefore/topAfter`。

| code | 含义 | 动作 |
|---|---|---|
| `navigation_bar_unavailable` | 顶层不在 navigation controller 中 | 改用普通 view tap 或其他导航方式 |
| `invalid_data` | 选择器组合非法、placement/index 格式不合法 | 使用上述合法组合 |
| `navigation_bar_item_not_found` | 现场没有匹配按钮 | 重新 inspect 后定位 |
| `navigation_bar_item_mismatch` | title/identifier 与观察时不一致 | 页面已变化；用新观察重试 |
| `navigation_bar_item_disabled` | 按钮当前禁用 | 等待业务状态或修正前置输入 |
| `navigation_bar_item_unsupported` | item 没有可派发 action | 不改下标重试，改用 App 暴露的其他入口 |

## Tab 切换

优先直接调用 `ui_tabBar_selectTab`，不要绕到 `call_action`。`index` 与 `title` 必须且只能提供一个：

- `index`：0-based，顺序稳定时使用。
- `title`：精确匹配 `tabBarItem.title`，不是 view controller title。
- `tabBarControllerPath`：多 tab controller 时，从 `ui_controllers` 的 path 选择。
- `triggerDelegate`：默认 `true`；仅在明确只设置 `selectedIndex` 时设为 `false`。

响应的 `previousIndex/selectedIndex/previousTitle/selectedTitle/tabCount` 是 controller 层结果。目标 tab 仍需加载时，再 inspect/wait 验证页面内容。

找不到 `UITabBarController` 时，说明当前可能是自定义 tab bar；此时用 inspect 定位真实 tab 按钮并点击。

## Controller 层级

使用 `ui_controllers` 排查 navigation stack、tab、split、children 和 presented 链。默认不限制深度；`maxDepth:0` 只返回 root，逐步增大以控制输出。

节点 path 形如 `root.nav[1]`、`root.tab[0]`、`root.presented`，可用于需要 controller path 的命令。结合 `role/isSelected/isVisible/title/type` 判读当前结构，不靠单一 title 猜测。

## 边界

- `UIAlertController` 按钮交给 `ios-ui-alert`；自定义 modal 才使用普通导航/dismiss。
- 列表项查找与滚动交给 `ios-ui-list`。
- 长时转场后业务加载交给 `ios-ui-wait`。
- 导航前后视觉取证交给 `ios-ui-shot`。
