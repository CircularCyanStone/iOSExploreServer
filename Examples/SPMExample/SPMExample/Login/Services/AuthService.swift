//
//  AuthService.swift
//  SPMExample
//
//  模拟认证服务：模拟网络请求，带成功/失败场景和日志输出
//

import Foundation
import OSLog

/// 认证服务：模拟网络请求
@MainActor
final class AuthService {
    static let shared = AuthService()

    private let logger = Logger(subsystem: "com.coo.SPMExample", category: "AuthService")

    /// 模拟用户数据库（内存中）
    private var users: [String: (password: String, user: User)] = [:]

    /// 模拟网络延迟（秒）
    private let networkDelay: TimeInterval = 1.5

    /// 调试用随机故障率旋钮，默认 0（永不失败）；测试可设 0<x<1 模拟登录随机失败。
    /// 非测试场景勿动。设为 `private(set)` 收紧外部写入，避免运行时被意外置成非确定状态
    /// （内部仅由 `shouldSimulateFailure()` 读取）。若需在测试中改写，请通过本类提供的调试入口。
    private(set) var simulateFailureRate: Double = 0.0

    private init() {
        // 预置测试账号
        let testUser = User(username: "test", email: "test@example.com")
        users["test"] = (password: "123456", user: testUser)
        logger.info("🔐 AuthService 初始化完成，预置测试账号: test")
    }

    // MARK: - 登录

    /// 登录
    /// - Parameters:
    ///   - username: 用户名
    ///   - password: 密码
    /// - Returns: 认证响应
    func login(username: String, password: String) async throws -> AuthResponse {
        logger.info("📤 开始登录请求: username=\(username)")

        // 模拟网络延迟
        try await Task.sleep(for: .seconds(networkDelay))

        // 模拟随机失败
        if shouldSimulateFailure() {
            logger.error("❌ 登录失败（模拟网络错误）: username=\(username)")
            throw AuthError.networkError
        }

        // 验证用户
        guard let userData = users[username] else {
            logger.warning("⚠️ 登录失败（用户不存在）: username=\(username)")
            throw AuthError.invalidCredentials
        }

        guard userData.password == password else {
            logger.warning("⚠️ 登录失败（密码错误）: username=\(username)")
            throw AuthError.invalidCredentials
        }

        // 登录成功
        let token = UUID().uuidString
        let response = AuthResponse(
            success: true,
            message: "登录成功",
            user: userData.user,
            token: token
        )

        logger.info("✅ 登录成功: username=\(username), token=\(token)")
        return response
    }

    // MARK: - 注册

    /// 注册新用户
    /// - Parameters:
    ///   - username: 用户名
    ///   - email: 邮箱
    ///   - password: 密码
    /// - Returns: 认证响应
    func register(username: String, email: String, password: String) async throws -> AuthResponse {
        logger.info("📤 开始注册请求: username=\(username), email=\(email)")

        // 模拟网络延迟
        try await Task.sleep(for: .seconds(networkDelay))

        // 模拟随机失败
        if shouldSimulateFailure() {
            logger.error("❌ 注册失败（模拟网络错误）: username=\(username)")
            throw AuthError.networkError
        }

        // 验证邮箱格式
        guard isValidEmail(email) else {
            logger.warning("⚠️ 注册失败（邮箱格式错误）: email=\(email)")
            throw AuthError.invalidEmail
        }

        // 验证密码强度
        guard password.count >= 6 else {
            logger.warning("⚠️ 注册失败（密码强度不足）: password length=\(password.count)")
            throw AuthError.weakPassword
        }

        // 检查用户是否已存在
        guard users[username] == nil else {
            logger.warning("⚠️ 注册失败（用户已存在）: username=\(username)")
            throw AuthError.userAlreadyExists
        }

        // 创建新用户
        let newUser = User(username: username, email: email)
        users[username] = (password: password, user: newUser)

        let token = UUID().uuidString
        let response = AuthResponse(
            success: true,
            message: "注册成功",
            user: newUser,
            token: token
        )

        logger.info("✅ 注册成功: username=\(username), email=\(email), token=\(token)")
        return response
    }

    // MARK: - 重置密码

    /// 重置密码
    /// - Parameters:
    ///   - username: 用户名
    ///   - email: 邮箱（用于验证）
    ///   - newPassword: 新密码
    /// - Returns: 认证响应
    func resetPassword(username: String, email: String, newPassword: String) async throws -> AuthResponse {
        logger.info("📤 开始重置密码请求: username=\(username), email=\(email)")

        // 模拟网络延迟
        try await Task.sleep(for: .seconds(networkDelay))

        // 模拟随机失败
        if shouldSimulateFailure() {
            logger.error("❌ 重置密码失败（模拟网络错误）: username=\(username)")
            throw AuthError.networkError
        }

        // 验证密码强度
        guard newPassword.count >= 6 else {
            logger.warning("⚠️ 重置密码失败（密码强度不足）: password length=\(newPassword.count)")
            throw AuthError.weakPassword
        }

        // 验证用户存在且邮箱匹配
        guard let userData = users[username], userData.user.email == email else {
            logger.warning("⚠️ 重置密码失败（用户不存在或邮箱不匹配）: username=\(username), email=\(email)")
            throw AuthError.invalidCredentials
        }

        // 更新密码
        users[username] = (password: newPassword, user: userData.user)

        let response = AuthResponse(
            success: true,
            message: "密码重置成功",
            user: userData.user,
            token: nil
        )

        logger.info("✅ 密码重置成功: username=\(username)")
        return response
    }

    // MARK: - 辅助方法

    /// 验证邮箱格式
    private func isValidEmail(_ email: String) -> Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email)
    }

    /// 是否模拟失败
    private func shouldSimulateFailure() -> Bool {
        return Double.random(in: 0...1) < simulateFailureRate
    }

    /// 获取所有用户（调试用）
    func getAllUsers() -> [User] {
        return users.values.map { $0.user }
    }
}
