# Skills 使用快速参考

## 1️⃣ 自然语言使用（最简单）

直接告诉 Claude 你要做什么，Skills 会自动触发。

### 示例 1: 登录测试
```
在 iOS App 中测试登录：
- 输入用户名 test@example.com
- 输入密码 Password123
- 点击登录
- 验证进入首页

Server: http://localhost:38321
```

### 示例 2: 列表操作
```
在设置列表中：
1. 滚动到"隐私设置"
2. 点击进入
3. 截图保存
```

### 示例 3: Alert 处理
```
点击删除按钮，在确认弹窗中选择"确认删除"
```

**触发关键词**：iOS、iPhone、iPad、App、移动应用自动化

---

## 2️⃣ 结构化测试（测试平台集成）

### 最小示例

```json
{
  "testCase": {
    "id": "TC001",
    "name": "Login Test",
    "steps": [
      {
        "stepId": 1,
        "skill": "ios-form-filling",
        "action": "fillTextField",
        "params": {
          "identifier": "username_field",
          "text": "test@example.com"
        }
      },
      {
        "stepId": 2,
        "skill": "ios-navigation",
        "action": "tapButton",
        "params": {
          "identifier": "login_button"
        }
      }
    ]
  }
}
```

### 完整示例

```json
{
  "testSuite": "E2E Tests",
  "environment": {
    "serverUrl": "http://localhost:38321"
  },
  "testCases": [
    {
      "id": "TC001",
      "name": "User Login",
      "steps": [
        {
          "stepId": 1,
          "skill": "ios-form-filling",
          "action": "fillTextField",
          "params": {"identifier": "username", "text": "user@test.com"}
        },
        {
          "stepId": 2,
          "skill": "ios-form-filling",
          "action": "fillTextField",
          "params": {"identifier": "password", "text": "pass123"}
        },
        {
          "stepId": 3,
          "skill": "ios-navigation",
          "action": "tapButton",
          "params": {"identifier": "login_button"}
        },
        {
          "stepId": 4,
          "skill": "ios-screenshot",
          "action": "capture",
          "params": {"filename": "login-result.png"}
        }
      ]
    }
  ]
}
```

---

## 3️⃣ 可用的 Skills

| Skill | 用途 | 触发场景 |
|-------|------|----------|
| **ios-form-filling** ⭐ | 表单填写 | 输入文本、切换开关、调整滑块 |
| **ios-navigation** ⭐ | 导航操作 | 点击按钮、返回、页面跳转 |
| **ios-alert-handling** ⭐ | 弹窗处理 | 响应 Alert、确认对话框 |
| **ios-list-interaction** ⭐ | 列表操作 | 滚动列表、点击列表项 |
| **ios-screenshot** ⭐ | 截图保存 | 捕获屏幕、视觉验证 |
| ios-gestures | 手势操作 | 滑动、长按 |
| ios-dynamic-content | 动态内容 | 等待加载、异步内容 |
| ios-table-actions | 表格操作 | 滑动删除 |

⭐ = 生产就绪，可立即使用

---

## 4️⃣ 常见操作映射

### 表单操作
```json
// 填写文本
{"skill": "ios-form-filling", "action": "fillTextField", 
 "params": {"identifier": "email", "text": "test@example.com"}}

// 切换开关
{"skill": "ios-form-filling", "action": "toggleSwitch",
 "params": {"identifier": "remember_me"}}

// 关闭键盘
{"skill": "ios-form-filling", "action": "dismissKeyboard"}
```

### 导航操作
```json
// 点击按钮
{"skill": "ios-navigation", "action": "tapButton",
 "params": {"identifier": "submit_button"}}

// 返回上一页
{"skill": "ios-navigation", "action": "navigateBack"}

// 验证标题
{"skill": "ios-navigation", "action": "verifyTitle",
 "params": {"expected": "Home"}}
```

### Alert 处理
```json
// 响应 Alert
{"skill": "ios-alert-handling", "action": "respond",
 "params": {"buttonTitle": "确认"}}

// 等待 Alert
{"skill": "ios-alert-handling", "action": "waitForAlert",
 "params": {"timeout": 2000}}
```

### 列表操作
```json
// 滚动到元素
{"skill": "ios-list-interaction", "action": "scrollToItem",
 "params": {"text": "Settings"}}

// 点击列表项
{"skill": "ios-list-interaction", "action": "tapItem",
 "params": {"index": 0}}
```

### 截图
```json
// 捕获截图
{"skill": "ios-screenshot", "action": "capture",
 "params": {"filename": "test-result.png"}}
```

---

## 5️⃣ 实际使用流程

### 方式 A: 直接对话（推荐快速测试）

1. 启动 iOS App 和 iOSExploreServer
2. 在 Claude Code 中描述测试场景
3. Claude 自动选择合适的 Skills 执行
4. 查看执行结果和截图

### 方式 B: 结构化文件（推荐自动化测试）

1. 准备测试用例 JSON 文件
2. 使用测试平台或脚本调用
3. 收集执行结果和报告
4. 集成到 CI/CD

---

## 6️⃣ 示例代码

### Python 集成
```python
import json
import subprocess

# 加载测试用例
with open('test-case.json') as f:
    test_case = json.load(f)

# 执行测试（通过 Claude Code API）
result = subprocess.run([
    'claude-code', 'execute-ios-test',
    '--test-case', 'test-case.json',
    '--skills-path', '.claude/skills',
    '--server', 'http://localhost:38321'
], capture_output=True)

print(result.stdout)
```

### JavaScript 集成
```javascript
const fs = require('fs');
const { exec } = require('child_process');

// 加载测试用例
const testCase = JSON.parse(fs.readFileSync('test-case.json'));

// 执行测试
exec('claude-code execute-ios-test --test-case test-case.json', 
  (error, stdout, stderr) => {
    if (error) {
      console.error(`Error: ${error}`);
      return;
    }
    console.log(stdout);
  }
);
```

---

## 7️⃣ 故障排查

### 问题：Skills 没有触发
**解决**：确保描述中包含 iOS/iPhone/iPad 关键词

### 问题：找不到元素
**解决**：先运行 `ui.inspect` 查看实际的 identifier

### 问题：操作太快
**解决**：在步骤间添加等待时间

### 问题：Alert 没响应
**解决**：增加等待时间，使用 `waitForAlert`

---

## 8️⃣ 最佳实践

✅ **使用 accessibilityIdentifier**（最可靠）  
✅ **每步操作后等待动画完成**  
✅ **关键步骤截图验证**  
✅ **失败时重试 1-2 次**  
✅ **使用明确的验证条件**

❌ 避免硬编码坐标  
❌ 避免过长的等待时间  
❌ 避免依赖文本（可能变化）

---

## 9️⃣ 文档位置

**Skills 位置**：`.claude/skills/`  
**使用指南**：`reports/2026-07-13-14-skills-creation-project/SKILLS-USAGE-GUIDE.md`  
**Skills 索引**：`.claude/skills/iOS-AUTOMATION-SKILLS-INDEX.md`

---

**快速开始**：直接在 Claude Code 中说 "在 iOS App 中..." 即可！
