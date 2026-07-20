# XCUITest 使用指南

本文档说明如何为 SPMExample 创建和运行 XCUITest 测试，验证真机和模拟器上的 UI 自动化能力。

---

## 目录

1. [XCUITest 架构](#xcuitest-架构)
2. [创建 UI Test Target](#创建-ui-test-target)
3. [运行测试](#运行测试)
4. [真机测试注意事项](#真机测试注意事项)
5. [与 iOSExploreServer 的关系](#与-iosexploreserver-的关系)
6. [系统弹窗处理](#系统弹窗处理)
7. [常见问题](#常见问题)

---

## XCUITest 架构

XCUITest 是 Apple 官方的 UI 自动化测试框架，基于 **双进程架构**：

```
┌─────────────────────┐         ┌──────────────────────┐
│   App 进程          │         │   Test 进程          │
│                     │         │                      │
│  SPMExample         │         │  SPMExampleUITests   │
│  (被测试的 App)     │ ◄─────► │  (测试代码)          │
│                     │  XPC    │                      │
└─────────────────────┘         └──────────────────────┘
         │                               │
         │                               │
         └───────────┬───────────────────┘
                     │
                     ▼
         ┌───────────────────────┐
         │   SpringBoard 进程     │
         │  (系统级弹窗)          │
         └───────────────────────┘
```

### 核心特点

1. **进程隔离**：
   - App 进程运行被测试的应用
   - Test 进程运行测试代码
   - 两个进程通过 XPC (跨进程通信) 交互

2. **黑盒测试**：
   - 测试代码只能通过 UI 元素与 App 交互
   - 无法直接访问 App 的内部状态、变量、方法
   - 所有操作必须通过 `XCUIApplication`、`XCUIElement` API

3. **系统级访问**：
   - 可以访问 SpringBoard 进程（系统界面）
   - 可以检测和操作系统弹窗（权限请求、通知授权等）

4. **真机支持**：
   - 支持在真机上运行测试
   - 需要代码签名和设备信任

---

## 创建 UI Test Target

SPMExample 项目当前**没有** UI Test target，需要手动创建。

### 步骤 1：在 Xcode 中创建 UI Test Target

1. 打开 `Examples/SPMExample/SPMExample.xcodeproj`
2. 选择菜单：**File → New → Target...**
3. 选择 **iOS → Test → UI Testing Bundle**
4. 配置：
   - **Product Name**: `SPMExampleUITests`
   - **Team**: 选择你的开发团队
   - **Organization Identifier**: `com.coo`
   - **Language**: Swift
   - **Project**: SPMExample
   - **Target to be Tested**: SPMExample
5. 点击 **Finish**

### 步骤 2：添加测试文件

Xcode 会自动创建一个默认测试文件 `SPMExampleUITests.swift`，删除它，使用仓库提供的测试文件：

```bash
# 测试文件已在仓库中
Examples/SPMExample/SPMExampleUITests/
├── LoginFlowTests.swift            # 登录流程测试
└── SystemAlertMonitorTests.swift   # 系统弹窗监听示例
```

在 Xcode 中：
1. 右键点击 `SPMExampleUITests` 组
2. 选择 **Add Files to "SPMExample"...**
3. 选中仓库中的两个测试文件
4. 确保 **Target Membership** 勾选了 `SPMExampleUITests`

### 步骤 3：配置签名

1. 选择 `SPMExampleUITests` target
2. 在 **Signing & Capabilities** 标签页
3. 设置 **Team** 和 **Bundle Identifier**
4. 确保 **Automatically manage signing** 已勾选

### 步骤 4：验证配置

构建测试 target：

```bash
cd Examples/SPMExample
xcodebuild build-for-testing \
    -project SPMExample.xcodeproj \
    -scheme SPMExample \
    -destination 'platform=iOS Simulator,name=iPhone 17'
```

如果构建成功，UI Test target 已正确配置。

---

## 运行测试

### 方法 1：使用提供的脚本（推荐）

```bash
# 列出可用设备
./scripts/run-uitests.sh

# 在 iPhone 17 模拟器上运行所有测试
./scripts/run-uitests.sh --simulator "iPhone 17"

# 在真机上运行测试
./scripts/run-uitests.sh --device-id 00008030-XXXXXXXXXXXX

# 只运行登录测试
./scripts/run-uitests.sh --simulator "iPhone 17" --test-class LoginFlowTests

# 只运行成功登录测试
./scripts/run-uitests.sh --simulator "iPhone 17" --test testSuccessfulLogin

# 显示详细输出
./scripts/run-uitests.sh --simulator "iPhone 17" --verbose
```

### 方法 2：使用 Xcode

1. 打开 `Examples/SPMExample/SPMExample.xcodeproj`
2. 选择 scheme: **SPMExample**
3. 选择目标设备（模拟器或真机）
4. 按 **Cmd + U** 运行测试
5. 或者：打开测试文件，点击方法左侧的 ◆ 图标运行单个测试

### 方法 3：使用命令行

```bash
cd Examples/SPMExample

# 模拟器测试
xcodebuild test \
    -project SPMExample.xcodeproj \
    -scheme SPMExample \
    -destination 'platform=iOS Simulator,name=iPhone 17' \
    -only-testing:SPMExampleUITests/LoginFlowTests

# 真机测试
xcodebuild test \
    -project SPMExample.xcodeproj \
    -scheme SPMExample \
    -destination 'platform=iOS,id=00008030-XXXXXXXXXXXX' \
    -only-testing:SPMExampleUITests/LoginFlowTests
```

---

## 真机测试注意事项

### 1. 设备信任

首次连接真机时，需要在设备上点击 **"信任此电脑"**。

### 2. 开发者模式

iOS 16+ 需要启用开发者模式：
1. 设置 → 隐私与安全 → 开发者模式
2. 打开开关，重启设备

### 3. 代码签名

确保所有 target（App、UITests）使用相同的开发团队和签名配置。

### 4. 设备 ID

获取设备 UDID：

```bash
# 方法 1：使用 xctrace
xcrun xctrace list devices

# 方法 2：使用 idevice_id（需要安装 libimobiledevice）
idevice_id -l

# 方法 3：Xcode
Window → Devices and Simulators → 选择设备 → Identifier
```

### 5. 部署目标

SPMExample 的部署目标是 **iOS 26.2**，确保真机系统版本 ≥ 26.2。

### 6. 与 iOSExploreServer 通信

如果测试需要通过 HTTP 与 App 内的 iOSExploreServer 通信，需要：

1. 启动 iproxy USB 转发：
   ```bash
   ./scripts/proxy.sh --daemon
   ```

2. 在测试代码中使用 `localhost:38321`：
   ```swift
   let url = URL(string: "http://localhost:38321/")!
   var request = URLRequest(url: url)
   request.httpMethod = "POST"
   request.httpBody = #"{"action":"ping"}"#.data(using: .utf8)
   
   let (data, _) = try await URLSession.shared.data(for: request)
   // 解析响应
   ```

---

## 与 iOSExploreServer 的关系

### 双进程架构对比

| 特性 | iOSExploreServer | XCUITest |
|------|-----------------|----------|
| 运行位置 | App 进程内 | 独立的 Test 进程 |
| 通信方式 | HTTP (经 iproxy) | XPC (跨进程通信) |
| 访问能力 | App 内部状态、UIKit 私有 API | 只能访问 UI 元素（黑盒） |
| 系统弹窗 | 无法直接处理 | 可以检测和操作 |
| 真机部署 | 需要 iproxy USB 转发 | 直接运行（需签名） |
| 适用场景 | 远程调试、Agent 驱动 | 标准 UI 自动化测试 |

### 互补关系

1. **iOSExploreServer 擅长**：
   - 深度访问 App 内部状态
   - 执行复杂的 UIKit 操作（如 `ui.control.sendAction`）
   - 远程驱动（Mac → iPhone 经 iproxy）

2. **XCUITest 擅长**：
   - 标准 UI 自动化测试（点击、输入、滑动）
   - 系统弹窗处理（权限请求、通知授权）
   - 集成到 CI/CD 流程

3. **组合使用**：
   - XCUITest 驱动 UI 流程
   - iOSExploreServer 提供深度诊断（日志、UI 树）
   - 系统弹窗由 XCUITest 处理
   - 复杂操作由 iOSExploreServer 处理

### 示例：组合使用

```swift
// XCUITest 测试代码
func testLoginWithServerVerification() throws {
    // 1. XCUITest 驱动登录流程
    let usernameField = app.textFields["login_username_field"]
    let passwordField = app.secureTextFields["login_password_field"]
    let loginButton = app.buttons["login_button"]
    
    usernameField.tap()
    usernameField.typeText("test")
    passwordField.tap()
    passwordField.typeText("123456")
    loginButton.tap()
    
    // 2. 等待登录完成
    let welcomeLabel = app.staticTexts["home_welcome_label"]
    _ = welcomeLabel.waitForExistence(timeout: 5.0)
    
    // 3. 使用 iOSExploreServer 验证内部状态
    let url = URL(string: "http://localhost:38321/")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.httpBody = #"{"action":"ui.topViewHierarchy"}"#.data(using: .utf8)
    
    let (data, _) = try await URLSession.shared.data(for: request)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    
    // 验证 ViewController 层级
    XCTAssertEqual(json["code"] as? String, "ok")
}
```

---

## 系统弹窗处理

### XCUITest 的系统弹窗能力

XCUITest 可以访问 SpringBoard 进程，检测和操作系统级弹窗：

```swift
let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
let alert = springboard.alerts.firstMatch

if alert.waitForExistence(timeout: 3.0) {
    let allowButton = alert.buttons["允许"]
    if allowButton.exists {
        allowButton.tap()
    }
}
```

### 自动处理权限弹窗

使用 `addUIInterruptionMonitor`：

```swift
addUIInterruptionMonitor(withDescription: "Location Permission") { alert in
    let allowButton = alert.buttons["允许"]
    if allowButton.exists {
        allowButton.tap()
        return true  // 表示已处理
    }
    return false  // 表示未处理
}

// 执行 UI 操作，触发监听器检查
app.tap()
```

**注意**：`addUIInterruptionMonitor` 只在测试与 UI 交互时才会触发检查，不是后台持续监听。

### Darwin Notification 的限制

Darwin notification 是进程间通信机制，可以监听系统事件（如截图）。

**XCUITest 限制**：XCUITest 运行在独立的 test 进程中，无法注册 Darwin notification 观察者。

如果需要在 App 内监听系统事件，应在 App 代码中实现：

```swift
// 这段代码应在 App 进程中（如 AppDelegate），不是测试代码
let center = CFNotificationCenterGetDarwinNotifyCenter()
CFNotificationCenterAddObserver(
    center,
    Unmanaged.passUnretained(self).toOpaque(),
    { _, observer, name, _, _ in
        print("截图事件触发")
    },
    "com.apple.springboard.userTookScreenshot" as CFString,
    nil,
    .deliverImmediately
)
```

### SPMExample 的系统弹窗现状

SPMExample 当前**不请求任何系统权限**（定位、相机、通知等），因此：

- `SystemAlertMonitorTests.swift` 中的测试**仅作示例**
- 测试运行时不会检测到实际的系统弹窗
- 如果 SPMExample 未来添加权限请求功能，可以直接使用这些测试

---

## 常见问题

### Q1: 测试启动很慢，如何优化？

**A**: XCUITest 启动开销包括：
- App 冷启动（~2-3 秒）
- Test 进程初始化（~1 秒）
- XPC 连接建立（~0.5 秒）

优化方法：
- 在 `setUpWithError` 中只启动一次 App
- 使用 `setUp()`（类级别）在所有测试前启动一次
- 避免频繁重启 App

### Q2: 真机测试失败，提示 "Failed to install or launch the test runner"

**A**: 检查：
1. 设备是否信任此电脑
2. 开发者模式是否启用（iOS 16+）
3. 代码签名是否正确
4. 设备系统版本是否 ≥ 部署目标（iOS 26.2）

### Q3: 找不到 UI 元素，测试超时

**A**: 检查：
1. `accessibilityIdentifier` 是否正确
2. 元素是否在视图层级中（使用 Xcode 的 Accessibility Inspector）
3. 等待时间是否足够（`waitForExistence(timeout:)`）
4. 元素是否被覆盖或隐藏

### Q4: 如何调试 XCUITest？

**A**:
1. 在测试方法中设置断点
2. 运行测试（Cmd + U）
3. 测试暂停时，使用 LLDB 检查 App 状态：
   ```
   po app.debugDescription  // 打印 App 层级
   po app.buttons.allElementsBoundByIndex  // 打印所有按钮
   ```
4. 使用 Xcode 的 **View Hierarchy Debugger**（暂停测试时）

### Q5: XCUITest 与 iOSExploreServer 冲突吗？

**A**: 不冲突，可以同时使用：
- iOSExploreServer 运行在 App 进程内，监听 HTTP 请求
- XCUITest 运行在独立的 test 进程，通过 XPC 与 App 交互
- 测试代码可以通过 `URLSession` 向 `localhost:38321` 发送 HTTP 请求

### Q6: 为什么 `addUIInterruptionMonitor` 不触发？

**A**: 监听器只在测试与 UI 交互时触发检查。

解决方法：
1. 触发权限请求后，调用 `app.tap()` 激活监听器
2. 或使用手动检测：
   ```swift
   let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
   let alert = springboard.alerts.firstMatch
   if alert.waitForExistence(timeout: 3.0) {
       alert.buttons["允许"].tap()
   }
   ```

### Q7: 测试在模拟器通过，真机失败

**A**: 可能原因：
1. 真机性能差异，超时时间不足 → 增加 `timeout`
2. 真机网络环境不同 → 检查网络依赖
3. 真机系统版本不同 → 检查 API 兼容性
4. iproxy 未启动 → 运行 `./scripts/proxy.sh --daemon`

### Q8: 如何在 CI/CD 中运行 XCUITest？

**A**: 示例（GitHub Actions）：

```yaml
- name: Run UI Tests
  run: |
    xcodebuild test \
      -project Examples/SPMExample/SPMExample.xcodeproj \
      -scheme SPMExample \
      -destination 'platform=iOS Simulator,name=iPhone 17' \
      -resultBundlePath UITestResults.xcresult
      
- name: Upload Test Results
  uses: actions/upload-artifact@v3
  with:
    name: uitest-results
    path: UITestResults.xcresult
```

---

## 测试清单

当前实现的测试用例：

### LoginFlowTests.swift

- ✅ `testSuccessfulLogin` - 成功登录流程
- ✅ `testLoginFailure_UserNotFound` - 登录失败（用户不存在）
- ✅ `testLoginFailure_WrongPassword` - 登录失败（密码错误）
- ✅ `testLoginButtonLoadingState` - 登录按钮加载状态
- ✅ `testNavigateToRegister` - 导航到注册页面
- ✅ `testNavigateToResetPassword` - 导航到重置密码页面
- ✅ `testLogoutFlow` - 退出登录流程
- ✅ `testCancelLogout` - 取消退出登录

### SystemAlertMonitorTests.swift

- ⚠️ `testLocationPermissionAlert_ManualDetection` - 手动检测定位权限弹窗（示例）
- ⚠️ `testLocationPermissionAlert_AutomaticHandling` - 自动处理定位权限弹窗（示例）
- ⚠️ `testNotificationPermissionAlert` - 通知权限弹窗（示例）
- ⚠️ `testCameraPermissionAlert` - 相机权限弹窗（示例）
- ⚠️ `testGenericSystemAlertHandling` - 通用系统弹窗处理器（示例）

**注**：⚠️ 标记的测试仅作示例，SPMExample 当前不请求权限，测试不会检测到实际弹窗。

---

## 下一步

1. **在 Xcode 中创建 UI Test target**（参考 [创建 UI Test Target](#创建-ui-test-target)）
2. **在模拟器运行测试**：`./scripts/run-uitests.sh --simulator "iPhone 17"`
3. **在真机运行测试**：`./scripts/run-uitests.sh --device-id <UDID>`
4. **扩展测试用例**：添加更多业务流程测试（注册、重置密码等）
5. **集成到 CI/CD**：将测试加入自动化流程

---

## 参考资料

- [Apple - XCTest Framework](https://developer.apple.com/documentation/xctest)
- [Apple - UI Testing in Xcode](https://developer.apple.com/library/archive/documentation/DeveloperTools/Conceptual/testing_with_xcode/chapters/09-ui_testing.html)
- [iOSExploreServer Documentation](../../README.md)
