# Input 和 Keyboard 命令端到端测试报告

**测试日期**: 2026-07-12  
**测试执行者**: Claude (自动化端到端测试)  
**测试方法**: 使用 `mcp-inspector.mjs` 和 `curl` 直接调用 MCPServer，验证 `ui.input` 和 `ui.keyboard.dismiss` 命令在真实 App 中的表现

---

## 测试环境

- **测试 App**: Examples/SPMExample (模拟器 iPhone 17)
- **测试页面**: `InputTestViewController` (新建的文本输入测试页面)
- **测试场景数**: 7 种文本控件 + 多种边界和错误场景
- **MCP 协议**: stdio JSON-RPC 2.0
- **iOSExplore Server**: localhost:38321

---

## 测试场景总览

### ✅ 成功场景 (21 个)

| # | 场景描述 | 命令 | 验证点 |
|---|---------|------|--------|
| 1 | 简单 TextField replace 模式 | `ui.input` | 文本正确替换，返回 `finalText` |
| 2 | 预填充 TextField append 模式 | `ui.input` | 追加到原内容，返回完整文本 |
| 3 | UITextView 多行文本，submit=false | `ui.input` | 多行文本正确插入，键盘保持显示 |
| 4 | 键盘收起 - auto 策略 | `ui.keyboard.dismiss` | 成功收起，返回 before/after 类型 |
| 5 | UISearchTextField | `ui.input` | 搜索框正确输入，返回类型 `UISearchTextField` |
| 6 | 密码框 secure text entry | `ui.input` | 返回 masked 和 length，不暴露原文 |
| 7 | 数字键盘，submit=false | `ui.input` | 数字正确输入，键盘保持显示 |
| 8 | 键盘收起 - resignFirstResponder | `ui.keyboard.dismiss` | 成功收起，策略正确返回 |
| 9 | 键盘收起 - endEditing | `ui.keyboard.dismiss` | 成功收起，策略正确返回 |
| 10 | 禁用 TextField 输入错误处理 | `ui.input` | 返回 `become_first_responder_failed` |
| 11 | 使用 path 定位 | `ui.input` | path 定位成功 |
| 12 | 使用陈旧 viewSnapshotID + identifier | `ui.input` | **意外成功** (见问题分析) |
| 13 | 使用陈旧 viewSnapshotID + path | `ui.input` | **意外成功** (见问题分析) |
| 14 | 特殊字符输入 | `ui.input` | 特殊符号正确处理 |
| 15 | Emoji 输入 | `ui.input` | Emoji 正确插入 |
| 16 | 空字符串清空 | `ui.input` | 文本框成功清空 |
| 17 | 无键盘时调用 dismiss | `ui.keyboard.dismiss` | 返回 `dismissed: false`，不报错 |
| 18 | 缺少必填 text 字段 | `ui.input` | 返回 `invalid_data` |
| 19 | identifier 和 path 互斥 | `ui.input` | 返回互斥错误 |
| 20 | 缺少定位条件 | `ui.input` | 返回必填错误 |
| 21 | 不存在的 identifier | `ui.input` | 返回 `invalid_data` |
| 22 | 非输入控件（Label） | `ui.input` | 返回 `unsupported_text_input_type` |
| 23 | 无效 strategy | `ui.keyboard.dismiss` | 返回枚举值错误 |
| 24 | waitAfterMs 超出范围 | `ui.keyboard.dismiss` | 返回范围错误 |

### ✅ 综合流程测试

**流程**: 搜索框输入 → 检查键盘显示 → 收起键盘 → 验证键盘隐藏 → textView 多行输入 → 验证内容

**结果**: 全部步骤成功，状态转换正确

---

## 发现的问题

### ~~问题 1: viewSnapshotID 陈旧检测未生效~~ (已验证：非 Bug)

**初步现象**:  
在早期测试中，使用陈旧的 `viewSnapshotID` 操作其他文本框后再操作目标文本框，命令仍然成功执行。

**深入验证后的结论**: ✅ **陈旧检测正常工作**

**陈旧检测的工作原理**:  
陈旧检测是基于**单个目标 view 的指纹**（包括 path、frame、semanticDigest 等），而不是全局快照版本号。只有当**目标 view 自身**的指纹发生变化时，才会触发 `stale_locator` 错误。

**验证测试**:
```bash
# 1. 向 simpleTextField 输入 "初始内容"，获取快照 snap-35
# 2. 修改 simpleTextField 自身内容为 "修改后的内容"，触发新快照 snap-38
# 3. 用旧快照 snap-35 尝试操作 simpleTextField
# 结果: 返回 stale_locator 错误 ✅
```

**为什么早期测试没触发陈旧检测**:  
- 修改的是**其他文本框**（prefillTextField），而不是目标文本框（simpleTextField）
- 目标文本框的指纹（text、frame、semanticDigest）没有变化
- 陈旧检测正确地判断目标 view 未变化，允许操作继续

**设计合理性**:  
这是**正确的设计**。陈旧检测的目的是防止操作已经变化的目标，而不是强制每次操作都必须用最新的全局快照。如果页面上其他控件变化了，但目标控件本身没变，操作仍然是安全的。

**与 ui.tap 的一致性**: ✅  
`ui.tap` 也是基于单个 view 的指纹检测，行为完全一致。两者都调用 `UIKitActionExecutor.validateViewSnapshot`。

---

### 问题 2: ui.inspect 响应中 targets 没有 viewSnapshotID 字段 (严重程度: 低-文档)

**现象**:  
`ui.inspect` 返回的 `data.targets[]` 中每个 target 的 `viewSnapshotID` 都是 `null`，只有顶层 `data.viewSnapshotID` 有值。

**观察**:
```json
{
  "data": {
    "viewSnapshotID": "snap-10",
    "targets": [
      {
        "path": "root/5/0/1",
        "viewSnapshotID": null,  // ← 总是 null
        "availableActions": ["tap"]
      }
    ]
  }
}
```

**是否是 Bug**:  
不确定。可能是设计如此（一个 inspect 响应只签发一个全局 snapshotID），但文档和代码注释没有明确说明。

**影响**:
- 文档未明确说明 viewSnapshotID 的作用域（全局 vs 每个 target）
- 如果 agent 期望从单个 target 对象获取 snapshotID 会失败

**建议**:
- 在 `ui.inspect` 的文档中明确说明：`viewSnapshotID` 在响应顶层，覆盖本次 inspect 返回的所有 targets
- 或者考虑在每个 target 中重复 viewSnapshotID（与顶层相同），避免 agent 误解

---

### 问题 1: ui.inspect 响应中 targets 没有 viewSnapshotID 字段 (严重程度: 低-文档)

**现象**:  
`ui.inspect` 返回的 `data.targets[]` 中每个 target 的 `viewSnapshotID` 都是 `null`，只有顶层 `data.viewSnapshotID` 有值。

**观察**:
```json
{
  "data": {
    "viewSnapshotID": "snap-10",
    "targets": [
      {
        "path": "root/5/0/1",
        "viewSnapshotID": null,  // ← 总是 null
        "availableActions": ["tap"]
      }
    ]
  }
}
```

**是否是 Bug**:  
不确定。可能是设计如此（一个 inspect 响应只签发一个全局 snapshotID），但文档和代码注释没有明确说明。

**影响**:
- 文档未明确说明 viewSnapshotID 的作用域（全局 vs 每个 target）
- 如果 agent 期望从单个 target 对象获取 snapshotID 会失败

**建议**:
- 在 `ui.inspect` 的文档中明确说明：`viewSnapshotID` 在响应顶层，覆盖本次 inspect 返回的所有 targets
- 或者考虑在每个 target 中重复 viewSnapshotID（与顶层相同），避免 agent 误解

---

以下设计点在端到端测试中表现正确：

### ✅ 错误处理完整性
- 缺少必填字段 → 明确错误信息
- 互斥字段冲突 → 正确拒绝
- 参数范围验证 → 边界值正确拒绝
- 不存在的 identifier → 明确"未找到"
- 非输入控件 → 明确"不支持的类型"
- 禁用控件 → 明确"无法成为 first responder"

### ✅ 功能完整性
- replace 模式：先清空再写入 ✓
- append 模式：追加到末尾 ✓
- submit=true：自动收起键盘 ✓
- submit=false：保持键盘显示 ✓
- 密码框：返回 masked + length，不泄露原文 ✓
- 多行文本：换行符正确处理 ✓
- Emoji 和特殊字符：正确插入 ✓
- 空字符串：清空文本框 ✓

### ✅ 键盘控制
- auto 策略：先 resign，失败后 endEditing ✓
- resignFirstResponder 策略：只调用 resign ✓
- endEditing 策略：只调用 endEditing ✓
- 无键盘时 dismiss：返回 dismissed=false，不报错 ✓
- 返回 before/after first responder 类型 ✓

### ✅ 陈旧检测机制
- 基于单个 view 的指纹检测 ✓
- 目标 view 自身变化时正确触发 stale_locator ✓
- 其他 view 变化不影响未变化目标的操作 ✓
- 与 ui.tap 行为完全一致 ✓

### ✅ MCP 协议层
- 工具名映射：`ui.input` / `ui_input` ✓
- 工具名映射：`ui.keyboard.dismiss` / `ui_keyboard_dismiss` ✓
- schema 正确生成 ✓
- 约束信息正确传递 ✓
- 错误码正确映射 ✓

---

## 测试覆盖率

### 命令参数覆盖

#### ui.input
- ✅ `accessibilityIdentifier` (必选之一)
- ✅ `path` (必选之一)
- ✅ `viewSnapshotID` (可选，但陈旧检测未生效)
- ✅ `text` (必填)
- ✅ `mode`: replace / append
- ✅ `submit`: true / false

#### ui.keyboard.dismiss
- ✅ `strategy`: auto / resignFirstResponder / endEditing
- ✅ `waitAfterMs`: 0-3000 范围

### 控件类型覆盖
- ✅ UITextField (普通 / 预填充 / 密码 / 数字键盘 / 禁用)
- ✅ UITextView (多行文本)
- ✅ UISearchTextField
- ✅ UILabel (错误处理)

### 错误场景覆盖
- ✅ 缺少必填字段
- ✅ 互斥字段冲突
- ✅ 参数超出范围
- ✅ 无效枚举值
- ✅ 不存在的 identifier
- ✅ 非输入控件
- ✅ 禁用控件
- ✅ 陈旧 snapshotID (发现问题)

---

## 与其他命令的行为对比

### ui.tap 的陈旧检测 (已验证过)
在之前的 `ui.tap` 端到端测试中，使用陈旧的 `viewSnapshotID` 会正确返回 `stale_locator` 错误。

**对比结论**:  
`ui.input` 的陈旧检测实现缺失或未生效，与 `ui.tap` 行为不一致。

### ui.wait 的 targetExists/targetGone
在之前的测试中发现 `ui.wait` 忽略 `isHidden` 的 bug。

**本次测试无此问题**:  
`ui.input` 正确处理 enabled/disabled 状态，不会对禁用控件进行操作。

---

## 修复优先级

### 高优先级
无

### 中优先级
无

### 低优先级
1. **ui.inspect 文档澄清** - targets 中的 viewSnapshotID 总是 null 的设计意图需要明确

---

## 推荐后续测试

1. **代码审查**: 检查 `UITextInputExecutor.swift` 的陈旧检测实现
2. **单元测试补充**: 为 viewSnapshotID 陈旧检测添加专门的单元测试
3. **性能测试**: 测试极长文本（10000+ 字符）的输入性能
4. **并发测试**: 快速连续调用 ui.input 和 ui.keyboard.dismiss 的竞态行为
5. **真机验证**: 在真机上验证键盘行为（模拟器和真机键盘行为可能有差异）

---

## 总结

**总体评价**: ✅ 优秀

`ui.input` 和 `ui.keyboard.dismiss` 命令在端到端测试中表现优秀，功能完整，错误处理清晰，陈旧检测机制正确实现。没有发现实际 bug，只有一个低优先级的文档澄清建议。

**测试通过率**: 24/24 场景执行成功（包括预期的错误场景）  
**发现 Bug 数**: 0 个  
**发现文档问题**: 1 个（低优先级澄清）

---

## 附录：关键发现和澄清

### 陈旧检测机制的深入理解

初期测试时误以为陈旧检测未生效，深入验证后发现：

**陈旧检测的正确理解**:
- 检测基于**单个目标 view 的指纹**，不是全局快照版本号
- 指纹包括：path、frame、text、semanticDigest 等
- 只有当**目标 view 自身**的指纹变化时才触发 `stale_locator`
- 页面其他部分变化不影响未变化目标的操作

**为什么这样设计是正确的**:
1. **避免过度严格**：如果强制每次操作都用最新全局快照，会导致大量误报
2. **实际安全保障**：只要目标本身没变，操作就是安全的
3. **与 ui.tap 一致**：两个命令共用同一陈旧检测逻辑（`UIKitActionExecutor.validateViewSnapshot`）

**验证方法**:
```bash
# 触发陈旧检测的正确场景
1. 向目标 view 输入 "初始内容"，获取快照
2. 修改目标 view 自身内容
3. 用旧快照操作该目标 → 正确返回 stale_locator
```
