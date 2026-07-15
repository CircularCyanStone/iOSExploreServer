//
//  User.swift
//  SPMExample
//
//  用户模型
//

import Foundation

/// 用户信息
struct User: Codable, Sendable {
    let id: String
    let username: String
    let email: String
    let createdAt: Date

    init(id: String = UUID().uuidString, username: String, email: String, createdAt: Date = Date()) {
        self.id = id
        self.username = username
        self.email = email
        self.createdAt = createdAt
    }
}
