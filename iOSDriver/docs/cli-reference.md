# iOSDriver CLI 命令参考

本文说明 `iosdriver` 每条命令的目的、执行过程、输出、文件副作用和退出状态。App action
的字段、默认值、错误码以 [生成合同](../../docs/generated/contracts.md) 为准，本文不复制合同字段表。

## 运行入口

安装或执行 `npm link` 后使用：

```bash
iosdriver <command> [options]
```

在当前仓库开发时，先构建再直接运行产物：

```bash
cd iOSDriver
npm install
npm run build
node dist/adapters/cli/main.js <command> [options]
```

Node.js 要求 20 或更高版本。`doctor` 会显式报告版本是否支持；npm 安装也会读取
`package.json` 中的 `engines.node`。

当前 CLI 没有独立的 `--help` 或 `--version` 命令。缺少命令或传入未知命令时，会把单行
用法写到 stderr 并返回退出码 2。`call` 的 action 必须紧跟在 `call` 后面，随后再写 flags。

## 命令总览

| 命令 | 目的 | 是否连接 App | 是否修改文件 |
| --- | --- | --- | --- |
| `iosdriver init` | 创建缺失的本机 App 连接配置 | 否 | 可能写 iOSDriver 配置文件 |
| `iosdriver doctor` | 检查 endpoint、基础 action、模块注册和合同兼容性 | 是 | 否 |
| `iosdriver call <action>` | 从终端或脚本调用一个 App action | 是 | 仅显式 `--output` 时写 artifact |
| `iosdriver mcp` | 启动供 MCP 客户端使用的 stdio server | App 调用工具时连接 | 否 |
| `iosdriver mcp setup <client>` | 把 stdio 启动命令注册到 MCP 客户端 | 否 | 可能修改客户端配置 |

## 通用 App 配置参数

`init`、`doctor`、`call` 和 `mcp` 接受以下参数：

| 参数 | 作用 |
| --- | --- |
| `--base-url <url>` | 覆盖本次进程访问的 App HTTP endpoint，只接受 `http` 或 `https` |
| `--timeout <ms>` | 覆盖普通 transport 请求超时，必须为正整数 |
| `--config <path>` | 改用指定配置文件；相对路径以当前工作目录为基准 |
| `--human` | 让 `doctor` 输出两行摘要；其他命令接受但不使用该选项 |

有效值按以下顺序选择，左侧优先：

```text
CLI 参数 > 环境变量 > 配置文件 > 默认值
```

| 配置 | CLI | 环境变量 | 配置文件键 | 默认值 |
| --- | --- | --- | --- | --- |
| Endpoint | `--base-url` | `IOS_EXPLORE_BASE_URL` | `baseURL`，兼容读取 `baseUrl` | `http://localhost:38321/` |
| 请求超时 | `--timeout` | `IOS_EXPLORE_REQUEST_TIMEOUT_MS` | `requestTimeoutMs`，兼容读取 `request_timeout_ms` | `10000` ms |
| Token | 无 | `IOS_EXPLORE_AUTH_TOKEN` | `authToken`，兼容读取 `auth_token` | 不发送 |
| 文件路径 | `--config` | `IOSDRIVER_CONFIG` | 不适用 | 见下文 |

默认配置路径为 `$XDG_CONFIG_HOME/iosdriver/config.json`；未设置 `XDG_CONFIG_HOME` 时使用
`~/.config/iosdriver/config.json`。endpoint 会被规范化为带尾部 `/` 的 URL。

`authToken` 是预留 header。host 会将非空值作为 `X-Auth-Token` 发送，但当前 App 不校验，
因此它不能提供访问控制。

`--timeout` 是普通单次 transport 预算。合同标记为 `wait` 的 action 若在 data 中带
`timeoutMs`，runtime 会采用“配置预算”和“业务 timeout + 5000 ms”中的较大值，避免 App
刚结束业务等待就被 host 提前取消。

## `iosdriver init`

用途：首次使用时创建 App 连接配置，或为现有 JSON 对象补齐缺失的 canonical 字段。

```bash
iosdriver init
iosdriver init --base-url http://localhost:39000/ --timeout 15000
iosdriver init --config ./local/iosdriver.json
```

执行效果：

1. 读取目标配置；文件不存在时按空对象处理。
2. 按配置优先级解析 `baseURL` 和 `requestTimeoutMs`。
3. 保留现有字段和未知字段，只补写缺失的 canonical 字段。
4. 内容有变化时先写同目录临时文件，再原子 rename 到目标路径。
5. 内容无变化时不重写文件。

`init` 不连接 App、不启动 `iproxy`、不注册 MCP 客户端。已存在的 canonical `baseURL` 或
`requestTimeoutMs` 不会被命令行参数覆盖写回；需要永久修改时应编辑配置文件。环境变量
中的 `IOS_EXPLORE_AUTH_TOKEN` 只影响本次解析，不会写入磁盘。

stdout 示例：

```json
{
  "configPath": "/Users/me/.config/iosdriver/config.json",
  "configChanged": true
}
```

## `iosdriver doctor`

用途：在执行 UI 自动化前确认 host 能访问 App，并判断 App 当前注册能力是否与本地合同一致。

```bash
iosdriver doctor
iosdriver doctor --human
iosdriver doctor --base-url http://localhost:38321/ --timeout 15000
```

检查顺序：

1. 调用 `ping`，验证响应为成功 envelope 且包含 `pong: true`。
2. 调用 `help`，读取当前注册 action 及协议/合同元数据。
3. 将 help 中的 action 与本地 generated contracts 比较。
4. 分别计算 UIKit、Diagnostics 的 `registered`、`partial`、`not_registered` 或 `unknown`。
5. 比较 `protocolVersion`、`contractVersion` 和 `contractHash`。
6. 报告 Node 版本是否达到 20。

默认 stdout 是完整 JSON，主要字段包括 `node`、`config`、`endpoint`、`ping`、`help`、
`actions`、`modules`、`contractCompatibility` 和 `metadata`。`--human` 只输出 Node 状态及
endpoint/ping/help/contract 摘要，适合人工快速查看，不适合需要完整缺失 action 列表的脚本。

`doctor` 只做 HTTP 探测，不启动、停止或重启 App、模拟器、真机和 `iproxy`。

## `iosdriver call <action>`

用途：直接调用任意 App action，适合 shell 脚本、单步调试和验证新扩展 action。

```bash
iosdriver call ping
iosdriver call ui.inspect --data '{"mode":"minimal"}'
iosdriver call ui.inspect --data @inspect-input.json
iosdriver call ui.screenshot --output ./artifacts/current.png
```

专属参数：

| 参数 | 作用 |
| --- | --- |
| `--data <json>` | 传入内联 JSON 对象；省略时发送 `{}` |
| `--data @<path>` | 从 UTF-8 文件读取 JSON 对象；路径以当前工作目录为基准 |
| `--output <path>` | 将第一个 image artifact 写入指定文件；不会自动创建父目录 |

`--data` 的顶层必须是 JSON 对象，数组、标量和 `null` 会在发请求前以参数错误结束。CLI
不会在 Mac 侧复制每个 device action 的业务字段校验；具体字段仍由 App 的 typed input
factory 处理。文件内容和非法 JSON 原文不会回显到 stderr。

本地 generated contracts 已知的 action 直接使用合同中的幂等性和 timeout class。未知
action 会先执行一次 `ping/help` 能力探测：若 help 提供唯一且合法的策略，runtime 使用该
策略；否则仍会发送 action，但按保守规则不自动重试。

成功时 stdout 输出格式化 JSON。`ui.screenshot` 的 base64 不会出现在 JSON 中；runtime
验证 PNG 后将它转为 image artifact。指定 `--output` 时文件写入成功后，stdout 增加以下摘要：

```json
{
  "format": "png",
  "width": 1179,
  "height": 2556,
  "artifact": {
    "kind": "image",
    "mimeType": "image/png",
    "bytes": 245760,
    "path": "./artifacts/current.png"
  }
}
```

未指定 `--output` 时 CLI 不隐式落盘。指定 `--output` 但响应没有 image artifact 时，也不会
创建空文件。App 业务失败的稳定 JSON 写 stderr；stderr 同时包含结构化生命周期日志，不能
把整个通道当成单个 JSON 文档解析。`call` 期间按 Ctrl-C 会取消当前请求并返回 transport
失败退出码。

对于合同声明为 `readOnly` 或 `idempotent` 的 action，runtime 只会在尚未收到 HTTP 响应的
connect/reset 失败后自动重试一次。side-effecting、未知策略、timeout、主动取消以及已经
收到响应后的失败都不会自动重放。

## `iosdriver mcp`

用途：启动 MCP 客户端管理的 stdio server，并暴露静态工具目录。

```bash
iosdriver mcp
iosdriver mcp --config /absolute/path/to/config.json
```

该命令是长生命周期进程，通常由 Codex、Claude Code 或 TRAE 启动，不应在普通终端中期待
交互式提示。stdout 只允许 MCP 协议帧，结构化生命周期日志固定写 stderr。server 启动和
`tools/list` 不访问 App；客户端实际调用 health、action 或 workflow 时才会发 HTTP 请求。

工具目录由 generated contracts 和显式兼容映射构造，不从 App `help` 动态增删。这样 App
离线时客户端仍可发现工具；某模块未注册时，具体调用会返回 `unknown_action`。修改 `src/`
后必须重新 `npm run build` 并重启 MCP 客户端，已运行的 stdio 进程不会热加载 `dist/`。

## `iosdriver mcp setup <client>`

用途：将当前 Node 可执行文件、CLI 入口和 App 配置文件的绝对路径登记到 MCP 客户端。
setup 不连接 App，也不要求 App 已启动。

```bash
iosdriver mcp setup codex --dry-run
iosdriver mcp setup codex
iosdriver mcp setup claude --scope project --project-dir /path/to/project
iosdriver mcp setup trae --project-dir /path/to/project
```

支持的 client 和配置位置：

| client | 默认 scope | 支持 scope | 管理方式或文件位置 |
| --- | --- | --- | --- |
| `codex` | `user` | `user` | 调用 `codex mcp get/add` |
| `claude` | `project` | `project` | `<project-dir>/.mcp.json` |
| `claude` | 不适用 | `user` | `$CLAUDE_CONFIG_DIR/.claude.json` 或 `~/.claude.json` |
| `trae` | `project` | `project` | `<project-dir>/.trae/mcp.json` |

专属参数：

| 参数 | 作用 |
| --- | --- |
| `--scope user\|project` | 选择客户端支持的配置作用域 |
| `--project-dir <path>` | project scope 根目录，默认当前工作目录 |
| `--config <path>` | 注册后传给 `iosdriver mcp` 的 App 配置路径 |
| `--dry-run` | 只返回 create/update 计划，不运行注册命令、不写 JSON |
| `--force` | 允许替换同名但启动配置不同的 `iOSDriver` 注册 |

setup 保留客户端 JSON 中的未知顶层字段和其他 MCP server。相同配置重复执行返回
`unchanged`；同名配置不同且未给 `--force` 时返回错误。JSON 客户端使用临时文件加 rename
写入。`--config` 在注册内容中会转为绝对路径，因此客户端从其他工作目录启动时仍读取同一
App 配置。

stdout 是以下结构的 JSON：

```json
{
  "client": "claude",
  "scope": "project",
  "status": "created",
  "operation": "create",
  "registrationName": "iOSDriver",
  "manager": "json-file",
  "configPath": "/path/to/project/.mcp.json",
  "launch": {
    "command": "/absolute/path/to/node",
    "args": [
      "/absolute/path/to/main.js",
      "mcp",
      "--config",
      "/absolute/path/to/iosdriver/config.json"
    ]
  }
}
```

`status` 可能为 `created`、`updated`、`unchanged` 或 `planned`；对应 `operation` 为
`create`、`update` 或 `none`。Codex 由官方 CLI 管理，因此结果没有 `configPath`。

## 输出通道

| 内容 | 通道 |
| --- | --- |
| 成功 JSON、`doctor --human` 摘要 | stdout |
| App/runtime 失败 JSON | stderr |
| 参数和配置错误文本 | stderr |
| Host 结构化生命周期日志 | stderr |
| MCP 协议帧 | `mcp` 进程 stdout |

结构化日志不会记录完整 argv、`--data`、token、base64、请求/响应 payload 或未截断正文。
自动化脚本应优先使用退出码判断结果。成功命令的 stdout 可按命令约定解析；失败 stderr
混合了日志与错误投影，不应假设它是单个 JSON 文档。

## 退出码

| code | 含义 | 常见情况 |
| ---: | --- | --- |
| `0` | 成功 | action 成功、doctor 完全兼容、setup 完成或无需修改 |
| `1` | App/workflow/合同兼容失败 | App 业务错误、workflow 失败、合同不精确匹配 |
| `2` | 参数或本地配置错误 | 未知参数、非法 JSON、无效 URL/timeout、Node 版本过低、setup 冲突 |
| `3` | transport/HTTP/protocol/artifact 或未分类 host 失败 | App 不可达、请求超时、非法响应、截图解码/写文件失败 |

`doctor` 对兼容性的判定更严格：协议版本显式不匹配返回 3；合同 version/hash 不精确或缺少
本地 action 返回 1；只有 endpoint 可达、ping/help 有效且合同 `exact` 时返回 0。

## 推荐验证顺序

模拟器：

```bash
iosdriver init
iosdriver doctor
iosdriver call ping
```

真机先确认端口转发，再运行相同命令：

```bash
iproxy 38321 38321
lsof -iTCP:38321 -sTCP:LISTEN
iosdriver doctor
```

`doctor` 不可达时，先检查 Debug App 是否启动 ExploreServer。`doctor` 可达但 UIKit 或
Diagnostics 为 `not_registered/partial` 时，检查 App 是否显式调用对应模块注册方法。MCP
客户端注册成功但工具仍旧时，重新构建 iOSDriver 并重启客户端的 stdio 子进程。
