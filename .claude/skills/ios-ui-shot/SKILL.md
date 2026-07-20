---
name: ios-ui-shot
description: iOS App 截图与视觉取证(开发调试 + 自动化测试)/ screenshot, png, base64, visual verification, layout check, before/after, regression, ui_screenshot
allowed-tools:
  - mcp__iOSDriver__ui_screenshot
  - mcp__iOSDriver__ui_inspect
  - mcp__iOSDriver__ui_wait
---

# iOS 截图与视觉取证

基于 iOSDriver MCP Server(`mcp__iOSDriver__*`),对当前前台 `UIWindow` 做 PNG 截图,支持降采样、base64 编码、前后对比、导航流程文档、alert 外观取证。合并自原 `ios-screenshot`。

## 目标

解决"把当前屏幕状态以 PNG 形式拍下来,用于人工排障、测试报告、视觉回归对比、bug 证据"这一场景。关键不是单条命令,而是:

- **截图只是视觉证据,不参与结构化定位**:`ui_screenshot` 不签发、不刷新、不返回 `viewSnapshotID`;控件树 / path / 按钮文案 / alert 结构这些结构化信息走 `ui_inspect`。截图 + inspect 并用才能既看画面又定位。
- **`maxDimension` 是像素长边上限,不是 point**:Retina 屏若按 point 设上限会导致像素体积失控,执行器按 `cgImage.width/height` 的最长边降采样;默认 1280,范围 1-4096。
- **截图时机决定成败**:顶层 `UIViewController` 转场中截图会抓到不可靠中间帧(`transitionInProgress`);tap 后立即截图会抓到动作前状态。必须等稳定窗口后再截。
- **体积超限有明确业务码**:base64 ≈ `pngData × 4/3`,超过响应 body 上限时返回 `responseTooLarge`,降 `maxDimension` 即可,不会因巨大字符串分配造成内存峰值。

## 何时使用

- ✅ 用户要"截一张当前屏幕"
- ✅ 用户要"对比操作前 / 操作后的界面"(开关切换、表单提交、登录前后)
- ✅ 用户要"把多步导航流程截图存档"(每步一张 PNG)
- ✅ 用户要"截下 alert / action sheet 的外观"做证据
- ✅ 用户要"为 bug 报告配图" / "为测试报告收集证据"
- ✅ 用户说 "截图" / "screenshot" / "截屏" / "画面" / "视觉验证" / "视觉回归"
- ❌ 不要用于"读控件树 / 定位元素 / 读按钮文案"(走 `ios-ui-form` / `ios-ui-alert` / `ios-ui-list` 的 `ui_inspect`,截图不带结构化字段)
- ❌ 不要用于"等动画 / loading 结束"(走 `ios-ui-wait`,截图是瞬时快照不等任何东西)
- ❌ 不要用于"连续截图自动判 diff"的回归自动化(本 skill 只取单张 / 序列张;像素 diff 需外部工具如 ImageMagick / Pillow)

## 工作原理

截图时序:**(可选)等稳定窗口 → `ui_screenshot` → 解 base64 存 PNG → (可选)`ui_inspect` 存结构化元数据**。

### 1. 基础调用

```
ui_screenshot(maxDimension: 1280)   // 默认值,可省
→ {
    code: "ok",
    data: {
      image: "<base64 PNG>",
      format: "png",
      width: 1280,           // 缩放后像素宽
      height: 2778,          // 缩放后像素高
      scale: 3.0,            // window.screen.scale(Retina 倍数)
      pixelScale: 0.6667     // 原始像素 → 输出像素的比例(< 1.0 说明已降采样)
    }
  }
```

存文件(流式,避免 base64 串占内存):

```
curl -s -X POST http://localhost:38321/ -d '{"action":"ui.screenshot"}' \
  | jq -r '.data.image' | base64 -d > screen.png
```

### 2. 渲染管线(三级回退)

执行器按顺序尝试,全部失败才返回 `renderingFailed`:

1. `drawHierarchy(afterScreenUpdates: false)` — 生产环境 keyWindow 已上屏,false 既能截当前帧又避免额外布局 pass
2. `drawHierarchy(afterScreenUpdates: true)` — 第一次失败时(未渲染过的 window)强制一次渲染循环
3. `layer.render` — CPU 侧逐层合成,不依赖 render server,覆盖无 scene 的极端场景

### 3. 降采样逻辑

- 渲染出的 `UIImage` 取 `cgImage.width / height` 的最长边
- 若超过 `maxDimension`,按 `pixelScale = maxDimension / longestPx` 等比缩小
- `pixelScale == 1.0` 说明没降采样;`< 1.0` 说明已缩
- **范围 1-4096**:越界返回 `invalid_data`;不传时默认 1280

### 4. 前后对比(操作前后各一张)

```
1. ui_screenshot               → before.png
2. (操作:tap / sendAction / input)
3. 等稳定(ui_wait mode:"idle" stableMs:300,或由 ui_tap_and_inspect 的稳定窗口承接)
4. ui_screenshot               → after.png
5. 外部对比:compare before.png after.png diff.png  (ImageMagick)
```

要点:操作后不要立刻截,会抓到动作前帧;`ui_waitAny` 判稳定后再截。

### 5. 导航流程文档

每步截一张 + 存一份 inspect 元数据,文件名按序编号:

```
01_home.png       / 01_home.json
02_settings.png   / 02_settings.json
03_account.png    / 03_account.json
```

### 6. alert 截图

alert 弹出后(`ui_tap_and_inspect` 返回 `alert.available == true` 之后),直接 `ui_screenshot`。alert 是同进程渲染,会被 keyWindow 的 `drawHierarchy` 一并截下,不需要特殊参数。系统级权限弹窗(位置 / 通知 / 相机)不在 App 进程内,截不到。

### 7. 配合 ui_inspect(可选,推荐)

截图能看画面但读不到结构化字段(控件类型、按钮文案、path、`viewSnapshotID`)。做测试证据时建议成对保存:

```
ui_screenshot → step.png
ui_inspect    → step.json   // 带 targets[] / alert / navigationBar
```

## 关键参数

### `ui_screenshot`

| 参数 | 含义 | 注意 |
|---|---|---|
| `maxDimension` | 长边像素上限 | 默认 1280,范围 1-4096;**像素非 point**;越小文件越小 |

### 响应字段

| 字段 | 含义 |
|---|---|
| `image` | base64 编码的 PNG(可直接 `base64 -d` 解文件) |
| `format` | 固定 `"png"`(无损) |
| `width` / `height` | **缩放后**的像素尺寸,非屏幕原始分辨率 |
| `scale` | `window.screen.scale`(Retina 倍数,如 2.0 / 3.0) |
| `pixelScale` | 原始像素 → 输出像素的比例(`< 1.0` 已降采样,`1.0` 未缩) |

### 性能基线

| 操作 | 典型耗时 | 大小 |
|---|---|---|
| `ui_screenshot`(默认 1280) | 200-500ms | 50-200KB |
| 单次命令超时上限 | 30 秒(自声明,覆盖全局 commandTimeout) | — |

## 常见错误与判别

### `transitionInProgress`

- **现象**:截图失败,业务码 `transitionInProgress`
- **原因**:顶层 `UIViewController` 正在转场(present / dismiss / push 中),`transitionCoordinator != nil`,当前帧不可靠
- **判别**:看响应 code 字段
- **处理**:等转场动画结束(`ui_wait mode:"idle" stableMs:300-500`)再截图;**已知限制:键盘开合动画不在此检测范围**,键盘动画期间截到的画面可能含半开键盘

### `responseTooLarge`(截图太大)

- **现象**:截图失败,业务码 `responseTooLarge`,message `"screenshot too large; reduce maxDimension"`
- **原因**:PNG base64 估算(`pngData × 4/3`)超过响应 body 上限
- **判别**:message 明确提示 reduce maxDimension
- **处理**:降 `maxDimension`(如 1280 → 800 或 640)再试;体积检查在 base64 编码之前,不会因巨大字符串分配导致峰值内存

### `renderingFailed`

- **现象**:截图失败,业务码 `renderingFailed`
- **原因**:三级渲染管线全部失败,典型于 window 未挂到真实 render server 的极端场景(如无 `UIWindowScene` 的 logic test)
- **判别**:message 的 reason 标注失败环节(`drawHierarchy and layer render both failed` / `png encode failed` / `no cgImage`)
- **处理**:确认 App 有真实前台 window;App 刚启动 window 还没上屏时等几百毫秒再试

### `invalid_data`(maxDimension 越界)

- **现象**:截图失败,业务码 `invalid_data`
- **原因**:`maxDimension` 不在 1-4096 范围
- **判别**:看 message 提示字段
- **处理**:把 `maxDimension` 调到 1-4096,或省略走默认 1280

### 截到操作前状态(tap 后立即截图)

- **现象**:截完发现画面还是 tap 之前
- **原因**:tap / input 后 UI 还没刷新就截图,抓到旧帧
- **判别**:对比截图与预期,没变化通常是太快
- **处理**:用 `ui_tap_and_inspect` 让 tap 后等稳定窗口;或 tap 后 `ui_wait mode:"idle" stableMs:300-500` 再截图

### 误以为截图带 viewSnapshotID

- **现象**:截图后想用响应里的字段定位控件,找不到
- **原因**:`ui_screenshot` 不签发、不返回 `viewSnapshotID`,响应里只有 `image / format / width / height / scale / pixelScale`
- **判别**:看响应字段,没有 `viewSnapshotID` / `targets` / `alert`
- **处理**:定位控件走 `ui_inspect`,截图只用于视觉证据;两者成对调用即可

## 相关 skill

- `ios-ui-wait` — 截图前等 UI 稳定(idle)、等 loading / 异步结束归它;本 skill 内联 `ui_wait` 只做短稳定窗口
- `ios-ui-nav` — 导航流程截图的"导航"部分走它(返回、nav bar 按钮、controller 层级);本 skill 只负责把每步截下来
- `ios-ui-alert` — alert 的检测与按钮触发走它;本 skill 只负责把 alert 外观截下来
- `ios-ui-form` / `ios-ui-list` — 操作(填表 / 点 cell / 触发 swipe action)本身走它们;本 skill 只负责操作前后取证
- `ios-automation` — L1 总入口;不确定走哪个子 skill 时先问它

**平台约束**:iOSExploreServer 要求 iOS 15+,部署目标视宿主 App 而定。仅 Debug 集成(渲染依赖 iOSExploreServer 注入路径,Release 下整套 ui.* 不可用)。命令在主线程执行,单次截图必须在 30 秒内完成(自声明超时)。`width` / `height` 是缩放后尺寸,非屏幕原始分辨率;默认 `maxDimension=1280` 对应大多数 iOS 设备的屏幕长边会被缩到 1280 像素以内。
