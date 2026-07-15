//
//  ResetPasswordViewModel.swift
//  SPMExample
//
//  重置密码视图模型
//

import Foundation
import Combine
import OSLog

/// 重置密码视图模型
@MainActor
final class ResetPasswordViewModel: ObservableObject {
    @Published var username: String = ""
    @Published var email: String = ""
    @Published var newPassword: String = ""
    @Published var confirmPassword: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    private let authService = AuthService.shared
    private let logger = Logger(subsystem: "com.coo.SPMExample", category: "ResetPasswordViewModel")

    /// 重置密码
    func resetPassword() async -> AuthResponse? {
        logger.info("🔵 开始重置密码流程: username=\(self.username), email=\(self.email)")

        // 验证输入
        guard !username.isEmpty else {
            errorMessage = "请输入用户名"
            logger.warning("⚠️ 重置密码失败: 用户名为空")
            return nil
        }

        guard !email.isEmpty else {
            errorMessage = "请输入邮箱"
            logger.warning("⚠️ 重置密码失败: 邮箱为空")
            return nil
        }

        guard !newPassword.isEmpty else {
            errorMessage = "请输入新密码"
            logger.warning("⚠️ 重置密码失败: 新密码为空")
            return nil
        }

        guard newPassword == confirmPassword else {
            errorMessage = "两次密码输入不一致"
            logger.warning("⚠️ 重置密码失败: 密码不一致")
            return nil
        }

        isLoading = true
        errorMessage = nil

        do {
            let response = try await authService.resetPassword(username: username, email: email, newPassword: newPassword)
            logger.info("✅ 重置密码成功: username=\(self.username)")
            isLoading = false
            return response
        } catch let error as AuthError {
            errorMessage = error.localizedDescription
            logger.error("❌ 重置密码失败: \(error.localizedDescription)")
            isLoading = false
            return nil
        } catch {
            errorMessage = "未知错误: \(error.localizedDescription)"
            logger.error("❌ 重置密码失败（未知错误）: \(error.localizedDescription)")
            isLoading = false
            return nil
        }
    }

    /// 重置状态
    func reset() {
        username = ""
        email = ""
        newPassword = ""
        confirmPassword = ""
        errorMessage = nil
        isLoading = false
    }
}
