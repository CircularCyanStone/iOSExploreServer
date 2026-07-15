//
//  RegisterViewModel.swift
//  SPMExample
//
//  注册视图模型
//

import Foundation
import Combine
import OSLog

/// 注册视图模型
@MainActor
final class RegisterViewModel: ObservableObject {
    @Published var username: String = ""
    @Published var email: String = ""
    @Published var password: String = ""
    @Published var confirmPassword: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    private let authService = AuthService.shared
    private let logger = Logger(subsystem: "com.coo.SPMExample", category: "RegisterViewModel")

    /// 注册
    func register() async -> AuthResponse? {
        logger.info("🔵 开始注册流程: username=\(self.username), email=\(self.email)")

        // 验证输入
        guard !username.isEmpty else {
            errorMessage = "请输入用户名"
            logger.warning("⚠️ 注册失败: 用户名为空")
            return nil
        }

        guard !email.isEmpty else {
            errorMessage = "请输入邮箱"
            logger.warning("⚠️ 注册失败: 邮箱为空")
            return nil
        }

        guard !password.isEmpty else {
            errorMessage = "请输入密码"
            logger.warning("⚠️ 注册失败: 密码为空")
            return nil
        }

        guard password == confirmPassword else {
            errorMessage = "两次密码输入不一致"
            logger.warning("⚠️ 注册失败: 密码不一致")
            return nil
        }

        isLoading = true
        errorMessage = nil

        do {
            let response = try await authService.register(username: username, email: email, password: password)
            logger.info("✅ 注册成功: username=\(self.username)")
            isLoading = false
            return response
        } catch let error as AuthError {
            errorMessage = error.localizedDescription
            logger.error("❌ 注册失败: \(error.localizedDescription)")
            isLoading = false
            return nil
        } catch {
            errorMessage = "未知错误: \(error.localizedDescription)"
            logger.error("❌ 注册失败（未知错误）: \(error.localizedDescription)")
            isLoading = false
            return nil
        }
    }

    /// 重置状态
    func reset() {
        username = ""
        email = ""
        password = ""
        confirmPassword = ""
        errorMessage = nil
        isLoading = false
    }
}
