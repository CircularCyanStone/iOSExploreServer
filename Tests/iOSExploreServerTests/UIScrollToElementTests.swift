#if canImport(UIKit)
import UIKit
import Testing
import iOSExploreServer
@testable import iOSExploreUIKit

/// `ui.scrollToElement` 执行核心的 iOS 测试。
/// 覆盖 text 命中（scrollRectToVisible）、目标缺失、container 非 scrollView 三条路径。

@Test("scrollToElement text 找到 UILabel 并滚到可见") @MainActor
func scrollToElementFindsLabel() throws {
    var scrollView: UIScrollView!
    let context = UIKitTestHost.context { root in
        let sv = UIScrollView()
        sv.accessibilityIdentifier = "list"
        sv.frame = CGRect(x: 0, y: 0, width: 320, height: 568)
        sv.contentSize = CGSize(width: 320, height: 2000)
        // 目标 label 在 contentSize 底部（滚出可见区）。
        let label = UILabel()
        label.text = "订单详情"
        label.frame = CGRect(x: 0, y: 1500, width: 200, height: 40)
        sv.addSubview(label)
        root.addSubview(sv)
        scrollView = sv
    }
    let beforeY = scrollView.contentOffset.y
    let input = UIScrollToElementInput(value: "订单", container: .accessibilityIdentifier("list"))
    let data = try UIScrollToElementExecutor.execute(input: input, context: context)
    let afterY = scrollView.contentOffset.y
    #expect(data["found"]?.boolValue == true)
    #expect(data["match"]?.stringValue == "text")
    #expect(data["targetType"]?.stringValue == "UILabel")
    // 验证 scrollRectToVisible 真的滚动了（目标在 y=1500，必须向下滚）。
    #expect(afterY > beforeY)
}

@Test("scrollToElement 目标缺失抛 targetNotFound") @MainActor
func scrollToElementTargetNotFoundThrows() {
    let context = UIKitTestHost.context { root in
        let scrollView = UIScrollView()
        scrollView.frame = CGRect(x: 0, y: 0, width: 320, height: 568)
        scrollView.contentSize = CGSize(width: 320, height: 2000)
        root.addSubview(scrollView)
    }
    let input = UIScrollToElementInput(value: "不存在")
    do {
        _ = try UIScrollToElementExecutor.execute(input: input, context: context)
        Issue.record("expected failure, got success")
    } catch let error as UIKitCommandError {
        #expect(error.failure.code == .targetNotFound)
    } catch {
        Issue.record("unexpected error: \(error)")
    }
}

@Test("scrollToElement container 非 scrollView 抛 scrollContainerUnavailable") @MainActor
func scrollToElementContainerNotScrollViewThrows() {
    let context = UIKitTestHost.context { root in
        let label = UILabel()
        label.accessibilityIdentifier = "notscroll"
        label.frame = CGRect(x: 0, y: 0, width: 100, height: 40)
        root.addSubview(label)
    }
    let input = UIScrollToElementInput(value: "x", container: .accessibilityIdentifier("notscroll"))
    do {
        _ = try UIScrollToElementExecutor.execute(input: input, context: context)
        Issue.record("expected failure, got success")
    } catch let error as UIKitCommandError {
        #expect(error.failure.code == .scrollContainerUnavailable)
    } catch {
        Issue.record("unexpected error: \(error)")
    }
}

@Test("scrollToElement 容器禁用滚动抛 containerNotScrollable") @MainActor
func scrollToElementDisabledContainerThrows() {
    let context = UIKitTestHost.context { root in
        let scrollView = UIScrollView()
        scrollView.frame = CGRect(x: 0, y: 0, width: 320, height: 568)
        scrollView.contentSize = CGSize(width: 320, height: 2000)
        // 禁用滚动：scrollRectToVisible 会变 no-op，executor 必须显式失败而非 found=true。
        // 容器已存在但不可滚动——区别于容器不存在（scrollContainerUnavailable），命中
        // containerNotScrollable，避免 agent 误以为容器不存在而反复 inspect 重试。
        scrollView.isScrollEnabled = false
        let label = UILabel()
        label.text = "目标"
        label.frame = CGRect(x: 0, y: 1500, width: 200, height: 40)
        scrollView.addSubview(label)
        root.addSubview(scrollView)
    }
    let input = UIScrollToElementInput(value: "目标")
    do {
        _ = try UIScrollToElementExecutor.execute(input: input, context: context)
        Issue.record("expected failure, got success")
    } catch let error as UIKitCommandError {
        #expect(error.failure.code == .containerNotScrollable)
        #expect(error.failure.message == "scroll container exists but is not scrollable (isScrollEnabled=false or window=nil)")
    } catch {
        Issue.record("unexpected error: \(error)")
    }
}
#endif
