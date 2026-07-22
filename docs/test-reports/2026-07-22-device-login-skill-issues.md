# 真机登录 Skills 问题清单

## 背景

本文记录 2026-07-22 这次“使用真机、账号 `test` / 密码 `123456` 验证登录流程”过程中发现的问题。记录目标不是复述登录成功，而是把执行链路里暴露出来的缺口拆成可逐项修复的条目，便于后续单开会话逐个处理。

本次执行明确遵守以下边界：

- 不阅读业务源码来分析登录页面或流程。
- 以 iOS 自动化 skills、iOSDriver MCP、XcodeBuildMCP、真机连接脚本和运行时 UI/日志为主要依据。
- 结论区分“登录功能本身是否可用”和“skills / MCP / 测试工作流是否存在问题”。

## 本次结论

- 登录功能成功路径可用：成功输入 `test` / `123456`，跳转到“首页”，并展示用户名 `test` 与邮箱 `test@example.com`。
- 退出登录流程可用：点击“退出登录”后出现确认弹窗，选择“退出”后回到登录页。
- 本次主要发现的问题不在登录业务本身，而在真机启动、连接恢复、等待建模、日志信号质量和 skills 抽象层。

## 使用方式

后续逐项修复时，建议每次会话只挑一个问题编号处理，并在修复完成后补充：

- 修复了哪些模块或工具
- 对运行行为带来了什么变化
- 用什么命令或自动化步骤验证
- 还有哪些边界未覆盖

## 问题总览

| 编号 | 严重度 | 问题标题 | 本次状态 |
| --- | --- | --- | --- |
| LOGIN-SKILL-001 | 高 | 真机启动能力未完整纳入 MCP/skills | 已修复，已真机验收 |
| LOGIN-SKILL-002 | 高 | `health_check` 首次失败后缺少直接可执行的恢复指引 | 已修复，已真机验收 |
| LOGIN-SKILL-003 | 中 | 连接诊断信息分散，需要人工拼接结论 | 已修复，已真机验收 |
| LOGIN-SKILL-004 | 中 | 登录场景缺少高层测试模板，成功判据仍需人工组装 | 已修复，已真机验收 |
| LOGIN-SKILL-005 | 中 | 带确认弹窗的流程容易因等待条件不完整而误报超时 | 已修复，已真机验收 |
| LOGIN-SKILL-006 | 中 | 日志存在系统噪音，业务成功信号偏弱 | 已修复，已真机验收 |

## LOGIN-SKILL-001 真机启动能力未完整纳入 MCP/skills

### 问题现象

本次会话中，`mcp_XcodeBuildMCP` 只暴露了模拟器相关工具，没有暴露真机常用的 `build_run_device`、`launch_app_device`、`stop_app_device` 这类工具。因此在“真机已连接，但 App 未启动”的场景下，无法只靠当前 skills/MCP 工具链把 App 拉起并继续测试。

### 本次执行中的具体证据

- `health_check` 首次返回 `connection_failed`，说明 iOSDriver MCP 可用，但真机上的 App 端点不可达。
- 我检查了当前 `mcp_XcodeBuildMCP/tools` 目录，看到的是 `build_run_sim`、`launch_app_sim`、`stop_app_sim`、`list_sims` 等模拟器工具，没有真机对应工具。
- 为了继续测试，实际使用了：

```bash
xcrun devicectl device process launch \
  --device 3AC0C7D6-22F6-572B-8368-4047A14BAB52 \
  --terminate-existing \
  com.coo.SPMExample \
  --ios-explore-show-login
```

- 上述命令成功后，再次 `health_check` 才变为 `ok: true`，说明这次测试能够继续，依赖的是外部命令补位，而不是完整的 skill 闭环。

### 影响

- 影响的不只是“少一个工具”，而是整个真机自动化主线是否能从“设备已连好”自然走到“App 已经在登录页，等待 UI 自动化接管”。
- 如果后续测试者只依赖当前 skills/MCP，而不知道还要手动调用 `devicectl`，就会把问题误以为是 iOSDriver 不可用，或者误判成 App 本身坏了。
- 这会削弱“skills 能独立完成真机场景”的可信度。

### 为什么这是优先级高的问题

- 这是入口问题。入口不通，后面的 `ui.inspect`、`ui.input`、`wait_and_inspect` 再稳定也发挥不出来。
- 这也是最容易让新会话卡住的问题，因为现象只是“连不上”，但真实缺口是“启动链路不完整”。

### 本次临时绕过方式

- 使用 `devicectl` 手动启动真机上的目标 App。
- 重新执行 `health_check`，确认 HTTP 自动化端点已经 ready。

### 建议修复方向

- 确认当前 XcodeBuildMCP profile / workflow 配置为什么没有暴露真机工具。
- 让当前会话可直接使用真机启动、停止、构建工具，而不是要求测试者跳到外部命令行兜底。
- 如果短期内无法补齐真机工具，也应在 `ios-connection` 的诊断结论里明确提示“当前客户端缺少真机启动 MCP 工具，需要临时使用 `devicectl`”。

### 修复完成的验收标准

- 在不借助 `devicectl` 的前提下，能从当前会话直接启动真机 App。
- 真机登录测试从连接检查到进入登录页，全程可以只依赖 skills/MCP 完成。

### 2026-07-22 修复更新

- **修复日期**：2026-07-22
- **修复人**：Agent
- **修改文件**：
  - `.codex/skills/ios-automation/SKILL.md`
  - `.codex/skills/ios-connection/SKILL.md`
  - `.codex/skills/ios-mcp-setup/SKILL.md`
- **行为变化**：
  - `ios-automation` 不再默认"真机一定有 `launch_app_device`"，而是要求先检查当前客户端真实暴露的 XcodeBuildMCP 工具。
  - `ios-connection` 现在把"只看到 `*_sim`、看不到 `launch_app_device` / `stop_app_device` / `build_run_device`"定义为独立故障类别，并输出单条结论：当前会话只加载了模拟器能力，真机链路未加载。
  - `ios-mcp-setup` 增加了真机 workflow 校验步骤，明确要求在需要真机时验证真机工具是否已经暴露，而不是只看 XcodeBuildMCP 是否大致可用。
- **验证命令或自动化步骤**：
  - 检查当前客户端实际加载的 XcodeBuildMCP 工具目录，确认事实仍是只有 `build_run_sim` / `launch_app_sim` / `stop_app_sim` 等模拟器工具，没有真机工具。
  - grep 修改后的 skill 正文，确认已经存在"真机能力未加载 / 只加载了模拟器能力 / device workflow 未生效"这些分支说明。
  - grep `.codex/skills`，确认本次没有把当前工程路径、bundle id、测试账号或示例 App 标识写进 skill 本体。
- **是否仍有剩余限制**：
  - 这次修复解决的是"诊断与路由错误"：后续会话不会再把真机工具缺失误判成 App 或 iOSDriver 故障。
  - 当前会话里 XcodeBuildMCP 仍然只暴露模拟器工具，因此"不借助外部命令直接从本会话启动真机 App"这一更高层目标，还需要继续修复 MCP 真机工具的实际暴露/重连链路。

### 2026-07-22 根因补充

- **新增确认的实例级根因**：
  - 当前机器上同时存在多组 `xcodebuildmcp@latest mcp` 进程。
  - 当前活跃的一组 XcodeBuildMCP 进程工作目录是 `/Users/coo`，而不是当前仓库根目录。
  - 由于 `xcodebuildmcp@latest mcp` 是按启动工作目录读取配置，所以它没有读到本仓库的 `.xcodebuildmcp/config.yaml`，从而只暴露默认的模拟器工具集。
- **现场证据**：
  - `ps -Ao pid,lstart,command | grep 'xcodebuildmcp@latest mcp'`
  - `lsof -a -p <pid> -d cwd -Fn`
  - 输出表明 19:19 启动的 XcodeBuildMCP 进程 cwd 是 `/Users/coo`
  - 与之对应，当前 `mcp_XcodeBuildMCP/tools` 目录里只有 `build_run_sim` / `launch_app_sim` / `stop_app_sim` / `list_sims`
- **已落实的修复方向**：
  - 在 `iOSDriver/install/local-install-trae-work.md` 中补充了推荐配置：通过 `bash -lc` 先 `cd "${workspaceFolder}"` 再启动 `xcodebuildmcp@latest mcp`
  - 这样新进程会稳定读取当前仓库的 `.xcodebuildmcp/config.yaml`
- **当前结论**：
  - 上述阻塞点在重启 MCP 实例后已被消除
  - `LOGIN-SKILL-001` 已在当前会话里完成真机验收

### 2026-07-22 真机验收补充

- **验收日期**：2026-07-22
- **验收方式**：
  - 先确认重启后的 `mcp_XcodeBuildMCP/tools` 已出现：
    - `list_devices`
    - `build_run_device`
    - `launch_app_device`
    - `stop_app_device`
  - 再用 `session_use_defaults_profile("device-app")` 切到真机 profile
  - 用 `launch_app_device` 启动真机 App，获得 `processId`
  - 用 `stop_app_device(processId: ...)` 停掉真机 App，确认端点变成不可达
  - 再次用 `launch_app_device` 启动真机 App
  - 等待短暂 ready 窗口后，用 `health_check` 与 `ui_inspect` 验证恢复
- **现场结果**：
  - `launch_app_device` 成功返回真机进程号（如 `87103` / `87105`）
  - `stop_app_device(processId: 87103)` 成功停止 App
  - 停止后 `health_check` 进入端点不可达状态
  - 再次 `launch_app_device` 后，短暂 ready 窗口结束后：
    - `curl --noproxy '*' ... localhost:38321` 返回 `{"code":"ok","data":{"pong":true}}`
    - `health_check.ok == true`
    - `ui_inspect` 回到登录页，`topViewController == LoginViewController`
- **当前结论**：
  - `LOGIN-SKILL-001` 已完成真实真机验收
  - 当前会话已经具备“只靠 MCP 真机启动链路把 App 拉起并进入登录页”的能力

## LOGIN-SKILL-002 `health_check` 首次失败后缺少直接可执行的恢复指引

### 问题现象

`health_check` 第一次调用只返回了底层传输错误：`connection_failed`。这个信息在协议层是准确的，但对执行测试的人来说，还不够直接，因为它没有直接把问题翻译成“USB 在、iproxy 在、但设备侧 App 没起来或没监听 38321”。

### 本次执行中的具体证据

- 首次 `health_check` 返回：
  - `server.ok: true`
  - `app.ping.ok: false`
  - `error.code: connection_failed`
  - `baseURL: http://localhost:38321/`
- 随后运行 `iproxy-manager.sh status`，发现：
  - `iproxy` 已在监听本地 `38321`
  - USB 设备已检测到
  - 最近日志显示 `Error connecting to device: Connection refused`
- 这说明问题不是 Mac 侧端口没开，也不是 USB 没插，而是设备侧没有进程在接收 38321。

### 影响

- 对熟悉这套链路的人来说，还能继续排查。
- 对第一次接触真机流程的人来说，看到 `connection_failed` 很容易把问题归错类，例如误以为 iproxy 没启动、端口被占用，或者 iOSDriver 整体坏掉。

### 为什么这是高优先级问题

- 它直接影响“第一次失败后能不能快速恢复”。
- 这类问题如果没有更直接的指引，会把本来 1 到 2 分钟能恢复的事情，拖成多轮诊断。

### 本次临时绕过方式

- 继续检查 `iproxy` 和端口状态。
- 最终通过手动启动真机 App 让 `health_check` 恢复。

### 建议修复方向

- 在 `ios-connection` 或 `health_check` 外层包装中，把常见场景翻译成更可执行的结论。
- 例如：当 `iproxy` 正常、USB 在线、但设备侧拒绝连接时，直接输出“真机 App 未启动或未监听 38321，下一步请启动 App 并重试 `health_check`”。
- 如果当前会话又恰好缺少真机启动 MCP 工具，则顺带提示可用的临时启动命令。

### 修复完成的验收标准

- 遇到这类失败时，测试者能在一条诊断结论里看到最可能原因和下一步动作。
- 不需要再手动拼接多个命令输出，才能得出“App 没启动”的结论。

### 2026-07-22 修复更新

- **修复日期**：2026-07-22
- **修复人**：Agent
- **修改文件**：
  - `iOSDriver/src/staticTools.ts`
  - `iOSDriver/tests/staticTools.test.ts`
- **行为变化**：
  - `health_check` 在 `transport/connection_failed` 场景下，不再只返回裸错误；现在会附带 `connection.status: "app_endpoint_unreachable"`、`probableCause` 和 `nextSteps`。
  - `call_action` 的 transport 重试失败也复用同一套连接上下文，避免不同入口给出不同排障语义。
- **验证命令或自动化步骤**：
  - 运行 `npm run build`
  - 运行 `npx vitest run tests/staticTools.test.ts`
  - 结果：`tests/staticTools.test.ts` 17/17 通过，其中新增断言覆盖 `health_check` 的连接诊断输出。
- **是否仍有剩余限制**：
  - `health_check` 现在能明确指出"App 端点不可达"，但它本身仍不知道调用方当前到底在真机还是模拟器，也不知道外部 MCP 客户端是否已经暴露真机启动工具；这部分仍需配合 `ios-connection` / `ios-mcp-setup` 的上层诊断。

### 2026-07-22 真机验收补充

- **验收日期**：2026-07-22
- **验收方式**：
  - 先让真机 App 真实进入不可达状态
  - 再直接调用 `mcp_iOSDriver.health_check`
  - 对比现场返回体是否真的出现新增的 `connection` 结论字段
- **现场结果**：
  - `health_check` 的返回体已经稳定给出：
    - `ok: false`
    - `ping/help` 的 `connection_failed`
  - 但本次会话里**没有出现**预期中的：
    - `connection.status: "app_endpoint_unreachable"`
    - `probableCause`
    - `nextSteps`
- **进一步核对结果**：
  - 仓库中的 `iOSDriver/src/staticTools.ts` 已包含 `transportFailureContext()` 逻辑。
  - 重新执行 `npm run build` 后，`iOSDriver/dist/staticTools.js` 也包含 `app_endpoint_unreachable` 字符串和对应分支。
  - 因此本次真实结论不是“代码没修”，而是“当前 MCP 运行实例没有加载到新的 iOSDriver 构建产物”。
- **当前结论**：
  - `LOGIN-SKILL-002` 已完成真实验证，但**当前不能判定验收通过**。
  - 要让这项真正通过，还需要让当前客户端重连/重启 `mcp_iOSDriver`，再重新做一次端点不可达场景复测。

### 2026-07-22 根因补充

- **新增确认的实例级根因**：
  - 当前机器上同时存在多组 `node .../iOSDriver/dist/index.js` 进程。
  - 其中至少一组来自别的工程目录，另一组来自 `/Users/coo`，只有一组来自当前仓库。
  - 这说明当前客户端存在“旧 MCP 子进程未退出，新旧实例并存”的情况。
- **现场证据**：
  - `ps -Ao pid,lstart,command | grep '/iOSDriver/dist/index.js'`
  - `lsof -a -p <pid> -d cwd -Fn`
  - 输出显示：
    - 一组 iOSDriver 进程 cwd 为 `/Users/coo/Desktop/BOSC_EMOP/iOS_emop`
    - 一组 cwd 为 `/Users/coo`
    - 一组 cwd 为 `/Users/coo/Desktop/iOS_agent_debugger/iOSExploreServer`
- **与本问题的关系**：
  - 本地源码与 `dist/staticTools.js` 都已包含 `app_endpoint_unreachable`
  - 但端点不可达时，当前 `health_check` 返回体依然没有该字段
  - 最合理解释是：当前被调用的 MCP 实例仍是旧进程，没有加载最新构建产物
- **已落实的修复方向**：
  - 在 `iOSDriver/install/local-install-trae-work.md` 中明确补充：修改 `iOSDriver/src` 后，除了 `npm run build`，还必须在 MCP 管理页重启 `iOSDriver`
- **当前结论**：
  - 上述阻塞点在重启 MCP 实例后已被消除
  - `LOGIN-SKILL-002` 已在当前会话里完成真机验收

### 2026-07-22 真机验收补充（最终通过）

- **验收日期**：2026-07-22
- **验收方式**：
  - 在真机 App 被 `stop_app_device` 停止、端点真实不可达的情况下，直接调用 `mcp_iOSDriver.health_check`
  - 对比返回体是否出现增强诊断字段
- **现场结果**：
  - `health_check` 返回：
    - `ok: false`
    - `ping/help.error.code: connection_failed`
    - `connection.status: "app_endpoint_unreachable"`
    - `connection.probableCause`
    - `connection.nextSteps[]`
  - 说明增强诊断字段已经在当前运行实例里生效
- **当前结论**：
  - `LOGIN-SKILL-002` 已完成真实真机验收
  - 端点不可达时，当前 `health_check` 已能直接给出可执行恢复指引，不再只有裸 `connection_failed`

## LOGIN-SKILL-003 连接诊断信息分散，需要人工拼接结论

### 问题现象

本次为了确认连接问题的真实位置，先后查看了 `health_check`、`iproxy-manager.sh status` 和 `lsof -iTCP:38321`。每个工具都只提供局部信息，必须由操作者人工拼起来，才能判断：

- 本地端口是开的
- 监听者是 `iproxy`
- USB 设备在线
- 但设备侧 App 还没有提供 38321 服务

### 本次执行中的具体证据

- `health_check` 告诉我“HTTP 端点连不上”。
- `lsof` 告诉我“监听 38321 的进程是 `iproxy`，不是模拟器残留进程”。
- `iproxy-manager.sh status` 告诉我“USB 设备在线，但设备侧返回 `Connection refused`”。

### 影响

- 诊断效率依赖操作者对整条链路的熟悉程度。
- 一个新会话如果只跑了其中一项检查，就可能得出错误结论。
- 这会让“连接问题”看起来比实际更复杂。

### 为什么这是中优先级问题

- 它不会阻止熟悉系统的人继续推进，但会明显降低定位效率。
- 这个问题和 `LOGIN-SKILL-002` 不同：`002` 是错误结论不够直接，`003` 是诊断证据分散在多个入口，导致恢复路径过长。

### 本次临时绕过方式

- 手动串行执行多个检查命令，再由人来归纳结论。

### 建议修复方向

- 为 `ios-connection` 增加一条汇总结论，把端口占用、iproxy 状态、USB 状态、App 端口拒绝这几个维度在一次输出里讲清楚。
- 让输出直接回答“问题在 Mac 本地、USB 转发、还是设备上的 App”。

### 修复完成的验收标准

- 运行一次连接诊断后，就能得到单条最终结论和推荐下一步。
- 不需要额外再跑 `lsof` 才能确认是否是模拟器残留占用了端口。

### 2026-07-22 修复更新

- **修复日期**：2026-07-22
- **修复人**：Agent
- **修改文件**：
  - `.codex/skills/ios-connection/scripts/iproxy-manager.sh`
- **行为变化**：
  - `iproxy-manager.sh status` 现在在详细证据后追加“最终结论”块，直接区分：
    - 真机链路已打通
    - Mac 端口和 USB 正常，但设备侧拒绝连接
    - USB 设备不在线
    - 端口被非 `iproxy` 进程占用
    - launchd 已加载但未监听
  - 调用者不需要再手动把 `lsof`、USB 检测和 ping 结果拼成一句结论。
- **验证命令或自动化步骤**：
  - 运行 `bash -n .codex/skills/ios-connection/scripts/iproxy-manager.sh`
  - 运行 `.codex/skills/ios-connection/scripts/iproxy-manager.sh status`
  - 当前实测输出的最终结论是："Mac 本地端口和 USB 转发都在，但设备侧当前拒绝连接；最可能是目标 App 未启动，或 App 尚未监听 38321。"
- **是否仍有剩余限制**：
  - 这次汇总的是 `iproxy-manager.sh status` 一条本地诊断路径；如果调用方完全不运行脚本、只看 `health_check`，仍然需要依赖 `LOGIN-SKILL-002` 中补充的 iOSDriver 连接提示。

### 2026-07-22 真机验收补充

- **验收日期**：2026-07-22
- **验收方式**：
  - 真机链路保持在线时，先运行 `.codex/skills/ios-connection/scripts/iproxy-manager.sh status`
  - 再运行 `health_check`
  - 再分别运行：
    - `curl --noproxy '*' -sS -m 3 -X POST http://localhost:38321/ -H 'Content-Type: application/json' -d '{"action":"ping"}'`
    - `curl --noproxy '*' -sS -m 3 -X POST http://127.0.0.1:38321/ -H 'Content-Type: application/json' -d '{"action":"ping"}'`
- **新发现并已修复的问题**：
  - 当前终端环境带有 `HTTP_PROXY/HTTPS_PROXY=http://127.0.0.1:7897`，未显式绕过代理时，脚本里的 `curl localhost:38321` 会被代理到 `127.0.0.1:7897`，从而把本来已经打通的真机链路误报成失败。
  - 已在 `.codex/skills/ios-connection/scripts/iproxy-manager.sh` 的本地 ping 检查中补充 `curl --noproxy '*'` 和 `Content-Type: application/json`。
- **验收结果**：
  - 修复后再次运行 `iproxy-manager.sh status`，实测输出：
    - `✅ 服务正常响应 (ping 成功)`
    - 最终结论变为“USB 转发和设备侧 HTTP 服务都正常，当前真机链路已打通。”
  - 同时 `curl --noproxy '*'` 对 `localhost:38321` 和 `127.0.0.1:38321` 都返回 `{"code":"ok","data":{"pong":true}}`。
- **当前结论**：
  - `LOGIN-SKILL-003` 现在不只是能汇总结论，而且在存在终端代理环境时也能给出正确结论，不再因为本机代理把真机链路误判成失败。

## LOGIN-SKILL-004 登录场景缺少高层测试模板，成功判据仍需人工组装

### 问题现象

虽然本次严格遵守“不读源码”，依然通过 `ui_inspect` 发现了登录页和首页的稳定标识，但整个测试过程仍然依赖人工把这些底层能力组装成一个登录场景：

- 先识别用户名、密码和登录按钮
- 再输入文本
- 再点提交
- 再自己设计成功/失败等待条件
- 最后再用首页元素确认成功

### 本次执行中的具体证据

- 登录页识别出的关键元素包括：
  - `login_username_field`
  - `login_password_field`
  - `login_button`
- 成功页识别出的关键元素包括：
  - `home_welcome_label`
  - `home_username_label`
  - `home_email_label`
  - `home_logout_button`
- 这些发现都来自运行时 `ui.inspect`，不是来自源码。
- 但“哪些元素足以作为成功判据”仍然是我在现场人工判断出来的。

### 影响

- 本次能做成，不代表下一次任何人都能同样稳定地做成。
- 换一个页面结构稍复杂的 App，就可能出现：
  - 成功页没那么明显
  - 首页会延迟加载
  - 失败态是弹窗而不是文本
- 如果没有高层模板，每次都要重新拼场景，效率和稳定性都会下降。

### 为什么这是中优先级问题

- 它不影响底层工具可用性，但影响“用 skills 做业务验证”是否真正高效。
- 这类问题会在更多业务流里重复出现，不仅是登录。

### 本次临时绕过方式

- 现场根据运行时 UI 树人工选取成功判据：
  - 登录按钮消失
  - 导航标题变为“首页”
  - 出现“欢迎回来！”
  - 展示用户名 `test`

### 建议修复方向

- 为登录、注册、提交表单、退出登录这类高频流程沉淀可复用的测试模板或意图清单格式。
- 让模板天然支持：
  - 成功页元素
  - 失败文案
  - 弹窗分支
  - 中间 loading

### 修复完成的验收标准

- 下次做类似登录验证时，不需要重新从零设计等待条件和成功判据。
- 在不读源码的前提下，也能快速生成一份清晰、可执行的测试步骤和断言集合。

### 2026-07-22 修复更新

- **修复日期**：2026-07-22
- **修复人**：Agent
- **修改文件**：
  - `.codex/skills/ios-ui-form/references/form-examples.md`
- **行为变化**：
  - 新增“登录 / 认证模板”，把输入元素、成功判据、失败判据、loading 分支和确认弹窗分支整理成一份泛化骨架。
  - 后续做登录、注册、认证表单时，可以直接从模板替换 `<username>` / `<password>` / `<home-title>` / `<login-error-text>` 这类占位符，而不必从零拼 wait 条件。
- **验证命令或自动化步骤**：
  - grep `ios-ui-form/references/form-examples.md`，确认已经包含“登录 / 认证模板”“pass criteria / fail criteria”“confirm_alert”等字段。
  - grep 模板文件，确认没有引入当前工程路径、示例 App 标识、测试账号或真实业务文案。
- **是否仍有剩余限制**：
  - 这次补的是通用模板，不是可自动执行的 manifest 生成器；如果后续希望直接产出结构化登录意图清单，还可以继续把这套模板下沉到 `ios-test-intent` / `ios-test-runner`。

### 2026-07-22 真机验收补充

- **验收日期**：2026-07-22
- **验收方式**：
  - 真机登录页只依赖运行时 `ui.inspect` 发现字段和按钮
  - 先跑一次错误密码路径，再跑一次正确密码路径
  - 不使用源码提前知道失败态或成功态长什么样
- **首次模板化尝试暴露的问题**：
  - 我一开始把成功条件写成了 `textExists("欢迎")`
  - 结果它在登录页标题“欢迎登录”上就提前命中，造成**假成功**
- **基于真实运行时发现收窄后的有效判据**：
  - 成功判据：
    - `targetExists("home_username_label")`
    - `targetExists("home_logout_button")`
    - `textExists("首页")`
  - 失败判据：
    - `targetExists("login_error_label")`
    - `textExists("用户名或密码错误")`
- **实测结果**：
  - 错误密码路径停留在登录页，并出现：
    - `login_error_label`
    - 文案：`用户名或密码错误`
  - 正确密码路径命中：
    - `home_username_label`
    - 首页导航标题：`首页`
    - 退出按钮：`home_logout_button`
- **当前结论**：
  - `LOGIN-SKILL-004` 已完成真实真机验收。
  - 这次验收还证明了模板必须优先依赖稳定 identifier，而不能用过宽的文本片段做成功判据。

## LOGIN-SKILL-005 带确认弹窗的流程容易因等待条件不完整而误报超时

### 问题现象

本次退出登录时，我先点击了 `home_logout_button`，然后直接等待“回到登录页”。结果等待超时。继续查看才发现，并不是退出失败，而是中间先弹出了一个确认退出的 `UIAlertController`。

换句话说，这不是功能错误，而是测试等待条件建模不完整导致的误判。

### 本次执行中的具体证据

- 点击 `home_logout_button` 后，第一次 `wait_and_inspect` 没等到登录页，而是看到：
  - `alert.available: true`
  - 标题：`确认退出`
  - 消息：`确定要退出登录吗？`
  - 按钮：
    - `取消`
    - `退出`
- 随后使用 `ui_alert_respond(role:"destructive")` 点击“退出”，再等待一次，才成功回到登录页。

### 影响

- 如果自动化脚本只把“最终页面出现”作为唯一等待条件，就会把包含确认弹窗的正常流程误判为失败或超时。
- 这类问题不只会发生在退出登录，也会发生在删除、重置、提交敏感操作等所有“先确认，再执行”的路径上。

### 为什么这是中优先级问题

- 它不会破坏功能，但会破坏自动化结论的准确性。
- 如果不修，后续在更多带弹窗流程里会反复出现假失败。

### 本次临时绕过方式

- 将流程拆成两段：
  - 先等待 alert 出现
  - 再响应 alert
  - 最后等待登录页重新出现

### 建议修复方向

- 为这类流程建立标准的多分支等待模式：
  - 先等“确认弹窗出现”或“直接跳页成功”
  - 如果先命中弹窗，则进入 alert 处理子流程
  - alert 处理完成后，再等待最终页面
- 在技能文档或测试模板中把这种模式写成默认推荐路径。

### 修复完成的验收标准

- 遇到确认弹窗时，自动化不会直接报超时，而会先识别“中间态为 alert”。
- 退出登录、删除确认等流程可以稳定跑通，不产生误报失败。

### 2026-07-22 修复更新

- **修复日期**：2026-07-22
- **修复人**：Agent
- **修改文件**：
  - `.codex/skills/ios-ui-wait/SKILL.md`
  - `.codex/skills/ios-ui-form/SKILL.md`
- **行为变化**：
  - `ios-ui-wait` 新增“带确认弹窗的两段式等待”模式，默认先等“确认 alert 或最终页”二选一；命中 alert 后再进入第二段等待。
  - `ios-ui-form` 把退出登录、删除、重置等危险操作明确归入“带确认框的异步提交”，不再推荐只等最终页面。
- **验证命令或自动化步骤**：
  - grep `ios-ui-wait` / `ios-ui-form`，确认正文已经包含“确认 alert 或最终页”“两段式等待”“命中 alert 后转 `ios-ui-alert`”等规则和示例。
  - 这些修改只落在通用 skill 正文，没有引入当前工程、示例 App 或测试账号信息。
- **是否仍有剩余限制**：
  - 这次修复的是通用等待建模和技能说明；如果未来要把这套模式进一步下沉成可直接消费的意图模板，还需要继续处理 `LOGIN-SKILL-004`。

### 2026-07-22 真机验收补充

- **验收日期**：2026-07-22
- **验收方式**：
  - 在真机已登录到首页的前提下，只依赖运行时 UI 和 skills：
    - `ui_inspect` 读取首页结构
    - `ui_tap_and_inspect(accessibilityIdentifier:"home_logout_button")`
    - `ui_alert_respond(role:"destructive")`
    - `wait_and_inspect` 等待登录页重新出现
  - 全程未阅读业务源码来分析退出登录流程。
- **运行时证据**：
  - 点击 `home_logout_button` 后，`ui_tap_and_inspect` 直接读到：
    - `alert.available: true`
    - 标题：`确认退出`
    - 消息：`确定要退出登录吗？`
    - 按钮：`取消` / `退出`
  - `ui_alert_respond(role:"destructive")` 返回：
    - `performed: true`
    - `dismissed: true`
    - `presentedAfterDismiss: false`
  - 随后 `wait_and_inspect` 命中 `back_to_login`，新的 UI 结构回到：
    - `navigationBar.title: 登录`
    - `topViewController: LoginViewController`
    - `login_button` 再次出现
- **日志分层结果**：
  - `explore/bridge` 增量日志证明 alert 路径和返回登录页路径执行完成。
  - `minimumLevel:"error"` 里出现的错误只对应一次已恢复的 `stale_locator`（旧 `viewSnapshotID` 过期），不对应业务失败。
- **当前结论**：
  - `LOGIN-SKILL-005` 已经完成真实真机验收：skills 现在能先识别中间 alert，再响应 alert，最后稳定回到最终页，不再把确认弹窗流程误报成超时或失败。

## LOGIN-SKILL-006 日志存在系统噪音，业务成功信号偏弱

### 问题现象

本次我在登录动作前后分别读取了增量日志。结果有两个明显现象：

- `explore` 日志能证明自动化命令链执行成功，但对业务本身的语义帮助有限，更多是在说“命令被路由和完成了”。
- `minimumLevel: error` 的日志里出现了两条 `oslog` 系统错误，但它们没有导致登录失败，也没有对应的 UI 异常。

### 本次执行中的具体证据

- 有用的 `explore` 日志主要是：
  - `ui.tap` 开始
  - `ui.tap` 完成
  - `router route success`
  - `http responded ... ok=true`
- `bridge` 增量日志在本次没有产出对登录业务判定特别有帮助的信息。
- `oslog error` 读到了两条系统消息，核心内容包括：
  - `Invalidation handler invoked, clearing connection`
  - `com.apple.mobile.usermanagerd.xpc was invalidated`
- 与此同时，UI 终态明确显示登录成功：首页标题是“首页”，欢迎文案和用户信息都正确。

### 影响

- 如果将“日志里出现 error”直接等价于“被测功能失败”，就会产生误报。
- 如果业务日志又不够清晰，自动化最终只能更多依赖 UI 终态来判断成功或失败。
- 这会让日志在复杂场景里的诊断价值下降。

### 为什么这是中优先级问题

- 它不会阻止流程执行，但会影响测试报告的可信度和可解释性。
- 后续一旦遇到真正的业务失败，系统噪音可能会淹没有价值的信号。

### 本次临时绕过方式

- 以 UI 终态作为主判据。
- 将 `oslog error` 仅记录为“需要关注的系统噪音”，而不是直接判成登录缺陷。

### 建议修复方向

- 在测试报告或日志读取层，把系统级噪音和业务错误分开归类。
- 如果业务侧能提供更明确的登录成功/失败日志，则优先读取这类信号，而不是只看自动化命令生命周期日志。
- 对 `bridge` 日志的定位也需要更清晰：它到底是用来证明桥接链路，还是用来证明业务动作。

### 修复完成的验收标准

- 自动化报告里能清楚区分：
  - 自动化命令成功
  - 业务功能成功
  - 系统噪音日志
- 日志中出现系统 `error` 时，不会默认把用例标成失败。

### 2026-07-22 修复更新

- **修复日期**：2026-07-22
- **修复人**：Agent
- **修改文件**：
  - `.codex/skills/ios-logs/SKILL.md`
- **行为变化**：
  - `ios-logs` 新增“三类信号必须分开判”，明确要求把：
    - 自动化命令成功（`explore`）
    - 业务功能成功 / 失败（`bridge` 或 UI 终态）
    - 系统噪音 / 环境错误（`oslog` / `nslog` / `stderr`）
    分成三层写入报告。
  - 新增“把系统 `error` 直接当业务失败”这一误判案例，明确当 `explore` 成功且 UI 终态成功时，默认结论应是“业务成功，伴随系统噪音”。
- **验证命令或自动化步骤**：
  - grep `ios-logs/SKILL.md`，确认已经出现“三类信号必须分开判”“业务成功,伴随系统噪音”“系统噪音 / 环境错误”等规则文本。
  - grep skill 正文，确认未引入当前工程、示例 App 或测试账号信息。
- **是否仍有剩余限制**：
  - 这次修的是日志判读规则和报告口径；如果后续想让日志读取结果自动输出三类标签，还需要继续改更上层的运行器或报告生成逻辑。

### 2026-07-22 真机验收补充

- **验收日期**：2026-07-22
- **验收方式**：
  - 真实读取两轮增量日志：
    - 错误密码登录
    - 正确密码登录
  - 每轮都分成两层读取：
    - `sources:["explore","bridge"]`
    - `minimumLevel:"error"`
- **错误密码路径结果**：
  - UI 终态：登录页出现 `login_error_label`，文案 `用户名或密码错误`
  - `minimumLevel:"error"` 读到的日志是明确业务失败：
    - `登录失败（密码错误）`
    - `登录失败: 用户名或密码错误`
    - `显示错误信息: 用户名或密码错误`
- **正确密码路径结果**：
  - UI 终态：进入首页，出现 `home_username_label` / `home_logout_button`
  - `minimumLevel:"error"` 仍然读到了系统级 `oslog` 错误：
    - `Invalidation handler invoked, clearing connection`
    - `com.apple.mobile.usermanagerd.xpc was invalidated`
  - 这些错误没有阻止业务成功
- **当前结论**：
  - `LOGIN-SKILL-006` 已完成真实真机验收。
  - 这次实测直接证明：日志里出现系统 `error` 时，不能默认把业务判成失败；必须用 UI 终态和自动化命令链分层判断。

## 建议修复顺序

建议按下面顺序开新窗口逐个处理：

1. `LOGIN-SKILL-001`：先补齐真机启动能力，否则每次真机回归都可能卡在入口。
2. `LOGIN-SKILL-002`：改善首次失败后的可恢复性，减少重复排查成本。
3. `LOGIN-SKILL-003`：把连接诊断收敛成单条结论，降低排障门槛。
4. `LOGIN-SKILL-005`：修复带确认弹窗流程的等待模型，减少假失败。
5. `LOGIN-SKILL-004`：补高层登录模板，提高类似业务流的复用效率。
6. `LOGIN-SKILL-006`：整理日志信号质量，提升报告可解释性。

## 后续更新约定

每修完一个问题，建议在对应小节追加以下字段：

- 修复日期
- 修复人
- 修改文件
- 行为变化
- 验证命令或自动化步骤
- 是否仍有剩余限制
