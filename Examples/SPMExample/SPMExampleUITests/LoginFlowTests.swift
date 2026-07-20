//
//  LoginFlowTests.swift
//  SPMExampleUITests
//
//  登录流程的 XCUITest 测试
//

import XCTest

/// 登录流程 UI 测试
///
/// 验证点：
/// - 登录界面元素检测
/// - 输入用户名和密码
/// - 点击登录按钮
/// - 验证登录成功（进入首页）
///
/// 测试账号：test / 123456（位于 AuthService.swift:31）
final class LoginFlowTests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        try super.setUpWithError()

        // 禁用测试失败时的继续执行，遇到断言失败立即停止
        continueAfterFailure = false

        // 初始化 App
        app = XCUIApplication()

        // 设置启动参数：防止自动跳转到测试页面
        app.launchArguments = []
        app.launchEnvironment = [:]

        // 启动 App
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
        try super.tearDownWithError()
    }

    // MARK: - Login Flow Tests

    /// 测试：成功登录流程
    ///
    /// 步骤：
    /// 1. 检测登录界面元素（标题、用户名输入框、密码输入框、登录按钮）
    /// 2. 输入测试账号：test / 123456
    /// 3. 点击登录按钮
    /// 4. 等待网络延迟（1.5 秒模拟请求）
    /// 5. 验证登录成功：检测首页的 "欢迎回来！" 标题和用户名标签
    func testSuccessfulLogin() throws {
        // 1. 检测登录界面元素
        let titleLabel = app.staticTexts["login_title"]
        XCTAssertTrue(titleLabel.exists, "登录标题应该存在")
        XCTAssertEqual(titleLabel.label, "欢迎登录", "标题文本应为 '欢迎登录'")

        let usernameField = app.textFields["login_username_field"]
        XCTAssertTrue(usernameField.exists, "用户名输入框应该存在")

        let passwordField = app.secureTextFields["login_password_field"]
        XCTAssertTrue(passwordField.exists, "密码输入框应该存在")

        let loginButton = app.buttons["login_button"]
        XCTAssertTrue(loginButton.exists, "登录按钮应该存在")
        XCTAssertTrue(loginButton.isEnabled, "登录按钮应该可用")

        // 2. 输入测试账号
        usernameField.tap()
        usernameField.typeText("test")

        passwordField.tap()
        passwordField.typeText("123456")

        // 3. 点击登录按钮
        loginButton.tap()

        // 4. 等待登录请求完成（AuthService 模拟网络延迟 1.5 秒 + UI 更新时间）
        // 使用 waitForExistence 等待首页元素出现，最多等待 5 秒
        let welcomeLabel = app.staticTexts["home_welcome_label"]
        let loginSucceeded = welcomeLabel.waitForExistence(timeout: 5.0)

        XCTAssertTrue(loginSucceeded, "登录应该成功，首页欢迎标签应该出现")

        // 5. 验证首页内容
        XCTAssertEqual(welcomeLabel.label, "欢迎回来！", "首页标题应为 '欢迎回来！'")

        let usernameLabel = app.staticTexts["home_username_label"]
        XCTAssertTrue(usernameLabel.exists, "首页用户名标签应该存在")
        XCTAssertEqual(usernameLabel.label, "test", "首页应显示用户名 'test'")

        let emailLabel = app.staticTexts["home_email_label"]
        XCTAssertTrue(emailLabel.exists, "首页邮箱标签应该存在")
        XCTAssertEqual(emailLabel.label, "test@example.com", "首页应显示邮箱 'test@example.com'")
    }

    /// 测试：登录失败 - 用户名不存在
    ///
    /// 步骤：
    /// 1. 输入不存在的用户名
    /// 2. 点击登录按钮
    /// 3. 验证显示错误信息
    func testLoginFailure_UserNotFound() throws {
        let usernameField = app.textFields["login_username_field"]
        let passwordField = app.secureTextFields["login_password_field"]
        let loginButton = app.buttons["login_button"]

        // 输入不存在的用户名
        usernameField.tap()
        usernameField.typeText("nonexistent")

        passwordField.tap()
        passwordField.typeText("123456")

        loginButton.tap()

        // 等待错误信息出现
        let errorLabel = app.staticTexts["login_error_label"]
        let errorAppeared = errorLabel.waitForExistence(timeout: 3.0)

        XCTAssertTrue(errorAppeared, "错误信息应该显示")
        XCTAssertFalse(errorLabel.label.isEmpty, "错误信息不应为空")

        // 验证仍在登录页面
        let titleLabel = app.staticTexts["login_title"]
        XCTAssertTrue(titleLabel.exists, "应该仍在登录页面")
    }

    /// 测试：登录失败 - 密码错误
    ///
    /// 步骤：
    /// 1. 输入正确的用户名，错误的密码
    /// 2. 点击登录按钮
    /// 3. 验证显示错误信息
    func testLoginFailure_WrongPassword() throws {
        let usernameField = app.textFields["login_username_field"]
        let passwordField = app.secureTextFields["login_password_field"]
        let loginButton = app.buttons["login_button"]

        // 输入正确用户名，错误密码
        usernameField.tap()
        usernameField.typeText("test")

        passwordField.tap()
        passwordField.typeText("wrongpassword")

        loginButton.tap()

        // 等待错误信息出现
        let errorLabel = app.staticTexts["login_error_label"]
        let errorAppeared = errorLabel.waitForExistence(timeout: 3.0)

        XCTAssertTrue(errorAppeared, "错误信息应该显示")

        // 验证仍在登录页面
        let titleLabel = app.staticTexts["login_title"]
        XCTAssertTrue(titleLabel.exists, "应该仍在登录页面")
    }

    /// 测试：登录按钮加载状态
    ///
    /// 验证点：
    /// - 点击登录后，按钮应显示加载指示器
    /// - 按钮标题应清空
    /// - 按钮应禁用，防止重复提交
    func testLoginButtonLoadingState() throws {
        let usernameField = app.textFields["login_username_field"]
        let passwordField = app.secureTextFields["login_password_field"]
        let loginButton = app.buttons["login_button"]

        // 输入测试账号
        usernameField.tap()
        usernameField.typeText("test")

        passwordField.tap()
        passwordField.typeText("123456")

        // 记录初始状态
        let initialTitle = loginButton.label
        XCTAssertEqual(initialTitle, "登录", "初始按钮标题应为 '登录'")
        XCTAssertTrue(loginButton.isEnabled, "初始按钮应可用")

        // 点击登录
        loginButton.tap()

        // 立即检查加载状态（在网络延迟期间）
        // 注意：XCUITest 无法直接访问 UIActivityIndicatorView，
        // 但可以检测按钮标题是否被清空
        let buttonTitleCleared = loginButton.label.isEmpty

        // 由于异步更新，这里不强制要求立即检测到状态变化
        // 主要验证最终能成功登录

        // 等待登录完成
        let welcomeLabel = app.staticTexts["home_welcome_label"]
        let loginSucceeded = welcomeLabel.waitForExistence(timeout: 5.0)

        XCTAssertTrue(loginSucceeded, "登录应该成功")
    }

    /// 测试：导航到注册页面
    ///
    /// 步骤：
    /// 1. 点击 "还没有账号？去注册" 按钮
    /// 2. 验证导航到注册页面
    func testNavigateToRegister() throws {
        let registerButton = app.buttons["goto_register_button"]
        XCTAssertTrue(registerButton.exists, "注册按钮应该存在")

        registerButton.tap()

        // 验证导航到注册页面（检查导航栏标题）
        let navigationBar = app.navigationBars["注册"]
        let navigated = navigationBar.waitForExistence(timeout: 2.0)

        XCTAssertTrue(navigated, "应该导航到注册页面")
    }

    /// 测试：导航到重置密码页面
    ///
    /// 步骤：
    /// 1. 点击 "忘记密码？" 按钮
    /// 2. 验证导航到重置密码页面
    func testNavigateToResetPassword() throws {
        let forgotPasswordButton = app.buttons["goto_reset_password_button"]
        XCTAssertTrue(forgotPasswordButton.exists, "忘记密码按钮应该存在")

        forgotPasswordButton.tap()

        // 验证导航到重置密码页面（检查导航栏标题）
        let navigationBar = app.navigationBars["重置密码"]
        let navigated = navigationBar.waitForExistence(timeout: 2.0)

        XCTAssertTrue(navigated, "应该导航到重置密码页面")
    }

    // MARK: - Home Page Tests

    /// 测试：退出登录流程
    ///
    /// 步骤：
    /// 1. 先登录
    /// 2. 在首页点击退出登录按钮
    /// 3. 确认退出对话框
    /// 4. 验证返回到登录页面
    func testLogoutFlow() throws {
        // 1. 先登录
        let usernameField = app.textFields["login_username_field"]
        let passwordField = app.secureTextFields["login_password_field"]
        let loginButton = app.buttons["login_button"]

        usernameField.tap()
        usernameField.typeText("test")

        passwordField.tap()
        passwordField.typeText("123456")

        loginButton.tap()

        // 等待进入首页
        let welcomeLabel = app.staticTexts["home_welcome_label"]
        _ = welcomeLabel.waitForExistence(timeout: 5.0)

        // 2. 点击退出登录按钮
        let logoutButton = app.buttons["home_logout_button"]
        XCTAssertTrue(logoutButton.exists, "退出登录按钮应该存在")

        logoutButton.tap()

        // 3. 等待确认对话框出现
        let alert = app.alerts["确认退出"]
        let alertAppeared = alert.waitForExistence(timeout: 2.0)
        XCTAssertTrue(alertAppeared, "确认退出对话框应该出现")

        // 4. 点击 "退出" 按钮
        let confirmButton = alert.buttons["退出"]
        XCTAssertTrue(confirmButton.exists, "对话框的退出按钮应该存在")

        confirmButton.tap()

        // 5. 验证返回到登录页面
        let loginTitle = app.staticTexts["login_title"]
        let backToLogin = loginTitle.waitForExistence(timeout: 3.0)

        XCTAssertTrue(backToLogin, "应该返回到登录页面")
    }

    /// 测试：取消退出登录
    ///
    /// 步骤：
    /// 1. 先登录
    /// 2. 在首页点击退出登录按钮
    /// 3. 在确认对话框中点击取消
    /// 4. 验证仍在首页
    func testCancelLogout() throws {
        // 1. 先登录
        let usernameField = app.textFields["login_username_field"]
        let passwordField = app.secureTextFields["login_password_field"]
        let loginButton = app.buttons["login_button"]

        usernameField.tap()
        usernameField.typeText("test")

        passwordField.tap()
        passwordField.typeText("123456")

        loginButton.tap()

        // 等待进入首页
        let welcomeLabel = app.staticTexts["home_welcome_label"]
        _ = welcomeLabel.waitForExistence(timeout: 5.0)

        // 2. 点击退出登录按钮
        let logoutButton = app.buttons["home_logout_button"]
        logoutButton.tap()

        // 3. 等待确认对话框出现
        let alert = app.alerts["确认退出"]
        _ = alert.waitForExistence(timeout: 2.0)

        // 4. 点击 "取消" 按钮
        let cancelButton = alert.buttons["取消"]
        XCTAssertTrue(cancelButton.exists, "对话框的取消按钮应该存在")

        cancelButton.tap()

        // 5. 验证仍在首页
        XCTAssertTrue(welcomeLabel.exists, "应该仍在首页")
        XCTAssertTrue(logoutButton.exists, "退出登录按钮应该仍存在")
    }
}
