# UIKit View Targets Design

## 目标

新增一个轻量 UIKit 目标查询命令，用于让 Mac 侧 agent 在执行 `ui.tap`、`ui.control.sendAction` 以及后续输入、滚动、手势等事件下发前，快速找到可操作控件的 `path` 和语义摘要。

该命令不替代 `ui.topViewHierarchy`。`ui.topViewHierarchy` 继续负责完整页面结构、布局验收和排查；新命令只负责生成交互目标索引，减少为了查 path 而返回完整布局树带来的 payload 和 token 成本。

## 边界

- 基础网络、协议、路由层仍只依赖 `Foundation` + `Network`。
- UIKit 实现继续放在 `Sources/iOSExploreServer/Handlers/UIKit/`，并用 `#if canImport(UIKit)` 隔离。
- 查询命令只读取 UI 状态，不修改业务 UI，不触发事件。
- path 规则必须复用 `UIKitViewLookupTarget` 的 `root/0/2/1` 规则，保证查询结果可直接传给 `ui.tap` 和 `ui.control.sendAction`。
- 默认不返回完整递归树、不返回外观验收字段、不返回图片、滚动详情、字体、颜色、圆角等布局验收信息。
- 返回文本类字段时必须做长度限制，避免大块用户输入或长文本进入日志和响应。

## 命令

推荐 action：

```text
ui.viewTargets
```

命令返回当前 foreground window 顶部控制器 view 下的扁平目标列表。默认只返回具有交互意义或语义意义的节点：

- `UIControl` 及其子类。
- `isUserInteractionEnabled == true` 且有 gesture recognizer 的 view。
- 有 `accessibilityIdentifier` 的 view。
- 有 `accessibilityLabel`、title、text、placeholder 等可解释语义的 view。

可选参数：

- `includeHidden`：是否包含隐藏 view，默认 `false`。
- `includeDisabled`：是否包含 disabled control，默认 `true`。disabled 控件仍可能帮助 agent 理解页面状态。
- `includeStaticText`：是否包含仅展示文本的 label/text view，默认 `false`。
- `includeContainers`：是否包含普通容器 view，默认 `false`。
- `maxDepth`：最大递归深度，默认无限制。
- `accessibilityIdentifier`：按 identifier 精确筛选。
- `accessibilityIdentifierPrefix`：按 identifier 前缀筛选。
- `textLimit`：title/text/placeholder/value 的最大返回字符数，默认 `80`，上限 `200`。

## 响应结构

响应使用统一 envelope，`data` 内返回 screen 摘要和目标列表：

```json
{
  "screen": {
    "windowType": "UIWindow",
    "rootViewController": "RootViewController",
    "topViewController": "HomeViewController"
  },
  "targetCount": 1,
  "targets": [
    {
      "path": "root/0/2/1",
      "type": "UIButton",
      "role": "button",
      "accessibilityIdentifier": "home.submit",
      "accessibilityLabel": "提交",
      "title": "提交",
      "text": null,
      "placeholder": null,
      "value": null,
      "frame": {
        "x": 24,
        "y": 680,
        "width": 327,
        "height": 48
      },
      "isHidden": false,
      "alpha": 1,
      "isUserInteractionEnabled": true,
      "isEnabled": true,
      "isSelected": false,
      "isHighlighted": false,
      "hasGestureRecognizers": false,
      "suggestedActions": [
        "tap",
        "control.touchUpInside"
      ]
    }
  ]
}
```

字段说明：

- `path`：当前快照内的只读定位路径，可直接传给事件下发命令。
- `type`：运行时类型名，用于判断控件类别。
- `role`：轻量角色归类，例如 `button`、`switch`、`slider`、`textField`、`textView`、`label`、`imageView`、`container`、`view`。
- `accessibilityIdentifier` / `accessibilityLabel`：优先用于稳定定位和语义理解。
- `title` / `text` / `placeholder` / `value`：能解释控件含义的短文本，按 `textLimit` 截断。
- `frame`：window 坐标系下的位置和尺寸，方便后续坐标点击或截图对齐。
- `isHidden` / `alpha` / `isUserInteractionEnabled`：基础可见性和交互状态。
- `isEnabled` / `isSelected` / `isHighlighted`：仅适用于 `UIControl`，非 control 返回 `null` 或省略。
- `hasGestureRecognizers`：帮助识别非 `UIControl` 的可交互 view。
- `suggestedActions`：面向 agent 的动作提示，不代表命令自动执行。

## path 稳定性

`path` 是当前顶部控制器 root view 下的 `subviews` 下标链，只保证对当前快照有效。页面插入、删除、重排、动画完成或控制器切换后，旧 path 可能失效。

事件下发优先级：

1. 优先使用业务设置的 `accessibilityIdentifier`。
2. 缺少 identifier 时，在刚调用 `ui.viewTargets` 后立即使用 `path`。
3. 页面发生明显变化后重新调用 `ui.viewTargets`，不要复用旧 path。

## 与现有命令的关系

`ui.topViewHierarchy`：

- 用于查看完整布局、层级关系、视觉验收、颜色、字体、图片、滚动状态。
- 可以继续支持 `detailLevel`、`maxDepth` 和 identifier 筛选。
- 不作为事件下发前的默认目标发现入口。

`ui.viewTargets`：

- 用于事件下发前发现目标。
- 返回扁平、短字段、低 token 的目标摘要。
- 不返回完整 `subviews` 树，不承担视觉验收职责。

`ui.tap` / `ui.control.sendAction`：

- 继续只负责执行。
- 继续接收 `accessibilityIdentifier` 或 `path`。
- 文档和参数说明应从“按 `ui.topViewHierarchy` 返回的 path”调整为“按 `ui.viewTargets` 或 `ui.topViewHierarchy` 返回的 path”。

## 实现建议

新增目录：

```text
Sources/iOSExploreServer/Handlers/UIKit/ViewTargets/
```

建议文件：

- `UIViewTargetsModels.swift`：Foundation-only 查询参数、目标摘要、role、JSON 转换和文本截断规则。
- `UIViewTargetsCollector.swift`：UIKit-only MainActor 遍历，直接从 `UIView` 生成轻量目标列表。
- `ViewTargetsCommand.swift`：命令解析、日志、错误处理和响应封装。

采集器不应复用当前 `UIKitViewElement` 完整快照，因为它会读取 appearance、image、scroll 等重字段。新采集器应在递归遍历时按需读取最少字段，并在不符合 include 规则时跳过输出，但仍继续遍历子视图，避免漏掉深层控件。

## 日志

命令必须记录：

- 命令开始：action、includeHidden、includeDisabled、includeStaticText、includeContainers、maxDepth、筛选条件、textLimit。
- MainActor 查询开始和结束。
- UIKit 上下文不可用原因。
- 采集完成：遍历节点数、返回目标数、筛选命中数。
- 响应发送：targetCount、topViewController。

日志禁止输出完整 title/text/placeholder/value，只能输出长度、数量、role、type、path、identifier 摘要。

## 测试

macOS `swift test` 覆盖 Foundation-only 规则：

- 查询参数解析和非法参数拒绝。
- `path` 生成规则与 `UIKitViewLookupTarget` 保持一致。
- 文本字段按 `textLimit` 截断。
- role 到 suggestedActions 的映射。
- includeHidden/includeDisabled/includeStaticText/includeContainers 的过滤策略。
- 目标摘要转 JSON。

UIKit 采集器通过 `#if canImport(UIKit)` 参与 iOS/framework 构建；真实 UIView 遍历、gesture recognizer 和 window 坐标可在后续真机或 Example App 中验证。

## 验收标准

- `ui.viewTargets` 能在常见页面返回可操作目标列表，并且每个目标都包含可用于后续事件下发的 `path`。
- 对于按钮、switch、slider、text field 等常见控件，返回的 role 和 suggestedActions 能帮助 agent 判断应调用哪个事件命令。
- 在同一页面上，调用 `ui.viewTargets` 的响应体明显小于 `ui.topViewHierarchy` 默认响应。
- `ui.tap` 和 `ui.control.sendAction` 的既有定位行为不改变。
- `swift test` 通过。
