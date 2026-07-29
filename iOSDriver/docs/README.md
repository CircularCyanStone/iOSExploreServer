# iOSDriver 文档

这里保留当前实现仍需要维护的 CLI/MCP 使用说明和设计决策。开发者安装入口在 `../install/`，action 字段和错误以仓库根 `docs/generated/contracts.md` 为准。

## 使用

- [local-mcp-test.md](./local-mcp-test.md)：不安装到任何 MCP 客户端，直接用仓库脚本做端到端 MCP smoke。

## 行为约束

- [navigation-commands-best-practices.md](./navigation-commands-best-practices.md)：`ui.navigation.*` 的定位方式、返回值边界和调用建议。

## 设计与决策

- [mcp-cli-design-discussion.md](./mcp-cli-design-discussion.md)：CLI、MCP stdio 入口与客户端 setup 的最终设计。
- [ui-tap-and-inspect-implementation.md](./ui-tap-and-inspect-implementation.md)：复合工具的输入输出和执行流程。

一次性报告、旧迁移清单和本机路径不进入这里。可重复验证请使用 `npm test`、`npm run contracts:check` 和 `scripts/mcp-inspector.mjs`。
