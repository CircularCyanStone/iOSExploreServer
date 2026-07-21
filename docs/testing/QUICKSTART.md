# XCUITest 快速参考

**快速启动**: 5 分钟上手 XCUITest

---

## 快速设置（首次使用）

```bash
# 1. 打开 Xcode 项目
open Examples/SPMExample/SPMExample.xcodeproj

# 2. 在 Xcode 中创建 UI Test target
#    File → New → Target → UI Testing Bundle
#    Name: SPMExampleUITests
#    详细步骤见: docs/testing/xcuitest-guide.md

# 3. 验证配置
cd Examples/SPMExample
xcodebuild -list -project SPMExample.xcodeproj
# 应该看到 SPMExampleUITests 在 Targets 列表中
```

---

## 快速运行

```bash
# 列出可用设备
./scripts/run-uitests.sh

# 模拟器 - 运行所有测试
./scripts/run-uitests.sh --simulator "iPhone 17"

# 真机 - 运行所有测试
./scripts/run-uitests.sh --device-id <UDID>

# 只运行登录测试
./scripts/run-uitests.sh --simulator "iPhone 17" --test-class LoginFlowTests

# 只运行单个测试
./scripts/run-uitests.sh --simulator "iPhone 17" --test testSuccessfulLogin
```

---

## 测试清单

### LoginFlowTests（8 个测试，~32s）

| 测试 | 验证点 | 时间 |
|------|--------|------|
| `testSuccessfulLogin` | 成功登录流程 | ~4.5s |
| `testLoginFailure_UserNotFound` | 用户不存在错误 | ~3.0s |
| `testLoginFailure_WrongPassword` | 密码错误处理 | ~3.0s |
| `testLoginButtonLoadingState` | 加载状态显示 | ~4.5s |
| `testNavigateToRegister` | 导航到注册页 | ~1.0s |
| `testNavigateToResetPassword` | 导航到重置密码 | ~1.0s |
| `testLogoutFlow` | 退出登录流程 | ~6.0s |
| `testCancelLogout` | 取消退出登录 | ~6.0s |

### SystemAlertMonitorTests（5 个示例）

⚠️ **示例性质**：SPMExample 不请求权限，测试会通过但不触发实际弹窗

---

## 真机测试清单

```bash
# 1. 获取设备 UDID
xcrun xctrace list devices

# 2. 确认设备状态
# ✅ 设备已信任此电脑
# ✅ 开发者模式已启用（设置 → 隐私与安全 → 开发者模式）
# ✅ iOS 版本 ≥ 26.2

# 3. （可选）启动 iproxy（如需与 iOSExploreServer 通信）
iproxy 38321 38321

# 4. 运行测试
./scripts/run-uitests.sh --device-id <UDID>
```

---

## 在 Xcode 中运行

1. 打开 `Examples/SPMExample/SPMExample.xcodeproj`
2. 选择 scheme: **SPMExample**
3. 选择目标设备（模拟器或真机）
4. 打开测试文件，点击方法左侧的 ◆ 图标
5. 或按 **Cmd + U** 运行所有测试

---

## 常见问题速查

### ❌ 找不到 UITests target

**原因**: 尚未在 Xcode 中创建 UITests target  
**解决**: 参考 `docs/testing/xcuitest-guide.md`

### ❌ 测试超时 - "Failed to find element"

**原因**: 元素未出现或 `accessibilityIdentifier` 错误  
**解决**: 增加 `waitForExistence(timeout:)` 或检查标识符

### ❌ 真机测试失败 - "Failed to install"

**原因**: 代码签名或设备配置问题  
**解决**:
1. 确保设备已信任此电脑
2. 确保开发者模式已启用
3. 检查 UITests target 的签名配置

### ❌ iproxy 端口占用

**原因**: 模拟器残留的 SPMExample 进程占用 38321  
**解决**:
```bash
# 检查占用进程
lsof -iTCP:38321

# 如果是 SPMExampl，清理模拟器残留
xcrun simctl terminate booted com.coo.SPMExample

# 停止旧 iproxy 后重新前台启动
pkill -x iproxy
iproxy 38321 38321
```

---

## 文件位置

| 文件 | 说明 |
|------|------|
| `Examples/SPMExample/SPMExampleUITests/LoginFlowTests.swift` | 登录流程测试 |
| `Examples/SPMExample/SPMExampleUITests/SystemAlertMonitorTests.swift` | 系统弹窗示例 |
| `scripts/run-uitests.sh` | 自动化运行脚本 |
| `docs/testing/xcuitest-guide.md` | 完整使用指南（架构、原理、FAQ） |
| `docs/testing/xcuitest-guide.md` | 完整使用与排障指南 |

---

## 测试账号

| 用户名 | 密码 | 说明 |
|-------|------|------|
| test | 123456 | 预置测试账号（AuthService.swift:31） |

---

## 与 iOSExploreServer 组合使用

```swift
// XCUITest 测试代码
func testWithServerVerification() throws {
    // 1. XCUITest 驱动登录
    app.textFields["login_username_field"].tap()
    app.textFields["login_username_field"].typeText("test")
    app.buttons["login_button"].tap()
    
    // 2. 使用 iOSExploreServer 验证状态
    let url = URL(string: "http://localhost:38321/")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.httpBody = #"{"action":"ui.topViewHierarchy"}"#.data(using: .utf8)
    
    let (data, _) = try await URLSession.shared.data(for: request)
    // 验证内部状态
}
```

---

## 下一步

1. ✅ 创建 UITests target（5 分钟）
2. ✅ 模拟器验证（2 分钟）
3. ✅ 真机验证（3 分钟）
4. ⬜ 扩展测试用例
5. ⬜ 集成到 CI/CD

---

**完整文档**: `docs/testing/xcuitest-guide.md`
