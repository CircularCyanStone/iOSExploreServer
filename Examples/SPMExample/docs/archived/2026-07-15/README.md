# 测试报告归档 - 2026-07-15

## 归档原因
这些报告中发现的问题已在 2026-07-15 同日修复并验证通过，归档以保留历史记录。

## 归档文件

### 1. complex-scenario-probe-report-2026-07-15.md
- **类型**: 复杂真实场景压力测试报告
- **方法**: 两阶段编排（4 静态并行 + 1 动态独占串行）
- **发现**: 24 个新问题（F-16~F-39）+ 更新 5 条已知（F-01/02/03/04/07）
- **关键发现**: 
  - F-16（P0）：ui.topViewHierarchy 密码泄露
  - F-01（P0）：ui.inspect UIFieldEditor 子节点泄露
  - F-18（P1）：ui.tap 不校验 isEnabled
  - F-19（P1）：登录按钮无防抖
  - F-33（P1）：skill swipe 参数名混淆

### 2. login-flow-e2e-test-report.md
- **类型**: 登录流程端到端测试报告
- **范围**: 场景 1-16（28 个子场景）
- **结果**: ✅ 全部通过（21/21 基础场景 + 4 新增场景）
- **关键发现**:
  - viewSnapshotID 陈旧校验机制（TTL 120s）
  - alert 字段设计优秀
  - semanticText 截断 bug（已修复为 F-06）
  - 密码泄露问题（发现 A，对应 F-01）

### 3. longpress-swipe-e2e-test-report.md
- **类型**: LongPress & Swipe 测试计划文档
- **状态**: 部分完成（代码审查 + 设计验证）
- **发现**: SceneDelegate 导航架构问题（未为主 ViewController 创建 UINavigationController）

### 4. longpress-swipe-e2e-test-results.md
- **类型**: LongPress & Swipe 测试执行结果
- **结果**: ✅ 全部通过（6/6 测试用例）
- **修复**: SceneDelegate 导航架构问题已修复
- **覆盖**: ui.longPress（3 策略）+ ui.swipe（3 策略）

## 修复状态总结

### ✅ 已修复（19 个）
**P0 安全（2个）**:
- F-16: UIViewHierarchyCollector.swift:334 secure 屏蔽
- F-01: UIKitInternalUtils.swift:76-102 祖先链 helper

**P1 功能错误（5个）**:
- F-18: UIKitActionExecutor.swift:213-227 isEnabled 守卫
- F-19: LoginViewController.swift:219 同步防抖
- F-20: RegisterViewController.swift:306 presenterForAlert
- F-17: AuthService.swift:33 删明文密码
- F-32: skill 文档工具映射校正

**P2 一致性（4个）**:
- F-03: UITextInputExecutor.swift:36-48 targetNotFound
- F-23: UIKitCommandError.swift:502 inputRejected message
- F-24: UIKitCommandError.swift:46 stale_locator 文本追踪警示
- F-21: Register/Reset/HomeVC present 检查

**Skill 文档（5个）**:
- F-33: list-interaction swipe 参数名（withinElementRef→direction/distance/...）
- F-34: form-filling submit 默认值（false→true）
- F-35: TTL（60s→120s）
- F-36: \n 多行输入区分 UITextField/UITextView
- F-37/F-38: navigation.back 参数 + call_action 兜底

**设计特性标注（3个）**:
- F-25/F-26/F-27: 代码注释防重复当 bug

### 🔴 未修复（1 个，有正当理由）
- **F-02**: MCP 工具未暴露（oneOf 参数）
  - 根因在 MCP 客户端侧（Claude Code），不在 iOSExploreServer 库内
  - 缓解措施：skill 文档标注 call_action 兜底

### 🟢 推翻的假设（5 个）
- D-04/D-05/D-07/D-09/D-10/D-11: snapshot 校验、path 稳定性、键盘态、ui.controllers 等机制验证正确

## 测试验证

### 测试通过
- `swift test`: **289 passed** ✅
- `xcodebuild test`: **489 passed** ✅
- 示例 App build: **SUCCEEDED** (0 warnings)

### 新增测试文件
- `UISecureTextLeakTests` (F-16/F-01)
- `UIKitActionExecutorTests` (F-18)
- `UIInputTests` (F-03)
- `UIKitCommandErrorTests` (F-23/F-24)

## 当前活跃文档

修复后的问题已更新到主台账：
- `/Examples/SPMExample/docs/findings-log.md` — 持续更新的问题与验证记录

## 验证报告

详细验证过程见 subagent 生成的报告（如有）。

---

**归档日期**: 2026-07-15  
**归档人**: Claude (Fable 5)  
**验证方式**: 代码审查 + 测试执行（289+489 passed）
