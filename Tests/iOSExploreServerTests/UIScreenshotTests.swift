#if canImport(UIKit)
import UIKit
import Testing
import iOSExploreServer
@testable import iOSExploreUIKit

/// `ui.screenshot` 渲染流水线端到端测试。
///
/// 通过 `UIKitTestHost` 注入可控 window + view 树，真实驱动 `UIScreenshotCollector` 的
/// drawHierarchy → 降采样 → PNG 编码 → base64 → 签发 snapshot 流水线。logic test 没有
/// 真实 UIApplication scene，因此走注入入口 `collect(input:maxResponseBodyBytes:context:)`。
@MainActor
struct UIScreenshotTests {
    @Test("screenshot: base64 解码回 UIImage 非空 + 像素非全透明 + 签发 snapshot")
    func screenshotProducesValidImage() throws {
        let context = UIKitTestHost.context { root in
            // 含对比色背景，防空白位图假通过。
            root.backgroundColor = .red
            let label = UILabel()
            label.text = "hello"
            label.accessibilityIdentifier = "greeting"
            label.frame = CGRect(x: 20, y: 20, width: 120, height: 40)
            root.addSubview(label)
        }

        let data = try UIScreenshotCollector.collect(input: .init(),
                                                     maxResponseBodyBytes: 6_000_000,
                                                     context: context)

        let base64 = try #require(data["image"]?.stringValue)
        let format = try #require(data["format"]?.stringValue)
        #expect(format == "png")
        let png = try #require(Data(base64Encoded: base64))
        let img = try #require(UIImage(data: png))
        #expect(img.cgImage != nil)

        let pxW = try #require(data["width"]?.doubleValue)
        let pxH = try #require(data["height"]?.doubleValue)
        #expect(pxW > 0)
        #expect(pxH > 0)
        // 像素尺寸与解码回的 cgImage 对齐。
        #expect(Double(img.cgImage?.width ?? 0) == pxW)
        #expect(Double(img.cgImage?.height ?? 0) == pxH)

        // 防空白位图假通过：至少存在一个非透明像素。
        #expect(Self.hasNonTransparentPixel(img))

        // 签发了有效 snapshotID（默认筛选下含 identifier 节点，应非空）。
        #expect(data["snapshotID"]?.stringValue != nil)
    }

    @Test("screenshot: maxDimension 像素长边降采样生效")
    func screenshotDownsamplesPixelLongEdge() throws {
        let context = UIKitTestHost.context { root in
            root.backgroundColor = .blue
        }

        // 取一个较小的 maxDimension，强制触发降采样。
        let data = try UIScreenshotCollector.collect(input: UIScreenshotInput(maxDimension: 200),
                                                     maxResponseBodyBytes: 6_000_000,
                                                     context: context)

        let pxW = try #require(data["width"]?.doubleValue)
        let pxH = try #require(data["height"]?.doubleValue)
        let longestPx = max(pxW, pxH)
        // 降采样后长边不应显著超过 maxDimension（允许 1px 抽样误差）。
        #expect(longestPx <= 201)
        // pixelScale < 1 表示确实发生了降采样。
        let pixelScale = try #require(data["pixelScale"]?.doubleValue)
        #expect(pixelScale < 1.0)
    }

    @Test("screenshot: base64 估算超限返回 responseTooLarge")
    func screenshotRejectsTooLargeResponse() throws {
        let context = UIKitTestHost.context { root in
            root.backgroundColor = .green
        }

        #expect(throws: UIKitCommandError.self) {
            _ = try UIScreenshotCollector.collect(input: .init(),
                                                  maxResponseBodyBytes: 1,
                                                  context: context)
        }
    }

    /// 检查 UIImage 是否存在至少一个 alpha > 0 的像素，防止渲染出全透明空白位图假通过。
    private static func hasNonTransparentPixel(_ image: UIImage) -> Bool {
        guard let cg = image.cgImage else { return false }
        let width = cg.width
        let height = cg.height
        // 抽样：步长采样避免逐像素遍历大图，足够发现非透明像素。
        let stepX = max(1, width / 32)
        let stepY = max(1, height / 32)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        guard let context = CGContext(data: &pixels,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: bytesPerRow,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return false
        }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        for y in stride(from: 0, to: height, by: stepY) {
            for x in stride(from: 0, to: width, by: stepX) {
                let alpha = pixels[(y * width + x) * bytesPerPixel + 3]
                if alpha > 0 {
                    return true
                }
            }
        }
        return false
    }
}
#endif
