# iOSDriver 文档

这里仅保留当前实现仍有参考价值的使用说明和设计决策。

## 使用

- [本地 MCP 端到端测试](./local-mcp-test.md)：启动条件、`mcp-inspector.mjs` 用法和常见排障。

## 行为约束

- [Navigation 命令使用注意事项](./navigation-commands-best-practices.md)：`ui.navigation.*` 的定位方式、返回值边界和调用建议。

## 设计与决策

- [Navigation 命令问题修复记录](./fix-navigation-issues-2026-07-12.md)：`tapBarButton` 定位参数调整及 `topAfter` 已知限制。
- [ui_tap_and_inspect 设计说明](./ui-tap-and-inspect-implementation.md)：复合工具的动机、输入输出和执行流程。

测试过程中的一次性报告、原始数据和临时分析不纳入版本文档；可重复验证请使用 `npm test` 和本地 MCP 测试指南。
