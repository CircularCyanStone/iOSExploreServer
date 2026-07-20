# ios-automation Skill 深度审计与优化方案

**日期**: 2026-07-20  
**审计对象**: `.claude/skills/ios-automation/SKILL.md` (289 行)  
**审计维度**: curl 违规、职责边界、复杂度、可测试性  

---

## 执行摘要

`ios-automation` 当前存在三个核心问题:

1. **违反 MCP 优先原则**: 正文多处指导 Agent 调用 `scripts/proxy.sh` bash 命令,与"所有 HTTP 请求应通过 MCP"的原则冲突
2. **职责膨胀**: 作为入口 skill 却承载了连接管理、设备同步、智能启动、诊断排查、错误判别等 5 类职责,单文件 289 行
3. **测试性差**: 大量流程描述("先 A 后 B 再 C")但缺少关键决策点的明确判据,Agent 难以独立执行

**建议**: 拆分出 `ios-connection` 专门处理连接管理与诊断,`ios-automation` 退回纯路由角色。

---

## 1. curl 与 Bash 命令违规分析

### 1.1 违规位置统计

| 行号 | 内容 | 违规类型 | 影响 |
|------|------|----------|------|
| 47, 59, 67 | 提及 `curl http://localhost:38321/` 作为判断标准 | 概念引用 | 低(仅作说明) |
| 89 | "不要尝试使用 curl 等底层命令替代" | 正确禁止 | ✅ 合规 |
| 230-232 | curl 示例代码块 | 开发者手动验证示例 | 中等 |
| 164 | Agent 调用 `scripts/proxy.sh --status` 诊断 | **Agent 指令违规** | **高** |
| 249 | Agent 通过 Bash 调用 `scripts/proxy.sh --status` | **Agent 指令违规** | **高** |
| 281 | "Agent 通过 MCP ... 开发者可使用 Bash" | 角色区分 | ✅ 合规 |

### 1.2 问题根源

**第 164、249 行明确指导 Agent 调用 bash 命令**:

```markdown
# 第 164 行
验证连接 — 多次 health_check 确认稳定,失败时自动诊断(scripts/proxy.sh --status)

# 第 249 行
- **Agent 处理**: 检查 App 是否已启动;真机场景确保 iproxy 已启动(通过 Bash 调用 scripts/proxy.sh --status)
```

这与第 89 行的"不要尝试使用 curl 等底层命令替代"自相矛盾。

### 1.3 修复方案

**短期(本次修复)**:
1. 删除所有 Agent 调用 bash 的指令(第 164、249 行)
2. 改为: Agent 只能调用 `health_check`,失败时**提示用户**手动执行 `scripts/proxy.sh --status`
3. 保留"开发者手动排查"小节的 curl/bash 示例(第 224-241 行),但明确标注"仅供开发者在终端使用"

**长期(MCP 能力补齐)**:
- 在 iOSDriver MCP 中新增 `diagnose_connection` 工具,封装 `scripts/proxy.sh --status` 的诊断逻辑
- 新增 `manage_iproxy` 工具,封装 `--start` / `--stop` / `--restart`

---

## 2. 职责边界与复杂度分析

### 2.1 当前职责清单(5 类)

| 职责 | 行数占比 | 关键小节 | 问题 |
|------|----------|----------|------|
| **1. MCP 依赖检测** | 52 行(18%) | §5–§6 | 启动流程、配置提示、工具加载机制 |
| **2. 连接管理** | 68 行(24%) | §7–§8 | 模拟器/真机差异、iproxy 启动、四个关键差异 |
| **3. 任务路由** | 18 行(6%) | §9 | 路由表(正常) |
| **4. 快速诊断** | 42 行(15%) | §10 | 三段式诊断流程 |
| **5. 错误判别** | 38 行(13%) | §11 | 5 种常见错误 + Agent/开发者处理 |
| 其他(frontmatter、目标、关键参数) | 71 行(24%) | §1–§4、§12–§13 | — |

### 2.2 复杂度热点

**最复杂的三个小节**:

1. **§7.3 真机测试标准流程**(第 157-167 行):
   - 4 步自动化流程(启动 iproxy、同步设备、智能启动、验证连接)
   - 每步都有条件分支(多设备选择、启动失败类型、验证重试)
   - Agent 需要理解"什么时候调哪个工具、失败了怎么办"

2. **§8 四个关键差异**(第 169-174 行):
   - 设备 ID 两套体系、iOS 版本判定、env 注入、端口占用
   - 每条都是"曾经踩过的坑",但对 Agent 来说是隐式约束
   - Agent 在执行时需要记住这些前置条件

3. **§11 常见错误与判别**(第 243-270 行):
   - 5 种错误,每种 4 字段(现象/原因/Agent 处理/开发者修复)
   - "Agent 处理"字段混合了 MCP 调用、bash 命令、用户提示,语义不统一

### 2.3 为什么复杂度高?

入口 skill 的职责应该是**路由**(判断去哪个子 skill)和**前置检查**(MCP 可用性),但 `ios-automation` 还承载了:

- **环境管理**(iproxy 的生命周期)
- **设备管理**(多设备选择、设备 ID 同步)
- **智能修复**(启动失败时的自动重试与提示)
- **深度诊断**(端口冲突、进程残留、日志读取)

这些本应是独立的 `ios-connection` 或 `ios-device-manager` skill 的职责。

---

## 3. 拆分方案

### 3.1 设计原则

1. **单一职责**: 每个 skill 只解决一类问题
2. **可测试性**: 每个决策点都有明确输入输出
3. **渐进增强**: 入口 skill 提供 80% 场景的快速路径,复杂场景路由给专项 skill

### 3.2 推荐拆分: 1 入口 + 1 连接 skill

| Skill | 职责 | 行数估算 | allowed-tools |
|-------|------|----------|---------------|
| **`ios-automation`**(重构后) | 1. MCP 可用性检测<br>2. 简单连接验证(health_check)<br>3. 任务路由表<br>4. L0/L1 选择规则 | 120–150 | `health_check`、`ui_inspect`(快速诊断)、`app_logs_read`(快速诊断) |
| **`ios-connection`**(新建) | 1. 模拟器/真机连接管理<br>2. iproxy 生命周期管理<br>3. 设备同步与多设备选择<br>4. 深度诊断(端口冲突、进程残留)<br>5. 常见错误判别与修复建议 | 180–200 | `list_devices`、`launch_app_device`、`launch_app_sim`、`stop_app_*`、`health_check`、`ui_inspect` |

### 3.3 调用关系

```
用户请求
   ↓
ios-automation (入口)
   ├─ health_check 成功 → 直接路由到 ios-ui-* / ios-logs
   ├─ health_check 失败 → 路由到 ios-connection 处理连接问题
   └─ 用户明确说"连不上"/"iproxy"/"端口" → 路由到 ios-connection
```

### 3.4 重构后的 ios-automation 结构(精简版)

```markdown
---
name: ios-automation
description: iOS App 自动化操作统一入口(开发调试 + 自动化测试)。当用户说"查看 iOS App"、"测试"、"检查登录页面"、"截图看看布局"时使用。处理 MCP 检测、快速连接验证、任务路由。连接问题路由到 ios-connection。
allowed-tools:
  - mcp__iOSDriver__health_check
  - mcp__iOSDriver__ui_inspect
  - mcp__iOSDriver__ui_tap_and_inspect
  - mcp__iOSDriver__app_logs_read
  - mcp__XcodeBuildMCP__list_devices
---

# iOS 自动化操作统一入口(L1)

## 目标
回答三个问题:
- MCP 可用吗?(不可用给配置提示)
- App 能连上吗?(能连直接路由,连不上走 ios-connection)
- 该用哪个子 skill?(路由表)

## 何时使用
- ✅ 开发调试、自动化测试入口
- ✅ 用户要操作 App 但不确定从哪开始
- ❌ 连接问题、iproxy 管理 → 路由到 ios-connection

## MCP 依赖检测
(保留第 71–136 行,精简到 50 行)

## 快速连接验证
1. 调用 health_check
2. 成功 → 继续路由
3. 失败 → 路由到 ios-connection 处理

## L0 vs L1 选择规则
(保留第 57–69 行)

## 路由到子 skill
(保留第 176–199 行的路由表)

## 相关 skill
- ios-connection — 连接管理、iproxy、诊断
- ios-ui-* — 具体 UI 操作
- ios-logs — 进程日志
```

**关键简化**:
- 删除"真机测试标准流程"(移到 ios-connection)
- 删除"四个关键差异"(移到 ios-connection)
- 删除"常见错误与判别"(移到 ios-connection)
- 保留最简单的 health_check 验证

### 3.5 新建 ios-connection 结构

```markdown
---
name: ios-connection
description: iOS App 连接管理与诊断。当用户说"连不上 App"、"iproxy"、"端口 38321"、"真机测试连接"、"Address already in use"时使用。处理模拟器/真机连接差异、iproxy 管理、设备同步、端口冲突诊断。
allowed-tools:
  - mcp__iOSDriver__health_check
  - mcp__iOSDriver__ui_inspect
  - mcp__XcodeBuildMCP__list_devices
  - mcp__XcodeBuildMCP__launch_app_device
  - mcp__XcodeBuildMCP__launch_app_sim
  - mcp__XcodeBuildMCP__stop_app_device
  - mcp__XcodeBuildMCP__stop_app_sim
---

# iOS App 连接管理与诊断

## 目标
解决"怎么连上 App"与"连不上怎么办"两个问题。

## 何时使用
- ✅ health_check 失败
- ✅ 用户说"连不上"/"iproxy"/"端口"
- ❌ App 已连上,做 UI 操作 → 回到 ios-automation 路由

## 模拟器连接
(第 145–152 行内容)

## 真机连接
(移入第 154–167 行"真机测试标准流程")
(移入第 169–174 行"四个关键差异")

## 诊断流程
(移入第 200–222 行"快速诊断")
(移入第 243–270 行"常见错误与判别")

## 开发者手动排查
(保留第 224–241 行的 curl/bash 示例,明确标注"仅供终端使用")
```

---

## 4. 可测试性分析

### 4.1 当前问题

**流程描述多,判据不足**。例如第 160 行:

> 1. **启动 iproxy** — 检查安装状态、启动服务、清理端口冲突

Agent 读到后不知道:
- "检查安装状态"是调哪个工具?返回什么结果算"已安装"?
- "清理端口冲突"是自动清理还是提示用户?
- 失败了下一步是什么?

### 4.2 改进方向

**将每个流程步骤改写为"条件 → 工具调用 → 判据 → 动作"格式**:

**改写前**(第 161 行):
> 2. **同步设备配置** — 调用 list_devices 获取已连接设备,自动更新 deviceId 到 session defaults。多设备时提示用户选择。

**改写后**:
```markdown
2. **同步设备配置**
   - 调用: list_devices
   - 判据: devices.length === 1 → 自动选择
           devices.length > 1 → 提示用户:"检测到 N 台设备,请选择:[列表]"
           devices.length === 0 → 错误:"未检测到 USB 设备,请检查连接"
   - 动作: 记住 deviceId,传给后续 launch_app_device
```

这样 Agent 能直接执行,也方便写 eval 测试。

### 4.3 测试用例设计

每个小节都应有 2-3 个 eval:

| 小节 | eval 场景 | 预期输出 |
|------|-----------|----------|
| 快速连接验证 | App 已运行 | 返回"连接成功",路由到 ios-ui-nav |
| 快速连接验证 | App 未运行 | 路由到 ios-connection |
| 任务路由 | 用户说"填写表单" | 路由到 ios-ui-form |
| MCP 检测 | iOSDriver 未配置 | 返回配置步骤,不继续执行 |

---

## 5. 推荐执行计划

### Phase 1: 修复 curl 违规(本周,1-2 小时)

**优先级**: 🔴 高(违反明确规则)

1. 删除第 164、249 行的 Agent bash 调用指令
2. 改为"health_check 失败时,告知用户在终端执行 `scripts/proxy.sh --status`"
3. 在第 89 行补充:"Agent 不应调用任何 bash 脚本,包括 scripts/proxy.sh"
4. 保留第 224-241 行的开发者示例,但在 §10 标题改为"**开发者**手动排查(Agent 禁用)"
5. 提交 commit:"fix(ios-automation): 移除 Agent bash 调用,遵循 MCP 优先原则"

### Phase 2: 拆分 ios-connection(下周,4-6 小时)

**优先级**: 🟡 中(改善可维护性,非紧急)

1. **新建** `ios-connection/SKILL.md`,移入:
   - §7.3 真机测试标准流程(157-167 行)
   - §8 四个关键差异(169-174 行)
   - §10 快速诊断(200-222 行)
   - §11 常见错误与判别(243-270 行)

2. **重写** `ios-automation/SKILL.md`:
   - 保留 §5 MCP 依赖检测(精简到 50 行)
   - 保留 §4 L0/L1 选择规则
   - 保留 §9 路由表
   - §7 改为"快速连接验证"(仅 health_check,失败路由到 ios-connection)
   - 删除所有诊断流程

3. **更新** `inventory.md`,新增一行:
   ```
   | ios-connection | L1 入口 | iOSDriver + XcodeBuildMCP | health_check / list_devices / launch_app_* | healthy | active | 连接管理与诊断;从 ios-automation 拆分 |
   ```

4. **写 evals**(各 3 个测试用例):
   - ios-automation: MCP 检测、快速验证、路由
   - ios-connection: 真机连接、端口冲突、多设备选择

5. 提交:"refactor(skills): 拆分 ios-connection,简化 ios-automation"

### Phase 3: 补强可测试性(未来迭代,按需)

**优先级**: 🟢 低(质量改进)

1. 将 ios-connection 的流程描述改写为"条件 → 工具 → 判据 → 动作"格式
2. 每个决策点补充 inline 示例
3. 扩充 evals 到每个小节覆盖

---

## 6. 风险与替代方案

### 6.1 不拆分的风险

- **维护成本高**: 每次改连接逻辑都要改 289 行文件,改错的概率大
- **认知负担重**: Agent 每次触发 ios-automation 都要加载全部连接管理逻辑,即使只是做简单路由
- **测试困难**: 无法独立测试"连接管理"能力

### 6.2 替代方案: 不拆分,只做内部重组

如果不想新建 skill,可在 ios-automation 内部用 Markdown 注释明确分区:

```markdown
<!-- ========== SECTION A: 入口与路由(Agent 必读) ========== -->
## MCP 检测
## 快速验证
## 路由表

<!-- ========== SECTION B: 连接管理(仅连接问题时读) ========== -->
## 真机连接
## 诊断流程
## 常见错误
```

然后在 description 里加:"连接问题时,重点阅读 SECTION B"。

**优点**: 不改 skill 数量,风险小  
**缺点**: 不解决认知负担问题,Agent 仍需加载全文

### 6.3 我的建议

**Phase 1 立即执行**(修复 curl 违规),**Phase 2 观察 1-2 周后决定**:

- 如果发现 Agent 经常在连接诊断上卡住 → 执行拆分
- 如果 ios-automation 使用平稳 → 暂缓拆分,用 SECTION 注释重组

---

## 7. 附录: 具体改动 diff

### 7.1 Phase 1: 删除 bash 调用(第 164、249 行)

**第 164 行改动**:

```diff
  3. **智能启动 App** — health_check 检测 App 是否运行,未运行则调用 launch_app_device。启动失败时根据错误类型给出明确提示(未安装/证书未信任/其他错误)。
- 4. **验证连接** — 多次 health_check 确认稳定,失败时自动诊断(scripts/proxy.sh --status)。
+ 4. **验证连接** — 多次 health_check 确认稳定,失败时提示用户在终端执行 `scripts/proxy.sh --status` 诊断。
```

**第 249 行改动**:

```diff
  ### 连接失败(Failed to connect to localhost port 38321)
  
  - **现象**: health_check 失败,无法连接到 App
  - **原因**: App 未启动、App 起了但 server.start() 没调、或 38321 未监听
- - **Agent 处理**: 检查 App 是否已启动;真机场景确保 iproxy 已启动(通过 Bash 调用 scripts/proxy.sh --status)
+ - **Agent 处理**: 检查 App 是否已启动;真机场景提示用户在终端执行 `scripts/proxy.sh --status` 检查 iproxy 状态
  - **开发者手动排查**: scripts/proxy.sh --status 检查端口和服务状态
```

**第 89 行补充**:

```diff
  ### MCP 服务不可用时的配置提示
  
- 当检测到 MCP 服务不可用时,Agent 必须立即停止执行并提供以下配置指引,不要尝试使用 curl 等底层命令替代:
+ 当检测到 MCP 服务不可用时,Agent 必须立即停止执行并提供以下配置指引,不要尝试使用 curl 等底层命令或 bash 脚本(包括 scripts/proxy.sh)替代:
```

**第 224 行标题改动**:

```diff
- ### 开发者手动排查(Bash 命令)
+ ### 开发者手动排查(仅供终端使用,Agent 禁用)
  
- 以下命令供开发者在终端手动验证连接和排查问题,**Agent 不应使用这些 Bash 命令,而应使用上述 MCP 工具**。
+ 以下命令**仅供开发者在终端手动使用**,Agent 禁止调用任何 bash 命令或脚本。Agent 只能使用 MCP 工具,连接失败时应提示用户手动执行这些命令。
```

---

## 8. 结论

`ios-automation` 需要立即修复 curl 违规(Phase 1),建议 1-2 周后评估是否拆分 ios-connection(Phase 2)。

**立即行动项**:
1. ✅ 删除第 164、249 行的 Agent bash 调用
2. ✅ 补充第 89 行的"禁用 bash 脚本"说明
3. ✅ 标注第 224 行为"开发者专用,Agent 禁用"
4. ⏳ 观察 1-2 周,决定是否执行 Phase 2 拆分

**不拆分的条件**: ios-automation 使用平稳,Agent 很少在连接诊断上卡住  
**拆分的条件**: Agent 频繁在连接诊断上卡住,或开发者反馈 skill 太长难维护
