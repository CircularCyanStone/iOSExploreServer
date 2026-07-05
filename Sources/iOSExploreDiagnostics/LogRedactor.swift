import Foundation

/// 日志脱敏器。
///
/// Diagnostics 在写入 store 前统一调用它，确保内存中不保存 token、cookie、password 等明显
/// 敏感内容。规则保持保守，不尝试理解完整业务 payload。
public struct LogRedactor: Sendable, Equatable {
    /// 默认脱敏规则。
    public static let standard = LogRedactor()

    private let sensitiveKeys: Set<String> = [
        "authorization",
        "cookie",
        "password",
        "token",
        "access_token",
        "refresh_token",
    ]

    /// 创建脱敏器。
    public init() {}

    /// 脱敏日志正文。
    ///
    /// - Parameter message: 原始日志正文。
    /// - Returns: 已替换明显敏感片段的正文。
    public func redactMessage(_ message: String) -> String {
        var result = message
        result = replace(pattern: #"(?i)Authorization:\s*Bearer\s+[^\s,;]+"#, in: result, with: "Authorization: [REDACTED]")
        result = replace(pattern: #"(?i)Authorization:\s*[^\s,;]+"#, in: result, with: "Authorization: [REDACTED]")
        result = replace(pattern: #"(?i)Cookie:\s*[^\n]+"#, in: result, with: "Cookie: [REDACTED]")
        result = replace(pattern: #"(?i)(password|token|access_token|refresh_token)=([^&\s,;]+)"#, in: result, with: "$1=[REDACTED]")
        result = replace(pattern: #"(?i)"(password|token|authorization|cookie)"\s*:\s*"[^"]*""#, in: result, with: "\"$1\":\"[REDACTED]\"")
        return result
    }

    /// 脱敏 metadata。
    ///
    /// - Parameter metadata: 宿主传入的轻量结构化上下文。
    /// - Returns: key 命中敏感规则时 value 替换为 `[REDACTED]`。
    public func redactMetadata(_ metadata: [String: String]?) -> [String: String]? {
        guard let metadata else { return nil }
        var redacted: [String: String] = [:]
        for (key, value) in metadata {
            if sensitiveKeys.contains(key.lowercased()) {
                redacted[key] = "[REDACTED]"
            } else {
                redacted[key] = redactMessage(value)
            }
        }
        return redacted
    }

    private func replace(pattern: String, in text: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }
}
