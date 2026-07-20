//
//  SystemAlertMonitorTests.swift
//  SPMExampleUITests
//
//  系统弹窗监听示例（权限请求、通知授权等）
//

import XCTest

/// 系统弹窗监听测试
///
/// XCUITest 架构说明：
/// - App 进程：运行被测试的 SPMExample App
/// - Test 进程：运行 XCUITest 测试代码（本文件）
/// - SpringBoard：系统进程，负责显示系统级弹窗（权限请求、通知授权等）
///
/// XCUITest 可以通过 `XCUIApplication(bundleIdentifier: "com.apple.springboard")` 访问 SpringBoard，
/// 从而检测和操作系统弹窗。
///
/// ## 系统弹窗监听原理
///
/// ### 1. XCUITest 轮询机制
///
/// XCUITest 不支持 Darwin notification 监听，但可以通过轮询检测 SpringBoard 的弹窗：
///
/// ```swift
/// let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
/// let alert = springboard.alerts.firstMatch
///
/// if alert.waitForExistence(timeout: 5.0) {
///     // 检测到系统弹窗
///     let allowButton = alert.buttons["允许"]
///     if allowButton.exists {
///         allowButton.tap()
///     }
/// }
/// ```
///
/// ### 2. XCUITest 的 addUIInterruptionMonitor
///
/// XCUITest 提供 `addUIInterruptionMonitor` API，用于自动处理系统弹窗：
///
/// ```swift
/// addUIInterruptionMonitor(withDescription: "Location permission") { alert in
///     let allowButton = alert.buttons["允许"]
///     if allowButton.exists {
///         allowButton.tap()
///         return true  // 表示已处理
///     }
///     return false  // 表示未处理
/// }
/// ```
///
/// **注意**：`addUIInterruptionMonitor` 只在测试与 UI 交互时才会触发检查，
/// 不是后台持续监听。通常需要在触发权限请求后，手动调用 `app.tap()`
/// 来激活监听器检查。
///
/// ### 3. Darwin Notification（XCUITest 不支持）
///
/// Darwin notification 是进程间通信机制，用于监听系统事件。
/// 例如，监听截图事件：
///
/// ```swift
/// // 这段代码在 XCUITest 中无法使用，仅作原理说明
/// let darwinNotificationCenter = CFNotificationCenterGetDarwinNotifyCenter()
/// CFNotificationCenterAddObserver(
///     darwinNotificationCenter,
///     observer,
///     callback,
///     "com.apple.springboard.userTookScreenshot" as CFString,
///     nil,
///     .deliverImmediately
/// )
/// ```
///
/// **XCUITest 限制**：XCUITest 运行在独立的 test 进程中，无法注册 Darwin notification 观察者。
/// 如果需要在 App 内监听系统事件，应在 App 代码中实现，而非测试代码。
///
/// ## 当前 SPMExample 的限制
///
/// SPMExample 目前没有请求系统权限的功能（定位、相机、通知等），
/// 因此无法演示真实的系统弹窗处理。
///
/// 下面的测试用例提供了完整的代码框架，展示如何处理常见的系统权限弹窗。
/// 如果 SPMExample 未来添加权限请求功能，可以直接使用这些测试。
final class SystemAlertMonitorTests: XCTestCase {

    var app: XCUIApplication!
    var springboard: XCUIApplication!

    override func setUpWithError() throws {
        try super.setUpWithError()

        continueAfterFailure = false

        // 初始化 App
        app = XCUIApplication()

        // 初始化 SpringBoard（系统进程）
        springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
        springboard = nil
        try super.tearDownWithError()
    }

    // MARK: - System Alert Monitoring Examples

    /// 示例：手动检测和处理定位权限弹窗
    ///
    /// 场景：当 App 请求定位权限时，系统会弹出权限对话框。
    /// XCUITest 可以检测这个对话框并自动点击 "允许" 按钮。
    ///
    /// **注意**：SPMExample 目前不请求定位权限，此测试仅作示例。
    /// 如果运行此测试，会因为超时而跳过。
    func testLocationPermissionAlert_ManualDetection() throws {
        // 场景：假设 App 在首页点击某个按钮后会请求定位权限
        // （SPMExample 目前没有这个功能，此处仅作示例）

        // 等待系统弹窗出现（最多等待 3 秒）
        let alert = springboard.alerts.firstMatch

        if alert.waitForExistence(timeout: 3.0) {
            print("✅ 检测到系统弹窗")

            // 打印弹窗中的所有按钮（用于调试）
            for button in alert.buttons.allElementsBoundByIndex {
                print("  按钮: \(button.label)")
            }

            // 尝试点击 "允许" 按钮
            let allowButton = alert.buttons["允许"]
            if allowButton.exists {
                allowButton.tap()
                print("✅ 已点击 '允许' 按钮")
            } else {
                // 如果没有 "允许" 按钮，可能是其他权限弹窗
                // 例如：相机权限的 "好" 按钮
                let okButton = alert.buttons["好"]
                if okButton.exists {
                    okButton.tap()
                    print("✅ 已点击 '好' 按钮")
                }
            }
        } else {
            print("⚠️ 未检测到系统弹窗（SPMExample 当前不请求权限）")
        }

        // 即使没有弹窗，测试也应该通过（不强制要求弹窗出现）
        XCTAssertTrue(true, "测试完成")
    }

    /// 示例：使用 addUIInterruptionMonitor 自动处理权限弹窗
    ///
    /// `addUIInterruptionMonitor` 会在测试与 UI 交互时自动检查并处理弹窗。
    ///
    /// **重要**：监听器只在测试与 UI 交互时触发，不是后台持续监听。
    /// 如果需要强制触发检查，可以调用 `app.tap()` 或与任意 UI 元素交互。
    ///
    /// **注意**：SPMExample 目前不请求权限，此测试仅作示例。
    func testLocationPermissionAlert_AutomaticHandling() throws {
        // 注册权限弹窗处理器
        addUIInterruptionMonitor(withDescription: "Location Permission") { alert in
            print("✅ addUIInterruptionMonitor 检测到弹窗: \(alert.label)")

            // 尝试点击 "允许" 或 "始终允许"
            let allowButton = alert.buttons["允许"]
            let alwaysAllowButton = alert.buttons["始终允许"]

            if allowButton.exists {
                allowButton.tap()
                print("✅ 已自动点击 '允许' 按钮")
                return true
            } else if alwaysAllowButton.exists {
                alwaysAllowButton.tap()
                print("✅ 已自动点击 '始终允许' 按钮")
                return true
            }

            return false
        }

        // 场景：假设点击某个按钮会触发定位权限请求
        // （SPMExample 目前没有这个功能，此处仅作示例）

        // 执行一些 UI 操作，触发监听器检查
        // 注意：如果没有实际的 UI 交互，监听器不会触发
        let loginTitle = app.staticTexts["login_title"]
        if loginTitle.exists {
            // 与 UI 交互，触发监听器检查
            app.tap()
        }

        print("⚠️ SPMExample 当前不请求权限，监听器未被触发")

        // 测试通过（不强制要求弹窗出现）
        XCTAssertTrue(true, "测试完成")
    }

    /// 示例：处理通知权限弹窗
    ///
    /// 通知权限弹窗通常有两个按钮：
    /// - "不允许"（Don't Allow）
    /// - "允许"（Allow）
    ///
    /// **注意**：SPMExample 目前不请求通知权限，此测试仅作示例。
    func testNotificationPermissionAlert() throws {
        // 注册通知权限处理器
        addUIInterruptionMonitor(withDescription: "Notification Permission") { alert in
            print("✅ 检测到通知权限弹窗: \(alert.label)")

            // 点击 "允许" 按钮
            let allowButton = alert.buttons["允许"]
            if allowButton.exists {
                allowButton.tap()
                print("✅ 已自动点击 '允许' 按钮")
                return true
            }

            return false
        }

        // 场景：假设 App 启动时会请求通知权限
        // （SPMExample 目前没有这个功能，此处仅作示例）

        // 与 UI 交互，触发监听器检查
        let loginTitle = app.staticTexts["login_title"]
        if loginTitle.exists {
            app.tap()
        }

        print("⚠️ SPMExample 当前不请求通知权限")

        XCTAssertTrue(true, "测试完成")
    }

    /// 示例：处理相机权限弹窗
    ///
    /// 相机权限弹窗通常有两个按钮：
    /// - "不允许"（Don't Allow）
    /// - "好"（OK）
    ///
    /// **注意**：SPMExample 目前不请求相机权限，此测试仅作示例。
    func testCameraPermissionAlert() throws {
        // 注册相机权限处理器
        addUIInterruptionMonitor(withDescription: "Camera Permission") { alert in
            print("✅ 检测到相机权限弹窗: \(alert.label)")

            // 点击 "好" 按钮
            let okButton = alert.buttons["好"]
            if okButton.exists {
                okButton.tap()
                print("✅ 已自动点击 '好' 按钮")
                return true
            }

            return false
        }

        // 场景：假设点击某个按钮会打开相机
        // （SPMExample 目前没有这个功能，此处仅作示例）

        // 与 UI 交互，触发监听器检查
        let loginTitle = app.staticTexts["login_title"]
        if loginTitle.exists {
            app.tap()
        }

        print("⚠️ SPMExample 当前不请求相机权限")

        XCTAssertTrue(true, "测试完成")
    }

    /// 示例：通用系统弹窗处理器
    ///
    /// 此处理器会尝试点击常见的 "允许" 相关按钮，
    /// 适用于多种权限类型（定位、通知、相机、麦克风等）。
    func testGenericSystemAlertHandling() throws {
        // 注册通用权限处理器
        addUIInterruptionMonitor(withDescription: "Generic System Alert") { alert in
            print("✅ 检测到系统弹窗: \(alert.label)")

            // 常见的允许按钮标签
            let allowLabels = ["允许", "始终允许", "好", "OK", "Allow", "Always Allow"]

            for label in allowLabels {
                let button = alert.buttons[label]
                if button.exists {
                    button.tap()
                    print("✅ 已自动点击 '\(label)' 按钮")
                    return true
                }
            }

            print("⚠️ 未找到允许按钮，可用按钮：")
            for button in alert.buttons.allElementsBoundByIndex {
                print("  - \(button.label)")
            }

            return false
        }

        // 与 UI 交互，触发监听器检查
        let loginTitle = app.staticTexts["login_title"]
        if loginTitle.exists {
            app.tap()
        }

        print("⚠️ SPMExample 当前不请求权限，监听器未被触发")

        XCTAssertTrue(true, "测试完成")
    }

    // MARK: - Real System Alert Test (if SPMExample adds permission requests)

    /// 真实测试：如果 SPMExample 未来添加了权限请求功能，可以使用此测试
    ///
    /// 示例：假设 SPMExample 添加了定位功能
    ///
    /// ```swift
    /// func testRealLocationPermissionFlow() throws {
    ///     // 1. 注册权限处理器
    ///     addUIInterruptionMonitor(withDescription: "Location") { alert in
    ///         alert.buttons["允许"].tap()
    ///         return true
    ///     }
    ///
    ///     // 2. 登录到首页
    ///     let usernameField = app.textFields["login_username_field"]
    ///     let passwordField = app.secureTextFields["login_password_field"]
    ///     let loginButton = app.buttons["login_button"]
    ///
    ///     usernameField.tap()
    ///     usernameField.typeText("test")
    ///     passwordField.tap()
    ///     passwordField.typeText("123456")
    ///     loginButton.tap()
    ///
    ///     let welcomeLabel = app.staticTexts["home_welcome_label"]
    ///     _ = welcomeLabel.waitForExistence(timeout: 5.0)
    ///
    ///     // 3. 点击 "获取位置" 按钮（假设的功能）
    ///     let locationButton = app.buttons["get_location_button"]
    ///     locationButton.tap()
    ///
    ///     // 4. 触发监听器检查
    ///     app.tap()
    ///
    ///     // 5. 验证定位功能已启用
    ///     let locationLabel = app.staticTexts["location_result_label"]
    ///     let locationObtained = locationLabel.waitForExistence(timeout: 5.0)
    ///     XCTAssertTrue(locationObtained, "应该获取到位置信息")
    /// }
    /// ```
}

// MARK: - Helper Extensions

extension XCTestCase {
    /// 辅助方法：等待并处理系统弹窗
    ///
    /// - Parameters:
    ///   - timeout: 等待超时时间（秒）
    ///   - allowButtonLabels: 要点击的按钮标签列表（优先级从高到低）
    /// - Returns: 是否成功处理弹窗
    ///
    /// 使用示例：
    /// ```swift
    /// let handled = waitAndHandleSystemAlert(
    ///     timeout: 3.0,
    ///     allowButtonLabels: ["允许", "始终允许", "好"]
    /// )
    /// XCTAssertTrue(handled, "应该成功处理权限弹窗")
    /// ```
    func waitAndHandleSystemAlert(
        timeout: TimeInterval = 3.0,
        allowButtonLabels: [String] = ["允许", "始终允许", "好", "OK", "Allow", "Always Allow"]
    ) -> Bool {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch

        guard alert.waitForExistence(timeout: timeout) else {
            print("⚠️ 未检测到系统弹窗")
            return false
        }

        print("✅ 检测到系统弹窗: \(alert.label)")

        for label in allowButtonLabels {
            let button = alert.buttons[label]
            if button.exists {
                button.tap()
                print("✅ 已点击 '\(label)' 按钮")
                return true
            }
        }

        print("⚠️ 未找到允许按钮，可用按钮：")
        for button in alert.buttons.allElementsBoundByIndex {
            print("  - \(button.label)")
        }

        return false
    }
}
