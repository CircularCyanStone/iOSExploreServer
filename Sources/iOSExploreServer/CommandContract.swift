import Foundation

/// 命令合同声明的提供方。
public enum CommandContractProvider: String, Sendable, Equatable {
    /// core 内置命令。
    case core
    /// UIKit 扩展命令。
    case uikit
    /// Diagnostics 扩展命令。
    case diagnostics
    /// 宿主在运行时注册的扩展命令。
    case `extension`
}

/// 命令合同的稳定性级别。
public enum CommandContractStability: String, Sendable, Equatable {
    /// 对外稳定发布的合同。
    case `public`
    /// 已提供但仍可能调整的合同。
    case experimental
    /// 仅供内部或运行时扩展使用的合同。
    case `internal`
}

/// 命令结果在 wire 层的表示类型。
public enum CommandContractResultKind: String, Sendable, Equatable {
    /// JSON object 或 JSON value 结果。
    case json
    /// 图片二进制结果。
    case image
    /// 文本结果。
    case text
}

/// 命令的重试安全性分类。
public enum CommandContractIdempotency: String, Sendable, Equatable {
    /// 只读命令，重复调用不会产生副作用。
    case readOnly
    /// 可重复执行且结果语义稳定的命令。
    case idempotent
    /// 可能产生副作用的命令。
    case sideEffecting
}

/// 命令使用的超时策略分类。
public enum CommandContractTimeoutClass: String, Sendable, Equatable {
    /// 普通命令超时策略。
    case standard
    /// 等待状态变化的命令超时策略。
    case wait
    /// 截图等资源密集型命令超时策略。
    case screenshot
}

/// 命令合同元数据的来源。
public enum CommandContractSource: String, Sendable, Equatable {
    /// 由受控合同生成器产生的合同。
    case generated
    /// 由宿主在运行时注册的合同。
    case runtime
}

/// 命令合同构造和动作名校验错误。
public enum CommandContractError: Error, Sendable, Equatable {
    /// 动作名不符合协议允许的 ASCII 标识格式。
    case invalidAction(String)
}

/// 描述一个可注册命令的完整、Foundation-only 合同。
///
/// 合同只携带 wire 层 metadata，不携带输入 schema、UIKit、executor 或业务领域
/// 类型，因此可以安全地跨模块和 Swift 并发边界传递。实例本身不可变；运行时扩展应创建
/// 新值，而不是修改已发布合同。
public struct CommandContract: Sendable, Equatable {
    /// 命令名，也是 HTTP 请求中 `action` 字段的匹配键。
    public let action: String

    /// 命令的人类可读描述。
    public let description: String

    /// 提供该命令的模块或运行时扩展。
    public let provider: CommandContractProvider

    /// 命令的公开稳定性级别。
    public let stability: CommandContractStability

    /// 命令结果的 wire-level 表示类型。
    public let resultKind: CommandContractResultKind

    /// 命令可能返回的业务错误码。
    public let declaredErrors: [String]

    /// 命令的重复执行和重试安全性。
    public let idempotency: CommandContractIdempotency

    /// 命令使用的超时策略分类。
    public let timeoutClass: CommandContractTimeoutClass

    /// 这组合同遵循的版本号。
    public let contractVersion: String

    /// 规范化合同 bundle 的哈希，通常形如 `sha256:<64 位小写十六进制>`。
    public let contractHash: String

    /// 合同是生成产物还是运行时注册值。
    public let contractSource: CommandContractSource

    /// 创建一份不可变命令合同。
    ///
    /// - Parameters:
    ///   - action: 命令名；需要执行严格格式校验时先调用 `validateAction(_:)`。
    ///   - description: 命令的人类可读描述。
    ///   - provider: 提供命令的模块或运行时扩展。
    ///   - stability: 命令的公开稳定性级别。
    ///   - resultKind: 命令结果的 wire-level 表示类型。
    ///   - declaredErrors: 命令可能返回的业务错误码。
    ///   - idempotency: 命令的重复执行和重试安全性。
    ///   - timeoutClass: 命令使用的超时策略分类。
    ///   - contractVersion: 合同 bundle 版本号。
    ///   - contractHash: 规范化合同 bundle 的哈希。
    ///   - contractSource: 合同来源，默认是生成产物。
    public init(action: String,
                description: String,
                provider: CommandContractProvider,
                stability: CommandContractStability,
                resultKind: CommandContractResultKind,
                declaredErrors: [String],
                idempotency: CommandContractIdempotency,
                timeoutClass: CommandContractTimeoutClass,
                contractVersion: String,
                contractHash: String,
                contractSource: CommandContractSource = .generated) {
        self.action = action
        self.description = description
        self.provider = provider
        self.stability = stability
        self.resultKind = resultKind
        self.declaredErrors = declaredErrors
        self.idempotency = idempotency
        self.timeoutClass = timeoutClass
        self.contractVersion = contractVersion
        self.contractHash = contractHash
        self.contractSource = contractSource
    }

    /// 校验动作名是否匹配 `^[A-Za-z][A-Za-z0-9]*(?:[._-][A-Za-z0-9]+)*$`。
    ///
    /// - Parameter action: 待校验的动作名。
    /// - Returns: 动作名符合格式时正常返回，无返回值表示校验通过。
    /// - Throws: 动作名为空、含非 ASCII 字母数字字符、含空格或非法/尾部分隔符时抛出
    ///   `CommandContractError.invalidAction`。
    public static func validateAction(_ action: String) throws {
        let bytes = Array(action.utf8)
        guard let first = bytes.first, isASCIIAlpha(first) else {
            throw CommandContractError.invalidAction(action)
        }

        for index in 1..<bytes.count {
            let byte = bytes[index]
            if isASCIIAlphaNumeric(byte) {
                continue
            }
            guard isSeparator(byte),
                  index + 1 < bytes.count,
                  !isSeparator(bytes[index - 1]),
                  isASCIIAlphaNumeric(bytes[index + 1]) else {
                throw CommandContractError.invalidAction(action)
            }
        }
    }

    private static func isASCIIAlpha(_ byte: UInt8) -> Bool {
        (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122)
    }

    private static func isASCIIAlphaNumeric(_ byte: UInt8) -> Bool {
        isASCIIAlpha(byte) || (byte >= 48 && byte <= 57)
    }

    private static func isSeparator(_ byte: UInt8) -> Bool {
        byte == 46 || byte == 95 || byte == 45
    }
}
