---
name: ios-connection
description: iOS App 连接管理与诊断。当用户说"连不上 App"、"iproxy"、"端口 38321"、"真机测试连接"、"Address already in use"时使用。处理模拟器/真机连接差异、iproxy 管理、设备上下文和端口冲突；MCP 工具未安装或未加载时转 ios-mcp-setup。connection troubleshooting, iproxy setup, device context, port conflict, simulator vs device
---

# iOS App 连接管理与诊断

处理 iOSDriver MCP 已可调用、但目标 App HTTP 自动化端点不可达或设备上下文不明确的问题。MCP 工具本身缺失时转 `ios-mcp-setup`；连接成功后的 UI 和日志任务转回 `ios-automation`。

## 连接模型

- 模拟器与 Mac 共享网络命名空间，目标 App 监听后直接访问 `localhost:<PORT>`，不启动 `iproxy`。
- 真机端口不能直接从 Mac 访问时，用 `iproxy` 把 Mac 本地端口转发到设备端口。默认端口是 `38321`，实际值以 iOSDriver 的 base URL 和 App 配置为准。
- XcodeBuildMCP 的 `deviceId` 与 `iproxy -u` 接受的 USB UDID 来自不同工具，不能互换。前者使用设备列表返回值，后者由本 skill 脚本从 `idevice_id -l` 获取或通过 `DEVICE_UDID` 显式传入。
- 不能仅凭一次 `health_check` 失败判断当前是模拟器还是真机，也不能据此判断真机启动工具是否已加载。

## 诊断流程

按顺序执行，得到结论后停止当前分支：

1. 调用 iOSDriver `health_check`。
2. 工具不存在或调用无法发起：MCP server 未加载，转 `ios-mcp-setup`。
3. 返回 `ok:true`：连接正常，转回 `ios-automation` 处理用户任务。
4. 返回 `ok:false`，且 `connection.status == "app_endpoint_unreachable"`，或 `connection.error` / `app.ping.error` 显示 transport `connection_failed`：iOSDriver MCP 已运行，但 App 端点当前不可达；继续判断设备上下文。
5. 通过当前构建/设备管理工具的真实设备列表、会话配置和工具清单判断目标环境。多台可用设备时让用户选择，不猜测设备。
6. 启动或重启目标 App 后重试 `health_check`。重试仍失败时，模拟器检查 App 是否启动 HTTP server；真机继续检查 `iproxy` 和端口占用。

`ui_inspect` 可调用但返回 `unknown_action` 表示 App 未注册 UIKit 命令，不是连接失败。连接 skill 到此给出模块注册结论，再把具体修复交给宿主集成或相应 UI skill。

## 模拟器路径

1. 确认目标模拟器已启动，目标 App 已安装并运行。
2. 如果需要改变启动参数，先停止 App，再按当前构建/设备管理工具的真实 schema 重新启动；不要假设已运行进程会自动重启。
3. 重试 `health_check`。端点仍不可达时，检查 App 是否已启动 HTTP server，以及 iOSDriver base URL 与 App 监听端口是否一致。

## 真机路径

本 skill 提供 `$SKILL_DIR/scripts/iproxy-manager.sh`。`SKILL_DIR` 必须由当前 `ios-connection/SKILL.md` 的实际路径计算，不能按工作目录猜测。

1. 运行 `"$SKILL_DIR/scripts/iproxy-manager.sh" start` 建立 launchd 托管的 USB 转发。该命令会修改当前用户的 LaunchAgents；只在用户任务确实需要建立真机连接时执行。
2. 从构建/设备管理工具的设备列表选择可用真机，并使用其返回的 `deviceId` 设置会话上下文。
3. 检查当前会话是否真实暴露真机启动能力。缺少 `launch_app_device` / `stop_app_device` / `build_run_device` 时，结论是“构建/设备管理 MCP 的真机 workflow 未加载”，转 `ios-mcp-setup`，不要归因于 App 或 iOSDriver。
4. 真机工具可用时启动或重启 App，再重试 `health_check`。
5. 仍失败时运行 `"$SKILL_DIR/scripts/iproxy-manager.sh" status`，按其最终结论处理 USB、端口监听者或设备侧服务状态。

只有用户明确接受平台原生命令兜底时，才在真机 MCP 工具缺失后改用 `xcrun devicectl` 等命令。

## iproxy 脚本

| 命令 | 作用 | 使用条件 |
|---|---|---|
| `install` | 通过 Homebrew 安装 libimobiledevice | 本机没有 `iproxy` 时 |
| `start` | 创建并加载当前用户 LaunchAgent | 真机需要建立转发时 |
| `stop` | 卸载本脚本管理的 LaunchAgent | 不再需要转发时 |
| `restart` | 重建转发 | 设备切换或既有转发异常时 |
| `status` | 检查监听者、USB 设备和 App ping | 真机连接失败时 |
| `check` | 只检查 App ping | 已知转发存在时 |
| `clean` | 清理指定模拟器 App 的端口残留 | 必须提供 `APP_BUNDLE_ID` 或 `SIMULATOR_PROCESS_NAME`；不对未知进程猜测或强杀 |

脚本支持用 `PORT`、`REMOTE_PORT`、`DEVICE_UDID` 覆盖连接参数。只有清理已知模拟器 App 时才传 `APP_BUNDLE_ID` 或 `SIMULATOR_PROCESS_NAME`。其余细节直接运行脚本 `help`，不要在正文复制完整参数说明。

## 失败分诊

| 现象 | 结论 | 下一步 |
|---|---|---|
| `health_check.connection.status` 是 `app_endpoint_unreachable` | MCP server 可调用，App 端点不可达 | 启动 App；真机再检查 `iproxy status` |
| `health_check` 先失败、启动 App 后成功 | 早期失败发生在端点 ready 前 | 记录为启动时序，不再诊断连接 |
| 真机任务只有 `*_sim` 工具 | 真机 workflow 未加载 | 转 `ios-mcp-setup`，重连后复查工具清单 |
| 端口由非 `iproxy` 进程监听 | 当前不是预期真机转发链路 | 停止已知冲突进程；未知进程不自动清理 |
| `Address already in use` | 本地端口已有监听者 | 先 `status` 识别进程，再决定 `restart` 或定向清理 |
| `ui_inspect` 返回 `unknown_action` | 连接正常，UIKit 命令未注册 | 检查宿主 UIKit 注册入口 |
| 启动参数没有效果 | App 可能未被停止，或参数不符合当前工具 schema | 停止后按工具 schema 重新启动 |

## 边界

- `ios-automation`：上游入口；只做依赖检测、连接验证和任务路由。
- `ios-mcp-setup`：安装 MCP、启用 workflow、修复工具不可见。
- `ios-ui-*`：连接成功后的 UI 操作与 UI 失败分诊。
- `ios-logs`：连接成功后的 App 进程内日志读取。
- 构建/设备管理工具：构建、安装、启动、停止和系统级调试；本 skill 不复制这些工具的参数表。
