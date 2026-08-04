# MCP 启动流程与 Node 包机制知识点回顾

> 本文是个人学习回顾笔记，内容来自一次关于「iOSExploreServer 项目 MCP 服务启动流程」的
> 深入会话：Claude Code 项目级 MCP 配置、iOSDriver 启动链、npm/npx/全局安装的机制差异、
> Node 包内路径坐标系。所有命令均在 macOS + nvm 环境验证过。
>
> 事实源仍以 `contracts/`、`iOSDriver/src/` 和安装文档（`iOSDriver/install/`）为准；
> 本文是对它们背后原理的解释。

---

## 1. 项目 MCP 全貌

| 项目 | 说明 |
| --- | --- |
| iOSExploreServer | Debug-only 的 iOS App HTTP 自动化库。App 内 `ExploreServer` 监听 `POST /`，按 `action` 执行命令，返回统一 envelope |
| iOSDriver（host 侧） | Mac 上的 CLI + MCP adapter，同一合同调用 App |
| MCP server 名 | `iOSDriver`（本地构建产物）+ `XcodeBuildMCP`（npx 拉取） |

App 端点固定：`POST http://localhost:38321/`，请求体 `{"action":"ping", ...}`。

---

## 2. Claude Code 项目级 MCP 配置（`.mcp.json`）

### 2.1 配置位置

| scope | 文件位置 |
| --- | --- |
| project（默认） | `<项目根>/.mcp.json` |
| user | `~/.claude.json`（设置 `CLAUDE_CONFIG_DIR` 时在该目录下） |

### 2.2 配置形态

```json
{
  "mcpServers": {
    "iOSDriver": {
      "type": "stdio",
      "command": "/path/to/node",
      "args": ["/abs/path/dist/adapters/cli/main.js", "mcp", "--config", "/abs/path/config.json"]
    }
  }
}
```

- `command` + `args` 只服务于 **stdio transport**：客户端 spawn 本地进程，MCP JSON-RPC 帧走该进程的 stdin/stdout。
- 配置里没有 `command` 时是远程 transport（`http` / `sse` / `ssh`）。
- **纪律**：MCP stdio 进程的 stdout 被协议帧独占，所有日志必须写 stderr。

### 2.3 协议流程

```
initialize（握手）→ tools/list（静态目录，离线可用）→ tools/call（按工具分流执行）
```

- `tools/list` 返回**静态工具目录**（iOSDriver 是 28 个），不碰 App、不联网。
- `tools/call` 分流：
  - `deviceAction` → 直接 `runtime.invoke`（字段由 App 端 typed input factory 校验，host 不重复解释 schema）；
  - `hostOperation` → 先在 Mac 侧按 generated schema 校验，再分流：`health`/`capabilities` 走能力探针、`call_action` 走 runtime + 策略缓存、`wait_and_inspect`/`tap_and_inspect` 走 workflow runner（共享总 deadline）。

---

## 3. iOSDriver MCP 启动链（安装成功后）

### 3.1 一次性安装

```bash
cd <repo>/iOSDriver
npm install
npm run build        # clean → contracts:check → tsc → chmod 755
npm link             # 生成全局命令 iosdriver（符号链接指向仓库产物）
iosdriver init       # 生成 ~/.config/iosdriver/config.json
```

构建产物：`iOSDriver/dist/adapters/cli/main.js` —— **这就是 MCP server 的进程入口文件**。

### 3.2 注册到 Claude Code

```bash
# project scope（默认）：写入 <repo>/.mcp.json
iosdriver mcp setup claude --project-dir <repo>

# 全部项目共用：user scope，写入 ~/.claude.json
iosdriver mcp setup claude --scope user

# 先看计划不执行 / 强制覆盖已有不同配置
iosdriver mcp setup claude --project-dir <repo> --dry-run
iosdriver mcp setup claude --project-dir <repo> --force
```

setup 写出的注册内容（关键：**三条路径全部是绝对路径**）：

```json
{
  "type": "stdio",
  "command": "/Users/coo/.nvm/versions/node/v24.16.0/bin/node",
  "args": [
    "/Users/coo/Desktop/iOS_agent_debugger/iOSExploreServer/iOSDriver/dist/adapters/cli/main.js",
    "mcp",
    "--config",
    "/Users/coo/.config/iosdriver/config.json"
  ]
}
```

为什么全绝对路径：客户端（Claude Code）将来可能在**任意工作目录** spawn 这条命令，相对路径必然失败。

### 3.3 进程内调用链

```
node <main.js> mcp --config <config.json>
  → main.ts: isMainModule 判断自己是入口（realpathSync 解符号链接）→ main() → runCLI()
  → application.ts: parse argv → 读 --config（resolveCLIConfig）→ 组装
        DriverRuntime（HTTP transport → baseURL）/ CapabilityProbe / WorkflowRunner
  → commands.ts: executeCLICommand("mcp") → startMCPStdioServer(...)
  → mcp/server.ts: new Server(...) → server.connect(new StdioServerTransport())
  → connect 返回后进程不退出，生命周期由 transport 持有，等 stdin 上的 JSON-RPC 帧
```

### 3.4 更新与重启

```bash
cd <repo>/iOSDriver && npm run build   # 只换新产物
```

**已启动的 stdio 子进程不会热加载新 dist** —— 必须完全退出并重启 Claude Code。
重建后绝对路径没变，不需要重跑 `setup`。

---

## 4. `--config` 参数的作用

`--config` 指向 **iOSDriver 自身（Host 侧）配置文件** `~/.config/iosdriver/config.json`，
内容 = App 地址（`baseURL`）+ 请求超时（`requestTimeoutMs`）。与 `.mcp.json`（描述"怎么启动"）是两码事——这个文件描述"App 在哪"。

### 4.1 配置优先级（四层）

```
命令行（--base-url/--timeout/--config）> 环境变量（IOS_EXPLORE_*）> 配置文件 > 默认值
```

### 4.2 不传 `--config` 会怎样

1. 回落 `configPathFor(env)`：`IOSDRIVER_CONFIG` 环境变量 > `XDG_CONFIG_HOME` > `~/.config/iosdriver/config.json`；
2. 文件不存在（ENOENT）**不是错误**，视为空配置 `{}`；
3. 继续用内置默认：`baseURL=http://localhost:38321/`、`requestTimeoutMs=10000`。

所以模拟器/iproxy 的默认场景下，不传 `--config` 行为完全一样。

### 4.3 setup 为什么写死它

- 固化配置位置：GUI 启动的客户端可能剥离环境变量，绝对路径不受影响；
- 自定义配置传递：`iosdriver init --config /custom/path.json`（如局域网真机 IP）会原样写进启动命令；不写则 MCP server 回落默认路径，**baseURL 悄悄变回 localhost:38321**，App 连不上且从 MCP 侧很难排查；
- `--config` 同时决定 `init` 的写入位置，读写两侧同一份文件。

---

## 5. `command` 的配置方案大全（不限于本项目）

### 5.1 stdio 家族

| 方案 | 配置 | 效果 |
| --- | --- | --- |
| 1. 全路径直接 spawn | `"command": "/Users/coo/.nvm/.../bin/node"` | 不经 shell（免注入）；不依赖 PATH（GUI 客户端 PATH 很干净）；锁定 node 版本；换机器要改配置 |
| 2. 短名命令 | `"command": "node"` 或 `"iosdriver"`（npm i -g 后） | 可移植，但解析取决于 spawn 时 PATH：GUI 下可能只有 `/usr/bin/node`（老版本）或没有；nvm 多版本时版本不确定 |
| 3. 包管理器下载执行 | `"command": "npx", "args": ["-y", "pkg@latest", "mcp"]` | 零本地安装；冷启动可能联网；`@latest` 版本漂移不可复现；npx 自身也依赖 PATH |
| 4. shell 包装 | `"command": "bash", "args": ["-lc", "source ~/.zshrc && iosdriver mcp"]` | 能加载环境/管道/串联；恢复 shell 注入面；依赖 bash 在 PATH |
| 5. 容器 | `"command": "docker", "args": ["run", "--rm", "-i", "ghcr.io/xxx/mcp"]` | 宿主零依赖；每次冷启动；**必须 `-i` 保持 stdin** |

### 5.2 远程 transport（没有 command）

```json
{ "type": "http", "url": "https://example.com/mcp" }   // Streamable HTTP
{ "type": "sse",  "url": "https://example.com/sse" }   // 旧规范
{ "type": "ssh",  "host": "dev-box", "command": "iosdriver", "args": ["mcp"] }
```

效果：多客户端共享、跨机器、常驻独立服务（客户端断开不影响）；需自管服务端与鉴权。

### 5.3 选型权衡

1. 确定性：全路径 > 短名 > npx@latest（漂移）
2. 可移植性：短名/npx > 全路径
3. 安全面：spawn 直连最小（无 shell 解释）> bash -c（二次解释）
4. 生命周期：stdio 子进程随客户端生灭；http 常驻独立

---

## 6. npx vs 全局安装 vs npm link

### 6.1 查找机制差异

| 维度 | 全局安装 | npx |
| --- | --- | --- |
| 查找 | 无查找，bin 目录在 PATH 里直接命中 | ① 本地 `node_modules/.bin` → ② 全局 bin → ③ registry 下载到 `~/.npm/_npx/<随机hash>/node_modules/<pkg>/` |
| 包位置 | `$(npm prefix -g)/lib/node_modules/<pkg>/` | `~/.npm/_npx/<hash>/node_modules/<pkg>/` |
| 首次成本 | 安装时一次联网 | 每次冷启动解析 registry 元数据 |
| 版本 | 固定，显式升级 | `@latest` 随 registry 漂移；可 `pkg@1.2.3` 锁 |
| 多项目 | 全局一份 | 每次独立缓存目录 |

常用 flag：`npx --no-install`（不下载）、`npx --offline` / `--prefer-offline`、`npx --registry <url>`（私有源）。

### 6.2 npm link 是什么

`npm link` = 全局安装的变体：在全局 `bin/` 建符号链接指向**仓库产物**。
改仓库代码即时生效，不用重装；是 `iOSDriver/install/local-install-claude.md` 推荐的开发期方案。

### 6.3 全局安装目录结构（本机实测）

```
$ npm prefix -g
/Users/coo/.nvm/versions/node/v24.16.0        # 全局根 = 当前 nvm node 版本目录

$ npm root -g
/Users/coo/.nvm/versions/node/v24.16.0/lib/node_modules   # 包本体

~/.nvm/versions/node/v24.16.0/
├── bin/                      # 可执行入口（符号链接）
│   ├── node  npm  npx
│   └── iosdriver -> ../lib/node_modules/ios-explore-mcp-server/dist/adapters/cli/main.js
└── lib/node_modules/
    ├── ios-explore-mcp-server -> ~/Desktop/.../iOSDriver   # npm link：链接到仓库
    └── xcodebuildmcp/        # 真安装：真实目录
```

关键点：

- `npm prefix -g` 是"当前激活的 node 版本"的全局根，`nvm use <其他版本>` 后**跟着变**——每个 node 版本一套独立的全局目录；
- 终端能敲 `iosdriver`，是因为 PATH 里包含 `~/.nvm/versions/node/v24.16.0/bin`；
- **两层链接**：`bin/iosdriver` → `lib/node_modules/ios-explore-mcp-server`（npm link 再链到仓库）→ 仓库 `dist/adapters/cli/main.js`；
- 所以 `main.ts` 的 `isMainModule` 必须 `realpathSync` 解开链接再比较 `process.argv[1]` 与 `import.meta.url`，否则永远判定"不是入口"，CLI 不启动。

---

## 7. Node 包内路径的"三个坐标系"

判断一个路径在"安装后"变不变，先问它属于哪个坐标系：

| 坐标系 | 怎么取 | 安装后变不变 | 本项目使用点 |
| --- | --- | --- | --- |
| 模块位置 | `import.meta.url` / `__dirname` / 相对 import | **变**：本地=仓库路径；npm 安装=`node_modules/<pkg>/dist/...`；npx=`~/.npm/_npx/<hash>/node_modules/<pkg>/dist/...` | `server.ts` 的 `createRequire(import.meta.url)("../../../package.json")`、所有相对 import |
| 工作目录 | `process.cwd()` | **不变**：永远是 spawn 时的目录 | `application.ts` 默认 cwd、`call --data @file` 相对路径 |
| 用户目录/系统 | `os.homedir()`、`process.execPath`、env | **不变** | `config.ts` 的 `~/.config/iosdriver/config.json`、setup 写入的 node 全路径 |

结论：**只要代码里"依赖位置的路径"都按模块相对位置写（跟着包走），包内容完整，安装/缓存到任何位置都能跑。** 所以 setup 写绝对路径、配置放 `~/.config` 都是把关键状态放在"不变"的坐标系里。

### 7.1 本项目发布后能否跑（逐项核对）

| 项 | 结论 |
| --- | --- |
| `createRequire(import.meta.url)("../../../package.json")` | 包布局固定 `<包根>/package.json` + `<包根>/dist/adapters/cli/server.js`，上溯三级永远到包根 → 任何安装位置成立（刻意设计） |
| 相对 import（`../../generated/hostOperationSpecs.js` 等） | 包内文件整体搬迁，自洽 |
| `@modelcontextprotocol/sdk` | 在 `dependencies`，安装随包装上 → 可 import |
| `tsx`/`vitest`/`typescript` | 在 `devDependencies`，**安装时不装**；运行时不需要（只有构建期 `contracts:check` 用） |
| `files: ["dist", "README.md", "install"]` | 运行时只需要 `dist`（合同已编译进 `dist/generated/`）；`contracts/`、`Sources/` 不进包不影响运行 |
| `--config` 绝对路径 | 属于"不变"坐标系 → 任意 cwd 可读 |
| `realpathSync` 链接处理 | npx 缓存/全局安装下逻辑正常通过 |

---

## 8. 常用命令速查表

### 8.1 查看/排查类

```bash
npm prefix -g                          # 全局根目录（nvm 下 = 当前 node 版本目录）
npm root -g                            # 全局包安装目录
ls -la "$(npm prefix -g)/bin"          # 全局命令入口（看符号链接指向）
ls -la "$(npm root -g)/<pkg>"          # 看包本体是链接（npm link）还是真目录（npm i -g）
which -a iosdriver npx node            # PATH 解析结果
echo $PATH | tr ':' '\n'               # 查看 PATH
```

### 8.2 发布/打包类

```bash
npm pack --dry-run                     # 预览发布物清单（最该先做：确认 dist/generated 都在）
npm pack                               # 打出 tarball，如 ios-explore-mcp-server-1.0.0.tgz
npm install -g ./ios-explore-mcp-server-1.0.0.tgz   # 从 tarball 安装（模拟已发布）

# 模拟"已安装"验证路径自洽：
mkdir -p /tmp/play && cd /tmp/play
npm i <repo>/iOSDriver/ios-explore-mcp-server-1.0.0.tgz
node node_modules/ios-explore-mcp-server/dist/adapters/cli/main.js mcp   # 任意 cwd 下能启动即证明包内路径自洽
```

> 验证时注意：`--config` 必须绝对路径（或回落默认 `~/.config/iosdriver/config.json`），因为 cwd 已不是仓库。

### 8.3 npx 相关

```bash
npx -y <pkg> <cmd>                     # 下载到缓存后执行
npx -y <pkg>@1.2.3 <cmd>               # 锁版本
npx --no-install <pkg> <cmd>           # 不联网，本地没有就报错
npx --registry http://私有源:4873 <pkg> <cmd>   # 私有 registry
npx ./iOSDriver                       # 路径形式跑本地包
```

### 8.4 iOSDriver 验证类

```bash
node <repo>/iOSDriver/dist/adapters/cli/main.js mcp        # 手动试启 stdio server（会挂住，正常）
node <repo>/iOSDriver/dist/adapters/cli/main.js doctor     # host → App 连接体检
iosdriver doctor
curl -s -X POST http://localhost:38321/ -d '{"action":"ping"}'   # App 侧存活
# Claude Code 内：/mcp 看 iOSDriver 状态 → 调 health_check 验证全链路
```

---

## 9. 本仓库已知问题记录

1. **`.mcp.json` 漂移**：仓库根 `.mcp.json` 里 iOSDriver 配置为 `node ./iOSDriver/dist/index.js`
   —— 该文件不存在（dist 里没有 `index.js`，src 也没有 `index.ts`），且是**相对路径**。
   官方生成器产物是 `node <绝对路径>/dist/adapters/cli/main.js mcp --config <绝对路径>`。
   修正方式：`iosdriver mcp setup claude --project-dir <repo> --force`（或先 `--dry-run --force` 看计划）。
2. **GUI 启动的 Claude Code PATH 很干净**：短名命令（`node`/`npx`/`iosdriver`）可能 ENOENT；
   nvm 的 node 不在 `/usr/bin`。这是全绝对路径配置存在的根本原因。
3. **已启动的 stdio 子进程不热加载**：改 `iOSDriver/src` 后必须重启 Claude Code 才能让 MCP 用上新 dist。

---

## 10. 一句话总结

- MCP 启动 = 客户端按配置 spawn 一个 stdio 进程；`command` 写法决定确定性/可移植性/安全面，全路径最稳。
- 路径是否随安装变化取决于坐标系：模块位置随包走（npm 保证包内自洽），cwd/用户目录不随包走（所以绝对路径 + `~/.config`）。
- npx 是"探测 + 兜底下载"，全局安装是"装进 bin 目录靠 PATH 命中"，npm link 是"全局链接到仓库"——三者查找机制和包位置不同，对本项目 `main.ts` 的 realpathSync 逻辑各有含义。
