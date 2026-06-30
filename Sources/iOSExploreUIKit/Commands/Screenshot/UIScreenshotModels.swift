import Foundation
import iOSExploreServer

/// `ui.screenshot` 的命令参数（Foundation-only，macOS SPM 可测 schema/parse）。
///
/// 该类型刻意不 `import UIKit`，使 schema 与解析逻辑在 macOS 单元测试下可独立驱动，
/// 与既有 `UIViewTargetsInput` / `UIKitLocatorInput` 的拆分模式一致。UIKit 渲染逻辑由
/// `UIScreenshotCollector` 在 `#if canImport(UIKit)` 内完成，UIKit 类型不穿过本边界。
///
/// `maxDimension` 语义为像素（pixel）长边上限，不是 point：渲染后按 `cgImage.width/height`
/// 判断最长边并降采样，避免 Retina 屏 point 上限导致像素体积失控。
public struct UIScreenshotInput: CommandInput, Sendable, Equatable {
    private enum Fields {
        static let maxDimension = CommandFields.optionalNonNegativeInt(
            "maxDimension",
            description: "截图长边像素上限(1-4096), 默认 1280"
        )

        static let all: [AnyCommandField] = [maxDimension.erased]
    }

    /// `ui.screenshot` 暴露给 help 和工具客户端的输入 schema。
    public static let inputSchema = CommandInputSchema(fields: Fields.all, constraints: [])

    /// 截图长边像素上限。渲染后最长像素边超过该值时按比例降采样。
    public let maxDimension: Int

    /// 创建截图输入。
    ///
    /// - Parameter maxDimension: 长边像素上限，默认 1280，合法范围 1-4096。
    public init(maxDimension: Int = 1280) {
        self.maxDimension = maxDimension
    }

    /// 按 `CommandInputDecoder` 读取 `maxDimension` 并执行 1-4096 范围校验。
    ///
    /// 缺省值由本方法在读取后填充（默认 1280），保证 schema 暴露的"可选字段"语义与实际
    /// 默认行为一致；范围越界抛出 `CommandInputParseError`，由 `AnyCommand` 转 `invalid_data`。
    ///
    /// - Parameter decoder: 绑定 `inputSchema` 与请求 data 的字段读取器。
    /// - Returns: 已完成默认值填充与范围校验的截图输入。
    /// - Throws: `maxDimension` 不在 1-4096 时抛出 `CommandInputParseError`。
    public static func parse(decoding decoder: inout CommandInputDecoder) throws -> UIScreenshotInput {
        let raw = try decoder.read(Fields.maxDimension)
        let dim = raw ?? 1280
        guard (1...4096).contains(dim) else {
            throw CommandInputParseError("maxDimension must be in 1...4096")
        }
        return UIScreenshotInput(maxDimension: dim)
    }
}
