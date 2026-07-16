# Skills 历史产物归档

本目录存放 iOSExploreServer skill 体系历次迭代产生的一次性报告、测试快照和旧索引。
这些文件记录了 skill 体系从设计、命名调整到覆盖率验收的演进过程,但不再是日常使用的入口,**不再维护**。

## 这里的东西是什么

| 类别 | 文件 | 说明 |
|---|---|---|
| 设计定稿快照 | `skill-design-final.md` | skill 体系早期设计文档的一次性定稿快照 |
| 改进建议与落地记录 | `skills-improvement-recommendations.md`、`skills-improvements-applied.md` | 某轮重构周期里写下的建议清单与已落地清单 |
| 命名变更记录 | `renaming-report.md` | skill 从旧名(`ios-form-filling` 等)重命名到新名(`ios-ui-form` 等)的迁移报告 |
| 覆盖率/缺口验收 | `100-PERCENT-COVERAGE-FINAL.md`、`final-command-coverage.md`、`command-gap-analysis.md` | 某次覆盖率里程碑与命令缺口分析的一次性快照 |
| 测试报告(含配套 JSON) | `alert-test-complete-report.{md,json}`、`input-alert-control-test-report.{md,json}`、`input-alert-control-test-data.json`、`final-two-commands-test-report.{md,json}`、`skills-test-report.{md,json}`、`testing-summary.md` | 各轮实跑测试产生的报告与原始数据 |
| 项目阶段总结 | `ALL-TESTS-COMPLETE-SUMMARY.md`、`TASK-COMPLETION-SUMMARY.md` | skill 创建项目的阶段性完成总结 |
| 已废弃的旧索引 | `ios-automation-skills-index.md` | 旧版 skill 索引,已被 `docs/skills/README.md` + `docs/skills/inventory.md` 取代 |
| 已过时的快速入门 | `QUICK_START.md` | 引用旧 skill 名(`/ios-form-filling` 等)、已废弃的 `IOS_EXPLORE_AUTOSTART` 环境变量,和本目录里的旧索引;排障内容已在 `docs/runbooks/debugging.md` 覆盖,故整体归档 |

## 哪里是权威源

- **当前 skill 设计规范**: `docs/skills/design/` 下的 spec
- **当前 skill 清单与状态**: `docs/skills/inventory.md`
- **当前 skill 体系总入口**: `docs/skills/README.md`
- **集成与运行指南**: 仓库根 `README.md`、`AGENTS.md`、`CLAUDE.md`
- **排障与真机/模拟器跑法**: `docs/runbooks/debugging.md`、`docs/runbooks/build-and-test.md`

## 与仓库根 `reports/` 的关系

仓库根 `reports/2026-07-13-14-skills-creation-project/` 和 `reports/2026-07-14-skills-creation/` 是 skill 创建项目另一份阶段性产出副本,内容与本目录部分重叠但各自独立,**不作为权威源**。本目录与 `docs/skills/design/` 的 spec 一起构成 skill 体系的权威历史记录。仓库根 `reports/` 不在本次归档范围内,保持原样。
