# iOSDriver Claude CLI MCP Setup Design

## 状态

已获用户确认，进入实现前规格审阅。

## 目标

让 `iosdriver mcp setup claude` 按照与 Codex 相同的外层策略，调用 Claude Code
官方 MCP 管理命令注册 `iOSDriver`，而不是由 iOSDriver 直接改 Claude 配置文件。

注册的 stdio 启动合同为：

```text
claude mcp add --transport stdio --scope <scope> iOSDriver -- <node> <main.js> mcp [--config <absolute-path>]
```

实测 Claude Code `2.1.207` 会把 `--` 后的所有参数原样保存。`mcp get` 也能显示完整的
command 和 args；测试使用临时 `CLAUDE_CONFIG_DIR`，不会改动用户现有配置。

## Scope

Claude 支持三种 scope：

- `local`：当前项目、当前用户私有配置；默认值。
- `user`：当前用户所有项目可用的私有配置。
- `project`：当前项目共享配置，通常写入项目 `.mcp.json`。

CLI 参数解析和注册输入的 `MCPRegistrationScope` 增加 `local`。Codex 仍只接受
`user`，TRAE 仍只接受 `project`。

## 运行流程

Claude 适配器使用注入的命令执行器，便于单元测试：

1. 执行 `claude mcp get iOSDriver` 检查当前注册。
2. 当前不存在时，`--dry-run` 返回 `planned/create`，否则执行 `claude mcp add`。
3. 当前启动命令与目标完全一致时返回 `unchanged`，不执行写操作。
4. 当前配置不同且未指定 `--force` 时返回冲突错误。
5. 当前配置不同且指定 `--force` 时，先执行 `claude mcp remove iOSDriver --scope <scope>`，
   再执行 `claude mcp add`；这是对 Claude 官方 CLI 不提供 force 的外层模拟。

Claude 官方 CLI 没有 `--force` 或 `--dry-run`，这两个选项属于 iOSDriver 的统一 setup
合同。Claude 的 force 更新由两个官方命令组成，因此不是单次原子操作；若 add 失败，适配器
必须返回明确错误，不得伪报成功。

## 命令构造

stdio 注册必须使用 `--` 分隔 Claude 自身选项和子进程参数：

```text
["mcp", "add", "--transport", "stdio", "--scope", scope,
 "iOSDriver", "--", launch.command, ...launch.args]
```

`launch.command` 和 `launch.args` 必须保持数组边界，不拼接 shell 字符串。`--config`、路径和
其他启动参数只能出现在分隔符之后。

## 幂等比较

Claude `mcp get` 当前只提供人类可读输出，没有 `--json`。适配器将解析固定的
`Command:` 与 `Args:` 行，并将它们规范化为 `{ command, args }` 后比较。无法解析、命令退出
异常或输出不符合预期时，setup 失败并报告诊断信息，不猜测当前配置。

## 结果与错误

成功结果沿用 `MCPClientSetupResult`，Claude 的 manager 标记为 `claude-cli`，保留 client、
scope、status、operation 和 launch 字段。Claude 官方命令非零退出时映射为
`MCPClientSetupError`，错误消息包含命令和截断后的 stderr/stdout 摘要，不回显敏感参数。

## 测试

新增或调整以下测试：

- `local`、`user`、`project` 三种 scope 的默认值和参数校验。
- `get` 无注册、相同注册、不同注册三条路径。
- `--dry-run` 不执行 add/remove。
- `--force` 按 remove 后 add 的顺序调用，并传播任一失败。
- `--` 后的 node、入口、`mcp`、`--config` 参数逐项透传。
- Claude CLI 非零退出、无法解析 get 输出时返回 setup 错误。

Codex、TRAE 和现有 JSON 文件测试保持原有语义，不因 Claude CLI 适配而改变。
