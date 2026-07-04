# iOSExploreServer — Claude Code Guide

本仓库同时支持 Codex（`AGENTS.md`）与 Claude Code（本文件）。入口规则统一维护在 `AGENTS.md`，此处直接引入，避免双份维护：

## Claude Code 额外提醒：抽象短词必须解释

不要只用“工程化”“落地”“打通”“闭环”“收敛”“主线”“兜底”“边界”“能力补齐”“行为对齐”“协议演进”“验证完成”这类压缩后的短词回复用户。Claude Code 可能因为刚读过文档、源码和测试输出而知道这些词背后的完整含义，但开发者未必看到同样的上下文，所以只给一个短词会让人不知道下一步到底要做什么。

使用这类词时，必须在同一段里补清楚它在当前任务中的具体意思：会改哪些文件或模块、会改变什么运行行为、为什么这些动作是下一步、推荐先做哪件事、完成后用什么命令或真实流程验证。比如不能只说“把闭环打通”，而要解释这个闭环是“示例 App 弹出 alert，Mac 侧发 `ui.alert.respond` 请求，App 侧执行对应 `UIAlertAction` handler，alert 关闭，响应返回 `performed/dismissed/button`”。

如果必须使用项目术语，也要在第一次出现时解释它在当前代码里的含义。例如说“兜底”时，要说明兜底的是哪条路径、在什么条件下启用、失败时返回什么错误；说“边界”时，要说明边界隔离了哪些类型或责任，避免哪些代码散落到调用方。

## Claude Code 额外提醒：示例 App 验证要自动启动 Server

做 `Examples/SPMExample` 的真实闭环验证时，不要重新研究“服务没启动，远程命令无法点击启动服务按钮”这个问题。固定做法是通过启动参数或环境变量让 `Examples/SPMExample/SPMExample/ViewController.swift` 在 Debug 启动后自动调用 `server.start()`，先让 38321 端口可访问，再继续用 `curl` 或 `ui.*` 命令验证页面交互。

推荐沿用语义清楚的开关：`--ios-explore-autostart` 或 `IOS_EXPLORE_AUTOSTART=1` 表示自动启动 server；需要直接进入弹窗测试页时，用 `--ios-explore-open-alert-test` 或 `IOS_EXPLORE_OPEN_ALERT_TEST=1`。如果代码里还没有这些入口，先补 Debug-only 的启动参数/环境变量读取逻辑，不要退回手动点击“启动 Server”的流程。

这些开关是测试工具的长期约定，不是一次性临时环境。验证结束后不用专门删除环境变量或启动参数；后续继续复用，除非项目明确改名或改变行为。

## Claude Code 额外提醒：用 XcodeBuildMCP 跑真机/模拟器走 profile + iproxy

用 XcodeBuildMCP 跑 `Examples/SPMExample` 的完整方案（`enabledWorkflows`、`sim-app`/`sim-fw`/`device-app` 三个 profile、模拟器直接 `curl localhost:38321`、真机经 `iproxy` USB 转发、完整命令序列）写在 `AGENTS.md` 的「XcodeBuildMCP 运行配置」节，不在此重复。下面只列 Claude Code 用 MCP 时最容易踩的四个坑（每次跑真机/模拟器前先过一遍）：

1. **设备 ID 两套**：MCP 的 `deviceId` 是 CoreDevice identifier（`list_devices` 返回的 `3AC0C7D6-...`），`iproxy -u` 是 USB UDID（`00008030-...`），同一台设备不能混用。
2. **devicectl 的机型字段会串号**：判 iOS 版本看 `list_devices` 的 `osVersion`，别信 `devicectl` 的 `Model`（曾把 iOS 26.5 的真机显成 iPhone 11）。SPMExample 部署目标 26.2，低于装不上。
3. **`build_run_sim`/`build_run_device` 不注入 profile 的 `env`**：autostart 必须用 `launch_app_sim`/`launch_app_device` 的 `env` 或 `launchArgs` 驱动，且要先 `stop_app_*` 再 `launch_app_*`（已运行的 App 不重启、参数不生效）。
4. **curl 真机前先 `lsof -iTCP:38321` 确认是 `iproxy` 在监听**：`sim-app` 跑过没关的模拟器 SPMExample 会残留成 Mac 进程占住 38321，`curl localhost:38321` 打到的是这个**模拟器残留**（旧 binary、不是真机、env 也没设），结果对不上真机预期——曾导致真机验证反复卡住。`lsof` 的 COMMAND 列是 `SPMExampl` 则 `xcrun simctl terminate 065CC8DB-8978-46C5-82D6-C96625B608D8 com.coo.SPMExample` 清理后再起 iproxy；`iproxy` 启动立即报 `Address already in use: 38321` 也是这个原因。详细排查见 AGENTS.md「四个必须记住的差异」第 4 点。

@AGENTS.md
