//
//  AuthResponse.swift
//  SPMExample
//
//  认证响应模型
//

import Foundation

/// 认证响应
struct AuthResponse: Codable, Sendable {
    let success: Bool
    let message: String
    let user: User?
    let token: String?

    init(success: Bool, message: String, user: User? = nil, token: String? = nil) {
        self.success = success
        self.message = message
        self.user = user
        self.token = token
    }
}

/// 认证错误
enum AuthError: LocalizedError, Sendable {
    case invalidCredentials
    case userAlreadyExists
    case weakPassword
    case invalidEmail
    case networkError
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "用户名或密码错误"
        case .userAlreadyExists:
            return "用户已存在"
        case .weakPassword:
            return "密码强度不足（至少6位）"
        case .invalidEmail:
            return "邮箱格式不正确"
        case .networkError:
            return "网络连接失败"
        case .serverError(let message):
            return "服务器错误: \(message)"
        }
    }
}
