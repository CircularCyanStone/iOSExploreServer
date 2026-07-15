# 快速开始指南

## 1. 启动应用（模拟器）

```bash
# 使用 XcodeBuildMCP 启动（推荐）
# 首先设置 profile
session_use_defaults_profile("sim-app")

# 构建并运行
build_run_sim()

# 启动 App（可选：显示登录界面）
launch_app_sim(env={
    "IOS_EXPLORE_SHOW_LOGIN": "1"
})

# Server 会在 DEBUG 环境自动启动（viewDidAppear 中执行）
```

## 2. 基础测试

### 测试账号
- 用户名：`test`
- 密码：`123456`

### 快速登录测试

```bash
# 1. 输入用户名
curl -X POST http://localhost:38321/ -d '{
  "action": "ui.input",
  "data": {"accessibilityIdentifier": "login_username_field", "text": "test"}
}'

# 2. 输入密码
curl -X POST http://localhost:38321/ -d '{
  "action": "ui.input",
  "data": {"accessibilityIdentifier": "login_password_field", "text": "123456"}
}'

# 3. 点击登录
curl -X POST http://localhost:38321/ -d '{
  "action": "ui.tap",
  "data": {"accessibilityIdentifier": "login_button"}
}'

# 4. 等待 3 秒（网络延迟 1.5s + UI 转场）
sleep 3

# 5. 验证首页
curl -X POST http://localhost:38321/ -d '{
  "action": "ui.inspect",
  "data": {}
}' | jq '.data.full[] | select(.accessibilityIdentifier == "home_username_label")'
```

## 3. 运行完整测试套件

```bash
cd Examples/SPMExample
./test_login_flow.sh
```

## 4. 查看日志

```bash
# 实时查看日志
log stream --predicate 'subsystem == "com.coo.SPMExample"' --level debug

# 或在 Console.app 中筛选 "SPMExample"
```

## 5. 关键 Accessibility Identifiers

### 登录页面
- `login_username_field` - 用户名输入框
- `login_password_field` - 密码输入框
- `login_button` - 登录按钮
- `login_error_label` - 错误提示
- `goto_register_button` - 去注册
- `goto_reset_password_button` - 忘记密码

### 首页
- `home_username_label` - 用户名显示
- `home_logout_button` - 退出登录按钮

完整列表见 `LOGIN_TESTING_GUIDE.md`

## 6. 常用测试场景

### 场景 1：完整注册流程
```bash
./test_login_flow.sh
# 或查看脚本内容，复制相关命令
```

### 场景 2：错误处理（密码错误）
```bash
curl -X POST http://localhost:38321/ -d '{"action":"ui.input","data":{"accessibilityIdentifier":"login_username_field","text":"test"}}'
curl -X POST http://localhost:38321/ -d '{"action":"ui.input","data":{"accessibilityIdentifier":"login_password_field","text":"wrong"}}'
curl -X POST http://localhost:38321/ -d '{"action":"ui.tap","data":{"accessibilityIdentifier":"login_button"}}'
sleep 2
# 应该看到 "用户名或密码错误"
curl -X POST http://localhost:38321/ -d '{"action":"ui.inspect","data":{}}' | jq '.data.full[] | select(.accessibilityIdentifier == "login_error_label")'
```

### 场景 3：模拟网络错误
在启动 App 前，修改代码设置失败率：
```swift
// 在 AuthService.swift 的 init() 中添加
self.simulateFailureRate = 0.5  // 50% 失败率
```

## 7. 使用 iOS Automation Skills

```bash
# 自动化登录
/ios-automation 在 SPMExample 登录页面，用户名填写 test，密码填写 123456，然后点击登录按钮

# 表单填充
/ios-form-filling 填写登录表单，用户名 test，密码 123456

# Alert 处理
/ios-alert-handling 确认退出登录对话框
```

## 8. 故障排查

### 问题：ui.input 无响应
**解决**：检查 `accessibilityIdentifier` 是否正确，使用 `ui.inspect` 确认

### 问题：点击按钮后无反应
**解决**：等待足够时间（网络延迟 1.5s），检查日志输出

### 问题：看不到登录界面
**解决**：确认启动时设置了环境变量 `IOS_EXPLORE_SHOW_LOGIN=1`

### 问题：找不到某个元素
**解决**：运行 `ui.inspect` 查看完整界面结构

## 9. 下一步

- 阅读 `LOGIN_TESTING_GUIDE.md` 了解完整 API
- 查看 `README.md` 了解架构设计
- 修改 `AuthService.swift` 自定义测试数据
- 扩展新的测试场景

---

**提示**：所有命令都假设 App 已启动并且 server 在 38321 端口运行。
