# System Alert XCUITest Spike

**目标**：验证 XCUITest 在真机环境下访问系统权限弹窗的可行性

**日期**：2026-07-19

---

## 背景

系统权限弹窗（相机、位置、通知等）由 SpringBoard 进程管理，不在 App 的 view hierarchy 中。需要验证：
1. XCUITest 能否在真机访问系统弹窗
2. UI Test target 与 App target 的 IPC 通信方式
3. 部署和运行的复杂度

---

## 实验设计

### 步骤 1：创建 UI Test Target

在 `SPMExample.xcodeproj` 中新建 `SPMExampleUITests` target（如果不存在）。

### 步骤 2：实现系统弹窗检测

```swift
// SPMExampleUITests/SystemAlertTests.swift
import XCTest

class SystemAlertTests: XCTestCase {
    func testDetectCameraPermissionAlert() {
        let app = XCUIApplication()
        app.launch()
        
        // 触发相机权限请求（需要 App 内有触发代码）
        app.buttons["requestCameraPermission"].tap()
        
        // 检测系统弹窗
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        
        if alert.waitForExistence(timeout: 5) {
            print("✅ 检测到系统弹窗")
            print("弹窗标题: \(alert.label)")
            
            // 列出所有按钮
            let buttons = alert.buttons.allElementsBoundByIndex
            for (index, button) in buttons.enumerated() {
                print("按钮 \(index): \(button.label)")
            }
            
            // 点击"允许"
            if alert.buttons["允许"].exists {
                alert.buttons["允许"].tap()
                print("✅ 已点击允许")
            } else if alert.buttons["Allow"].exists {
                alert.buttons["Allow"].tap()
                print("✅ 已点击 Allow")
            }
        } else {
            print("❌ 未检测到系统弹窗")
        }
        
        // 验证权限已授予
        sleep(1)
        XCTAssert(app.staticTexts["cameraPermissionGranted"].exists)
    }
}
```

### 步骤 3：在 App 中添加触发代码

```swift
// SPMExample/ViewController.swift
#if DEBUG
import AVFoundation

@objc func requestCameraPermissionTapped() {
    AVCaptureDevice.requestAccess(for: .video) { granted in
        DispatchQueue.main.async {
            self.permissionStatusLabel.text = granted ? "cameraPermissionGranted" : "cameraPermissionDenied"
        }
    }
}
#endif
```

### 步骤 4：真机测试

```bash
# 1. 重置权限状态
xcrun devicectl device process reset-privacy <device-id> com.coo.SPMExample

# 2. 运行 UI Test
xcodebuild test \
  -project Examples/SPMExample/SPMExample.xcodeproj \
  -scheme SPMExample \
  -destination 'platform=iOS,id=<device-udid>' \
  -only-testing:SPMExampleUITests/SystemAlertTests/testDetectCameraPermissionAlert
```

---

## 预期结果

### 成功标准
- ✅ XCUITest 能检测到 SpringBoard 的 alert
- ✅ 能读取按钮标签（"允许" / "不允许"）
- ✅ 能点击按钮并触发系统授权
- ✅ App 能收到授权结果

### 失败标准
- ❌ XCUITest 无法访问 SpringBoard（沙箱限制）
- ❌ 真机不允许跨进程 accessibility 访问
- ❌ iOS 26 安全策略阻止

---

## 备选方案（如果 XCUITest 不可行）

### 方案 1：Darwin Notification + 手动点击
- App 发送 Darwin notification 提示有弹窗
- 测试脚本暂停，提示用户手动点击
- 适用于开发调试，不适合自动化

### 方案 2：仅模拟器自动化
- 模拟器使用 `simctl privacy grant/revoke`
- 真机改为预授权 + 重置权限测试
- 无法测试真实弹窗交互

### 方案 3：XcodeBuildMCP 的 devicectl 探索
- 研究 `devicectl` 是否支持权限控制
- iOS 26+ 可能有新的自动化 API

---

## 下一步

1. **立即验证**：在模拟器运行 XCUITest，确认基础可行性
2. **真机验证**：在 iOS 26 真机运行，记录任何限制
3. **性能评估**：测量 Test runner 启动开销、IPC 延迟
4. **架构设计**：如果可行，设计 App ↔ UITest 的 IPC 协议

---

## 实验日志

### 2026-07-19
- 创建 spike 文档
- 待执行实验

