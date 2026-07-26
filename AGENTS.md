# iOSExploreServer — Agent Guide

本文件只给 agent 使用。给开发者看的接入、安装和使用说明放在 `README.md` 与 `docs/developers/`。

## 当前项目形态

iOSExploreServer 是 Debug-only 的 iOS App HTTP 自动化库。App 内 `ExploreServer` 基于 `NWListener` 监听单一端点 `POST /`，按 `action` 执行命令并返回统一 envelope。Mac 侧 `iOSDriver/` 提供同一合同上的 CLI 与 MCP adapter。

核心事实源：

- App wire 协议与 action 字段：`contracts/`，生成文档为 `docs/generated/contracts.md`。
- Swift runtime：`Sources/iOSExploreServer/`、`Sources/iOSExploreUIKit/`、`Sources/iOSExploreDiagnostics/`。
- Mac host runtime / CLI / MCP：`iOSDriver/src/`。
- Agent 参考入口：`docs/agents/README.md`。
- 开发者参考入口：`docs/developers/README.md`。

## 硬规则

1. **Debug-only**：自动化与私有 API 相关代码只在 Debug 集成，必要时用 `#if DEBUG` 隔离。
2. **Core 不依赖 UIKit**：`Sources/iOSExploreServer/` 不 import UIKit；UIKit 信息由 `iOSExploreUIKit` 或宿主 handler 注入。
3. **新增能力注册 action，不改 endpoint**：HTTP endpoint 固定 `POST /`；成功 `{"code":"ok","data"?}`，失败 `{"code":"...","message":"..."}`。
4. **通信失败和业务失败分层**：HTTP/JSON/请求体问题用 HTTP 400/500；action 业务失败用 HTTP 200 + 失败 envelope。
5. **Typed input factory**：UIKit 命令入参先用 Foundation-only `CommandInput` 解析校验，UIKit 类型不穿 public 边界。
6. **Swift 6.2 严格并发**：跨边界模型 `Sendable`，共享状态用 `Mutex`，闭包标注 `@Sendable`。
7. **显式注册扩展模块**：Core 内置命令在 `ExploreServer.init` 注册；UIKit 命令由 `server.registerUIKitCommands()` 注册；Diagnostics 命令由 `server.registerDiagnosticsCommands()` 注册。
8. **合同是 schema 单一事实源**：不要在 README、skill 或 adapter 中手写复制 action 字段表；改合同后运行生成与漂移检查。
9. **只保留合理设计**：开发期不要保留“能用先这样”的兼容分支；不合理设计应收敛到当前最合理方案。
10. **通用 skill 与本项目解耦**：`.codex/skills` 是可迁移能力说明，不写本仓库路径、bundle id、设备 ID、测试账号或一次性验收记录。真实案例放 `docs/skills/examples/` 或项目文档。

## 模块边界

| 模块 | 职责 |
| --- | --- |
| `Sources/iOSExploreServer/` | Core HTTP listener、router、envelope、内置 `ping`/`echo`/`info`/`help`。不能依赖 UIKit。 |
| `Sources/iOSExploreUIKit/` | `ui.*` 命令、UIKit resolver/executor/snapshot store。只通过 public API 挂到 core。 |
| `Sources/iOSExploreDiagnostics/` | `app.logs.*`、Debug 日志桥接、可选 stdout/stderr/NSLog/os_log 捕获。 |
| `contracts/` | Device action 与 host operation 合同。生成 Swift metadata、TypeScript schema 和文档。 |
| `iOSDriver/src/runtime/` | Mac 侧 transport、timeout、错误归一化、capability probe、artifact 解码。 |
| `iOSDriver/src/workflows/` | `wait_and_inspect`、`tap_and_inspect` 等跨 action workflow。 |
| `iOSDriver/src/adapters/cli/` | `iosdriver init|doctor|call|mcp`。只做 CLI 参数、配置、输出和退出码投影。 |
| `iOSDriver/src/adapters/mcp/` | 静态 MCP 工具列表、工具映射和 MCP 内容渲染。不能从 App `help` 动态生成工具。 |

## 文档分层

- 开发者文档：`README.md`、`docs/developers/`、`iOSDriver/README.md`、`iOSDriver/install/`。
- Agent 文档：`AGENTS.md`、`CLAUDE.md`、`docs/agents/`、`docs/architecture/`、`docs/runbooks/`、`docs/skills/`。
- 历史设计：`docs/superpowers/`。可查背景，但当前 action/字段/错误以 `contracts/` 和源码为准。
- Generated 文档：`docs/generated/contracts.md`。不要手写修改。

## 修改前核验

- 涉及 action 名、参数、默认值、返回结构、错误码或限制时，先查 `contracts/`、当前实现和测试；三者不一致时先查明真实契约。
- 涉及 CLI/MCP 时，查 `iOSDriver/src/adapters/cli/`、`iOSDriver/src/adapters/mcp/` 和 `iOSDriver/package.json`，不要沿用历史兼容入口安装说明。
- 涉及真机连接时，查 `docs/runbooks/debugging.md`；不要把本机设备 ID 写进通用文档。

## 验证策略

按影响范围选择验证，不机械全量跑：

- 只读、解释、查文件：不跑测试。
- 只改文档、README、注释：默认做链接、路径、过期关键词或格式检查；不跑 Swift/Node 全量测试。
- 移动文件或调整目录结构：优先 `swift build`、`swift package describe` 或相关引用检查。
- 改 Swift 源码、HTTP 协议、命令行为、并发、网络、日志捕获、错误码或 public API：先跑直接相关定向测试；风险高或跨模块再跑全量 `swift test`。
- 改合同或 iOSDriver runtime/adapter：运行 `cd iOSDriver && npm run contracts:check`，再按影响跑 `npm test` 或定向 vitest。
- 用户明确要求不跑测试时，不得擅自运行；最终说明未验证风险。

## 常用命令

| 命令 | 用途 |
| --- | --- |
| `swift build` | 构建 SPM 库。 |
| `swift test` | macOS SPM 测试。 |
| `cd iOSDriver && npm run contracts:check` | 检查合同生成产物是否漂移。 |
| `cd iOSDriver && npm test` | iOSDriver build + vitest。 |
| `curl -s -X POST http://localhost:38321/ -d '{"action":"ping"}'` | 检查 App HTTP 服务。 |
| `node iOSDriver/dist/adapters/cli/main.js doctor` | 用本地构建产物检查 host 到 App 的连接和能力。 |

## Skill 内容治理

适用于所有通用 skill：

- 修改前先阅读当前 `SKILL.md`、关联 `references/`、`agents/openai.yaml` 和快捷方式目标，确认问题真实存在。
- 正文只保留多数任务需要、跨 App 稳定、能减少临场判断且由该 skill 唯一负责的规则。
- 长示例、参数变体和模板下沉到 `references/`；真实项目案例放 `docs/skills/examples/`。
- 每条跨 skill 规则只能有一个所有者；入口 skill 只说明路由和交接契约。
- 修改过的 skill 要运行对应 `quick_validate.py`，并检查链接、快捷方式、重复内容和本地工程耦合。

## 沟通要求

不要只用“工程化”“打通”“闭环”“收敛”“边界”“主线”“兜底”“能力补齐”“验证完成”等抽象短词回复。使用这些词时，同一段必须解释：具体涉及哪些文件/模块/命令，会改变什么运行行为，为什么现在要做，下一步先做什么，完成后用什么验证。

## 完成汇报

每次任务结束必须说明：

- **本次任务目标**：用户想解决的实际问题。
- **修改了什么**：按模块/文件解释。
- **产生什么效果**：对外行为、HTTP 命令响应、配置开关或文档入口的变化。
- **怎么使用或验证**：关键配置、curl、启动参数或测试命令。
- **仍未实现和限制**：没做的能力、默认关闭项、平台限制或未运行的验证。
