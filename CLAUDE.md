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

@AGENTS.md
