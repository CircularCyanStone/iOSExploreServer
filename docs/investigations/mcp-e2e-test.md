# iOSDriver 端到端测试指南

> 适用场景：Mac MCP Server + iOS 真机（经 iproxy USB 转发）
> 最后更新：2026-07-06

## 前置条件

### 1. 工具安装

```bash
brew install libimobiledevide  # 提供 iproxy
```

### 2. 设备连接

```bash
# 查看已连接的真机 UDID
xctrace list devices

# 确认当前 App 的 bundle ID
# SPMExample 示例: com.coo.SPMExample
```

### 3. 启动 App + iproxy

**真机**：用 Xcode 在真机上 Run SPMExample（确保 `IOS_EXPLORE_AUTOSTART=1` 已配置）

**iproxy 转发**（新终端，保持前台运行）：

```bash
cd /Users/coo/Desktop/iOS_agent_debugger/iOSExploreServer
./scripts/proxy.sh
# 或用完整命令：
iproxy 38321 38321 -u <UDID>
```

### 4. 验证基础连通性

```bash
# 检查 iproxy 是否在监听
lsof -iTCP:38321 -sTCP:LISTEN
# COMMAND 必须是 iproxy，不是残留的 SPMExampl

# 验证 App 在线
curl -s http://localhost:38321/ -d '{"action":"ping"}'
# 应返回: {"code":"ok","data":{"pong":true}}
```

---

## 第一层：基础 API 验证（curl）

### 1.1 ping

```bash
curl -s http://localhost:38321/ -d '{"action":"ping"}' | python3 -m json.tool
```

预期：`{"code":"ok","data":{"pong":true}}`

### 1.2 help

```bash
curl -s http://localhost:38321/ -d '{"action":"help"}' | python3 -m json.tool
```

预期：返回所有注册命令的列表，包含 action、description、inputSchema

### 1.3 echo

```bash
curl -s http://localhost:38321/ -d '{"action":"echo","data":{"hello":"world"}}' | python3 -m json.tool
```

预期：`{"code":"ok","data":{"hello":"world"}}`

### 1.4 info

```bash
curl -s http://localhost:38321/ -d '{"action":"info"}' | python3 -m json.tool
```

预期：返回设备/系统/App bundle 信息

### 1.5 device

```bash
curl -s http://localhost:38321/ -d '{"action":"device"}' | python3 -m json.tool
```

预期：返回设备机型名称

---

## 第二层：日志能力验证（curl）

### 2.1 app.logs.mark

```bash
curl -s http://localhost:38321/ -d '{"action":"app.logs.mark"}' | python3 -m json.tool
```

预期返回：

```json
{
  "code": "ok",
  "data": {
    "cursor": { "captureSessionID": "...", "id": 123 },
    "oldestAvailableID": 1,
    "latestAvailableID": 456,
    "capture": {
      "explore": { "state": "..." },
      "bridge": { "state": "..." },
      "stdout": { "state": "..." },
      "stderr": { "state": "..." },
      "nslog": { "state": "..." },
      "oslog": { "state": "..." }
    }
  }
}
```

> `capture` 对象展示每个日志来源的当前状态（enabled / notCaptured / unavaliable）

### 2.2 app.logs.read（全量读取）

```bash
curl -s http://localhost:38321/ -d '{"action":"app.logs.read","data":{"limit":20}}' | python3 -m json.tool
```

预期：返回 `entries` 数组，每条包含 `source`、`level`、`category`、`message`

### 2.3 按来源过滤读取

```bash
# 只读 stdout
curl -s http://localhost:38321/ -d '{"action":"app.logs.read","data":{"sources":["stdout"],"limit":20}}' | python3 -m json.tool

# 只读 stderr
curl -s http://localhost:38321/ -d '{"action":"app.logs.read","data":{"sources":["stderr"],"limit":20}}' | python3 -m json.tool

# 只读 os_log
curl -s http://localhost:38321/ -d '{"action":"app.logs.read","data":{"sources":["oslog"],"limit":20}}' | python3 -m json.tool

# 只读 bridge
curl -s http://localhost:38321/ -d '{"action":"app.logs.read","data":{"sources":["bridge"],"limit":20}}' | python3 -m json.tool
```

### 2.4 增量读取（mark → 写日志 → read after cursor）

```bash
# 1) 打标记
curl -s http://localhost:38321/ -d '{"action":"app.logs.mark"}' | python3 -m json.tool
# 记下返回的 cursor：captureSessionID 和 id 值

# 2) 在真机 App 上执行产生日志的操作
#    （如点 DiagnosticsTestViewController 的场景按钮）

# 3) 从刚才的 cursor 之后读取
curl -s http://localhost:38321/ -d '{"action":"app.logs.read","data":{"after":{"captureSessionID":"<上面返回的captureSessionID>","id":<上面返回的id>},"sources":["stdout"],"limit":20}}' | python3 -m json.tool
```

### 2.5 日志诊断场景测试（SPMExample DiagnosticsTestViewController）

在真机 App 上进入「日志诊断测试」页，依次点击 5 个场景按钮，每次点击后用 curl 读取验证：

**场景 A：网络请求场景**
```bash
# 点「🌐 网络请求场景」按钮
curl -s http://localhost:38321/ -d '{"action":"app.logs.read","data":{"sources":["stdout","oslog","bridge"],"limit":30}}' | python3 -m json.tool
```

预期：可见 `stdout` 的 curl 调试日志、`bridge` 的 API 埋点、`oslog` 的 `[Network]` 标记

**场景 B：认证流程场景**
```bash
# 点「🔐 认证流程场景」按钮
curl -s http://localhost:38321/ -d '{"action":"app.logs.read","data":{"sources":["stdout","stderr","oslog","bridge"],"limit":30}}' | python3 -m json.tool
```

预期：`stderr` 的 token 告警、`bridge` 的认证埋点、`oslog` 的 `[Auth]` 标记

**场景 C：业务事件场景**
```bash
# 点「📊 业务事件场景」按钮
curl -s http://localhost:38321/ -d '{"action":"app.logs.read","data":{"sources":["stdout","stderr","bridge","oslog"],"limit":30}}' | python3 -m json.tool
```

预期：多种埋点事件

**场景 D：系统级场景**
```bash
# 点「⚠️ 系统级场景」按钮
curl -s http://localhost:38321/ -d '{"action":"app.logs.read","data":{"sources":["stderr","nslog","oslog","bridge"],"limit":30}}' | python3 -m json.tool
```

预期：`NSLog` 和 `os_log` 的系统告警、`stderr` 的配置加载失败

**场景 E：全链路追踪场景**
```bash
# 点「🔍 全链路追踪场景」按钮
curl -s http://localhost:38321/ -d '{"action":"app.logs.read","data":{"limit":50}}' | python3 -m json.tool
```

预期：全流程日志，覆盖所有 6 个来源

---

## 第三层：iOSDriver 测试（MCP JSON-RPC 协议）

### 3.1 编译 iOSDriver

```bash
cd /Users/coo/Desktop/iOS_agent_debugger/iOSExploreServer/iOSDriver
npm run build
```

注意：`tsconfig.json` 的 `rootDir: "."` 使入口文件生成在 `dist/src/index.js`

### 3.2 tools/list

```bash
echo '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | node dist/src/index.js
```

预期：返回 tools 数组，包含 `health_check`、`observe`、`call_action`、`wait_and_observe`、`refresh_tools` 及所有动态注册的 `ios_*` 工具

### 3.3 逐个测试 MCP tools

```bash
# health_check
echo '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"health_check"}}' | node dist/src/index.js

# observe
echo '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"observe"}}' | node dist/src/index.js

# ios_ping
echo '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"ios_ping"}}' | node dist/src/index.js

# ios_info
echo '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"ios_info"}}' | node dist/src/index.js

# ios_help
echo '{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"ios_help"}}' | node dist/src/index.js

# ios_echo
echo '{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"ios_echo","arguments":{"hello":"world"}}}' | node dist/src/index.js

# ios_ui_viewTargets（获取当前屏幕元素）
echo '{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"ios_ui_viewTargets"}}' | node dist/src/index.js

# ios_ui_topViewHierarchy（视图层级树）
echo '{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"ios_ui_topViewHierarchy"}}' | node dist/src/index.js

# ios_ui_screenshot（截屏）
echo '{"jsonrpc":"2.0","id":10,"method":"tools/call","params":{"name":"ios_ui_screenshot"}}' | node dist/src/index.js
```

### 3.4 通过 MCP 测试日志

```bash
# ios_app_logs_mark
echo '{"jsonrpc":"2.0","id":11,"method":"tools/call","params":{"name":"ios_app_logs_mark"}}' | node dist/src/index.js

# ios_app_logs_read
echo '{"jsonrpc":"2.0","id":12,"method":"tools/call","params":{"name":"ios_app_logs_read"}}' | node dist/src/index.js
```

### 3.5 通过 MCP 模拟日志写入

```bash
# debug.emitStdout
echo '{"jsonrpc":"2.0","id":13,"method":"tools/call","params":{"name":"ios_debug_emitStdout","arguments":{"message":"mcp-e2e-test-stdout"}}}' | node dist/src/index.js

# debug.emitStderr
echo '{"jsonrpc":"2.0","id":14,"method":"tools/call","params":{"name":"ios_debug_emitStderr","arguments":{"message":"mcp-e2e-test-stderr"}}}' | node dist/src/index.js

# debug.emitNSLog
echo '{"jsonrpc":"2.0","id":15,"method":"tools/call","params":{"name":"ios_debug_emitNSLog","arguments":{"message":"mcp-e2e-test-nslog"}}}' | node dist/src/index.js

# debug.emitOSLog
echo '{"jsonrpc":"2.0","id":16,"method":"tools/call","params":{"name":"ios_debug_emitOSLog","arguments":{"message":"mcp-e2e-test-oslog"}}}' | node dist/src/index.js

# debug.emitLogger
echo '{"jsonrpc":"2.0","id":17,"method":"tools/call","params":{"name":"ios_debug_emitLogger","arguments":{"message":"mcp-e2e-test-logger"}}}' | node dist/src/index.js
```

### 3.6 MCP Inspector（UI 调试工具）

```bash
npx @modelcontextprotocol/inspector node dist/src/index.js
```

浏览器打开 http://localhost:5173，可在线执行 List Tools / Call Tool

---

## 第四层：UI 交互验证

前提：真机 App 已打开并处于可交互页面

### 4.1 获取当前可交互元素

```bash
curl -s http://localhost:38321/ -d '{"action":"ui.viewTargets"}' | python3 -m json.tool
```

返回 targets 数组，每条包含 accessibilityIdentifier、title、frame、viewSnapshotID 等

### 4.2 截图

```bash
curl -s http://localhost:38321/ -d '{"action":"ui.screenshot","data":{"maxDimension":1280}}' > /tmp/screenshot.json
cat /tmp/screenshot.json | python3 -c "
import json, base64, sys
data = json.load(sys.stdin)['data']
with open('/tmp/screenshot.png', 'wb') as f:
    f.write(base64.b64decode(data['screenshot']))
print('Saved to /tmp/screenshot.png')
"
```

### 4.3 视图层级树

```bash
curl -s http://localhost:38321/ -d '{"action":"ui.topViewHierarchy","data":{"detailLevel":"basic"}}' | python3 -m json.tool
```

### 4.4 导航返回

```bash
curl -s http://localhost:38321/ -d '{"action":"ui.navigation.back"}' | python3 -m json.tool
```

---

## 故障排查

| 现象 | 排查命令 | 原因 |
|------|---------|------|
| curl 无响应 | `lsof -iTCP:38321 -sTCP:LISTEN` | iproxy 没起或端口被占 |
| COMMAND=SPMExampl | `pkill -f "CoreSimulator.*SPMExample"` | 模拟器残留占端口 |
| iproxy 报 Address in use | `lsof` 查监听进程 | 端口 38321 被占 |
| `ios_ui_*` 返回 `hierarchyUnavailable` | 检查 App 是否在前台 | UI 命令需要可见的 keyWindow |
| 日志为空 | `app.logs.mark` 检查 capture 状态 | 某来源可能 notCaptured |

---

## 快速验证清单

```bash
# 一行命令跑完整基础链路
echo "=== 1. ping ==="
curl -s http://localhost:38321/ -d '{"action":"ping"}'
echo ""
echo "=== 2. help ==="
curl -s http://localhost:38321/ -d '{"action":"help"}' | python3 -c "import json,sys; d=json.load(sys.stdin); print(f'commands: {len(d[\"data\"][\"commands\"])}')"
echo "=== 3. mark ==="
curl -s http://localhost:38321/ -d '{"action":"app.logs.mark"}' | python3 -c "import json,sys; d=json.load(sys.stdin); print(f'sessionID: {d[\"data\"][\"cursor\"][\"captureSessionID\"]}')"
echo "=== 4. read ==="
curl -s http://localhost:38321/ -d '{"action":"app.logs.read","data":{"limit":5}}' | python3 -c "import json,sys; d=json.load(sys.stdin); print(f'entries: {len(d[\"data\"][\"entries\"])}')"
echo "=== 5. echo ==="
curl -s http://localhost:38321/ -d '{"action":"echo","data":{"test":true}}'
echo ""
echo "=== 6. ui.screenshot ==="
curl -s http://localhost:38321/ -d '{"action":"ui.screenshot","data":{"maxDimension":100}}' | python3 -c "import json,sys; d=json.load(sys.stdin); print(f'screenshot len: {len(d[\"data\"][\"screenshot\"])} chars')"
echo ""
echo "=== 7. device ==="
curl -s http://localhost:38321/ -d '{"action":"device"}' | python3 -c "import json,sys; d=json.load(sys.stdin); print(f'device: {d[\"data\"]}')"
echo ""
echo "=== 8. info ==="
curl -s http://localhost:38321/ -d '{"action":"info"}' | python3 -c "import json,sys; d=json.load(sys.stdin); print(f'bundle: {d[\"data\"][\"bundleName\"]}')"
echo ""
echo "=== DONE ==="
```
