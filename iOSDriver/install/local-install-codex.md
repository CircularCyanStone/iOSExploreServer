# iOSDriver 本地安装与更新（Codex）

本文用于把当前仓库中的 iOSDriver 直接注册到 Codex，方便测试本地修改后的 MCP 服务代码。iOSDriver 是 Node.js/TypeScript 服务，不是 Swift Package；Codex 启动的是 `dist/index.js`。

## 固定本地入口

源码目录：

```text
/Users/coo/Desktop/iOS_agent_debugger/iOSExploreServer/iOSDriver
```

MCP 配置固定指向：

```text
/Users/coo/Desktop/iOS_agent_debugger/iOSExploreServer/iOSDriver/dist/index.js
```

使用绝对路径，避免 Codex 的工作目录变化导致入口找不到。

## 首次安装

要求 macOS、Node.js 20 或更高版本，以及已安装的 Codex CLI。

```bash
cd /Users/coo/Desktop/iOS_agent_debugger/iOSExploreServer/iOSDriver
npm install
npm run build
```

确认编译产物存在：

```bash
test -f /Users/coo/Desktop/iOS_agent_debugger/iOSExploreServer/iOSDriver/dist/index.js
```

## 直接编辑 Codex 配置文件（推荐）

Codex 的 MCP 配置文件是：

```text
~/.codex/config.toml
```

用编辑器打开该文件，在已有配置末尾添加以下内容：

```toml
[mcp_servers.iOSDriver]
command = "node"
args = ["/Users/coo/Desktop/iOS_agent_debugger/iOSExploreServer/iOSDriver/dist/index.js"]

[mcp_servers.iOSDriver.env]
IOS_EXPLORE_BASE_URL = "http://localhost:38321"
IOS_EXPLORE_REQUEST_TIMEOUT_MS = "10000"
```

如果文件中已经存在 `[mcp_servers.iOSDriver]`，不要再添加第二组同名表；直接把它的 `command`、`args` 和环境变量改成上面的值即可。当前仓库的 Codex 配置就是这种形式。

配置完成后完全退出并重新启动 Codex。用下面的命令检查文件中的 MCP 服务是否已被读取：

```bash
codex mcp list
codex mcp get iOSDriver
```

这种方式不依赖 `codex mcp add`，适合需要手动维护配置或把配置纳入本机初始化脚本的场景。

## 使用 Codex 命令注册（可选）

如果不想手动编辑文件，也可以注册本地 stdio MCP 服务：

```bash
codex mcp add iOSDriver \
  --env IOS_EXPLORE_BASE_URL=http://localhost:38321 \
  --env IOS_EXPLORE_REQUEST_TIMEOUT_MS=10000 \
  -- node /Users/coo/Desktop/iOS_agent_debugger/iOSExploreServer/iOSDriver/dist/index.js
```

检查注册结果：

```bash
codex mcp list
codex mcp get iOSDriver
```

如果 `iOSDriver` 已存在，且准备改用命令注册，先删除再注册：

```bash
codex mcp remove iOSDriver
```

## 验证

先确保集成了 iOSExploreServer 的 App 已启动并监听 `38321`。模拟器直接验证：

```bash
curl -s -X POST http://localhost:38321/ \
  -H 'Content-Type: application/json' \
  -d '{"action":"ping"}'
```

预期包含：

```json
{"code":"ok","data":{"pong":true}}
```

然后重新启动 Codex，在 MCP 工具列表中确认 `health_check`。调用它可以验证 iOSDriver 到 App HTTP 服务的连接；App 未启动时，MCP 服务仍可能启动，但 `health_check` 会报告连接失败。

真机还需要先运行 `iproxy 38321 38321`，并确认 `lsof -iTCP:38321 -sTCP:LISTEN` 显示的监听进程是 `iproxy`。

## 本地更新

修改 `iOSDriver/src` 下的代码后，执行：

```bash
cd /Users/coo/Desktop/iOS_agent_debugger/iOSExploreServer/iOSDriver
npm run build
```

因为 Codex 配置始终指向同一个 `dist/index.js`，不需要重新编辑配置文件，也不需要重新 `codex mcp add`。已运行的 MCP 子进程不会自动加载新代码，编译完成后请完全退出当前 Codex，再重新启动；新会话会启动新的 iOSDriver 进程。

可选地，先运行单元测试（测试命令也会先编译）：

```bash
npm test
```

## 常见问题

- `Cannot find module .../dist/index.js`：在 iOSDriver 目录执行 `npm run build`，并检查上面的绝对路径。
- Codex 启动失败或配置解析失败：检查 `~/.codex/config.toml` 的 TOML 表名、引号和数组语法；同名 `[mcp_servers.iOSDriver]` 只能保留一组。
- 工具列表没有更新：确认已经重新启动 Codex；动态工具还依赖 App 当前注册的 action。
- `health_check` 连接失败：先用上面的 `curl` 验证 App 端口，再检查模拟器/真机端口转发。
- 换了电脑或目录：重新注册 `iOSDriver`，把命令中的绝对路径替换为新路径。
