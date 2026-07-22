---
name: ios-logs
description: 读取 iOS App 进程内日志(开发调试 + 自动化测试)实时监控、排查、断言 / app logs, stdout, stderr, nslog, oslog, debug, mark, read, monitoring, troubleshooting
---

# iOS App 进程内日志读取

基于 iOSDriver MCP Server(`mcp__iOSDriver__app_logs_*`),封装 App 内诊断扩展的两个命令,解决"命令已经发到 App 进程,里面到底发生了什么"这一调试问题。核心是两个真实 action:`app.logs.mark`(建立检查点 cursor)、`app.logs.read`(从 cursor 之后增量读取进程内捕获的日志,可按 source / level 过滤、可分页)。

这是 Debug-only 能力,只读 App 当前进程内存 store,不做持久化、不上传、不进 Release 上架产物。与 L0 构建/设备管理工具的系统级日志捕获互补:L0 抓整个模拟器/系统控制台,L1 的本 skill 抓 App 进程内按来源分类的精准日志,可按 source/level 过滤、可做断言。

## 目标

解决三类问题:

1. **"命令发出去了,App 里面到底执行了什么"**:`app.logs.mark` 记一个检查点,触发动作后 `app.logs.read` 只读这个检查点之后的新日志,精确定位本次动作产生的事件(不混历史噪音)。
2. **"我的 print / NSLog / os_log 到底有没有输出"**:按 source 过滤读对应通道,看是否真有写入;读不到时通过 `capture.state` 区分"没执行"、"配置没开"还是"系统不让读"。
3. **"命令链失败在哪一步"**:`explore` source 含自动化服务自身的生命周期日志(http / listener / router / command),能看到请求有没有进来、命令是否注册、执行是成功还是失败。

关键不是单条命令,而是:**先 mark 建 cursor → 触发动作 → read 按 source 增量读 → 读不到先看 `capture.state` 再下结论**,绝不能把 `unavailable` / `notCaptured` 误判成"代码没执行"。自动化测试默认不要一上来读取全部 source + debug;那会把系统 oslog、键盘、haptic 等噪音混入报告。

## 何时使用

### 开发调试场景
- ✅ 用户说"实时监控 App 日志"/"看看有没有报错"(开发期排查)
- ✅ 用户说"检查一下刚才的网络请求日志"(开发期验证)
- ✅ 用户说"确认我的 print / NSLog / os_log 有没有真的输出"(开发期调试)

### 自动化测试场景
- ✅ 用户要"看 App 里刚才执行了什么日志"(测试验证)
- ✅ 用户要"对 App 日志做断言"(如 L2 测试闭环里验证关键业务点是否打日志)
- ✅ 用户要"排查 HTTP 命令是否到达 App、命令执行成功还是失败"(读 `explore` source)

### 通用触发词
- ✅ 用户说 "日志" / "log" / "stdout" / "stderr" / "NSLog" / "os_log" / "print 有没有输出" / "进程内日志"

### 不适用场景
- ❌ 不要用于抓系统级或整个模拟器控制台日志(走 L0 构建/设备管理工具的系统级日志能力,本 skill 只读 App 当前进程)
- ❌ 不要用于读别的 App 或别的进程的日志(`OSLogStore` 与 fd 接管都只覆盖当前 App 进程)
- ❌ 不要用于线上 Release 日志收集(本 skill 是 Debug-only,Release 构建下 Diagnostics 整体 disabled)

## 工作原理

时序:**`app.logs.mark`(建 cursor)→ 触发被测动作 → `app.logs.read`(用 cursor 增量读)**。所有 read 必须带前一次 mark 或 read 返回的 `after` cursor,否则会读到历史全量(混入无关日志)。响应里同时返回 6 个 source 的 `capture` 状态快照,可作自检。

### 0. 低噪音读取策略

自动化测试和回归验证默认按这个顺序读,逐级扩大范围:

1. **动作前 mark**:在被测动作即将发生前建立 cursor。例如表单测试应在字段已填好、提交按钮已定位后 mark,再点击提交。
2. **先读 App/自动化相关日志**:`app.logs.read(after: cursor, sources:["explore","bridge"], limit:80, minimumLevel:"debug")`。这能确认 HTTP action 是否到达、命令是否成功、App 是否通过 bridge 写了业务日志,且噪音最低。
3. **再查错误级别**:`app.logs.read(after: cursor, minimumLevel:"error", limit:100)`。这一步用于发现 stderr/nslog/oslog 的错误,不要把无 subsystem 的系统 oslog 直接判成业务失败;先结合 UI 终态和 `explore` 命令链判断。
4. **最后才全量 debug**:只有排查 stdout/NSLog/os_log 捕获、分页、系统日志延迟或疑难问题时,才读取全部 source + `minimumLevel:"debug"`。若 `hasMore:true`,用 `nextCursor` 分页,不要把第一页截断当完整证据。

### 0.1 三类信号必须分开判

自动化报告里,至少要把下面三类信号分开写,不要因为看到了 `error` 就直接判用例失败:

| 信号类型 | 主要来源 | 说明 | 推荐用途 |
|---|---|---|---|
| 自动化命令成功 | `explore` | 证明 HTTP 请求进了 App、命令被路由、命令返回成功或失败 | 判断自动化链路有没有打通 |
| 业务功能成功 / 失败 | `bridge` 优先,其次 UI 终态 | 证明登录、保存、删除等业务动作本身成功或失败 | 判断被测功能结果 |
| 系统噪音 / 环境错误 | `oslog` / `nslog` / `stderr` | 可能来自系统服务、权限、XPC、底层框架,不一定对应当前业务失败 | 记录为风险或辅助诊断,不要直接替代业务结论 |

推荐判定顺序:

1. 先用 `explore` 确认自动化命令是否真的执行
2. 再用 `bridge` 或 UI 终态确认业务动作是否成功
3. 最后把 `minimumLevel:"error"` 读到的系统日志单独归类成"系统噪音 / 环境异常 / 待跟进"

如果 `explore` 成功、UI 终态成功,但 `oslog` 出现零散系统 `error`,默认结论应是"业务成功,伴随系统噪音",而不是"测试失败"

### 1. 建立检查点(`app.logs.mark`)

无入参。返回 `data.cursor`(含 `captureSessionID` 和 `id`)和 `data.capture`(6 个 source 当前状态快照)。把这个 cursor 保存好,后续 read 放到 `after` 字段,表示"只读这个 cursor 之后发生的日志"。

App 每次重启都会产生新的 `captureSessionID`;旧 cursor 不能跨重启使用,否则 read 会报 cursor 太旧或返回 `gap` 字段说明日志已被 ring buffer 覆盖。

### 2. 增量读取(`app.logs.read`)

关键参数:

| 参数 | 含义 | 注意 |
|---|---|---|
| `after` | 上一次 mark 或 read 返回的 cursor | 增量读取的起点;省略时返回当前可见最近 `limit` 条(非增量) |
| `limit` | 本次最多返回多少条 | 范围 1...500,默认 100 |
| `sources` | 来源过滤数组 | 如 `["stdout"]`、`["stderr","nslog"]`;省略 = 全部 6 类 |
| `minimumLevel` | 最低等级过滤 | 枚举 `debug` / `info` / `error` / `fault` / `unknown`;如 `error` 表示只看 error/fault |

返回字段:

| 字段 | 含义 |
|---|---|
| `entries` | 本次返回的日志数组,每条含 `source` / `level` / `category` / `message` / `timestamp` 等 |
| `nextCursor` | 下一次读取应传的 cursor(分页用) |
| `capturedThrough` | 本次读取时 store 已捕获到的最新位置 |
| `hasMore` | 是否还有更多日志可继续分页 |
| `gap` | 若 cursor 太旧、日志已被 ring buffer 覆盖,这里说明丢失范围 |
| `capture` | 6 个 source 当前是 `enabled` / `notCaptured` / `unavailable`(带 `reason`) |

### 3. 六个 source 的含义与默认开关

| source | 开发者平时怎么产生 | 默认 | 开启方式 | 读到后的典型用途 |
|---|---|---|---|---|
| `explore` | 自动化服务内部自己写的日志 | 开 | `captureExploreLogs`(默认 true) | 看 HTTP 请求有没有进来、命令有没有注册、执行成功还是失败 |
| `bridge` | 宿主 App 调桥接日志 API 主动写 | 开 | `enableBridge`(默认 true,最稳定) | App 关键业务点主动打日志,不依赖系统日志实现 |
| `stdout` | `print(...)` / `FileHandle.standardOutput.write(...)` | 关 | `captureStdout: true` | 看临时 print 是否真的执行 |
| `stderr` | `FileHandle.standardError.write(...)` / `fprintf(stderr,...)` | 关 | `captureStderr: true` | 看错误输出,level 固定 `error` |
| `nslog` | `NSLog(...)` | 关 | `captureNSLog: true` | 看老代码 / Objective-C / 第三方调试代码的 NSLog |
| `oslog` | `os_log(...)` 和 Swift `Logger` | 关 | `captureOSLog: true` | 看 Apple 系统日志 API 写出的日志,带 subsystem / category |

`explore` 和 `bridge` 是纯内存路径,不依赖系统日志实现,最稳定、最推荐;其余 4 类需要宿主 App 在 `registerDiagnosticsCommands(.init(...))` 显式打开对应 capture 开关,默认关闭(避免进程级接管 stdout/stderr 影响开发者原本观察控制台的方式)。

### 4. 来源 × 平台可用性矩阵(实测)

下表来自 2026-07-16 的实测(模拟器 6 source 全 enabled;真机待补)。**关键原则:不要按平台写死断言**,`oslog` / `nslog` 源码里没有"模拟器特殊分支",模拟器跑的是真实 iOS 内核,能否读取决于系统权限而非"模拟器一定不行"。以实际 `capture.state` 为准。

| source | 模拟器 capture.state | 模拟器可读 | 真机 capture.state | 真机可读 |
|---|---|---|---|---|
| `explore` | enabled | 是(自动化服务自身生命周期日志:http / listener / router / command) | 待补 | 待补 |
| `bridge` | enabled | 是(宿主 App 经 `UIKitCommandLogging` 上报的桥接事件) | 待补 | 待补 |
| `stdout` | enabled | 是(`print` 写入,category=`stdio`,level=`info`) | 待补 | 待补 |
| `stderr` | enabled | 是(level 固定 `error`) | 待补 | 待补 |
| `nslog` | enabled | 是(完整 NSLog 行,带时间戳与 PID) | 取决于系统是否允许读 OSLogStore / 是否落到 stderr | 取决于系统实现与权限 |
| `oslog` | enabled | 是(`os_log` 与 Swift `Logger` 记录,带 subsystem / category;另含 NSLog 镜像条目) | 取决于系统是否允许当前进程读 `OSLogStore`(需 iOS 15+),以 `capture.state` 为准 | 同左 |

实测说明:
- **NSLog 镜像**:实测同一条 NSLog 文本会同时出现在 `nslog` source(NSLog 行格式)和 `oslog` source(裸条目),印证 NSLog 底层会写入 os_log 的系统行为。这是 iOS 系统行为而非自动化服务额外拷贝,在 `oslog` source 看到 NSLog 文本不要误判为重复捕获。
- **os_log 写入延迟**:`OSLogStore` 不是同步 stdout 管道,日志进入系统 store 可能有亚秒到秒级延迟;`app.logs.read` 会主动 flush 一次,但真实设备上首次 `oslog` 读空时建议等 1–2 秒重读一次,再判定为"无日志"。
- **真机 oslog 不保证可用**:真机上 `OSLogStore(.currentProcessIdentifier)` 有可能因系统进程级读取限制在不同 iOS 版本下返回 `unavailable`,这正是不能写死平台断言的根因。

### 5. `unavailable` 语义(读不到日志时的判别)

`app.logs.mark` / `app.logs.read` 的 `data.capture` 里,每个 source 有三态 `state`:

| state | 意思 | 开发者该怎么判断 |
|---|---|---|
| `enabled` | 已安装正在写入 store | 可以继续用对应 `sources` 读取 |
| `notCaptured` | 配置没打开(或 Release 构建下不可用) | 不是失败;需要打开对应 capture 配置再重启 App |
| `unavailable` | 配置打开了,但系统或安装步骤不允许(如 OS 版本不支持、fd 接管失败、`OSLogStore` 不让当前进程读) | 看 `reason` 字段;**这不是"日志没发生",而是"系统不让当前进程读"** |

**核心原则(必须记住)**:`unavailable` ≠ "日志没发生" ≠ "代码没执行"。它只表示"系统或安装步骤不允许当前进程读取这条通道"。把 `unavailable` 或 `notCaptured` 误判成"代码没执行"是最常见的错误——代码可能完全正常跑了、日志也写了,只是当前进程读不到。

如果 `entries` 为空,按这个顺序排查:
1. 先看 `capture.state`:
   - `notCaptured` → 没打开对应 capture 开关,需改 `registerDiagnosticsCommands` 配置再重启 App。
   - `unavailable` → 开关开了但系统不允许,看 `reason`(如 OS 版本不支持 / fd 接管失败)。
   - `enabled` → 来源可用,继续往下查。
2. `enabled` 但读空:检查 mark 是否在动作之前建的(顺序错会读到动作之前的历史);检查 `sources` 过滤是否写对(如 `["stdout"]` 不能写成 `["print"]`);`oslog` 读空先等 1–2 秒重读一次(写入延迟)。
3. 分页:若 `hasMore: true`,用 `nextCursor` 继续 read。

## 关键参数

### `app.logs.mark`

无入参。返回 `data.cursor`(`captureSessionID` + `id`)与 `data.capture`(6 个 source 状态快照)。每次 mark 拿到的 cursor 只在当前 App 进程生命周期内有效,App 重启后旧 cursor 失效。

### `app.logs.read`

| 参数 | 含义 | 注意 |
|---|---|---|
| `after` | 上一次 mark / read 返回的 cursor 对象(含 `captureSessionID` 和 `id`) | 省略 = 非增量读最近 `limit` 条;增量读必传 |
| `limit` | 最多返回多少条 | 范围 1...500,默认 100;`oslog` 噪音多时建议 500 |
| `sources` | 来源过滤 | 如 `["stdout"]`、`["stderr"]`、`["nslog"]`、`["oslog"]`、`["explore","bridge"]`;合法值就是上表 6 类 |
| `minimumLevel` | 最低等级过滤 | 枚举 `debug` / `info` / `error` / `fault` / `unknown`;设 `error` 会过滤掉 `stdout` 的 `info` 记录 |

响应关键字段:`entries[]`(每条含 `source` / `level` / `category` / `message`)、`nextCursor`、`hasMore`、`gap`、`capture`(6 source 状态快照,每次都回传可作自检)。

## 常见错误与判别

### 把 `unavailable` / `notCaptured` 误判成"代码没执行"(最严重)

- **现象**:read 某 source 返回空 `entries`,调用方下结论"我的 print / NSLog / os_log 没执行"
- **原因**:`capture.state` 是 `unavailable` 或 `notCaptured`,日志其实写了,只是当前进程读不到这条通道
- **判别**:先读 `data.capture` 里该 source 的 `state`;`notCaptured` = 配置没开,`unavailable` = 系统不让读(看 `reason`)
- **处理**:`notCaptured` 改 `registerDiagnosticsCommands` 配置打开对应 capture 再重启 App;`unavailable` 看 `reason` 决定能否绕过(如 oslog 不可用可改用 `bridge`,让 App 在关键点通过桥接日志 API 主动写)

### mark / read 顺序颠倒读到历史噪音

- **现象**:read 返回一大堆与本次动作无关的旧日志,找不到本次 token
- **原因**:mark 建在动作之后,或 read 没传 `after` cursor(非增量模式)
- **判别**:`entries` 的时间戳早于本次动作;或压根没传 `after`
- **处理**:严格按"mark → 动作 → read(after=mark 的 cursor)"顺序;read 的 `after` 必传

### App 重启后用旧 cursor

- **现象**:read 报 cursor 太旧,或返回 `gap` 字段说明日志已被 ring buffer 覆盖
- **原因**:App 重启产生新的 `captureSessionID`,旧 cursor 跨重启失效
- **判别**:read 响应含 `gap`,或 `captureSessionID` 与 mark 时不一致
- **处理**:App 每次重启后重新 mark,不要跨重启复用 cursor

### `sources` 写成不存在的值

- **现象**:read 返回空,或报参数无效
- **原因**:`sources` 写成 `["print"]` / `["os_log"]` / `["Logger"]` 这类非合法值;合法值只有 6 个:`explore` / `bridge` / `stdout` / `stderr` / `nslog` / `oslog`
- **判别**:响应 message 指向 sources 字段
- **处理**:对照上表改用合法 source 名;`print` 走 `stdout`,`os_log` 和 Swift `Logger` 都走 `oslog`

### oslog 读空就放弃

- **现象**:`capture.state` 是 `enabled` 但首次 read `oslog` 空
- **原因**:`OSLogStore` 写入有亚秒到秒级延迟;`app.logs.read` 会 flush 一次,但真机仍可能有延迟
- **判别**:state=enabled 且其他 source 能读到,只有 oslog 读空
- **处理**:等 1–2 秒重读一次;用唯一 token + `limit:500` 提高命中率;真机若反复读不到再看是否降级成 `unavailable`

### 在 `oslog` 看到 NSLog 文本以为是重复捕获

- **现象**:同一条 NSLog 文本同时出现在 `nslog` 和 `oslog` source
- **原因**:iOS 系统行为,NSLog 底层会写入 os_log;自动化服务没有额外拷贝
- **判别**:`nslog` source 里是带时间戳与 PID 的完整 NSLog 行;`oslog` source 里是无 subsystem / category 的裸条目
- **处理**:判别时按 source 分开看;这是系统行为不是 bug

### 把系统 `error` 直接当业务失败

- **现象**:`minimumLevel:"error"` 读到几条 `oslog` / `stderr`，报告就直接判成"登录失败"或"提交失败"
- **原因**:把系统噪音、自动化命令链和业务结果混成了一个结论层级
- **判别**:`explore` 显示命令执行成功，UI 终态或 `bridge` 也显示业务成功，但 `oslog` 里仍有无 subsystem 的系统错误
- **处理**:把结论拆成三层:自动化命令是否成功、业务功能是否成功、系统噪音是否存在。只有业务层失败时才把用例标成失败；系统错误默认记为噪音或待排查风险

## 相关 skill

- `ios-automation` — L1 总入口;不确定走哪个子 skill 时先问它
- 构建/设备管理 MCP（L0）— 需要**系统级或整个模拟器控制台日志**时改用它(抓 App 控制台);本 skill 只读 App 进程内按来源分类的精准日志。App 未接入 HTTP 自动化端点时也只能用 L0
- `ios-test-runner`(L2)— 消费测试意图清单跑测试时,用本 skill 的 `app.logs.read` 做日志断言;**前置必须检查对应 source 的 `capture.state`**,只有 `enabled` 才能作为有效日志判据,`unavailable` / `notCaptured` 的 source 要自动降级(跳过或改用 `bridge`,要求被测 App 在关键点通过桥接日志 API 主动写)

**平台约束**:App 内诊断扩展是 Debug-only 能力,Release 构建下 `registerDiagnosticsCommands` 返回 disabled,4 个 capture 开关都不会安装。`stdout` / `stderr` capture 是进程级 fd 接管(默认关闭,避免改变标准流行为);`oslog` / `nslog` 依赖系统是否允许当前进程读 `OSLogStore`(需 iOS 15+ / macOS 12+)。App 进程内 store 是 ring buffer,日志量大时旧条目会被覆盖(响应里通过 `gap` 字段说明丢失范围)。App 重启后内存 cursor 不继续使用。
