---
name: ios-connection
description: iOS App 连接管理与诊断。当用户说"连不上 App"、"iproxy"、"端口 38321"、"真机测试连接"、"Address already in use"时使用。处理模拟器/真机连接差异、iproxy 管理、设备同步、端口冲突诊断。connection troubleshooting, iproxy setup, device sync, port conflict, simulator vs device
---

# iOS App 连接管理与诊断

专门处理"怎么连上 App"与"连不上怎么办"两个问题。基于 iOSDriver MCP(`mcp__iOSDriver__*`)与 XcodeBuildMCP(`mcp__XcodeBuildMCP__*`)工具体系。

## 目标

解决 iOS App 连接管理的三个核心问题：

- **模拟器与真机连接差异** — 模拟器直连 localhost，真机需 iproxy USB 转发，且有四个易踩的坑
- **设备同步与智能启动** — 自动检测已连接设备，多设备时引导选择，未运行时智能启动 App
- **连接失败诊断** — 端口冲突、进程残留、启动参数未生效等 5 种常见错误的判别与处理

**不做**：不处理 App 已连上后的 UI 操作（回到 `ios-automation` 路由到 `ios-ui-*`），不构建/安装 App（走构建/设备管理 MCP 或项目的 L0 构建调试流程）。

## 何时使用

### 使用场景
- ✅ `ios-automation` 的 `health_check` 失败，路由到此处理连接问题
- ✅ 用户说"连不上 App"、"iproxy"、"端口 38321"、"真机测试连接"
- ✅ 用户遇到"Failed to connect"、"Address already in use"、"启动参数没生效"
- ✅ 需要切换真机/模拟器测试环境

### 不适用场景
- ❌ App 已连上，做 UI 操作 → 回到 `ios-automation` 路由到对应 `ios-ui-*`
- ❌ 需要构建/安装/LLDB 调试 → 走构建/设备管理 MCP 或项目的 L0 构建调试流程
- ❌ 读进程日志 → 走 `ios-logs`（连接成功后）

## 连接管理

目标 App 的 HTTP 自动化端点：`POST http://localhost:38321/`（body 是 `{"action": "..."}` JSON）。所有 iOSDriver MCP 工具最终都走这个端点。连接方式取决于 App 跑在模拟器还是真机。

### 模拟器：localhost 直连

模拟器与 Mac 共享 localhost，App 监听 38321 后 Mac 侧直接使用 `health_check` 验证连接即可，**不需要 iproxy**。

宿主 App 的自动化服务实例在 DEBUG 环境下，由宿主在 `viewDidLoad` / `viewDidAppear` / `applicationDidFinishLaunching` 中调用 `server.start()` 自动启动（具体入口由宿主决定；不需要 autostart 环境变量）。

**验证步骤**：
1. 调用 `mcp__iOSDriver__health_check`
2. 成功 → App 已运行，返回 `ios-automation` 继续路由
3. 失败 → 进入"模拟器诊断流程"（见"快速诊断"小节）

### 真机：iproxy USB 转发

真机的 38321 端口不暴露给 Mac，必须经 `iproxy` USB 隧道转发。本 skill 提供一键管理脚本 `scripts/iproxy-manager.sh`，自动处理安装、launchd 托管启动、端口清理、设备检测。

#### 真机测试标准流程（Agent 辅助执行）

Agent 执行本 skill 时协助完成以下步骤：

1. **启动 iproxy（launchd 托管）** — `scripts/iproxy-manager.sh start` 可以由开发者终端、Agent shell、Makefile 或其他自动化入口执行；脚本会写入 `~/Library/LaunchAgents/com.codex.iproxy.<PORT>.plist` 并交给 launchd 以 `KeepAlive` 方式托管。稳定性来自 launchd 接管后的服务生命周期，而不是执行脚本的那个 shell 是否继续存在。若当前 Agent 环境没有 shell 权限或不适合改本机 launchd 状态，才提示开发者手动执行该命令。
2. **同步设备配置** — 调用 `mcp__XcodeBuildMCP__list_devices` 获取已连接设备，自动更新 `deviceId` 到 session defaults。多设备时提示用户选择。
3. **智能启动 App** — `mcp__iOSDriver__health_check` 检测 App 是否运行，未运行则调用 `mcp__XcodeBuildMCP__launch_app_device`。启动失败时根据错误类型给出明确提示（未安装/证书未信任/其他错误）。
4. **验证连接** — 多次 `health_check` 确认稳定，失败时提示用户在终端执行 `scripts/iproxy-manager.sh status` 诊断。

`scripts/iproxy-manager.sh` 自动处理：iproxy 安装检查、残留清理、UDID 获取、launchd 服务管理、状态诊断。Agent 可在具备 shell 权限且任务需要时执行脚本；没有 shell 权限时才引导开发者执行。不要再以 `nohup ... &`、当前 agent shell、或旧 `scripts/proxy.sh --daemon` 作为长期稳定性的依据。

### 真机/模拟器四个关键差异

1. **设备 ID 两套体系** — XcodeBuildMCP 的 `deviceId`（`list_devices` 返回）用 **CoreDevice identifier**（8-4-4-4-12 形式的 UUID）；`iproxy -u` 用 **USB UDID**（连字符分隔的十六进制串）。同一台设备不能混用。脚本自动处理 UDID 获取，无需手动区分。
2. **iOS 版本别信 devicectl 的机型字段** — 会缓存串号（iOS 26.5 真机可能显示成 iPhone 11）。判版本只看 `list_devices` 的 `osVersion`。
3. **`build_run_*` 不注入 session env** — 要传启动参数（如回到流程起点），必须用 `launch_app_*(env/launchArgs)`，且先 `stop_app_*` 再 `launch_app_*`（已运行的 App 不会重启、参数不生效）。
4. **真机前先确认 38321 是 `iproxy` 在监听** — 模拟器跑过的 App 可能残留成 Mac 进程占住 38321，导致真机预期对不上。Agent 用 `health_check` 验证连接；开发者手动排查时用 `scripts/iproxy-manager.sh status` 检查占用进程类型。

## 快速诊断

连接或行为异常时按下列顺序排查。

### Agent 诊断路径（优先使用 MCP 工具）

#### 1. 验证连接（`health_check`）

90% 的"连不上"场景 App 其实已运行，Agent 优先用 `mcp__iOSDriver__health_check` 验证：

- ✅ 通 → 连接正常，问题在 UI 层（路由回 `ios-automation` → 对应 `ios-ui-*`）
- ❌ 工具调用成功但返回 `ok:false` / `source:"transport"` / `code:"connection_failed"` → iOSDriver MCP Server 已可用，只是 App 端点 `38321` 当前不可达；进入步骤 3，先启动或重启 App，再重试 `health_check`
- ❌ 工具本身不存在或无法发起 → MCP Server 未配置或未被客户端加载，转 `/ios-mcp-setup`

**反模式**：每次任务前都跑完整端口 / 进程诊断流程，浪费 2-3 秒。**正确**：先 `health_check`，失败了再深度查。

#### 2. UI 状态快照（`ui_inspect`）

连接通但行为异常时，用 `mcp__iOSDriver__ui_inspect` 取当前视图结构（targets / alert / navigationBar），签发 `viewSnapshotID` 给后续 `ui_tap_and_inspect` 用。本 skill 的诊断范围只到"读状态"，看到具体 UI 问题后路由给对应 `ios-ui-*`。

若 `health_check.ok == true` 且 `dynamicToolCount > 0`，但工具面板没有直接显示 `ui_inspect`，说明 App 的 `help` 已返回、动态工具加载链路已通，只是客户端工具列表没有刷新出来。此时允许用 `mcp__iOSDriver__call_action({action:"ui.inspect", data:{...}})` 兜底取快照，并在报告里记录"动态工具未直接暴露"；不要把这种情况误判为连接失败。

#### 3. 设备与 App 状态检查

连接失败时，按以下顺序检查：

1. **检查设备连接** — 调用 `mcp__XcodeBuildMCP__list_devices`，确认目标设备在列表中
2. **检查 App 是否运行** — 真机场景提示用户在终端执行 `scripts/iproxy-manager.sh status` 检查 iproxy 状态和端口占用
3. **尝试启动 App** — 调用 `mcp__XcodeBuildMCP__launch_app_device` 或 `launch_app_sim`，观察启动结果

### 开发者手动排查（仅供终端使用，Agent 禁用）

以下操作**仅供开发者在终端手动使用**，Agent 优先使用 MCP 工具做连接验证；连接失败且需要本机端口诊断时，应提示用户手动执行 `scripts/iproxy-manager.sh status`。

#### 手动连接验证与端口诊断

连接失败或行为异常时，在终端执行：

```bash
scripts/iproxy-manager.sh status
# 自动检查：
# - 端口 38321 占用情况（是 iproxy 还是残留目标 App 进程）
# - USB 设备连接状态（真机场景）
# - iproxy 服务可用性
# - 并给出针对性修复建议
```

## 常见错误与判别

### 连接失败（Failed to connect to localhost port 38321）

- **现象**：`health_check` 失败，无法连接到 App
- **原因**：App 未启动、App 起了但 `server.start()` 没调、或 38321 未监听
- **判别**：调用 `list_devices` 确认设备在线，再尝试 `launch_app_*`
- **Agent 处理**：检查 App 是否已启动；真机场景提示用户在终端执行 `scripts/iproxy-manager.sh status` 检查 iproxy 状态
- **开发者手动修复**：`scripts/iproxy-manager.sh status` 检查端口和服务状态

### 先失败后成功（health_check 瞬时失败）

- **现象**：第一次 `health_check` 返回 `connection_failed`，随后 XcodeBuildMCP 构建/启动 App 后再次 `health_check` 返回 `ok:true`、`ping.pong:true`
- **原因**：第一次检查发生在 App 尚未启动、DEBUG `server.start()` 尚未 ready、或真机 iproxy 隧道尚未连到 App 监听端口之前；这只能说明"当时端点不可达"，不能说明真机能力不可用
- **判别**：`mcp__iOSDriver__health_check` 能返回结构化 body，本身就证明 iOSDriver MCP Server 可调用；只有 `ok:false` 的错误来源指向 App 端点
- **Agent 处理**：先用 XcodeBuildMCP 启动目标 profile 的 App，等待短暂 ready 窗口后重试 `health_check`；成功后继续 UI 操作，并在报告里把早期失败标为"启动前端点未 ready"

### 真机返回模拟器旧数据

- **现象**：真机测试时收到的数据明显是旧版本或错误环境
- **原因**：模拟器跑过的 App 残留成 Mac 进程占住 38321（见"四个关键差异"第 4 点）
- **判别**：`health_check` 成功但返回数据不符合预期（如 bundle id 不对、版本号旧）
- **Agent 处理**：提示用户手动清理残留进程
- **开发者手动修复**：`scripts/iproxy-manager.sh restart`（自动卸载旧 LaunchAgent / 停止旧 iproxy → 重建 launchd 托管 → 验证；若端口被模拟器 App 占用，先按脚本提示执行 `clean`）

### 端口已被占用（Address already in use: 38321）

- **现象**：iproxy 启动失败，提示端口被占用
- **原因**：旧 iproxy 未停，或模拟器 App 残留占用
- **判别**：用户在终端看到 `Address already in use: 38321` 错误
- **Agent 处理**：提示用户手动重启 iproxy
- **开发者手动修复**：`scripts/iproxy-manager.sh restart`

### 启动参数没生效

- **现象**：用 `launch_app_*` 传了 `env` 或 `launchArgs`，但 App 行为未变
- **原因**：`build_run_sim` / `build_run_device` 不注入 session env；已运行的 App 不会重启（见"四个关键差异"第 3 点）
- **判别**：App 界面未进入预期测试页面（如未显示 alert test / login 页面）
- **Agent 处理**：先 `stop_app_*` 再 `launch_app_*(launchArgs=[...])`
- **开发者手动修复**：确认 App 完全停止后再启动

### App 启动失败

- **现象**：`launch_app_device` / `launch_app_sim` 返回错误
- **原因**：App 未安装、证书未信任、iOS 版本不匹配、其他系统错误
- **判别**：看 `launch_app_*` 返回的错误信息
- **Agent 处理**：
  - 未安装 → 提示"App 未安装，需要先通过构建/设备管理 MCP 构建安装"
  - 证书未信任 → 提示"设备上打开'设置 > 通用 > VPN 与设备管理'信任开发者证书"
  - iOS 版本不匹配 → 提示"检查 App 的 deployment target 是否匹配设备 iOS 版本"
  - 其他错误 → 返回完整错误信息，建议走构建/设备管理 MCP 或项目的 L0 调试流程

## 关键参数

本 skill 直接使用的 MCP 工具：

| 工具 | 含义 | 注意 |
|---|---|---|
| `mcp__iOSDriver__health_check` | 验证 App 是否运行并可连接 | 诊断第一步，通过才继续 |
| `mcp__iOSDriver__ui_inspect` | 读当前 UI 结构 | 连接通但行为异常时用 |
| `mcp__iOSDriver__call_action` | 工具面板没暴露动态 UI 工具时兜底转发 | 只在 `health_check.ok == true` 后使用 |
| `mcp__XcodeBuildMCP__list_devices` | 列出已连接设备 | 返回 CoreDevice identifier（不是 USB UDID） |
| `mcp__XcodeBuildMCP__launch_app_device` | 启动真机 App | 需先 `list_devices` 同步 deviceId |
| `mcp__XcodeBuildMCP__launch_app_sim` | 启动模拟器 App | 可传 `env` / `launchArgs` |
| `mcp__XcodeBuildMCP__stop_app_device` | 停止真机 App | 启动参数未生效时先停再启 |
| `mcp__XcodeBuildMCP__stop_app_sim` | 停止模拟器 App | 启动参数未生效时先停再启 |
| `mcp__XcodeBuildMCP__build_run_device` | 构建并运行真机 App | 不注入 session env，需单独 `launch_app_*` 传参 |
| `mcp__XcodeBuildMCP__build_run_sim` | 构建并运行模拟器 App | 不注入 session env，需单独 `launch_app_*` 传参 |

## 相关 skill

- `ios-automation`（L1 入口） — 本 skill 的上游，连接成功后回到该 skill 继续路由
- 构建/设备管理 MCP（L0） — App 未安装或需构建时改用它
- `ios-ui-*`（L1） — 连接成功后的具体 UI 操作
- `ios-logs`（L1） — 连接成功后读进程日志
