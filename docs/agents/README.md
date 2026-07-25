# Agent 文档

这个目录放 agent 工作时需要的路线和约束。项目硬规则仍以根 `AGENTS.md` 为入口；本目录只收纳可扩展的 agent 参考材料。

## 当前分工

- 根 `AGENTS.md`：所有 agent 必读的工程原则、验证策略、模块边界、沟通和完成汇报要求。
- `docs/architecture/`：实现架构、合同/runtime/adapter 边界和历史决策。
- `docs/runbooks/`：构建、测试、真机连接和端口排障。
- `docs/skills/`：可迁移 skill 的治理、示例和评估材料。
- `docs/superpowers/`：历史设计 spec 与阶段性计划，作为背景，不作为当前命令合同事实源。

## 与开发者文档的边界

开发者文档在 `docs/developers/`。Agent 不应把内部执行策略、历史踩坑、测试账号、本机路径或设备 ID 写入开发者入口；开发者文档也不应复制 agent 的工具调用顺序和技能治理规则。
