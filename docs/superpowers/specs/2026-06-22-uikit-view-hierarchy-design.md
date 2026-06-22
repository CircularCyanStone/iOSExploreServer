# UIKit View Hierarchy Design

## 目标

新增一组位于 `Sources/iOSExploreServer/Handlers/UIKit/` 的内置 UIKit 命令，用于让 Mac 侧 agent 获取当前页面的结构化 UI 快照。第一版重点是能有效跑通页面理解和 UI 验收：返回顶部控制器 view 及其全部子视图的关键结构、定位、语义、文本和外观信息，不做隐私裁剪。

## 边界

- 基础网络、协议、路由层仍只依赖 `Foundation` + `Network`。
- UIKit 能力放在共享源码 `Sources/iOSExploreServer/` 内，但所有直接引用 UIKit 的实现都用 `#if canImport(UIKit)` 隔离。
- SPM macOS 测试应继续可运行；可测试的节点模型、JSON 转换、筛选规则保持 Foundation-only。
- UIKit 命令作为内置命令注册，iOS/framework 构建时自动可用。

## 目录

```text
Sources/iOSExploreServer/Handlers/UIKit/
Sources/iOSExploreServer/Handlers/UIKit/ViewHierarchy/
```

每类 UIKit 命令放一个子目录。第一类为 `ViewHierarchy`，后续手势、截图、日志流等能力按同级目录扩展。

## 节点模型

`UIViewHierarchyNode` 是 Foundation-only 值类型，描述单个视图节点及递归子节点。基础字段始终存在：

- `path`：只读定位路径，例如 `root/0/2/1`。
- `type`：运行时类型名，例如 `UIButton`。
- `accessibilityIdentifier` / `accessibilityLabel` / `accessibilityValue` / `accessibilityHint`：直接复用 UIKit 标准 accessibility 字段。
- `frame` / `bounds`：布局位置与尺寸。
- `state`：`isHidden`、`alpha`、`isOpaque`、`isUserInteractionEnabled`。
- `subviews`：子节点数组。

验收相关信息以分组对象表达，避免根节点字段过度膨胀：

- `text`：文本值、字体名、字号、文本颜色、对齐方式、行数等。
- `appearance`：背景色、tintColor、圆角、边框、透明度相关外观。
- `control`：enabled/selected/highlighted、content alignment。
- `image`：图片尺寸、渲染模式、是否 highlighted。
- `scroll`：contentSize、contentOffset、contentInset、是否可滚动。

字段缺失时返回 `null` 或省略分组；第一版不做隐私过滤。

## accessibilityIdentifier 与 path

`accessibilityIdentifier` 是业务层给 agent 的语义锚点，适合设置为 `mine.header.avatar` 这类稳定、可读、跨布局变化仍成立的值。库不主动写入 identifier，只采集并返回。

`path` 是快照内的只读结构定位，适合在 identifier 缺失时引用节点。它对同一时刻的快照稳定，但页面插入、删除或重排子视图后可能变化。因此后续操作优先使用 `accessibilityIdentifier`，必要时降级使用 `path`。

## 命令

第一版 action：

```text
ui.topViewHierarchy
```

返回当前 foreground scene 的顶部控制器 view 层级。参数：

- `detailLevel`：`basic` / `appearance` / `full`，默认 `appearance`。
- `maxDepth`：最大递归深度，默认无限制。
- `includeHidden`：是否包含隐藏 view，默认 `false`。
- `accessibilityIdentifier`：按 identifier 精确筛选。
- `accessibilityIdentifierPrefix`：按 identifier 前缀筛选。

筛选参数用于返回匹配节点列表；默认无筛选时返回完整根树。

## 日志

命令需要记录：

- 命令开始：action、detailLevel、maxDepth、筛选条件。
- MainActor 采集开始和结束。
- 未找到 window / 顶部控制器 / root view 的失败原因。
- 采集完成：节点数、是否筛选、匹配数。
- 返回响应：字段规模和根节点类型。

日志不输出完整文本或完整 payload，只输出长度、数量、类型、筛选摘要。

## 测试

- macOS `swift test` 覆盖 Foundation-only 模型：
  - 节点转 JSON。
  - `path` 递归生成。
  - `maxDepth` 限制。
  - `includeHidden` 过滤。
  - accessibilityIdentifier 精确和前缀筛选。
- UIKit 采集器通过 `#if canImport(UIKit)` 参与 iOS/framework 构建；功能验证以 framework 构建和后续真机调用为准。
