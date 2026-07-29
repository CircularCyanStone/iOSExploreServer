# iOSDriver 本地安装与更新（Codex）

本文用于把当前仓库构建出的 iOSDriver 注册到 Codex。

## 准备

```bash
cd <repo>/iOSDriver
npm install
npm run build
npm link
iosdriver init
iosdriver doctor
```

默认 App endpoint 是 `http://localhost:38321/`。真机需要先运行 `iproxy 38321 38321`。

## 注册

Codex 当前使用用户级 MCP 配置。先预览，再执行：

```bash
iosdriver mcp setup codex --dry-run
iosdriver mcp setup codex
```

setup 调用 `codex mcp get/add`，登记当前 Node、iOSDriver CLI 和 App 配置文件的绝对路径。它不要求 Codex 继承终端 PATH，也不连接 App。

重复执行且内容相同时返回 `unchanged`。如果已有不同的 `iOSDriver` 配置：

```bash
iosdriver mcp setup codex --force
```

没有 link 时可直接使用构建产物：

```bash
node <repo>/iOSDriver/dist/adapters/cli/main.js mcp setup codex
```

## 验证

```bash
codex mcp list
codex mcp get iOSDriver
```

重启 Codex 后调用 MCP 工具 `health_check`。如果连接失败，按顺序检查：

```bash
curl -s -X POST http://localhost:38321/ -d '{"action":"ping"}'
iosdriver doctor
```

`health_check` 可达但 `ui.*` 返回 `unknown_action` 时，确认 App 已调用 `registerUIKitCommands()`。

## 更新

```bash
cd <repo>/iOSDriver
npm run build
iosdriver mcp setup codex --force
```

只有 Node、CLI 或配置文件绝对路径发生变化时才需要重新 setup。源码重新构建后仍需完全退出并重启 Codex，已运行的 stdio 子进程不会自动加载新代码。
