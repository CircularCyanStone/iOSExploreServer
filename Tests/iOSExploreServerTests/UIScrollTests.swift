#if canImport(UIKit)
import UIKit
import Testing
import iOSExploreServer
@testable import iOSExploreUIKit

/// `ui.scroll` 执行核心（`UIScrollExecutor.execute`）的 iOS 测试。
///
/// 通过 `UIKitTestHost` 注入可控 view 树，真实驱动 executor 的 locate → nearestScrollView
/// → setContentOffset → reachedExtent 全部分支。executor 已 throw 化：成功路径用 `try`
/// 直取 JSON，失败路径用 do/catch 断言 `error.failure.code`。
///
/// 用裸 `UIScrollView`（而非 UICollectionView/UITableView）：只需设置 contentSize 即可
/// 确定性地构造超屏内容，避免 collection 视图的布局/数据源依赖。

@Test("scroll: down 后 offset.y 增大量恰为 amount 且回传 adjustedContentInset 全 4 字段") @MainActor
func scrollDownIncreasesOffset() throws {
    let context = UIKitTestHost.context { root in
        let scrollView = UIScrollView()
        scrollView.accessibilityIdentifier = "list.scroll"
        scrollView.frame = CGRect(x: 0, y: 0, width: 320, height: 568)
        // 内容远超可见高度，向下滚 200pt 不会触底。
        scrollView.contentSize = CGSize(width: 320, height: 2000)
        root.addSubview(scrollView)
    }

    let input = UIScrollInput(direction: .down, amount: 200, locator: .accessibilityIdentifier("list.scroll"))
    let data = try UIScrollExecutor.execute(input: input, context: context)

    // iPhone 模拟器有 safe area inset，UIScrollView 初始 contentOffset.y = -adjustedContentInset.top，
    // 故 before 不一定是 0；executor 的正确性体现在「after - before == amount」。
    let beforeY = try #require(nestedDouble(data, "offsetBefore", "y"))
    let afterY = try #require(nestedDouble(data, "offsetAfter", "y"))
    #expect(afterY - beforeY == 200)
    // 内容 2000 远大于屏高，向下 200pt 不会触底（reachedExtent 不应是 bottom/top）。
    #expect(data["reachedExtent"]?.stringValue != "bottom")
    #expect(data["reachedExtent"]?.stringValue != "top")
    // adjustedContentInset 全 4 字段都回传（key 存在；具体值随 safe area 变化，不锁死）。
    #expect(nestedDouble(data, "adjustedContentInset", "top") != nil)
    #expect(nestedDouble(data, "adjustedContentInset", "bottom") != nil)
    #expect(nestedDouble(data, "adjustedContentInset", "left") != nil)
    #expect(nestedDouble(data, "adjustedContentInset", "right") != nil)
    #expect(data["container"]?.stringValue == "UIScrollView")
}

@Test("scroll: 无定位字段回退到 keyWindow 最前 scrollView") @MainActor
func scrollFallsBackToForemostScrollView() throws {
    let context = UIKitTestHost.context { root in
        let scrollView = UIScrollView()
        scrollView.frame = CGRect(x: 0, y: 0, width: 320, height: 568)
        scrollView.contentSize = CGSize(width: 320, height: 2000)
        root.addSubview(scrollView)
    }

    // locator 缺省，executor 应回退扫描 keyWindow。
    let input = UIScrollInput(direction: .down, amount: 100)
    let data = try UIScrollExecutor.execute(input: input, context: context)

    // 回退扫描命中 scrollView，after - before == amount 即证明回退成功。
    let beforeY = try #require(nestedDouble(data, "offsetBefore", "y"))
    let afterY = try #require(nestedDouble(data, "offsetAfter", "y"))
    #expect(afterY - beforeY == 100)
}

@Test("scroll: 向上回到顶部触发 reachedExtent=top") @MainActor
func scrollUpAtTopReachesTopExtent() throws {
    let context = UIKitTestHost.context { root in
        let scrollView = UIScrollView()
        scrollView.frame = CGRect(x: 0, y: 0, width: 320, height: 568)
        scrollView.contentSize = CGSize(width: 320, height: 2000)
        // 先把 contentOffset 挪到中部，再向上滚一大段回到顶部。
        scrollView.setContentOffset(CGPoint(x: 0, y: 500), animated: false)
        root.addSubview(scrollView)
    }

    // 用 path 定位第一个子 view（scrollView 本身）。
    let input = UIScrollInput(direction: .up, amount: 1000, locator: .path([0]))
    let data = try UIScrollExecutor.execute(input: input, context: context)

    // 向上滚一大段越过顶部；reachedExtent 必为 top（offset.y 已 <= -adjustedContentInset.top + 1）。
    #expect(data["reachedExtent"]?.stringValue == "top")
    // after.y 必然 <= -adjustedContentInset.top（越界到顶部以上）。
    let afterY = try #require(nestedDouble(data, "offsetAfter", "y"))
    let insetTop = try #require(nestedDouble(data, "adjustedContentInset", "top"))
    #expect(afterY <= -insetTop + 1)
}

@Test("scroll: 纯 UIView 无 scrollView 祖先抛 scrollContainerUnavailable") @MainActor
func scrollRejectsPlainUIView() {
    let context = UIKitTestHost.context { root in
        let label = UILabel()
        label.accessibilityIdentifier = "static.label"
        label.frame = CGRect(x: 10, y: 10, width: 200, height: 40)
        root.addSubview(label)
    }

    let input = UIScrollInput(direction: .down, amount: 50, locator: .accessibilityIdentifier("static.label"))
    do {
        _ = try UIScrollExecutor.execute(input: input, context: context)
        Issue.record("expected failure, got success")
    } catch let error as UIKitCommandError {
        #expect(error.failure.code == .scrollContainerUnavailable)
    } catch {
        Issue.record("unexpected error: \(error)")
    }
}

@Test("scroll: keyWindow 无 scrollView 回退扫描抛 scrollContainerUnavailable") @MainActor
func scrollRejectsWhenNoScrollViewAnywhere() {
    let context = UIKitTestHost.context { root in
        let label = UILabel()
        label.frame = CGRect(x: 10, y: 10, width: 200, height: 40)
        root.addSubview(label)
    }

    // 无定位字段、window 内无 scrollView → 回退扫描失败。
    let input = UIScrollInput(direction: .down, amount: 50)
    do {
        _ = try UIScrollExecutor.execute(input: input, context: context)
        Issue.record("expected failure, got success")
    } catch let error as UIKitCommandError {
        #expect(error.failure.code == .scrollContainerUnavailable)
    } catch {
        Issue.record("unexpected error: \(error)")
    }
}

@Test("scroll: UITextView 不被当作 scroll 容器") @MainActor
func scrollExcludesUITextView() {
    let context = UIKitTestHost.context { root in
        // UITextView 是 UIScrollView 子类，但应被排除。
        let textView = UITextView()
        textView.accessibilityIdentifier = "editor.text"
        textView.frame = CGRect(x: 0, y: 0, width: 320, height: 200)
        textView.text = String(repeating: "line\n", count: 100)
        root.addSubview(textView)
    }

    // 直接定位 textView：nearestScrollView 应排除 UITextView 向上找不到其它 scrollView → 抛错。
    let input = UIScrollInput(direction: .down, amount: 50, locator: .accessibilityIdentifier("editor.text"))
    do {
        _ = try UIScrollExecutor.execute(input: input, context: context)
        Issue.record("expected failure, got success")
    } catch let error as UIKitCommandError {
        #expect(error.failure.code == .scrollContainerUnavailable)
    } catch {
        Issue.record("unexpected error: \(error)")
    }
}

/// 从 JSON 响应里取「对象键 → 数字字段」的二级嵌套 Double。
private func nestedDouble(_ json: JSON, _ outer: String, _ inner: String) -> Double? {
    guard case .object(let innerJSON)? = json[outer] else { return nil }
    return innerJSON[inner]?.doubleValue
}

#endif
