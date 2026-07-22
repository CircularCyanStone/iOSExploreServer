---
name: ios-ui-shot
description: iOS App 当前前台 window 的 PNG 截图与视觉取证。用于布局问题、弹窗外观、操作前后画面、测试报告证据和人工视觉检查；控件定位、结构断言和等待不适用。触发词包括 screenshot、截图、视觉验证、layout、before/after、regression、ui_screenshot。
---

# iOS 截图与视觉取证

截图只提供视觉证据，不签发 `viewSnapshotID`，也不能替代 `ui_inspect` 的控件结构。需要定位或结构断言时同时使用 inspect，但不要假设二者是同一个原子快照。

## 截图时序

1. 操作前需要基线时先截图。
2. 执行 tap/input/navigation 等动作。
3. 用 `ios-ui-wait` 或组合操作返回的观察确认页面已到目标状态。
4. 调用 `ui_screenshot` 取得目标帧。
5. 需要结构证据时，再调用 `ui_inspect` 保存对应观察。

不要用固定 sleep 猜业务完成；先等待可判定的 UI 终态，再截图。截图命令检测 view-controller transition，但不覆盖所有动画（例如键盘开合）。

## 工具返回

`ui_screenshot` 静态 MCP 工具把 PNG 转为 image content，并附一条文本元数据；agent 可直接查看/保存该图像，不需要手工解 base64。元数据包含：

- `format`：固定 `png`。
- `width/height`：输出 PNG 的像素尺寸。
- `scale`：window screen scale。
- `pixelScale`：原始像素到输出像素的缩放比例；小于 1 表示已降采样。

底层 App action 的 `image` base64 是传输实现，不应成为通用 MCP 工作流。

## maxDimension

`maxDimension` 是输出长边的像素上限，不是 point。默认 `1280`，合法范围 `1...4096`。

- 普通证据保留默认值。
- 响应过大时逐步降低到 `800` 或 `640`。
- 需要检查细小文字时在响应限制允许的范围内提高。

不要在正文固定设备分辨率、典型文件大小或耗时；这些取决于屏幕和画面内容。

## 结果判读

- 页面行为是否成功优先依据结构化终态；截图用于补充布局、遮挡、颜色、裁剪等视觉信息。
- 前后截图需要在相同业务阶段采集，避免把转场或 loading 中间帧当作差异。
- 自动像素 diff 需要外部图像工具和稳定的渲染环境，不属于本 skill 的单次取证职责。

## 失败分诊

| code | 原因 | 动作 |
|---|---|---|
| `transition_in_progress` | 顶层 controller 正在 push/present/dismiss | 等目标状态稳定后重试 |
| `response_too_large` | PNG 转 MCP 响应后超过 body 上限 | 降低 `maxDimension` |
| `rendering_failed` | window 渲染或 PNG 编码失败 | 确认 App 在前台且 window 已上屏，稍后重试 |
| `invalid_data` | `maxDimension` 越界或类型错误 | 使用 `1...4096` 的整数 |

等待归 `ios-ui-wait`，弹窗操作归 `ios-ui-alert`，导航归 `ios-ui-nav`。本 skill 只负责在正确时机取得画面。
