//
//  LoginViewModel.swift
//  SPMExample
//
//  登录视图模型
//

import Foundation
import Combine
import OSLog

/// 登录视图模型
@MainActor
final class LoginViewModel: ObservableObject {
    @Published var username: String = ""
    @Published var password: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    private let authService = AuthService.shared
    private let logger = Logger(subsystem: "com.coo.SPMExample", category: "LoginViewModel")

    /// 登录
    func login() async -> AuthResponse? {
        logger.info("🔵 开始登录流程: username=\(self.username)")

        // 验证输入
        guard !username.isEmpty else {
            errorMessage = "请输入用户名"
            logger.warning("⚠️ 登录失败: 用户名为空")
            return nil
        }

        guard !password.isEmpty else {
            errorMessage = "请输入密码"
            logger.warning("⚠️ 登录失败: 密码为空")
            return nil
        }

        isLoading = true
        errorMessage = nil

        do {
            let response = try await authService.login(username: username, password: password)
            logger.info("✅ 登录成功: username=\(self.username)")
            isLoading = false
            return response
        } catch let error as AuthError {
            errorMessage = error.localizedDescription
            logger.error("❌ 登录失败: \(error.localizedDescription)")
            isLoading = false
            return nil
        } catch {
            errorMessage = "未知错误: \(error.localizedDescription)"
            logger.error("❌ 登录失败（未知错误）: \(error.localizedDescription)")
            isLoading = false
            return nil
        }
    }

    /// 重置状态
    func reset() {
        username = ""
        password = ""
        errorMessage = nil
        isLoading = false
    }
}
