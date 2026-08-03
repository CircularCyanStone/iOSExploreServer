# 待办：将 `iosdriver init` 重命名为 `iosdriver config`

- **状态**：待办（用户确认后实施）
- **类型**：CLI 命令重命名（破坏性变更）
- **创建日期**：2026-08-03
- **提出人**：开发者（学习 iOSDriver 时发现命名歧义）

## 背景：为什么现在叫 `init`

`iosdriver init` 是项目早期确定的命令名，职责是"创建/补全本机配置文件
`~/.config/iosdriver/config.json`"。README、`docs/cli-reference.md`、`install/` 文档、
`mcp setup` 相关流程均使用该名字。历史原因沿用至今。

## 问题：为什么 `init` 这个名字有歧义

1. **语义冲突**：`init` 在工具生态里通常表示"初始化目标项目"（如 `.xcodebuildmcp` 的
   项目级配置、脚手架初始化），而 iOSDriver 的 `init` 实际只做"把 host 本机的连接配置
   （baseURL/超时）显式固化到文件"——是**本机配置写入**，不是**目标项目初始化**。
2. **与配置文件名不配套**：命令写的是 `config.json`，命令名却是 `init`，直觉上
   `config`/`configure` 与 `config.json` 更匹配。
3. **误导新读者**：初读代码/文档时容易以为 `init` 会初始化被测试的 App 项目（编译
   target/workspace 等），实际 iOSDriver 完全不管理目标项目（那属于 Xcode 工程与
   XcodeBuildMCP 的 `.xcodebuildmcp/config.yaml` 职责）。
4. **与同类 CLI 惯例不符**：`git config` / `aws configure` / `npm config set` 都是
   "显式写配置"类命令，命名上直接体现"配置"。

## 因果链

```
历史命名 init（职责：固化 host 连接配置）
  → 语义与"项目初始化"混淆（.xcodebuildmcp 的 init 概念、脚手架 init）
  → 新读者无法从命名推断真实职责
  → 与 config.json 不配套、与 CLI 惯例不符
  → 结论：重命名为 config（或 configure）更合理
  → 依据：AGENTS.md 硬规则 9「只保留合理设计」——不合理命名应收敛到当前最合理方案
```

## 影响面（全部引用点）

### 代码（iOSDriver/src）

| 文件 | 位置 | 内容 |
| --- | --- | --- |
| `src/adapters/cli/commands.ts` | 第 25 行 | `CLICommandName` 联合类型中的 `"init"` |
| `src/adapters/cli/commands.ts` | 第 92 行 | `switch` 的 `case "init"` |
| `src/adapters/cli/commands.ts` | runInit | 函数名（内部实现，可选改名 `runConfig`） |
| `src/adapters/cli/arguments.ts` | 第 62 行 | `knownCLICommand` 白名单 `"init"` |
| `src/adapters/cli/arguments.ts` | 第 69 行 | `parseCommandName` 白名单 `"init"` |

### 测试（iOSDriver/tests）

- `tests/adapters/cli/arguments.test.ts`（init 命令解析）
- `tests/adapters/cli/commands.test.ts`（runInit 行为）
- `tests/adapters/cli/main.test.ts`（如涉及 init 调用）

### 文档

| 文件 | 说明 |
| --- | --- |
| `iOSDriver/README.md` | 命令表、使用说明 |
| `iOSDriver/docs/cli-reference.md` | CLI 命令参考（完整参数/退出码/副作用说明） |
| `iOSDriver/docs/mcp-cli-design-discussion.md` | 设计讨论（按需更新） |
| `iOSDriver/install/README.md`、`local-install-claude.md`、`local-install-codex.md`、`local-install-trae-work.md` | 安装流程中的 `iosdriver init` 步骤 |
| `docs/cli/README.md` | CLI 相关文档 |
| `docs/architecture/index.md`、`docs/developers/architecture.md` | 架构说明中的命令描述 |
| `docs/skills/examples/contract-runtime.md` | 示例（如有 init 用法） |
| `docs/superpowers/`（plans/specs） | 历史设计，只查背景，**不改** |

## 改造方案（待确认）

**方案 A（推荐）：直接重命名**
- 命令名从 `init` 改为 `config`，`CLICommandName`/白名单/switch 同步更新
- 文档与测试同步
- 破坏性：已有脚本 `iosdriver init` 失效

**方案 B：重命名 + 兼容别名**
- 新命令 `config`，保留 `init` 作为隐藏别名（白名单同时接受，文档只写 `config`）
- 兼容旧脚本，但保留了两份命令名，与硬规则 9「不保留能用先这样的兼容分支」冲突

## 验证方式

1. `cd iOSDriver && npm run typecheck` — 类型全绿
2. `npx vitest run tests/adapters/cli/` — CLI 层测试全过（改名后测试同步更新）
3. `node dist/adapters/cli/main.js config --config /tmp/test-config.json` — 真实执行生成配置
4. `node dist/adapters/cli/main.js`（无参数）— usage 文案已更新
5. 文档检查：grep 确认无残留 `iosdriver init`
6. 如选方案 B：额外验证 `init` 别名行为与 `config` 一致
