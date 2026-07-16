# 与示例 App(SPMExample)解耦规则

> 本文规定 skill 本体与 SPMExample 解耦的硬规则、占位符约定,以及**最关键的一条澄清**:skill 本体解耦 ≠ evals 不能用 SPMExample fixture。规范依据:`docs/skills/design/2026-07-16-skills-architecture.md` §8 + plan `2026-07-16-skills-refactor.md` 的 G3。

---

## 0. 身份重申(为什么必须解耦)

**SPMExample 是 iOSExploreServer 的集成示例 App,不是任何 skill 的私有测试夹具。** 每个 skill 必须对"任意集成了 iOSExploreServer 的 iOS App"都直接可用,不能在正文写死 SPMExample 的标识符、设备 ID 或测试账号。

skill 通用性 = skill 本体不能耦合;**但不等于** evals 不能用 SPMExample 作 fixture(详见第 3 节)。

---

## 1. 硬规则(G3 全文)

**`.claude/skills/<skill>/SKILL.md` 正文禁止出现以下 5 类硬编码**:

| # | 禁止内容 | 典型反例 | 为什么禁 |
|---|---|---|---|
| 1 | 真实 bundle id | `com.coo.SPMExample` | skill 必须通用,任意集成 App 都能用 |
| 2 | 真实 UDID(模拟器或 USB) | `065CC8DB-8978-46C5-82D6-C96625B608D8`、`00008030-...` | 设备 ID 因人而异,写死无法复用 |
| 3 | 测试账号 | `test` / `123456` | 这是 SPMExample 预置种子数据,不是通用示例 |
| 4 | SPMExample 专属启动参数作为固定流程 | `--ios-explore-show-login`、`IOS_EXPLORE_SHOW_LOGIN=1` 被写成"必备步骤" | 这些是 SPMExample 测试工程的快捷方式,不是 skill 通用 API |
| 5 | SPMExample 源码行号 / 类名作为 skill 通用示例 | `AuthService.swift:31`、`LoginViewModel.shared.users`、`LoginViewController` | 行号与类名是 SPMExample 实现细节,不能进 skill 正文 |

> **关键**:grep 验证**只扫 `SKILL.md` 正文、不扫 `evals/`**(动态 evals 允许用 fixture,见第 3 节)。grep 只查 bundle id / UDID(规则 1–2),**不查 `test` / `123456`**——规则 3 的 test/123456 仅禁 `SKILL.md` 正文,`evals` 动态 fixture 允许真实凭证,故不进 grep。

### 1.1 验证 grep(plan G5 命令 2)

```bash
F=.claude/skills/$SKILL/SKILL.md
grep -nE 'com\.coo\.SPMExample|065CC8DB|00008030' "$F" && echo FAIL || echo OK
```

输出 `OK` 才算过。这条 grep 同时被 spec §11 与 plan Task 18 列为最终验收命令。

---

## 2. 占位符约定

需举例时用以下占位符替代真实值:

| 场景 | 占位符 | 示例用法 |
|---|---|---|
| 目标 App bundle id | `<your.app.bundleid>` | `curl -X POST http://localhost:38321/ -d '{"action":"ping"}'` 前提是 `<your.app.bundleid>` 对应的 App 已集成 iOSExploreServer |
| 模拟器 UDID | `<your-simulator-udid>` | `xcrun simctl terminate <your-simulator-udid> <your.app.bundleid>` |
| 真机 USB UDID | `<your-device-udid>` | `iproxy 38321 38321 -u <your-device-udid>` |
| 测试账号用户名 | `<seed-user>` / `<your-username>` | `ui.input(..., text:"<seed-user>")` |
| 测试账号密码 | `<seed-password>` / `<your-password>` | `ui.input(..., text:"<seed-password>")` |
| 启动参数(如需回到流程起点) | "由调用方提供 App 专属启动参数" | 不写死参数名,只说"调用方提供" |
| SPMExample 源码引用 | 通用化为虚构 `<MyApp>` 的 `<LoginService>` / `<LoginViewModel>` | 不引真实类名与行号 |
| 产物路径(意图清单/报告) | `<app>-<flow>.json` | `docs/test-intents/<app>-<flow>.json`、`docs/test-reports/<app>-<flow>-run.json` |
| 报告里的 app 名 / simulator 名 | `<your-app>` / `<name> (<udid>)` | `"app":"<your-app>"`、`"simulator":"<name> (<udid>)"` |

**占位符必须够明显**:用 `<...>` 尖括号包裹,不要写 `"some-app"` / `"your-app"`(不带尖括号易被误读成真实值)。

---

## 3. 关键澄清:skill 本体解耦 ≠ evals 不能用 SPMExample fixture

这是 spec §6 "evals 策略"小节的核心,也是 decoupling 最容易被误解的地方。

### 3.1 两层 evals

| 类型 | 是否依赖运行 App | 内容 | 解耦要求 |
|---|---|---|---|
| **静态结构 evals**(每个 skill 必有) | 否 | 检查 frontmatter 含 `allowed-tools`、正文无 SPMExample 硬编码(本文 §1 全过)、引用的 action 在 iOSDriver 真实存在 | **严格通用**,G3 硬规则全过 |
| **动态回归 evals**(需要时) | 是 | 仓库内唯一可用的集成 App 是 SPMExample,作为**参考 fixture** 由 `docs/skills/examples/spmexample-login/` 提供 | **可引用 examples 里的案例**,不算 skill 本体耦合 |

### 3.2 一个具体例子

- **`ios-ui-form` 的 `SKILL.md` 正文**不许出现 `test/123456`——这是 skill 通用性要求。
- **`ios-ui-form` 的 `evals/evals.json` 动态 case**可以驱动 SPMExample 表单验证输入流程——这是测试夹具,不是 skill 耦合。
- 前者管 skill 通用性,后者是测试夹具,**两层分开**。

### 3.3 为什么不新建"占位 App"

仓库内无其他集成 iOSExploreServer 的 App,新建一个"占位 App"成本不值。本次重构**不新建**占位 App,SPMExample 作为唯一可用集成 App 充当动态 evals 的参考 fixture,放在 `docs/skills/examples/spmexample-login/`。

依据:spec §6 "evals 策略"末段、§12 风险与回退第 2 条。

### 3.4 SPMExample 案例的归属

SPMExample 登录流程(意图清单 + 实跑报告)作为"如何对真实 App 套用 test-intent/runner"的**完整参考案例**,放在 `docs/skills/examples/spmexample-login/`,**不进 skill 本体**。

- 现 `docs/test-intents/spmexample-login.json` → `docs/skills/examples/spmexample-login/intent.json`(plan Task 15)
- 现 `docs/test-reports/spmexample-login-run.json` → `docs/skills/examples/spmexample-login/run-report.json`(plan Task 15)
- `docs/test-intents/`、`docs/test-reports/` 原目录保留为通用目录(后续非 SPMExample 的意图清单/报告也写这里)。

---

## 4. 解耦动作定点表(spec §8)

不是所有 skill 都需要解耦改动。下表是 spec §8 给出的定点清单:

| skill | 解耦动作 |
|---|---|
| `ios-test-runner` | 正文报告样例改占位(`<your-simulator-udid>`、`<your.app.bundleid>`);SPMExample 登录完整真实案例移到 `docs/skills/examples/spmexample-login/` |
| `ios-test-intent` | 方法论保留(读 Service/VM/VC 产出判据),通用示例改占位 App;SPMExample 登录作为案例移到 examples |
| `ios-automation` | 诊断清理命令改占位 bundle id;登录示例改通用占位 |
| **其余 8 个 skill**(7 个 `ios-ui-*` + `ios-logs`) | **无耦合,无需动**(spec §8 原文"其余 10 个"指重构前 13 个项目级 − 3 个需解耦;重构后实际无耦合的是这 8 个) |

> 注:`ios-test-intent` / `ios-test-runner` 虽然也要解耦,但其与 SPMExample 案例的关联会在 `docs/skills/examples/spmexample-login/` 里保留(由 plan Task 15 处理)。

---

## 5. 自检清单(每次写完 skill 跑一遍)

写完一个 skill 的 `SKILL.md` 后,过以下清单:

- [ ] `grep -nE 'com\.coo\.SPMExample|065CC8DB|00008030' .claude/skills/<skill>/SKILL.md` 输出 `OK`(无匹配)
- [ ] 正文未把 `test` / `123456` 作为"步骤里的真实账号"出现(动态 evals 允许,正文不允许)
- [ ] 正文未把 `--ios-explore-show-login` 等 SPMExample 专属启动参数写成必备步骤
- [ ] 正文未出现 `AuthService` / `LoginViewController` 等 SPMExample 真实类名 + 行号作为通用示例
- [ ] 所有举例用本文 §2 的占位符(`<your.app.bundleid>` 等)
- [ ] `evals/evals.json` 的动态 case 引用 `docs/skills/examples/spmexample-login/` 路径,不是 `docs/test-intents/spmexample-login.json` 等旧路径(由 plan Task 15 迁移后)

---

## 6. 反例对照

### 6.1 反例(正文耦合 SPMExample)

```markdown
## 启动流程

1. `xcrun simctl boot 065CC8DB-8978-46C5-82D6-C96625B608D8`
2. 用 `test` / `123456` 登录 AuthService.shared.users
3. 启动参数 `--ios-explore-show-login` 进入登录页
```

违反:UDID(规则 2)、测试账号(规则 3)、专属启动参数作为固定流程(规则 4)、真实类名(规则 5)。

### 6.2 正例(占位符 + 通用化)

```markdown
## 启动流程

1. 启动集成 iOSExploreServer 的目标 App(`<your.app.bundleid>`),在 `viewDidLoad` / `applicationDidFinishLaunching` 中调用 `server.start()`
2. 用 `<seed-user>` / `<seed-password>` 登录(凭证由调用方提供)
3. 如需回到流程起点,由调用方提供 App 专属启动参数
```

通过:全用占位符,不写死任何 SPMExample 标识。
