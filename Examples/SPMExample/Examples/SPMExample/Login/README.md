# Login 模块 - 完整登录流程测试框架

## 概述

为 SPMExample 创建了一套完整的登录流程测试模块，用于测试 iOS MCP 和 automation skills。包含登录、注册、重置密码、首页四个界面，采用 MVVM 架构，带完整的日志输出和错误处理。

## 快速开始

### 1. 启动应用并展示登录界面

```bash
# 方式 1: 使用环境变量
IOS_EXPLORE_SHOW_LOGIN=1 IOS_EXPLORE_AUTOSTART=1 xcodebuild -project SPMExample.xcodeproj ...

# 方式 2: 使用启动参数
# 在 Xcode scheme 的 Arguments 中添加：
--ios-explore-show-login
--ios-explore-autostart
```

### 2. 运行自动化测试脚本

```bash
# 确保 App 已启动并且 iproxy 在运行
cd Examples/SPMExample
./test_login_flow.sh
```

### 3. 手动测试

**预置测试账号**：
- 用户名：`test`
- 密码：`123456`

## 文件结构

```
SPMExample/Login/
├── Models/                    # 数据模型
│   ├── User.swift
│   └── AuthResponse.swift
├── Services/                  # 业务服务
│   └── AuthService.swift      # 模拟认证服务（带网络延迟和日志）
├── ViewModels/                # 视图模型（MVVM）
│   ├── LoginViewModel.swift
│   ├── RegisterViewModel.swift
│   ├── ResetPasswordViewModel.swift
│   └── HomeViewModel.swift
└── ViewControllers/           # 视图控制器（UIKit）
    ├── LoginViewController.swift
    ├── RegisterViewController.swift
    ├── ResetPasswordViewController.swift
    └── HomeViewController.swift
```

## 核心特性

### 1. 模拟认证服务 (AuthService)

- ✅ **网络延迟模拟**：1.5 秒延迟
- ✅ **预置账号**：test/123456
- ✅ **完整日志**：OSLog 输出所有操作
- ✅ **错误模拟**：可配置失败率
- ✅ **输入验证**：
  - 邮箱格式验证
  - 密码强度验证（≥6位）
  - 用户重复检查

### 2. 界面导航流程

```
LoginViewController
  ├─→ RegisterViewController → 注册成功 → LoginViewController
  ├─→ ResetPasswordViewController → 重置成功 → LoginViewController
  └─→ HomeViewController
        └─→ 退出登录 → LoginViewController
```

### 3. Accessibility Identifiers

所有交互元素都有 `accessibilityIdentifier`，方便 MCP 自动化测试：

- **登录页**：`login_username_field`, `login_password_field`, `login_button`, ...
- **注册页**：`register_username_field`, `register_email_field`, `register_button`, ...
- **重置密码页**：`reset_username_field`, `reset_new_password_field`, ...
- **首页**：`home_username_label`, `home_logout_button`, ...

完整列表见 `LOGIN_TESTING_GUIDE.md`。

## 测试场景

### 基础流程测试

1. ✅ **成功登录**：使用预置账号 test/123456
2. ✅ **注册新用户**：完整注册流程
3. ✅ **重置密码**：修改已存在用户的密码
4. ✅ **退出登录**：从首页退出到登录页

### 错误场景测试

1. ✅ **空输入验证**：用户名/密码为空
2. ✅ **密码不一致**：两次密码输入不同
3. ✅ **密码强度不足**：少于 6 位
4. ✅ **邮箱格式错误**：无效邮箱
5. ✅ **用户已存在**：注册重复用户名
6. ✅ **登录失败**：错误的用户名或密码
7. ✅ **网络错误模拟**：可配置失败率

## 使用 MCP 测试

### 基础命令

```bash
# 输入文本
curl -X POST http://localhost:38321/ -d '{
  "action": "ui.input",
  "data": {
    "accessibilityIdentifier": "login_username_field",
    "text": "test"
  }
}'

# 点击按钮
curl -X POST http://localhost:38321/ -d '{
  "action": "ui.tap",
  "data": {"accessibilityIdentifier": "login_button"}
}'

# 处理 Alert
curl -X POST http://localhost:38321/ -d '{
  "action": "ui.alert.respond",
  "data": {"buttonTitle": "确定"}
}'

# 检查界面
curl -X POST http://localhost:38321/ -d '{
  "action": "ui.inspect",
  "data": {}
}'
```

### 使用 iOS Automation Skills

```bash
# 表单填充
/ios-form-filling 在登录页面填写用户名 test 和密码 123456

# Alert 处理
/ios-alert-handling 确认退出登录对话框

# 导航操作
/ios-navigation 返回到登录页面

# 截图验证
/ios-screenshot 截取当前页面
```

## 日志输出

所有操作都有详细的日志输出（使用 OSLog），可在 Console.app 中查看：

```
🔐 AuthService 初始化完成，预置测试账号: test/123456
🔵 LoginViewController viewDidLoad
🔵 登录按钮点击
🔵 开始登录流程: username=test
📤 开始登录请求: username=test
✅ 登录成功: username=test, token=XXX
✅ 登录成功，跳转到首页: username=test
🔵 HomeViewController 初始化: username=test
```

日志分类：
- 🔐 服务初始化
- 🔵 界面生命周期
- 📤 网络请求开始
- ✅ 操作成功
- ⚠️ 验证失败
- ❌ 网络错误

## 技术实现

### 架构模式

- **MVVM**：ViewModel 处理业务逻辑，ViewController 只负责 UI
- **依赖注入**：HomeViewController 通过构造函数接收 User
- **单例服务**：AuthService.shared 管理认证状态

### Swift 特性

- ✅ Swift 6.2 严格并发检查
- ✅ `@MainActor` 确保 UI 更新在主线程
- ✅ `async/await` 异步网络请求
- ✅ `Sendable` 协议确保跨并发域安全
- ✅ `@Published` 属性观察（Combine）
- ✅ `weak self` 避免循环引用

### 错误处理

```swift
enum AuthError: LocalizedError, Sendable {
    case invalidCredentials
    case userAlreadyExists
    case weakPassword
    case invalidEmail
    case networkError
    case serverError(String)
}
```

## 配置选项

### AuthService 配置

```swift
// 模拟网络延迟（秒）
AuthService.shared.networkDelay = 1.5

// 模拟失败率（0.0 - 1.0）
AuthService.shared.simulateFailureRate = 0.3  // 30% 失败率

// 查看所有用户
let users = AuthService.shared.getAllUsers()
```

### 启动配置

在 `SceneDelegate.swift` 中，通过以下方式控制显示登录界面：

1. 环境变量：`IOS_EXPLORE_SHOW_LOGIN=1`
2. 启动参数：`--ios-explore-show-login`
3. UserDefaults：`ios_explore_show_login`

## 文件说明

| 文件 | 说明 |
|------|------|
| `LOGIN_TESTING_GUIDE.md` | 详细的测试指南和 API 参考 |
| `test_login_flow.sh` | 自动化测试脚本 |
| `README.md` | 本文件 |

## 与现有功能集成

- ✅ 不影响现有测试界面（默认显示原 ViewController）
- ✅ 仅当设置启动参数时才显示登录界面
- ✅ 可与其他 UIKit 测试功能共存
- ✅ 使用相同的 iOSExploreServer 服务

## 后续扩展建议

可基于此模块测试：

1. **表单自动填充**：测试多字段表单的批量填充
2. **键盘交互**：测试键盘显示/隐藏、Return 键导航
3. **滚动行为**：测试长表单的滚动
4. **Loading 状态**：测试异步操作的加载指示器
5. **错误恢复**：测试网络错误后的重试
6. **会话管理**：测试 token 过期和刷新
7. **多设备测试**：在不同设备和方向上测试布局

## 常见问题

### Q: 为什么登录后看不到首页？

A: 检查日志输出，确认网络请求成功。默认有 1.5 秒延迟。

### Q: 如何添加新的测试账号？

A: 使用注册功能创建新账号，或在 `AuthService.init()` 中预置。

### Q: 如何查看完整日志？

A: 打开 Console.app，筛选进程 "SPMExample"，或使用 `log stream --predicate 'subsystem == "com.coo.SPMExample"'`

### Q: 如何模拟网络错误？

A: 设置 `AuthService.shared.simulateFailureRate = 0.5`（50% 失败率）

## 构建状态

✅ **构建成功**  
✅ **所有文件已添加到项目**  
✅ **文件系统同步组自动识别**

---

**创建时间**：2026-07-14  
**测试平台**：iOS 26.2+ / Xcode 17  
**架构**：MVVM + UIKit  
**用途**：MCP 和 iOS automation skills 测试
