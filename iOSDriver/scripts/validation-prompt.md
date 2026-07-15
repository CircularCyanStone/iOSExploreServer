# Mac MCP Server 能力验证提示词

## 目标

验证刚建好的 Mac MCP Server（`iOSDriver/`）的完整能力，通过「进入 SPMExample App → 导航到日志诊断测试界面 → 触发 5 个场景按钮 → 读取验证各日志来源」这条真实路径，发现 MCP server 是否有问题。

## 前置条件

iPhone 真机已连，iproxy 已启动：
```bash
iproxy 38321 38321 -u 00008030-001045C136D1402E
lsof -iTCP:38321 -sTCP:LISTEN
```
确认 COMMAND 是 `iproxy`，不是 `SPMExampl`。

APMExample App 已安装并运行，带 `IOS_EXPLORE_AUTOSTART=1` 环境变量。

## 验证步骤

### 0. 启动 MCP server

从仓库根目录 `iOSDriver/`：
```bash
npm run build
node dist/src/index.js
```

### 1. health_check

通过 MCP stdio 调用 `health_check` 工具。验证返回 `ok: true`，`dynamicToolCount > 0`。

如果 health_check 失败（连接拒绝/超时），验证它是否返回了结构化错误（区分 `transport` / `mcp_server` 错误源），而不是直接 crash 或返回非结构化的纯文本。

### 2. ui_inspect

通过 MCP 调用 `ui_inspect` 工具（对应 App 端 `ui.inspect` action）。验证：
- 返回 `viewSnapshotID`（格式 `snap-N`）
- 返回 `navigationBar.title` 为 "iOSExploreServer"
- 返回至少 20 个 targets
- 有 tappable 的目标（`availableActions` 包含 `"tap"`）

### 3. 导航到日志诊断测试界面

先通过 `ui_topViewHierarchy` 或 `ui_inspect` 找到"日志诊断测试"条目。观察发现：

- inspect 中的 `UIListContentView` 列表不直接显示文本内容，需要通过 `ui_topViewHierarchy(detailLevel=full)` 找到 cell 内 UILabel 的文本
- cell 的 tappable path 是 `root/5/0/1`（UIListContentView），不是 `root/5/0`（UITableViewCell）

用 `call_action(ui.tap, path, viewSnapshotID)` 点击该 cell。**关键注意点**：

- `viewSnapshotID` 必须跟 **同一个 ui_inspect 调用返回的** 值，不能重新 inspect 取新 ID 然后用它做 tap
- 如果 tap 返回 `stale_locator`，说明 viewSnapshotID 已过期 → 重新 inspect 获取新的 vsid → 立即带着新 vsid 调 tap（需要在一个 MCP session 内完成：inspect 返回后 100ms 内发 tap）
- tap 成功后验证返回 `"activated": true`

### 4. 探索日志诊断测试页面

再次 `ui_inspect`，确认导航栏标题变为 `"日志诊断测试"`，topViewController 变为 `DiagnosticsTestViewController`。

用 `call_action(ui.topViewHierarchy, detailLevel=full)` 查看完整页面结构。验证有：

- 场景说明文字："点击场景按钮..."
- 5 个场景按钮（通过 text 确认）：网络请求/认证流程/业务事件/系统级/全链路追踪
- 复制 cursor 按钮、清空事件流按钮

用 `call_action(ui.inspect)` 获取可交互目标列表。验证 5 个场景按钮的 path 都是 `root/0/0/0/N/0` 形式（N=1~5），均有 `availableActions: ["tap"]`，且有 `accessibilityIdentifier`。

### 5. 触发 5 个场景按钮

对每个场景按钮执行：ui_inspect（拿新 vsid）→ tap（用新 vsid）→ sleep 0.3s。验证每次 tap 返回 `activated: true`。

**注意点**：
- 场景 1 的 path 是 `root/0/0/0/1/0` 不是 `root/0/0/0/1`
- 如果遇到 `stale_locator`，原因是没有立即使用 ui_inspect 返回的 vsid

测试完成后，记录哪些场景按钮触发成功、哪些失败。

### 6. 读取各来源日志

先后验证：

1. `app.logs.mark` — 建立 cursor 检查点，验证返回 `cursor.id`
2. `app.logs.read(sources=["bridge"])` — 读 bridge 来源日志，验证存在场景触发后的业务日志（如 `Step N/5`、`Config load failed`）
3. `app.logs.read(sources=["stdout"])` — 读 stdout 来源
4. `app.logs.read(sources=["stderr"])` — 读 stderr 来源，验证有 `WARNING` 或 `ERROR` 条目
5. `app.logs.read(sources=["nslog"])` — 读 NSLog 来源
6. `app.logs.read(sources=["oslog"])` — 读 os_log 来源（会有大量系统级日志）
7. `app.logs.read(limit=30)` — 不加来源过滤，验证返回内容完整

### 7. 兜底能力验证

1. 调 `call_action(action="ping")` 验证兜底通道工作
2. 调一个不存在的 action（如 `call_action(action="notexist")`），验证返回结构化 `ios_envelope` 错误（`code: "unknown_action"`），不是直接崩溃
3. 关掉 iproxy，调 `health_check`，验证返回 `ok: false` 而非 crash

## 需要特别关注的 MCP server 问题区域

1. **viewSnapshotID 过期 vs 陈旧状态**：`ui_inspect` 返回 vsid 后，如果在 300ms 后才调 tap，是否返回 `stale_locator`？这说明 snapshot 的 TTL 很短。这是正常行为还是需要 MCP server 自动 retry？

2. **嵌套 cell 的 path**：为何 inspect 中 `UIListContentView` 有 `tap` action，但 tap `root/5/0/1` 实际上触发的是 `UITableViewCell` 的选中？需要确认是否所有 `UIListContentView` 的 tap 执行的都是 `cell.select` 路由。MCP server 的 `call_action` 透传，这里其实不是 MCP server 的问题，是 iPhone 端 UIKit 命令的行为。

3. **multiple MCP calls 在同一个 session**：如果 inspector 脚本把 inspect → tap → inspect 做到一个 MCP session 里，用 event-driven 方式（inspect 一返回立刻发 tap），就不会有 vsid 过期。但如果是手动命令一条条发（健康检查 → 观察 → 等指令 → 点击），就容易过期。这说明 **MCP server 本身没有问题，但推荐调用流程需要 document 清楚**：inspect 返回后必须在 100ms 内发 tap。

4. **scroll 后 vsid 失效**：如果先 scroll 再 tap，可能需要新的 inspect。确认 scroll 不会自动清空 snapshot。

## 预期结果

所有 5 个场景按钮应成功触发，bridge/explore 来源有日志产生。stdout/stderr/nslog 来源取决于对应 capture 是否在 app 启动时已启用。如果某个来源没有日志，记录该来源的 `capture.state`（通过 `app.logs.mark` 返回中的 `capture` 字段查看）。

## 报告要求

验证完成后，用通俗中文说明：
1. 哪些步骤通过 MCP 调用成功了
2. 哪些步骤遇到了问题，是 MCP server 的问题还是协议/使用方式的问题
3. 问题复现的步骤和规避方法
4. 对 MCP server 是否需要改动的建议
