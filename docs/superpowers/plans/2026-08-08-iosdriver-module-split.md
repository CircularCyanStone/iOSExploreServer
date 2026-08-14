# iOSDriver 模块职责拆分实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** 将 iOSDriver/src 中混合类型、配置、入口和内部实现的文件按职责拆分，同时保持现有 CLI、runtime、MCP 和合同生成行为不变。

**Architecture:** 先拆出稳定的类型、常量和辅助函数模块，再让原有模块保留对外入口和兼容导出。CLI 入口函数置于入口文件前部；命令和配置实现按“入口编排、领域逻辑、基础设施边界”分层。生成产物不手改。

**Tech Stack:** TypeScript 5.6、Node.js、Vitest、npm scripts。

---

### Task 1: 拆分 CLI 配置模块

**Files:**
- Create: iOSDriver/src/adapters/cli/configTypes.ts
- Create: iOSDriver/src/adapters/cli/configFile.ts
- Create: iOSDriver/src/adapters/cli/configValues.ts
- Modify: iOSDriver/src/adapters/cli/config.ts
- Test: iOSDriver/tests/adapters/cli/config.test.ts

- [x] 将配置接口、错误类型和文件系统边界移到 configTypes.ts。
- [x] 将文件读取、默认文件系统和缺失文件判断移到 configFile.ts。
- [x] 将 URL、超时、token、JSON 对象转换辅助函数移到 configValues.ts。
- [x] 保留 config.ts 的公共导出，并将公共配置入口集中在顶部。
- [x] 运行 CLI 配置定向测试和类型检查。

### Task 2: 拆分 CLI 命令支持代码

**Files:**
- Create: iOSDriver/src/adapters/cli/commandTypes.ts
- Create: iOSDriver/src/adapters/cli/commandSupport.ts
- Modify: iOSDriver/src/adapters/cli/commands.ts
- Test: iOSDriver/tests/adapters/cli/commands.test.ts

- [x] 将命令名、调用参数、命令上下文和退出码移到 commandTypes.ts。
- [x] 将 parseData、错误退出码映射和输出日志辅助移到 commandSupport.ts。
- [x] 让 commands.ts 顶部只保留 executeCLICommand 入口，具体命令实现按命令分组放入内部区域。
- [x] 保持原文件公共导出兼容。
- [x] 运行命令定向测试和类型检查。

### Task 3: 拆分 CLI 应用编排模型

**Files:**
- Create: iOSDriver/src/adapters/cli/applicationTypes.ts
- Modify: iOSDriver/src/adapters/cli/application.ts
- Test: iOSDriver/tests/adapters/cli/main.test.ts

- [x] 将应用依赖接口移到 applicationTypes.ts。
- [x] 将 runCLI 提到应用文件公共入口区域，内部启动和操作命令编排函数集中在后部。
- [x] 保持 runCLI 的参数和退出码行为不变。
- [x] 运行 CLI 入口定向测试和类型检查。

### Task 4: 拆分合同生成器模型

**Files:**
- Create: iOSDriver/src/contracts/generator/modelSchema.ts
- Create: iOSDriver/src/contracts/generator/modelContracts.ts
- Create: iOSDriver/src/contracts/generator/modelBundle.ts
- Modify: iOSDriver/src/contracts/generator/model.ts
- Test: iOSDriver/tests/contracts/generator/generator.load.test.ts

- [x] 按 JSON Schema、合同实体、bundle 聚合三类移动类型。
- [x] 让 model.ts 仅作为兼容聚合导出文件。
- [x] 保持所有现有导入路径可用。
- [x] 运行合同生成器定向测试和合同漂移检查。

### Task 5: 拆分 MCP 客户端注册模块

**Files:**
- Create: iOSDriver/src/registration/mcpClientSetupTypes.ts
- Create: iOSDriver/src/registration/mcpClientSetupRuntime.ts
- Modify: iOSDriver/src/registration/mcpClientSetup.ts
- Test: iOSDriver/tests/registration/mcpClientSetup.test.ts

- [x] 将注册输入、结果、文件系统和命令执行边界移到 mcpClientSetupTypes.ts。
- [x] 让 mcpClientSetup.ts 只保留公共入口与兼容导出。
- [x] 将 Codex、JSON 文件注册和底层比较/写入实现移到 mcpClientSetupRuntime.ts。
- [x] 运行注册模块定向测试和类型检查。

### Task 6: 全量验证与结构检查

- [x] 运行 npm run typecheck。
- [x] 运行 npm test。
- [x] 运行 npm run contracts:check。
- [x] 检查入口文件的公共导出顺序和未使用导入，汇总未拆分的生成文件与剩余限制。
