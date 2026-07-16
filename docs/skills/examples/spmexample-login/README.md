# SPMExample 登录案例:如何对真实 App 套用 ios-test-intent / ios-test-runner

本目录是 `ios-test-intent` + `ios-test-runner` 的**真实 App 参考案例**,展示"从业务源码产出测试意图清单 → 现场驱动 App 跑出 pass/fail 覆盖报告"的完整闭环。

## 为什么有这个案例

- `ios-test-intent` / `ios-test-runner` 的 SKILL 正文是**通用的**:示例只用占位 App `<MyApp>` / `<LoginService>`,不绑定任何真实工程。
- 但"如何对一个真实 App 套上去"这件事,光看通用正文不够直观——需要一份能端到端跑通的实测定稿。
- SPMExample 是本仓库自带的示例 App(`Examples/SPMExample/`,已集成 iOSExploreServer),它的登录流程足够典型(异步网络 + 成功/失败分支 + 整栈替换 + alert),于是把这套案例**从 skill 本体解耦出来**放在 `examples/`,既保留实测数据,又不污染 skill 通用性。

> **本案例不属 skill 耦合**:skill 正文不引用本目录的具体字段值,evals 的静态结构检查只校验"skill 正文里有且仅有一处 examples 指针指向本目录",不在通用示例里硬编码 SPMExample 的类名/bundle id/UDID/凭据。

## 文件说明

| 文件 | 产出 skill | 作用 |
|---|---|---|
| `intent.json` | `ios-test-intent` | 读 `Examples/SPMExample/SPMExample/Login/` 业务源码(`LoginViewModel` / `AuthService.login` / `LoginViewController`)产出的测试意图清单。每个 scenario 的 `pass_criteria` / `fail_criteria` 只用 ios-* 等待词汇(`textExists` / `targetExists` / `targetGone` / `alert`),**不含 path / accessibilityIdentifier / viewSnapshotID**——这些由运行时 `ui_inspect` 解析。覆盖 10 个场景(成功路径、错误密码、空字段、网络延迟期间、返回拦截等)。 |
| `run-report.json` | `ios-test-runner` | 消费上面的 intent 清单、现场驱动模拟器里的 SPMExample App 跑出来的覆盖报告。`manifest` 字段指回 `intent.json`;每条场景记 `pass` / `fail` / `skipped` + 命中的 `matchedID` / notes,含 `launch_args` / `simulator` / 连接方式等运行时元数据。 |
| `README.md` | — | 本文件,说明案例用途与解耦边界。 |

## 如何套用到你自己的 App

1. **产出 intent 清单**:用 `ios-test-intent` skill 读你 App 的业务源码(Service / ViewModel / ViewController),按 5 步方法论产出一份与 `intent.json` 同结构的清单,放到 `docs/test-intents/<your-app>-<flow>.json`。
2. **现场跑出报告**:用 `ios-test-runner` skill 消费该清单,按 6 步工作流驱动 App(模拟器或真机),把产出的覆盖报告放到 `docs/test-reports/<your-app>-<flow>-run.json`。
3. **参考但不照抄**:本目录的 `intent.json` 是 SPMExample 登录流程的**具体测定稿(含真实账号 test/123456、真实文案、真实业务点)**,你的 App 要换成自己的业务点与判据,不要复制字段值。

## 相关 skill

- `ios-test-intent` — 产出 intent 契约(离线,读源码)。
- `ios-test-runner` — 消费 intent、现场跑、判 pass/fail、汇总覆盖报告。
- 两个 skill 本体通用;本目录是它们唯一的真实 App 参考案例。

## 关联文档

- 设计背景:`docs/skills/design/2026-07-16-skills-architecture.md`(SPMExample 解耦与 examples 定位)
- 解耦约定:`docs/skills/conventions/decoupling.md`(为什么把案例移出 skill 本体)
