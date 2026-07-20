---
name: ios-mcp-setup
description: iOS 自动化工具 MCP 配置指引。当用户说"配置 MCP"、"安装 iOSDriver"、"工具不可用"、"MCP Server 连不上"、"怎么安装 XcodeBuildMCP"时使用。提供 iOSDriver MCP 与 XcodeBuildMCP 的安装、配置、验证步骤。MCP setup, iOSDriver installation, XcodeBuildMCP configuration
allowed-tools: []
---

# iOS MCP 配置指引

专门处理 iOS 自动化所需的两个 MCP Server 的安装、配置与验证。当 `ios-automation` 检测到 MCP 工具不可用时会路由到此 skill，或用户主动询问配置方法时使用。

## 目标

解决"怎么让 iOS 自动化工具可用"的配置问题：

- **检测当前状态** — 判断哪些 MCP Server 已安装、哪些缺失
- **提供安装步骤** — iOSDriver MCP 与 XcodeBuildMCP 的完整配置流程
- **验证安装结果** — 重启后如何确认工具可用

**不做**：不执行实际的 iOS App 操作（回到 `ios-automation` 路由），不处理连接问题（走 `ios-connection`），不构建调试 App（走 `ios-debugger-agent`）。

## 何时使用

### 使用场景
- ✅ `ios-automation` 检测到 MCP 工具不可用，路由到此处理配置
- ✅ 用户说"配置 MCP"、"安装 iOSDriver"、"怎么设置 XcodeBuildMCP"
- ✅ 用户遇到"tool not found"、"MCP Server 连不上"、"工具列表里没有 mcp__iOSDriver__*"
- ✅ 首次使用 iOS 自动化功能，需要环境准备

### 不适用场景
- ❌ MCP 已配置，要操作 iOS App → 回到 `ios-automation` 继续路由
- ❌ MCP 已配置但连接失败 → 走 `ios-connection` 处理连接问题
- ❌ 需要构建/安装/调试 App → 走 L0 `ios-debugger-agent`

## MCP Server 依赖

iOS 自动化需要两个 MCP Server：

| MCP Server | 层级 | 用途 | 工具前缀 |
|---|---|---|---|
| **iOSDriver MCP** | L1 | 已集成 iOSExploreServer 的 App UI 操作与日志 | `mcp__iOSDriver__*` |
| **XcodeBuildMCP** | L0 | Xcode 构建、设备管理、App 启动调试 | `mcp__XcodeBuildMCP__*` |

两者配合工作：XcodeBuildMCP 负责构建和启动 App，iOSDriver MCP 负责 App 内的 UI 操作与进程日志读取。

## 配置流程

### 1. 检测当前状态

首次配置时，Agent 应尝试列出当前可用的 MCP 工具，判断哪些已安装：

- 看到 `mcp__iOSDriver__health_check` / `mcp__iOSDriver__ui_inspect` → iOSDriver MCP 已安装
- 看到 `mcp__XcodeBuildMCP__list_devices` / `mcp__XcodeBuildMCP__build_run_sim` → XcodeBuildMCP 已安装
- 两者都缺失 → 需要全新安装
- 只有一个 → 补全另一个

### 2. iOSDriver MCP 安装

iOSDriver MCP Server 封装了 iOSExploreServer 的 HTTP API（`POST http://localhost:38321/`），提供类型安全的工具调用接口。

#### 安装步骤

**前置要求**：
- Node.js 14+ 已安装（`node --version` 验证）
- Git 已安装

**安装流程**：

1. **克隆仓库**
   ```bash
   git clone https://github.com/cystone/iOSDriver.git
   cd iOSDriver
   ```

2. **安装依赖**
   ```bash
   npm install
   ```

3. **构建项目**（如果仓库包含构建步骤）
   ```bash
   npm run build
   ```
   如果没有 build 脚本，跳过此步。

4. **配置 Claude Desktop**

   编辑 Claude Desktop MCP 配置文件（位置见下方"配置文件位置"），添加：

   ```json
   {
     "mcpServers": {
       "iOSDriver": {
         "command": "node",
         "args": ["/absolute/path/to/iOSDriver/build/index.js"],
         "env": {}
       }
     }
   }
   ```

   **注意**：
   - 将 `/absolute/path/to/iOSDriver` 替换为实际的绝对路径
   - 如果仓库没有 `build/index.js`，可能是 `src/index.js` 或 `index.js`，根据实际结构调整
   - `args` 必须是绝对路径，不能用 `~` 或相对路径

5. **重启 Claude Desktop**

   配置文件修改后必须完全退出并重启 Claude Desktop 才能加载新的 MCP Server。

#### 验证安装

重启后，执行 `/ios-automation`，应能看到以下工具可用：
- `mcp__iOSDriver__health_check`
- `mcp__iOSDriver__ui_inspect`
- `mcp__iOSDriver__ui_tap_and_inspect`
- `mcp__iOSDriver__app_logs_read`
- 其他 `mcp__iOSDriver__*` 工具

如果看不到这些工具，检查：
- Claude Desktop 是否完全重启（不是刷新，是退出后重新打开）
- 配置文件 JSON 格式是否正确（逗号、引号、括号）
- `args` 路径是否存在且可执行（`node /path/to/index.js` 能否运行）

### 3. XcodeBuildMCP 安装

XcodeBuildMCP 提供 Xcode 构建、设备管理、App 启动调试能力，是 L0 层的核心工具。

#### 安装步骤

**前置要求**：
- macOS 系统
- Xcode 已安装（`xcodebuild -version` 验证）
- Command Line Tools 已安装（`xcode-select --install`）

**安装流程**：

1. **通过 NPM 安装 CLI 工具**

   ```bash
   npm install -g xcodebuildmcp@latest
   ```

2. **配置 Claude Desktop**

   ```bash
   xcodebuildmcp install
   ```

   该命令会自动在 Claude Desktop MCP 配置中添加：
   ```json
   {
     "mcpServers": {
       "XcodeBuildMCP": {
         "command": "npx",
         "args": ["-y", "xcodebuildmcp@latest", "mcp"]
       }
     }
   }
   ```

3. **重启 Claude Desktop**

完整文档与最新安装方法：https://www.xcodebuildmcp.com/#get-started

#### 验证安装

重启后，应能看到以下工具可用：
- `mcp__XcodeBuildMCP__list_devices`
- `mcp__XcodeBuildMCP__build_run_sim`
- `mcp__XcodeBuildMCP__launch_app_device`
- `mcp__XcodeBuildMCP__session_show_defaults`
- 其他 `mcp__XcodeBuildMCP__*` 工具

如果看不到这些工具，执行：
```bash
xcodebuildmcp doctor
```
根据诊断结果修复问题。

### 4. 配置文件位置

Claude Desktop MCP 配置文件位于：

- **macOS**: `~/Library/Application Support/Claude/claude_desktop_config.json`
- **Windows**: `%APPDATA%\Claude\claude_desktop_config.json`
- **Linux**: `~/.config/claude/claude_desktop_config.json`

如果文件不存在，创建一个新的 JSON 文件，内容为：
```json
{
  "mcpServers": {}
}
```
然后按上述步骤添加各 MCP Server 配置。

### 5. 完整配置示例

同时配置两个 MCP Server 的完整 `claude_desktop_config.json` 示例：

```json
{
  "mcpServers": {
    "iOSDriver": {
      "command": "node",
      "args": ["/Users/username/Projects/iOSDriver/build/index.js"],
      "env": {}
    },
    "XcodeBuildMCP": {
      "command": "xcodebuildmcp",
      "args": ["mcp"],
      "env": {}
    }
  }
}
```

**注意**：
- XcodeBuildMCP 的配置可能由 `xcodebuildmcp install` 自动生成，以实际安装结果为准
- 如果已有其他 MCP Server 配置，在 `mcpServers` 对象内并列添加即可
- JSON 格式要求严格：对象最后一项后不能有逗号，所有字符串用双引号

## 常见问题

### 工具列表里看不到 mcp__iOSDriver__*

**原因**：
- iOSDriver MCP Server 未启动
- 配置文件路径错误
- Claude Desktop 未重启

**排查步骤**：
1. 检查配置文件位置是否正确（见"配置文件位置"）
2. 检查 JSON 格式是否有语法错误（用在线 JSON validator 验证）
3. 检查 `args` 路径是否存在：`ls -l /path/to/iOSDriver/build/index.js`
4. 尝试手动运行：`node /path/to/iOSDriver/build/index.js`，看是否报错
5. 完全退出 Claude Desktop（Command+Q 或右键 Dock 图标退出），重新打开

### xcodebuildmcp: command not found

**原因**：
- XcodeBuildMCP 未安装
- 安装路径未加入 PATH

**解决**：
1. 重新执行安装步骤：访问 https://www.xcodebuildmcp.com/#get-started
2. 检查安装是否成功：`which xcodebuildmcp`
3. 如果安装了但找不到，检查 shell 配置文件（`.zshrc` / `.bash_profile`）是否包含正确的 PATH

### 配置后工具仍不可用

**原因**：
- Claude Desktop 缓存未清理
- MCP Server 进程启动失败

**解决**：
1. 完全退出 Claude Desktop
2. 删除缓存（可选）：`rm -rf ~/Library/Caches/Claude`
3. 重新打开 Claude Desktop
4. 查看 Claude Desktop 日志（通常在 `~/Library/Logs/Claude/` 或开发者工具控制台）寻找错误信息

### 能看到工具但调用报错

**原因**：
- MCP Server 已连接但运行时出错
- 依赖环境不满足（如 Node.js 版本过低、Xcode 未安装）

**解决**：
1. 检查 Node.js 版本：`node --version`（需 14+）
2. 检查 Xcode 版本：`xcodebuild -version`
3. 尝试调用 `mcp__iOSDriver__health_check` 或 `mcp__XcodeBuildMCP__list_devices`，根据具体错误信息排查

## 验证完整流程

配置完成后，执行以下步骤验证：

1. **验证 MCP Server 可用**
   ```
   执行 /ios-automation，Agent 应能成功调用：
   - mcp__XcodeBuildMCP__list_devices（列出设备）
   - mcp__iOSDriver__health_check（检测 App 连接）
   ```

2. **验证 L0 能力（XcodeBuildMCP）**
   ```
   执行 /ios-debugger-agent，应能：
   - 列出已连接的模拟器和真机
   - 构建并运行 iOS 项目
   - 管理 session defaults
   ```

3. **验证 L1 能力（iOSDriver MCP）**
   ```
   在 App 已运行且集成 iOSExploreServer 的情况下：
   - health_check 返回成功
   - ui_inspect 返回当前 UI 结构
   - 可执行 ios-ui-* 系列操作
   ```

如果上述验证都通过，说明配置成功，可以开始使用 iOS 自动化功能。

## 后续步骤

配置完成后：

- **开发调试场景** → 回到 `/ios-automation`，它会自动路由到对应的 `ios-ui-*` 或 `ios-logs`
- **需要构建/安装 App** → 使用 `/ios-debugger-agent` 进行 L0 操作
- **连接问题** → 如果 `health_check` 失败，会自动路由到 `/ios-connection` 处理

## 相关 skill

- `ios-automation`（L1 入口） — 配置完成后的任务路由入口，会在启动时检测 MCP 可用性
- `ios-connection`（L1） — 处理 App 连接问题（iproxy、端口冲突等），需要 MCP 已配置
- `ios-debugger-agent`（L0） — XcodeBuildMCP 的主要使用者，负责构建调试
- `ios-ui-*`（L1） — iOSDriver MCP 的主要使用者，负责 UI 操作

## 参考资源

- iOSDriver MCP GitHub: https://github.com/cystone/iOSDriver
- XcodeBuildMCP 官网: https://www.xcodebuildmcp.com
- Claude Desktop MCP 文档: https://docs.anthropic.com/claude/docs/mcp
