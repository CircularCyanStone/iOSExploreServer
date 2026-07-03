# curl/JSON 闭环操作协议

> 日期：2026-07-03
>
> 本文给外部 Agent 或人工调试者一套可直接复制的 HTTP JSON 调用顺序。它不新增命令；只把当前已落地能力组合成标准闭环：
>
> ```text
> observe -> action -> ui.wait -> re-observe -> verify
> ```

## 0. 前置条件

真机先启动 USB 转发：

```bash
./scripts/proxy.sh
```

模拟器或已转发真机都用同一个地址：

```bash
BASE=http://localhost:38321/
```

所有请求都是 `POST /`，body 形如：

```json
{"action":"ui.viewTargets","data":{}}
```

## 1. 标准单步闭环

### 1.1 observe：先拿 targets 和 viewSnapshotID

```bash
curl -sS -X POST "$BASE" \
  -H 'Content-Type: application/json' \
  -d '{"action":"ui.viewTargets","data":{"textLimit":80,"maxTargets":200}}'
```

从响应里读取：

- `data.viewSnapshotID`：后续 `ui.tap` / `ui.control.sendAction` / `ui.wait(snapshotChanged)` 使用。
- `data.targets[]`：普通 view target，重点看 `path`、`accessibilityIdentifier`、`semanticText`、`availableActions`、`isEnabled`。
- `data.navigationBar`：导航栏按钮，走 `ui.navigation.tapBarButton`，不走 `ui.tap`。

如果 `viewSnapshotID` 是 `null`，说明本次目标太多无法签发；缩小筛选条件后重新 `ui.viewTargets`。

### 1.2 action：每次只做一个动作

按钮默认激活：

```bash
curl -sS -X POST "$BASE" \
  -H 'Content-Type: application/json' \
  -d '{"action":"ui.tap","data":{"accessibilityIdentifier":"login.submit","viewSnapshotID":"snap-1"}}'
```

无稳定 identifier 时用 path：

```bash
curl -sS -X POST "$BASE" \
  -H 'Content-Type: application/json' \
  -d '{"action":"ui.tap","data":{"path":"root/0/2/1","viewSnapshotID":"snap-1"}}'
```

精确 control event：

```bash
curl -sS -X POST "$BASE" \
  -H 'Content-Type: application/json' \
  -d '{"action":"ui.control.sendAction","data":{"path":"root/0/3","viewSnapshotID":"snap-1","event":"valueChanged"}}'
```

文本输入：

```bash
curl -sS -X POST "$BASE" \
  -H 'Content-Type: application/json' \
  -d '{"action":"ui.input","data":{"accessibilityIdentifier":"login.password","text":"wrong-password","mode":"replace","submit":true}}'
```

`ui.input` / `ui.scroll` 的 `viewSnapshotID` 只在 `path` 定位时可选使用。identifier 定位不能带 `viewSnapshotID`。

### 1.3 wait：动作后等反馈，不用固定 sleep

等待结构变化：

```bash
curl -sS -X POST "$BASE" \
  -H 'Content-Type: application/json' \
  -d '{"action":"ui.wait","data":{"mode":"snapshotChanged","viewSnapshotID":"snap-1","timeoutMs":3000,"intervalMs":100}}'
```

等待可见文本：

```bash
curl -sS -X POST "$BASE" \
  -H 'Content-Type: application/json' \
  -d '{"action":"ui.wait","data":{"mode":"textExists","text":"密码错误","timeoutMs":5000,"intervalMs":100}}'
```

`ui.wait` 当前是单条件等待。`snapshotChanged` 只能说明结构指纹表变了，不返回新页面；满足或超时后都要重新 observe。

多分支等待（`ui.waitAny`，一次覆盖登录后多个可能结局，第一个命中立即返回）：

```bash
curl -sS -X POST "$BASE" \
  -H 'Content-Type: application/json' \
  -d '{"action":"ui.waitAny","data":{"timeoutMs":8000,"intervalMs":200,"conditions":[{"id":"home","mode":"targetExists","accessibilityIdentifier":"home.root"},{"id":"pwd_error","mode":"textExists","text":"密码错误"},{"id":"network_error","mode":"textExists","text":"网络"},{"id":"loading_gone","mode":"targetGone","accessibilityIdentifier":"login.loading"}]}}'
```

返回命中的 `matchedID`（如 `"pwd_error"`）/ `matchedIndex` / `matchedMode`，按 `matchedID` 决定下一步；超时仍是 `wait_timeout`，需重新 observe 再判断。`conditions` 顺序即优先级（多个同时满足时返回靠前者），上限 16 个；`stableMs` / `includeHidden` 为顶层共享。命中后仍要重新 observe 拿页面证据。

### 1.4 re-observe：拿最新页面证据

```bash
curl -sS -X POST "$BASE" \
  -H 'Content-Type: application/json' \
  -d '{"action":"ui.viewTargets","data":{"textLimit":80,"maxTargets":200}}'
```

判断测试是否通过，只看这次重新观察后的页面证据：目标存在、状态正确、错误提示出现、导航栏标题变化、顶部控制器变化等。不要把 `ui.tap` 的 `activated:true` 当成测试通过。

## 2. 常见动作模板

### UIButton 默认激活

```bash
curl -sS -X POST "$BASE" -H 'Content-Type: application/json' \
  -d '{"action":"ui.tap","data":{"accessibilityIdentifier":"checkout.submit","viewSnapshotID":"snap-1"}}'
```

要求：目标在 `ui.viewTargets` 中，`availableActions` 含 `tap`，且 `isEnabled=true`。

### UISwitch 切换

```bash
curl -sS -X POST "$BASE" -H 'Content-Type: application/json' \
  -d '{"action":"ui.tap","data":{"path":"root/0/4","viewSnapshotID":"snap-1"}}'
```

成功响应会含 `activationRoute:"switch.toggle"`、`previousValue`、`currentValue`。之后重新 observe 验证业务页面状态。

### UIScrollView 滚动

```bash
curl -sS -X POST "$BASE" -H 'Content-Type: application/json' \
  -d '{"action":"ui.scroll","data":{"accessibilityIdentifier":"product.list","direction":"down","amount":400,"animated":false}}'
```

滚动会改变可见区域。滚动后默认重新 `ui.viewTargets`，不要继续复用旧 path。

### scrollToElement

```bash
curl -sS -X POST "$BASE" -H 'Content-Type: application/json' \
  -d '{"action":"ui.scrollToElement","data":{"match":"text","value":"提交订单","animated":false}}'
```

该命令不签发 `viewSnapshotID`。滚到目标后立刻重新 `ui.viewTargets`，再对新 snapshot 下的 canonical target 执行动作。

### navigation back

```bash
curl -sS -X POST "$BASE" -H 'Content-Type: application/json' \
  -d '{"action":"ui.navigation.back","data":{"strategy":"auto","animated":false,"waitAfterMs":300}}'
```

成功只说明 dismiss/pop 已执行；仍要重新 observe。

### navigation bar button

先从 `ui.viewTargets` 的 `navigationBar.rightItems` / `leftItems` 读取 `placement`、`index`、`title` 或 `accessibilityIdentifier`，再触发：

```bash
curl -sS -X POST "$BASE" -H 'Content-Type: application/json' \
  -d '{"action":"ui.navigation.tapBarButton","data":{"placement":"right","index":0,"title":"保存","waitAfterMs":300}}'
```

导航栏按钮不走 `ui.tap`，也不要坐标硬点。

### alert 查询

```bash
curl -sS -X POST "$BASE" -H 'Content-Type: application/json' \
  -d '{"action":"ui.alert.respond","data":{"dryRun":true}}'
```

当前版本只能查询 `UIAlertController` 标题、消息、按钮和输入框。`dryRun=false` 不会真实点击，返回明确错误；遇到弹窗阻断流程时，需要宿主自定义 action、人工处理，或后续单独评估私有 API 风险。

## 3. 错误后的固定处理

| code / 现象 | 处理 |
|---|---|
| `stale_locator` | 旧 `viewSnapshotID` 或旧 path 不可靠；重新 `ui.viewTargets`，不要重试旧输入。 |
| `wait_timeout` | 重新 observe，再判断业务失败、条件错误、目标不可见、弹窗遮挡或网络慢。 |
| `unsupported_target` | 目标没有默认 tap；改用 `ui.control.sendAction` 或专用命令。 |
| `alert_unavailable` | 当前无 `UIAlertController`；如果只是排查弹窗，可以继续下一步。 |
| `alert_button_required` | `dryRun=false` 当前版本不能点击/关闭 alert（公共 API 无法触发 `UIAlertAction` handler）。改回 `dryRun=true` 查询按钮，再走宿主自定义 action、人工或后续版本。 |
| `navigation_bar_item_mismatch` | 页面或按钮已变化；重新 observe navigationBar 区块。 |

## 4. 不要做的事

- 不要直接构造坐标 tap；`ui.tap` 已不接受坐标。
- 不要用 `ui.topViewHierarchy` / `ui.screenshot` 的结果当动作授权来源。
- 不要在 `stale_locator` 后继续复用旧 `viewSnapshotID`。
- 不要用 `ui.tap` 点 navigationBar 或 alert 按钮。
- 不要把 action 成功当作测试通过；必须重新观察并验证页面证据。
