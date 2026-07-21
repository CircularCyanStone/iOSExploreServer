# iOS Skills 开源化审计跟踪

**日期**: 2026-07-21  
**对象**: `.codex/skills/*` 下 15 个 iOS skills  
**目标**: 按 `skill-creator` 标准把这些 skills 收敛成通用、可开源、可迁移的 skills。  
**当前结论**: 静态开源化问题已完成第一轮修复；模拟器链路已实测通过；真机链路在设备解锁后已完成 ping/help/log 闭环实测。

## 核验标准

本次按用户要求和 `skill-creator` 核验:

- skill 不关联本地测试项目、示例 App 名称、真实账号、真实 bundle id 或设备标识。
- skill 不包含本地绝对路径、客户端私有目录或机器专属路径。
- skill 不绑定某个特定 agent 客户端或开发工具的私有能力名称。
- `SKILL.md` frontmatter 只保留 `name` 和 `description`。
- `SKILL.md` 正文保持精简，接近或超过 500 行时拆到 `references/`。
- skill 本体只保留直接支撑功能的 `scripts/`、`references/`、`assets/`、`agents/openai.yaml`；自测资产放在仓库 `docs/skills/evals/`。
- 运行能力结论来自真实模拟器/真机验证，不能只靠静态推测。

## 当前统计

| 项 | 结果 | 状态 |
|---|---:|---|
| skill 数量 | 15 | 记录 |
| 含额外 tool allowlist frontmatter 的 `SKILL.md` | 0 | 已修 |
| `quick_validate.py` 失败数 | 0 | 已修 |
| skill 本体内 `evals/` 目录 | 0 | 已修 |
| `agents/openai.yaml` | 15 | 已补 |
| skill 内 README | 0 | 已修 |
| 超过 500 行的 `SKILL.md` | 0 | 已修 |
| skill 内 macOS 元数据文件 | 0 | 已清理 |

## 问题跟踪

| ID | 严重级别 | 状态 | 问题 | 当前处理 |
|---|---|---|---|---|
| SKILL-AUDIT-001 | 高 | 已修 | 15 个 skill 的 frontmatter 曾含额外 tool allowlist 字段，不符合正文只保留 `name` / `description` 的规则 | 已移除；工具依赖改在正文描述 |
| SKILL-AUDIT-002 | 高 | 已修 | `ios-test-runner` description 曾含尖括号，导致校验失败 | 已改成无尖括号的通用描述，15 个 skill 均通过校验 |
| SKILL-AUDIT-003 | 高 | 已修 | 部分 skill 正文绑定具体示例 App、测试账号或仓库示例路径 | 已改为占位 App / 通用说明；真实案例不得作为 skill 本体依赖 |
| SKILL-AUDIT-004 | 高 | 已修 | iproxy 管理脚本曾写死具体 bundle id，且脚本归属与连接 skill 文档不一致 | 已迁到 `ios-connection/scripts/iproxy-manager.sh`，并改为 `APP_BUNDLE_ID` / `SIMULATOR_PROCESS_NAME` 等调用方参数；未提供时只诊断不强杀 |
| SKILL-AUDIT-005 | 高 | 已修 | skill 内脚本文档曾包含本机绝对路径 | 已删除该 README；必要说明保留在脚本 help 或主 skill |
| SKILL-AUDIT-006 | 高 | 已修 | skill 内脚本文档曾绑定客户端私有 skill 目录 | 已随 README 删除；正文不再使用客户端私有路径 |
| SKILL-AUDIT-007 | 高 | 已修 | `ios-mcp-setup` 曾绑定特定 MCP 客户端和私有工具发现方式 | 已改成客户端中立的 MCP 安装、配置、验证流程 |
| SKILL-AUDIT-008 | 中 | 已修 | `ios-ui-form/SKILL.md` 曾超过 500 行 | 已拆出 `references/form-examples.md`，主文降到 200 行以内 |
| SKILL-AUDIT-009 | 中 | 已修 | 11 个 `evals/` 目录混在 skill 本体里 | 已迁移到 `docs/skills/evals/<skill>/evals.json`，skill 本体不再包含 evals |
| SKILL-AUDIT-010 | 中 | 已修 | 所有 skill 缺少推荐的 `agents/openai.yaml` | 已按 `skill-creator` 生成 15 份 UI 元数据 |
| SKILL-AUDIT-011 | 中 | 已修 | `ios-automation` 曾绑定特定客户端的延迟工具加载命令 | 已改成“使用客户端提供的工具发现能力”这类中立表述 |
| SKILL-AUDIT-012 | 中 | 已修 | `ios-mcp-setup` 示例路径曾鼓励或展示本机用户路径 | 已改为 `/path/to/...` 占位路径，并说明按客户端要求替换为真实绝对路径 |
| SKILL-AUDIT-013 | 中 | 已修 | `ios-automation/scripts/README.md` 属于 `skill-creator` 不建议放入 skill 的辅助文档 | 已删除 |
| SKILL-AUDIT-014 | 中 | 已通过补测 | 真机链路依赖设备解锁、App 已启动和 USB 端口转发三件事同时成立；设备锁屏时构建/设备管理 MCP 会拒绝 launch，`iproxy` 即使监听也只能转发到不可用的 App 端口 | 设备解锁后已完成补测：真机 App 构建启动成功，前台 `iproxy` 连续转发成功，HTTP ping/help 与 iOSDriver health_check/call_action/log 闭环均通过 |
| SKILL-AUDIT-015 | 低 | 已记录 | `quick_validate.py` 依赖 PyYAML；本机缺依赖时会失败 | 本轮验证环境已补齐依赖；后续可另加统一验证脚本 |
| SKILL-AUDIT-016 | 中 | 已修 | `.xcodebuildmcp/iOSDriver-setup.md` 曾包含本机路径和客户端绑定 | 已改成通用 MCP 客户端配置说明 |
| SKILL-AUDIT-017 | 低 | 已修 | `.codex/skills` 内存在 macOS `.DS_Store` 元数据文件 | 已删除 |
| SKILL-AUDIT-018 | 中 | 已修 | 迁移后的 eval JSON 仍有旧断言，要求 frontmatter 含 tool allowlist | 已更新为新标准：frontmatter 只允许 `name` / `description` |

## 实测记录

### 模拟器

状态: 已实测通过。

- 构建并启动示例 App 成功。
- `POST http://localhost:38321/` 的 `ping` action 返回 `{"code":"ok","data":{"pong":true}}`。
- `help` action 返回 36 个命令，字段为 `data.commands`。
- 端口监听显示模拟器 App 进程直接监听本机 `38321`，证明模拟器 localhost 直连规则成立。
- `app.logs.mark` 不接受自定义字段；按真实 schema 调用 `app.logs.mark` + 触发 stdout 输出 + `app.logs.read`，成功按 cursor 读取唯一 token，证明进程内日志增量读取和 stdout capture 在模拟器可用。

### 真机

状态: 已实测通过。

- 已连接真机可被构建/设备管理 MCP 识别。
- 设备锁屏时曾复测失败，系统拒绝 launch；设备解锁后 `build_run_device` 成功构建、安装并启动 App。
- 在当前 agent 命令执行环境中，后台 `ios-connection/scripts/iproxy-manager.sh restart` 可检测 USB 设备并完成一次自检 ping，但命令结束后后台 `iproxy` 随后不可见；这更可能与执行环境回收后台子进程有关。为排除脚本输出误判，改用前台 `iproxy` 观察真实转发。
- 前台 `iproxy` 常驻期间，底层 HTTP 连续 3 次 `ping` 均返回 `pong:true`，`help` 返回 36 个命令。
- iOSDriver `health_check` 返回 `ok:true`，`dynamicToolCount:30`。
- iOSDriver `call_action("help")` 可读取命令表；`app.logs.mark` + `debug.emitStdout` + `app.logs.read` 成功按 cursor 读回 stdout token。
- 结论: 真机运行链路真实可用；文档中要求“先解锁并启动 App，再复查转发进程、端口监听和 ping”是必要的。后台脚本在当前 agent shell 中不适合作为持久 daemon 验证依据，开发者终端中仍应按 `status` 复查。

## 当前修复分工

| 分工 | 写入范围 | 目标 | 状态 |
|---|---|---|---|
| 主线程 | 审计文件、验证、最终整合 | 维护问题状态、补齐缺口、统一验证 | 已完成第一轮 |
| Worker A / Einstein | `.codex/skills/ios-automation/**` | 清理入口 skill、本地路径、示例 App 绑定和 iproxy 脚本硬编码 | 有落盘改动，已由主线程复核 |
| Worker B / Lorentz | `.codex/skills/ios-mcp-setup/SKILL.md`、`.xcodebuildmcp/iOSDriver-setup.md` | MCP 配置说明通用化 | 已完成并复核 |
| Worker C / Kepler | `.codex/skills/ios-test-intent/**`、`.codex/skills/ios-test-runner/**` | 修 frontmatter、测试类示例绑定、校验失败 | 有落盘改动，已由主线程复核 |
| Worker D / Meitner | `.codex/skills/ios-ui-*/*` | 修 UI skills frontmatter、本地绑定，拆分过长正文 | 有落盘改动，已由主线程复核 |
| Worker E / Wegener | `evals` 迁移 | 迁移 skill 本体内 evals | 因请求限流中断；主线程已完成 |

## 当前完成判定

本轮整改当前满足:

- `.codex/skills` 静态扫描无本机路径、客户端私有目录、真实设备标识、具体示例 App 名称或具体 bundle id 命中。
- 15 个 skill 的 `quick_validate.py` 已全部通过。
- `SKILL.md` frontmatter 中无额外 tool allowlist 字段。
- skill 内无 README、无 `evals/`、无 `.DS_Store`。
- 15 个 skill 均有 `agents/openai.yaml`。
- 模拟器 ping/help/log 链路已实测通过。

仍需继续:

- 可继续在开发者交互式终端观察 `ios-connection/scripts/iproxy-manager.sh restart` 启动的后台 `iproxy` 是否稳定常驻；当前真机能力已由前台 `iproxy` + HTTP + iOSDriver 闭环验证通过。
