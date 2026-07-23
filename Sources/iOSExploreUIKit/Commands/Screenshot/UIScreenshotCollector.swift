#if canImport(UIKit)
import Foundation
import iOSExploreServer
import UIKit

/// `ui.screenshot` 的渲染与编码核心。
///
/// 运行在 `MainActor`：负责取当前前台上下文、检测控制器过渡态、`drawHierarchy` 截屏、
/// 按像素长边降采样、PNG 编码、体积前置检查（base64 前拦截避免分配峰值）。所有 UIKit 对象
/// （`UIImage`/`UIWindow`/`UIView`）均不跨 actor 边界，返回值为纯 `JSON`（base64 字符串 +
/// 像素尺寸）。
///
/// **`ui.screenshot` 只是可选的视觉证据**：它不签发、不刷新、不返回 `viewSnapshotID`，也不
/// 参与结构化 freshness / 动作授权 / locator 签发。`viewSnapshotID` 只由 `ui.inspect`
/// 签发。截图用于人工排障或支持多模态的 Agent 的可选增强输入。
///
/// 失败统一 `throw UIKitCommandError`，由 `ScreenshotCommand` 顶层 catch 转 envelope。
@MainActor
enum UIScreenshotCollector {
    /// 采集当前前台 window 的截图。
    ///
    /// 流程：currentContext → transitionCoordinator 检测 → `drawHierarchy`（捕获 Bool）→
    /// 像素长边降采样 → MainActor PNG 编码 → 体积前置检查（base64 之前）→ base64 → 返回 JSON。
    ///
    /// - Parameters:
    ///   - input: 截图参数，`maxDimension` 为像素长边上限。
    ///   - maxResponseBodyBytes: 响应 body 字节上限，base64 估算超限即抛 `responseTooLarge`。
    /// - Returns: 含 `image`(base64)/`format`/`width`/`height`/`scale`/`pixelScale` 的 JSON。
    /// - Throws: `UIKitCommandError`——过渡态、渲染失败、PNG 编码失败、响应过大、上下文不可用。
    static func collect(input: UIScreenshotInput, maxResponseBodyBytes: Int) throws -> JSON {
        let action = ScreenshotCommand.actionName
        UIKitCommandLogger.info("command", "ui screenshot start maxDimension=\(input.maxDimension)")
        let context = try UIKitContextProvider.currentContext(action: action)
        return try collect(input: input, maxResponseBodyBytes: maxResponseBodyBytes, context: context)
    }

    /// 采集截图（注入入口：测试与内部复用）。
    ///
    /// 与 `collect(input:maxResponseBodyBytes:)` 的唯一区别是上下文由调用方提供，使渲染流水线
    /// 可在 logic test 里用 `UIKitTestHost` 构造的可控 window 驱动（真实 `currentContext` 依赖
    /// 前台 scene，logic test 没有）。其余逻辑完全一致。
    ///
    /// - Parameters:
    ///   - input: 截图参数。
    ///   - maxResponseBodyBytes: 响应 body 字节上限。
    ///   - context: 当前 UIKit 查询上下文（持有真实 window，可由测试构造）。
    /// - Returns: 截图 JSON。
    /// - Throws: `UIKitCommandError`——过渡态、渲染失败、PNG 编码失败、响应过大。
    static func collect(input: UIScreenshotInput,
                         maxResponseBodyBytes: Int,
                         context: UIKitContextProvider.Context) throws -> JSON {
        let action = ScreenshotCommand.actionName

        // 1. VC transition 检测：过渡中当前帧不可靠，提示调用方重试（不覆盖键盘动画——已知限制）。
        if context.topViewController.transitionCoordinator != nil {
            throw UIKitCommandError.transitionInProgress(action: action)
        }
        // Context.window 非 Optional，直接绑定避免 guard let 语义漂移。
        let window = context.window

        // 2. MainActor 渲染：截当前帧。
        //
        //    优先 `drawHierarchy(afterScreenUpdates: false)`：生产环境 keyWindow 已上屏，
        //    false 既能截到当前帧又避免触发额外布局/渲染循环。未渲染过的 window（页面从未
        //    上屏的极端场景）下 false 会失败——按 Apple 指引用 `afterScreenUpdates: true`
        //    重试一次（强制一次渲染循环）。
        //
        //    若两次都失败（如 window 未挂到真实 render server，典型于无 UIWindowScene 的
        //    logic test），回退到 `layer.render`：CPU 侧逐层合成，不依赖 render server，能
        //    覆盖 drawHierarchy 无法工作的场景。三者均失败才判定渲染失败。
        let image = try Self.renderWindow(window, action: action)

        // 3. 降采样到 maxDimension 像素长边（用 cgImage 像素，非 point）。
        guard let cg = image.cgImage else {
            throw UIKitCommandError.renderingFailed(action: action, reason: "no cgImage")
        }
        let longestPx = max(cg.width, cg.height)
        let pixelScale: Double = longestPx > input.maxDimension
            ? Double(input.maxDimension) / Double(longestPx)
            : 1.0
        let scaledImage: UIImage
        if pixelScale < 1.0 {
            let newSize = CGSize(width: image.size.width * pixelScale, height: image.size.height * pixelScale)
            let scaler = UIGraphicsImageRenderer(size: newSize)
            scaledImage = scaler.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
        } else {
            scaledImage = image
        }

        // 4. MainActor PNG 编码（UIImage 非 Sendable，不跨 actor；pngData 必须在 MainActor）。
        guard let pngData = scaledImage.pngData(), !pngData.isEmpty else {
            throw UIKitCommandError.renderingFailed(action: action, reason: "png encode failed")
        }

        // 5. 体积前置检查：base64 ≈ pngData × 4/3。在编码之前拦截，避免分配巨大字符串峰值。
        let estimated = pngData.count * 4 / 3
        if estimated > maxResponseBodyBytes {
            throw UIKitCommandError(code: .responseTooLarge,
                                    message: "screenshot too large; reduce maxDimension",
                                    logMessage: "ui screenshot too large action=\(action) bytes=\(pngData.count) est=\(estimated) limit=\(maxResponseBodyBytes)")
        }
        let base64 = pngData.base64EncodedString()

        // window.screen 非 Optional（UIWindow.screen 在 iOS 13+ 为非可选）。
        // screenshot 不签发 viewSnapshotID（结构化 freshness / locator 由 ui.inspect 负责）。
        let screenScale = window.screen.scale
        let scaledPxW = scaledImage.cgImage?.width ?? 0
        let scaledPxH = scaledImage.cgImage?.height ?? 0
        UIKitCommandLogger.info("command", "ui screenshot completed pngBytes=\(pngData.count) pxW=\(scaledPxW) pxH=\(scaledPxH) pixelScale=\(pixelScale)")

        return [
            "image": .string(base64),
            "format": .string("png"),
            "width": .double(Double(scaledPxW)),
            "height": .double(Double(scaledPxH)),
            "scale": .double(Double(screenScale)),
            "pixelScale": .double(pixelScale),
        ]
    }

    /// 渲染 window 为 UIImage，按 drawHierarchy(false) → drawHierarchy(true) → layer.render
    /// 顺序回退。
    ///
    /// - Parameters:
    ///   - window: 待截屏的前台 window。
    ///   - action: 触发渲染的 action 名，用于失败日志关联。
    /// - Returns: 渲染出的 UIImage。
    /// - Throws: `UIKitCommandError.renderingFailed`——三种渲染路径全部失败时。
    private static func renderWindow(_ window: UIWindow, action: String) throws -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: window.bounds.size)
        var attemptedRender = false
        let image = renderer.image { context in
            // false 优先（避免副作用），失败再 true（强制渲染），均失败则 layer.render 兜底。
            attemptedRender = window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
                || window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            if !attemptedRender {
                // layer.render：CPU 侧合成，不依赖 render server。覆盖无 scene 的场景。
                context.cgContext.saveGState()
                window.layer.render(in: context.cgContext)
                context.cgContext.restoreGState()
                attemptedRender = true
            }
        }
        guard attemptedRender, image.cgImage != nil else {
            throw UIKitCommandError.renderingFailed(action: action, reason: "drawHierarchy and layer render both failed")
        }
        return image
    }
}
#endif
