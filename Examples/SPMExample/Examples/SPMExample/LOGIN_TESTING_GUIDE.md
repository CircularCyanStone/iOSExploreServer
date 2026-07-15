# 登录流程测试模块

## 概述

在 `SPMExample/Login/` 目录下创建了一套完整的登录流程，用于测试 MCP 和 iOS automation skills。

## 文件结构

```
SPMExample/Login/
├── Models/
│   ├── User.swift                      # 用户模型
│   └── AuthResponse.swift              # 认证响应模型
├── Services/
│   └── AuthService.swift               # 模拟认证服务
├── ViewModels/
│   ├── LoginViewModel.swift            # 登录视图模型
│   ├── RegisterViewModel.swift         # 注册视图模型
│   ├── ResetPasswordViewModel.swift    # 重置密码视图模型
│   └── HomeViewModel.swift             # 首页视图模型
└── ViewControllers/
    ├── LoginViewController.swift       # 登录界面
    ├── RegisterViewController.swift    # 注册界面
    ├── ResetPasswordViewController.swift # 重置密码界面
    └── HomeViewController.swift        # 首页
```

## 功能特性

### 1. 认证服务 (AuthService)

- **模拟网络延迟**：1.5 秒延迟模拟真实网络请求
- **预置测试账号**：`test` / `123456`
- **完整日志输出**：使用 OSLog 输出所有操作的成功/失败日志
- **可配置失败率**：`simulateFailureRate` 属性可模拟网络错误
- **验证逻辑**：
  - 邮箱格式验证
  - 密码强度验证（至少 6 位）
  - 用户重复检查

### 2. 界面流程

```
LoginViewController (登录)
    ├─→ RegisterViewController (注册)
    ├─→ ResetPasswordViewController (重置密码)
    └─→ HomeViewController (首页)
            └─→ 退出登录 → LoginViewController
```

### 3. MVVM 架构

- **Model**：`User`、`AuthResponse`、`AuthError`
- **ViewModel**：处理业务逻辑，管理状态（loading、error）
- **ViewController**：纯 UIKit 界面，包含完整的 accessibilityIdentifier

### 4. Accessibility Identifiers（用于 MCP 测试）

#### 登录界面
- `login_scroll_view` - 滚动视图
- `login_title` - 标题
- `login_username_field` - 用户名输入框
- `login_password_field` - 密码输入框
- `login_button` - 登录按钮
- `login_error_label` - 错误提示
- `goto_register_button` - 跳转注册按钮
- `goto_reset_password_button` - 忘记密码按钮

#### 注册界面
- `register_scroll_view` - 滚动视图
- `register_title` - 标题
- `register_username_field` - 用户名输入框
- `register_email_field` - 邮箱输入框
- `register_password_field` - 密码输入框
- `register_confirm_password_field` - 确认密码输入框
- `register_button` - 注册按钮
- `register_error_label` - 错误提示
- `back_to_login_button` - 返回登录按钮

#### 重置密码界面
- `reset_password_scroll_view` - 滚动视图
- `reset_password_title` - 标题
- `reset_username_field` - 用户名输入框
- `reset_email_field` - 邮箱输入框
- `reset_new_password_field` - 新密码输入框
- `reset_confirm_password_field` - 确认密码输入框
- `reset_password_button` - 重置密码按钮
- `reset_password_error_label` - 错误提示
- `back_to_login_from_reset_button` - 返回登录按钮

#### 首页
- `home_scroll_view` - 滚动视图
- `home_welcome_label` - 欢迎标题
- `home_username_label` - 用户名显示
- `home_email_label` - 邮箱显示
- `home_user_id_label` - 用户 ID 显示
- `home_refresh_button` - 刷新按钮
- `home_logout_button` - 退出登录按钮

## 启动配置

### 方式 1：环境变量

```bash
IOS_EXPLORE_SHOW_LOGIN=1
```

### 方式 2：启动参数

```bash
--ios-explore-show-login
```

### 方式 3：UserDefaults

```swift
UserDefaults.standard.set(true, forKey: "ios_explore_show_login")
```

## 测试场景

### 1. 成功登录流程

```bash
# 使用 MCP 工具测试
curl -X POST http://localhost:38321/ -d '{
  "action": "ui.input",
  "data": {
    "accessibilityIdentifier": "login_username_field",
    "text": "test"
  }
}'

curl -X POST http://localhost:38321/ -d '{
  "action": "ui.input",
  "data": {
    "accessibilityIdentifier": "login_password_field",
    "text": "123456"
  }
}'

curl -X POST http://localhost:38321/ -d '{
  "action": "ui.tap",
  "data": {
    "accessibilityIdentifier": "login_button"
  }
}'
```

### 2. 注册新用户流程

```bash
# 1. 点击"去注册"按钮
curl -X POST http://localhost:38321/ -d '{
  "action": "ui.tap",
  "data": {"accessibilityIdentifier": "goto_register_button"}
}'

# 2. 填写注册信息
curl -X POST http://localhost:38321/ -d '{
  "action": "ui.input",
  "data": {"accessibilityIdentifier": "register_username_field", "text": "newuser"}
}'

curl -X POST http://localhost:38321/ -d '{
  "action": "ui.input",
  "data": {"accessibilityIdentifier": "register_email_field", "text": "newuser@example.com"}
}'

curl -X POST http://localhost:38321/ -d '{
  "action": "ui.input",
  "data": {"accessibilityIdentifier": "register_password_field", "text": "password123"}
}'

curl -X POST http://localhost:38321/ -d '{
  "action": "ui.input",
  "data": {"accessibilityIdentifier": "register_confirm_password_field", "text": "password123"}
}'

# 3. 点击注册按钮
curl -X POST http://localhost:38321/ -d '{
  "action": "ui.tap",
  "data": {"accessibilityIdentifier": "register_button"}
}'
```

### 3. 重置密码流程

```bash
# 1. 点击"忘记密码"
curl -X POST http://localhost:38321/ -d '{
  "action": "ui.tap",
  "data": {"accessibilityIdentifier": "goto_reset_password_button"}
}'

# 2. 填写重置信息
curl -X POST http://localhost:38321/ -d '{
  "action": "ui.input",
  "data": {"accessibilityIdentifier": "reset_username_field", "text": "test"}
}'

curl -X POST http://localhost:38321/ -d '{
  "action": "ui.input",
  "data": {"accessibilityIdentifier": "reset_email_field", "text": "test@example.com"}
}'

curl -X POST http://localhost:38321/ -d '{
  "action": "ui.input",
  "data": {"accessibilityIdentifier": "reset_new_password_field", "text": "newpass123"}
}'

curl -X POST http://localhost:38321/ -d '{
  "action": "ui.input",
  "data": {"accessibilityIdentifier": "reset_confirm_password_field", "text": "newpass123"}
}'

# 3. 点击重置按钮
curl -X POST http://localhost:38321/ -d '{
  "action": "ui.tap",
  "data": {"accessibilityIdentifier": "reset_password_button"}
}'
```

### 4. 退出登录

```bash
curl -X POST http://localhost:38321/ -d '{
  "action": "ui.tap",
  "data": {"accessibilityIdentifier": "home_logout_button"}
}'

# 确认对话框
curl -X POST http://localhost:38321/ -d '{
  "action": "ui.alert.respond",
  "data": {"buttonTitle": "退出"}
}'
```

## 错误场景测试

### 1. 用户名或密码为空

- 输入空用户名或密码，点击登录
- 预期：显示 "请输入用户名" 或 "请输入密码" 错误

### 2. 用户名或密码错误

- 输入 `test` / `wrong_password`
- 预期：显示 "用户名或密码错误"

### 3. 密码强度不足

- 注册时输入少于 6 位的密码
- 预期：显示 "密码强度不足（至少6位）"

### 4. 两次密码不一致

- 注册或重置密码时，两次输入不同
- 预期：显示 "两次密码输入不一致"

### 5. 邮箱格式错误

- 输入无效邮箱格式（如 `test`）
- 预期：显示 "邮箱格式不正确"

### 6. 用户已存在

- 尝试注册已存在的用户名（如 `test`）
- 预期：显示 "用户已存在"

### 7. 模拟网络错误

```swift
// 在测试前设置失败率
AuthService.shared.simulateFailureRate = 0.5  // 50% 失败率
```

## 日志输出示例

### 成功登录
```
🔐 AuthService 初始化完成，预置测试账号: test/123456
🔵 LoginViewController viewDidLoad
🔵 登录按钮点击
🔵 开始登录流程: username=test
📤 开始登录请求: username=test
✅ 登录成功: username=test, token=XXX
✅ 登录成功，跳转到首页: username=test
```

### 登录失败
```
🔵 开始登录流程: username=test
📤 开始登录请求: username=test
⚠️ 登录失败（密码错误）: username=test
❌ 登录失败: 用户名或密码错误
⚠️ 显示错误信息: 用户名或密码错误
```

## 与现有测试界面的集成

- 默认情况下，启动 App 仍显示原有的测试界面（`ViewController`）
- 只有设置了启动参数/环境变量时，才会显示登录界面
- 这样不影响现有的其他测试功能

## 使用 iOS Automation Skills 测试

```bash
# 使用 /ios-automation skill
/ios-automation 登录到 SPMExample，用户名 test，密码 123456

# 使用 /ios-form-filling skill
/ios-form-filling 在登录页面填写用户名 test 和密码 123456

# 使用 /ios-alert-handling skill（处理退出确认）
/ios-alert-handling 确认退出登录对话框
```

## 技术要点

1. **Swift 6.2 严格并发**：所有 ViewModel 标记为 `@MainActor`
2. **异步网络请求**：使用 `async/await` 模拟网络延迟
3. **完整的错误处理**：自定义 `AuthError` 枚举
4. **日志记录**：使用 OSLog 而非 print
5. **内存管理**：使用 `[weak self]` 避免循环引用
6. **UI 更新**：所有 UI 更新在主线程执行

## 后续扩展

可以基于此模块测试：

1. 表单自动填充
2. 键盘交互（显示/隐藏）
3. 滚动和导航
4. Alert 处理
5. 网络请求等待
6. 错误状态处理
7. 多步骤流程自动化
