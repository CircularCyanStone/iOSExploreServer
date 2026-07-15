//
//  HomeViewModel.swift
//  SPMExample
//
//  首页视图模型
//

import Foundation
import Combine
import OSLog

/// 首页视图模型
@MainActor
final class HomeViewModel: ObservableObject {
    @Published var user: User?
    @Published var isLoading: Bool = false

    private let logger = Logger(subsystem: "com.coo.SPMExample", category: "HomeViewModel")

    init(user: User?) {
        self.user = user
        logger.info("🔵 HomeViewModel 初始化: username=\(user?.username ?? "nil")")
    }

    /// 登出
    func logout() {
        logger.info("🔵 用户登出: username=\(self.user?.username ?? "unknown")")
        user = nil
    }

    /// 刷新用户信息（模拟）
    func refreshUserInfo() async {
        logger.info("🔵 开始刷新用户信息")
        isLoading = true

        // 模拟网络延迟
        try? await Task.sleep(for: .seconds(1.0))

        logger.info("✅ 用户信息刷新完成")
        isLoading = false
    }
}
