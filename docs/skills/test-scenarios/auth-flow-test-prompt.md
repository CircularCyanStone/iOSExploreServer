# SPMExample 认证流程测试提示词

## 一、测试目标

全面验证 SPMExample 应用的登录、注册、重置密码三大认证流程，确保：
- 正常流程可以成功完成
- 异常输入能正确提示错误
- UI 状态转换符合预期
- 边界条件处理正确

## 二、测试环境

### 启动配置
```bash
# 方式1：模拟器启动（推荐快速验证）
session_use_defaults_profile("sim-app")
build_run_sim()
launch_app_sim(env: {"IOS_EXPLORE_SHOW_LOGIN": "1"})

# 方式2：真机启动
session_use_defaults_profile("device-app")
build_run_device()
launch_app_device(env: {"IOS_EXPLORE_SHOW_LOGIN": "1"})
# 另开终端：./scripts/proxy.sh --daemon

# 验证服务就绪
curl -X POST http://localhost:38321/ -d '{"action":"ping"}'
```

### 预置测试数据
```json
{
  "existingUser": {
    "username": "test",
    "password": "123456",
    "email": "test@example.com"
  }
}
```

---

## 三、测试场景（结构化）

### 场景 1：登录流程

#### 1.1 正常登录（Happy Path）
```json
{
  "scenario": "login_success",
  "description": "使用预置账号成功登录",
  "steps": [
    {
      "action": "ui.inspect",
      "params": {"maxDepth": 3},
      "verify": "找到 login_username_field、login_password_field、login_button"
    },
    {
      "action": "ui.control.setValue",
      "params": {
        "accessibilityIdentifier": "login_username_field",
        "value": "test"
      },
      "verify": "用户名输入框显示 'test'"
    },
    {
      "action": "ui.control.setValue",
      "params": {
        "accessibilityIdentifier": "login_password_field",
        "value": "123456"
      },
      "verify": "密码输入框显示 ••••••"
    },
    {
      "action": "ui.tap",
      "params": {"accessibilityIdentifier": "login_button"},
      "verify": "按钮文字消失，loading indicator 出现"
    },
    {
      "action": "ui.wait",
      "params": {
        "mode": "textExists",
        "text": "欢迎",
        "timeoutMs": 3000
      },
      "verify": "1.5秒后跳转到首页，显示欢迎信息"
    }
  ],
  "expectedResult": {
    "navigation": "HomeViewController",
    "logs": ["✅ 登录成功，跳转到首页: username=test"]
  }
}
```

#### 1.2 登录失败 - 错误凭据
```json
{
  "scenario": "login_failed_invalid_credentials",
  "description": "用户名或密码错误",
  "testCases": [
    {
      "case": "用户不存在",
      "input": {"username": "nonexistent", "password": "123456"},
      "expectedError": "用户名或密码错误"
    },
    {
      "case": "密码错误",
      "input": {"username": "test", "password": "wrongpass"},
      "expectedError": "用户名或密码错误"
    }
  ],
  "steps": [
    {"action": "输入错误凭据"},
    {"action": "点击登录按钮"},
    {"action": "等待 loading 结束（1.5秒）"},
    {"action": "验证 login_error_label 显示且文本为 '用户名或密码错误'"},
    {"action": "验证密码框被清空"},
    {"action": "验证仍停留在登录页"}
  ],
  "verify": [
    "errorLabel.isHidden == false",
    "passwordTextField.text == \"\"",
    "navigationController.topViewController == LoginViewController"
  ]
}
```

#### 1.3 登录失败 - 空输入
```json
{
  "scenario": "login_failed_empty_input",
  "description": "用户名或密码为空",
  "testCases": [
    {"username": "", "password": "123456"},
    {"username": "test", "password": ""},
    {"username": "", "password": ""}
  ],
  "expectedBehavior": "ViewModel 验证失败，返回 nil，显示通用错误信息"
}
```

#### 1.4 防重复提交
```json
{
  "scenario": "login_prevent_double_submit",
  "description": "快速连续点击登录按钮，第二次点击应被忽略",
  "steps": [
    {"action": "输入有效凭据"},
    {"action": "快速双击登录按钮（间隔 < 100ms）"},
    {"action": "检查日志只有一次 '登录按钮点击'"},
    {"action": "等待 loading 结束"},
    {"action": "验证只发送一次登录请求"}
  ],
  "verify": "isLoading 同步守卫生效"
}
```

---

### 场景 2：注册流程

#### 2.1 正常注册
```json
{
  "scenario": "register_success",
  "description": "创建新账号成功",
  "steps": [
    {
      "action": "从登录页点击 goto_register_button",
      "verify": "跳转到注册页，title='注册'"
    },
    {
      "action": "ui.inspect",
      "verify": "找到 register_username_field、register_email_field、register_password_field、register_confirm_password_field"
    },
    {
      "action": "填写表单",
      "params": {
        "username": "newuser",
        "email": "newuser@example.com",
        "password": "password123",
        "confirmPassword": "password123"
      }
    },
    {
      "action": "点击 register_button"
    },
    {
      "action": "等待 loading（1.5秒）"
    },
    {
      "action": "ui.alert.getVisible",
      "verify": "显示 alert，title='注册成功'，message='账号创建成功，请使用新账号登录'"
    },
    {
      "action": "ui.alert.respond",
      "params": {"buttonTitle": "确定"},
      "verify": "点击确定后返回登录页"
    }
  ],
  "expectedResult": {
    "navigation": "返回 LoginViewController",
    "logs": ["✅ 注册成功: username=newuser, email=newuser@example.com"]
  }
}
```

#### 2.2 注册失败 - 验证错误
```json
{
  "scenario": "register_validation_errors",
  "description": "各种验证失败场景",
  "testCases": [
    {
      "case": "邮箱格式错误",
      "input": {
        "username": "user1",
        "email": "invalid-email",
        "password": "123456",
        "confirmPassword": "123456"
      },
      "expectedError": "邮箱格式不正确"
    },
    {
      "case": "密码过短",
      "input": {
        "username": "user2",
        "email": "user2@example.com",
        "password": "12345",
        "confirmPassword": "12345"
      },
      "expectedError": "密码长度至少为6位"
    },
    {
      "case": "两次密码不一致",
      "input": {
        "username": "user3",
        "email": "user3@example.com",
        "password": "123456",
        "confirmPassword": "123457"
      },
      "expectedError": "两次密码输入不一致"
    },
    {
      "case": "用户名已存在",
      "input": {
        "username": "test",
        "email": "test2@example.com",
        "password": "123456",
        "confirmPassword": "123456"
      },
      "expectedError": "用户名已存在"
    }
  ],
  "verify": "register_error_label 显示对应错误信息"
}
```

#### 2.3 注册成功后登录验证
```json
{
  "scenario": "register_then_login",
  "description": "注册成功后使用新账号登录",
  "steps": [
    {"action": "注册新账号 'testuser' / 'test@test.com' / '123456'"},
    {"action": "点击 alert 确定，返回登录页"},
    {"action": "使用新账号登录"},
    {"action": "验证登录成功"}
  ],
  "expectedResult": "新账号可以正常登录并跳转到首页"
}
```

---

### 场景 3：重置密码流程

#### 3.1 正常重置密码
```json
{
  "scenario": "reset_password_success",
  "description": "成功重置预置账号密码",
  "steps": [
    {
      "action": "从登录页点击 goto_reset_password_button",
      "verify": "跳转到重置密码页，title='重置密码'"
    },
    {
      "action": "ui.inspect",
      "verify": "找到 reset_username_field、reset_email_field、reset_new_password_field、reset_confirm_password_field"
    },
    {
      "action": "填写表单",
      "params": {
        "username": "test",
        "email": "test@example.com",
        "newPassword": "newpass123",
        "confirmPassword": "newpass123"
      }
    },
    {
      "action": "点击 reset_password_button"
    },
    {
      "action": "等待 loading（1.5秒）"
    },
    {
      "action": "ui.alert.getVisible",
      "verify": "显示 alert，title='重置成功'，message='密码已重置，请使用新密码登录'"
    },
    {
      "action": "ui.alert.respond",
      "params": {"buttonTitle": "确定"},
      "verify": "返回登录页"
    },
    {
      "action": "使用新密码登录",
      "params": {"username": "test", "password": "newpass123"},
      "verify": "登录成功"
    }
  ],
  "expectedResult": {
    "navigation": "返回 LoginViewController",
    "logs": ["✅ 密码重置成功: username=test"],
    "passwordChanged": true
  }
}
```

#### 3.2 重置密码失败 - 验证错误
```json
{
  "scenario": "reset_password_validation_errors",
  "description": "各种验证失败场景",
  "testCases": [
    {
      "case": "用户不存在",
      "input": {
        "username": "nonexistent",
        "email": "test@example.com",
        "newPassword": "123456",
        "confirmPassword": "123456"
      },
      "expectedError": "用户名或邮箱不正确"
    },
    {
      "case": "邮箱不匹配",
      "input": {
        "username": "test",
        "email": "wrong@example.com",
        "newPassword": "123456",
        "confirmPassword": "123456"
      },
      "expectedError": "用户名或邮箱不正确"
    },
    {
      "case": "新密码过短",
      "input": {
        "username": "test",
        "email": "test@example.com",
        "newPassword": "12345",
        "confirmPassword": "12345"
      },
      "expectedError": "密码长度至少为6位"
    },
    {
      "case": "两次密码不一致",
      "input": {
        "username": "test",
        "email": "test@example.com",
        "newPassword": "123456",
        "confirmPassword": "123457"
      },
      "expectedError": "两次密码输入不一致"
    }
  ],
  "verify": "reset_password_error_label 显示对应错误信息"
}
```

---

## 四、UI 状态验证清单

### 通用加载状态
```json
{
  "loadingState": {
    "during": {
      "button.title": "",
      "button.isEnabled": false,
      "loadingIndicator.isAnimating": true
    },
    "after": {
      "button.title": "恢复原文本",
      "button.isEnabled": true,
      "loadingIndicator.isAnimating": false
    }
  }
}
```

### 错误显示状态
```json
{
  "errorState": {
    "whenError": {
      "errorLabel.isHidden": false,
      "errorLabel.text": "具体错误信息",
      "errorLabel.textColor": ".systemRed"
    },
    "whenSuccess": {
      "errorLabel.isHidden": true
    }
  }
}
```

### 导航流程
```json
{
  "navigation": {
    "loginToRegister": "push RegisterViewController",
    "loginToResetPassword": "push ResetPasswordViewController",
    "registerToLogin": "pop to LoginViewController",
    "resetPasswordToLogin": "pop to LoginViewController",
    "loginToHome": "setViewControllers [HomeViewController] (替换栈)"
  }
}
```

---

## 五、边界条件测试

### 5.1 网络延迟模拟
```json
{
  "scenario": "network_delay_handling",
  "description": "模拟 1.5 秒网络延迟",
  "verify": [
    "loading indicator 在延迟期间持续显示",
    "用户无法重复点击按钮（isLoading 守卫生效）",
    "延迟结束后正确更新 UI 状态"
  ]
}
```

### 5.2 键盘处理
```json
{
  "scenario": "keyboard_handling",
  "description": "验证键盘交互",
  "steps": [
    {"action": "点击输入框", "verify": "键盘弹起"},
    {"action": "点击登录/注册按钮", "verify": "view.endEditing(true) 收起键盘"},
    {"action": "在 scrollView 中滚动", "verify": "内容可滚动避免键盘遮挡"}
  ]
}
```

### 5.3 输入框状态
```json
{
  "scenario": "textfield_properties",
  "verify": {
    "username": {
      "autocapitalizationType": ".none",
      "autocorrectionType": ".no"
    },
    "email": {
      "keyboardType": ".emailAddress",
      "autocapitalizationType": ".none"
    },
    "password": {
      "isSecureTextEntry": true
    }
  }
}
```

### 5.4 Alert 弹窗边界
```json
{
  "scenario": "alert_presenter_fallback",
  "description": "验证 VC 被 pop 后 alert 的 presenter 回退逻辑",
  "steps": [
    {"action": "快速点击注册按钮后立即返回"},
    {"action": "等待注册成功"},
    {"verify": "alert 在 keyWindow.rootViewController 上显示，不会静默失败"}
  ],
  "relatedIssues": ["F-20", "F-21"]
}
```

---

## 六、日志验证点

### 成功日志
```
🔐 AuthService 初始化完成，预置测试账号: test
🔵 LoginViewController viewDidLoad
🔵 登录按钮点击
📤 开始登录请求: username=test
✅ 登录成功: username=test, token=<UUID>
✅ 登录成功，跳转到首页: username=test
```

### 失败日志
```
⚠️ 登录失败（用户不存在）: username=nonexistent
⚠️ 登录失败（密码错误）: username=test
⚠️ 显示错误信息: 用户名或密码错误
```

---

## 七、测试执行命令模板

### 使用 iOSExplore 命令驱动测试
```bash
# 1. 检查登录页结构
curl -X POST http://localhost:38321/ \
  -d '{"action":"ui.inspect","maxDepth":3,"accessibilityIdentifierPrefix":"login_"}'

# 2. 输入用户名
curl -X POST http://localhost:38321/ \
  -d '{"action":"ui.control.setValue","accessibilityIdentifier":"login_username_field","value":"test"}'

# 3. 输入密码
curl -X POST http://localhost:38321/ \
  -d '{"action":"ui.control.setValue","accessibilityIdentifier":"login_password_field","value":"123456"}'

# 4. 点击登录按钮
curl -X POST http://localhost:38321/ \
  -d '{"action":"ui.tap","accessibilityIdentifier":"login_button"}'

# 5. 等待跳转
curl -X POST http://localhost:38321/ \
  -d '{"action":"ui.wait","mode":"textExists","text":"欢迎","timeoutMs":3000}'

# 6. 验证首页
curl -X POST http://localhost:38321/ \
  -d '{"action":"ui.inspect","maxDepth":2}'
```

---

## 八、测试覆盖率目标

| 流程 | 正常路径 | 异常路径 | 边界条件 | UI 状态 |
|------|---------|---------|----------|---------|
| 登录 | ✅ | ✅ | ✅ | ✅ |
| 注册 | ✅ | ✅ | ✅ | ✅ |
| 重置密码 | ✅ | ✅ | ✅ | ✅ |

**目标覆盖率**：
- 代码覆盖率：≥ 85%
- 场景覆盖率：100%（所有正常/异常路径）
- UI 元素覆盖率：100%（所有可交互元素）

---

## 九、使用说明

这份提示词可用于：

1. **人工测试指南**：按照场景描述手动执行测试
2. **自动化测试数据源**：JSON 格式的步骤可直接解析为测试脚本
3. **CI/CD 集成**：作为持续集成流程的测试用例定义
4. **Agent 测试驱动**：配合 `/ios-test-runner` skill 自动执行

### 快速开始

```bash
# 1. 启动示例 App（模拟器）
cd /Users/coo/Desktop/iOS_agent_debugger/iOSExploreServer
./scripts/proxy.sh --status  # 确保端口空闲

# 2. 使用 XcodeBuildMCP 启动
session_use_defaults_profile("sim-app")
build_run_sim()
launch_app_sim(env: {"IOS_EXPLORE_SHOW_LOGIN": "1"})

# 3. 验证服务
curl -X POST http://localhost:38321/ -d '{"action":"ping"}'

# 4. 开始测试
# 按照本文档的场景 1.1 开始执行登录测试
```

### 测试优先级

**P0 - 核心流程（必须通过）**：
- 场景 1.1：正常登录
- 场景 2.1：正常注册
- 场景 3.1：正常重置密码

**P1 - 异常处理（高优先级）**：
- 场景 1.2：登录失败 - 错误凭据
- 场景 2.2：注册失败 - 验证错误
- 场景 3.2：重置密码失败 - 验证错误

**P2 - 边界条件（中优先级）**：
- 场景 1.3：登录失败 - 空输入
- 场景 1.4：防重复提交
- 第五章所有边界条件测试

---

## 十、相关文档

- **项目文档**：`/Users/coo/Desktop/iOS_agent_debugger/iOSExploreServer/AGENTS.md`
- **Skills 文档**：`/Users/coo/Desktop/iOS_agent_debugger/iOSExploreServer/docs/skills/`
- **认证服务实现**：`Examples/SPMExample/SPMExample/Login/Services/AuthService.swift`
- **登录 VC**：`Examples/SPMExample/SPMExample/Login/ViewControllers/LoginViewController.swift`
- **注册 VC**：`Examples/SPMExample/SPMExample/Login/ViewControllers/RegisterViewController.swift`
- **重置密码 VC**：`Examples/SPMExample/SPMExample/Login/ViewControllers/ResetPasswordViewController.swift`
