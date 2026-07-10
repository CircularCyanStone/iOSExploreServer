#if canImport(UIKit)
import UIKit
import Testing
import iOSExploreServer
@testable import iOSExploreUIKit

/// `ui.tap` cell selection adapter（`UIGestureTargetExecutor.executeCellSelection` +
/// `UIKitActionExecutor.executeTap` 的 cellSelection 分支）的运行时测试。
///
/// 通过 `UIKitTestHost` 注入挂有 `UITableView`/`UICollectionView` + cell + delegate 的 view 树，
/// 先用 `UIInspectCollector.collect` 签发 `viewSnapshotID`（cell 子 view 经 canonical-only
/// 口径采集），再驱动 executor 的 locate / freshness / cellSelection 派发。覆盖：
/// - 非 cell 子树 view 返回 nil（executeTap 走原有 gesture adapter 分支不误触）。
/// - cell 子树 + 公有 API 路径命中 → activated=true, route=cell.select.public, indexPath 填回。
/// - indexPath(for:) 失败（cell 未注册）→ activated=false, route=cell.select.indexPath-nil。
/// - capability resolver 对 cell 子树 view 声明 .tap。
/// - UICollectionView 镜像覆盖。
///
/// 注意：`indexPath(for:)` 依赖 cell 经 `tableView.register + dequeueReusableCell` 注册到内部表，
/// 测试需复刻该流程；纯 `cell.addSubview` + `tableView.addSubview(cell)` 的合成 cell
/// `indexPath(for:)` 会返回 nil，正合「失败路径」测试需要。

/// 取一次 `ui.inspect` 签发的 viewSnapshotID，供 `ui.tap` 携带做 freshness 校验。
@MainActor
private func testViewSnapshotID(context: UIKitContextProvider.Context) -> String {
    let data = UIInspectCollector.collect(query: .default, context: context)
    guard let id = data["viewSnapshotID"]?.stringValue else {
        Issue.record("collect should produce viewSnapshotID")
        return ""
    }
    return id
}

/// 测试用 UITableViewDelegate：记录最后一次 didSelectRowAt 的 indexPath。
@MainActor
private final class TestTableViewDelegate: NSObject, UITableViewDelegate {
    var lastSelectedIndexPath: IndexPath?

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        lastSelectedIndexPath = indexPath
    }
}

/// 测试用 UICollectionViewDelegate：记录最后一次 didSelectItemAt 的 indexPath。
@MainActor
private final class TestCollectionViewDelegate: NSObject, UICollectionViewDelegate {
    var lastSelectedIndexPath: IndexPath?

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        lastSelectedIndexPath = indexPath
    }
}

/// 测试用 cell：注册到 tableView/collectionView，便于 indexPath(for:) 解析。
@MainActor
private final class TestTableViewCell: UITableViewCell {}
@MainActor
private final class TestCollectionViewCell: UICollectionViewCell {}

// MARK: - executeCellSelection 直接调用

@Test("executeCellSelection 非 cell 子树 view 返回 nil") @MainActor
func cellSelectionReturnsNilForNonCellSubtreeView() {
    let context = UIKitTestHost.context { root in
        let view = UIView(frame: CGRect(x: 10, y: 10, width: 100, height: 100))
        view.isUserInteractionEnabled = true
        root.addSubview(view)
    }
    // root 的第一个 subview 是测试 view，不是 cell 子树。
    let nonCellView = context.rootView.subviews.first!
    let attempt = UIGestureTargetExecutor.executeCellSelection(on: nonCellView)
    #expect(attempt == nil, "非 cell 子树 view 应返回 nil，让 executeTap 走原 gesture adapter 分支")
}

@Test("executeCellSelection cell 子树但无 tableView 祖先返回 nil") @MainActor
func cellSelectionReturnsNilForCellWithoutTableViewAncestor() {
    // 直接构造一个 cell，不放 tableView，单独 addSubview 到 root。
    let context = UIKitTestHost.context { root in
        let cell = TestTableViewCell(frame: CGRect(x: 10, y: 10, width: 100, height: 50))
        root.addSubview(cell)
    }
    // root 的第一个 subview 是 cell；cell.explore_cellAncestor 找不到 cell 祖先（cell 自身不算）。
    // 因此这里实际上测的是「cell 自身作为入参」 → explore_cellAncestor 返回 nil → 函数返回 nil。
    let cellView = context.rootView.subviews.first!
    let attempt = UIGestureTargetExecutor.executeCellSelection(on: cellView)
    #expect(attempt == nil, "cell 自身作为入参，向上找不到 cell 祖先，应返回 nil")
}

@Test("executeCellSelection cell 子树 + UITableViewDelegate 命中 → activated=true route=cell.select.public") @MainActor
func cellSelectionHitsPublicAPIPath() throws {
    let delegate = TestTableViewDelegate()
    // `UITableView.dataSource`/`delegate` 是 weak：直接把临时对象 `TestTableViewDataSource()`
    // 赋给它会立即被释放，`dataSource` 变 nil。必须像 delegate 一样在闭包外用 let 强引用持有，
    // 否则下方 `dataSource.tableView(...)` 与 `indexPath(for:)` 都拿不到 data source。
    let dataSource = TestTableViewDataSource()
    var tableViewHolder: UITableView?
    let context = UIKitTestHost.context { root in
        let tableView = UITableView(frame: CGRect(x: 0, y: 0, width: 320, height: 568), style: .plain)
        tableView.register(TestTableViewCell.self, forCellReuseIdentifier: "TestCell")
        tableView.delegate = delegate
        tableView.dataSource = dataSource
        tableView.reloadData()
        root.addSubview(tableView)
        tableViewHolder = tableView
    }
    let tableView = tableViewHolder!
    // 触发布局 + 让出一次 RunLoop，使 UITableView 在 key window 上真正完成 cell 的实例化与
    // 插入子树（reloadData + layoutIfNeeded 在无 run loop 的 logic-test 里不会立即渲染可见 cell，
    // 必须转一次 RunLoop 让 display cycle commit）。之后用 visibleCells 取已挂入子树的 cell，
    // 而非直接调 dataSource.cellForRowAt（后者 dequeue 出的 cell 不在层级里、indexPath(for:) 也为 nil）。
    tableView.layoutIfNeeded()
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
    let cell = tableView.visibleCells.first!
    let contentView = cell.contentView
    let attempt = UIGestureTargetExecutor.executeCellSelection(on: contentView)

    #expect(attempt != nil)
    #expect(attempt?.activated == true)
    #expect(attempt?.activationRoute == "cell.select.public")
    #expect(attempt?.containerViewType == "UITableView")
    #expect(attempt?.cellType == "TestTableViewCell")
    #expect(attempt?.indexPathSummary == IndexPathSummary(section: 0, item: 0))
    #expect(delegate.lastSelectedIndexPath == IndexPath(row: 0, section: 0),
           "executeCellSelection 应通过 delegate.didSelectRow 真正触发 selection 回调")
}

@Test("executeCellSelection cell 子树 indexPath(for:) 失败 → activated=false route=cell.select.indexPath-nil") @MainActor
func cellSelectionFailsWhenIndexPathReturnsNil() {
    // 构造tableView 但不放任何已注册 cell，indexPath(for:) 会返回 nil。
    let delegate = TestTableViewDelegate()
    let context = UIKitTestHost.context { root in
        let tableView = UITableView(frame: CGRect(x: 0, y: 0, width: 320, height: 568), style: .plain)
        tableView.delegate = delegate
        // 不 register、不 dataSource、不 reloadData —— 直接 addSubview 一个孤立 cell。
        let cell = TestTableViewCell()
        cell.frame = CGRect(x: 0, y: 0, width: 320, height: 50)
        tableView.addSubview(cell)
        root.addSubview(tableView)
    }
    let tableView = context.rootView.subviews.first as! UITableView
    let cell = tableView.subviews.first(where: { $0 is UITableViewCell }) as! UITableViewCell

    // 传 cell.contentView（而非 cell 自身）：executeCellSelection 的 explore_cellAncestor 不含
    // 自身，需从 cell 的子 view 入手才能命中 cell 祖先。此处 cell 经 addSubview 手动挂入
    // tableView 子树但未 register，indexPath(for:) 返回 nil，正合 indexPath-nil 失败路径。
    let attempt = UIGestureTargetExecutor.executeCellSelection(on: cell.contentView)

    #expect(attempt != nil)
    #expect(attempt?.activated == false)
    #expect(attempt?.activationRoute == "cell.select.indexPath-nil")
    #expect(delegate.lastSelectedIndexPath == nil, "indexPath(for:) 失败时不应触发 didSelectRow")
}

// MARK: - UICollectionView 镜像

@Test("executeCellSelection UICollectionView cell 子树命中 → activated=true route=cell.select.public") @MainActor
func cellSelectionHitsPublicAPIPathForCollectionView() throws {
    let delegate = TestCollectionViewDelegate()
    // `UICollectionView.dataSource` 同 UITableView 是 weak，临时对象需用 let 强引用持有。
    let dataSource = TestCollectionViewDataSource()
    var collectionViewHolder: UICollectionView?
    let context = UIKitTestHost.context { root in
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 320, height: 50)
        layout.minimumLineSpacing = 0
        let collectionView = UICollectionView(frame: CGRect(x: 0, y: 0, width: 320, height: 568), collectionViewLayout: layout)
        collectionView.register(TestCollectionViewCell.self, forCellWithReuseIdentifier: "TestCell")
        collectionView.delegate = delegate
        collectionView.dataSource = dataSource
        collectionView.reloadData()
        root.addSubview(collectionView)
        collectionViewHolder = collectionView
    }
    let collectionView = collectionViewHolder!
    // 让出一次 RunLoop 使 UICollectionView 真正渲染可见 cell（同 UITableView，见 cellSelectionHitsPublicAPIPath 注释）。
    collectionView.layoutIfNeeded()
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
    let cell = collectionView.visibleCells.first!
    let attempt = UIGestureTargetExecutor.executeCellSelection(on: cell.contentView)

    #expect(attempt != nil)
    #expect(attempt?.activated == true)
    #expect(attempt?.activationRoute == "cell.select.public")
    #expect(attempt?.containerViewType == "UICollectionView")
    #expect(attempt?.cellType == "TestCollectionViewCell")
    #expect(attempt?.indexPathSummary == IndexPathSummary(section: 0, item: 0))
    #expect(delegate.lastSelectedIndexPath == IndexPath(item: 0, section: 0))
}

// MARK: - UIKitActionExecutor.execute 端到端

@Test("executeTap cell 子树 view 命中 cellSelection → 返回 cell.select.public JSON") @MainActor
func executeTapCellSubtreeReturnsCellSelectionJSON() throws {
    let delegate = TestTableViewDelegate()
    // `UITableView.dataSource` 是 weak，临时对象需用 let 强引用持有（同 cellSelectionHitsPublicAPIPath）。
    let dataSource = TestTableViewDataSource()
    var tableViewHolder: UITableView?
    let context = UIKitTestHost.context { root in
        let tableView = UITableView(frame: CGRect(x: 0, y: 0, width: 320, height: 568), style: .plain)
        tableView.register(TestTableViewCell.self, forCellReuseIdentifier: "TestCell")
        tableView.delegate = delegate
        tableView.dataSource = dataSource
        tableView.reloadData()
        root.addSubview(tableView)
        tableViewHolder = tableView
    }
    let tableView = tableViewHolder!
    // 让出一次 RunLoop 使 UITableView 真正渲染可见 cell（见 cellSelectionHitsPublicAPIPath 注释）。
    tableView.layoutIfNeeded()
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
    let cell = tableView.visibleCells.first!
    let contentView = cell.contentView
    // 先让 cell 渲染入子树，再采集 viewSnapshotID，确保签发的指纹表包含目标 contentView。
    let viewSnapshotID = testViewSnapshotID(context: context)

    let path = try locatePath(of: contentView, in: context.rootView)
    let data = try UIKitActionExecutor.execute(.tap(locator: .path(path), viewSnapshotID: viewSnapshotID),
                                                context: context)

    #expect(data["activated"]?.boolValue == true)
    #expect(data["activationRoute"]?.stringValue == "cell.select.public")
    #expect(data["containerType"]?.stringValue == "UITableView")
    #expect(data["cellType"]?.stringValue == "TestTableViewCell")
    #expect(data["indexPath"]?.objectValue?["section"]?.doubleValue == 0)
    #expect(data["indexPath"]?.objectValue?["item"]?.doubleValue == 0)
    #expect(delegate.lastSelectedIndexPath == IndexPath(row: 0, section: 0))
}

// MARK: - capability resolver cell 子树声明

@Test("capability resolver 对 cell 子树 view 声明 tap") @MainActor
func capabilityResolverDeclaresTapForCellSubtreeView() {
    // `UITableView.dataSource` 是 weak，临时对象需用 let 强引用持有（同 cellSelectionHitsPublicAPIPath）。
    let dataSource = TestTableViewDataSource()
    var tableViewHolder: UITableView?
    let context = UIKitTestHost.context { root in
        let tableView = UITableView(frame: CGRect(x: 0, y: 0, width: 320, height: 568), style: .plain)
        tableView.register(TestTableViewCell.self, forCellReuseIdentifier: "TestCell")
        tableView.dataSource = dataSource
        tableView.reloadData()
        root.addSubview(tableView)
        tableViewHolder = tableView
    }
    let tableView = tableViewHolder!
    // 让出一次 RunLoop 使 UITableView 真正渲染可见 cell（见 cellSelectionHitsPublicAPIPath 注释）。
    tableView.layoutIfNeeded()
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
    let cell = tableView.visibleCells.first!
    let contentView = cell.contentView

    let availability = UIKitActionCapabilityResolver.resolve(view: contentView, rootView: context.rootView)
    #expect(availability.actions.contains(.tap),
           "cell 子树 view（contentView）应声明 tap，因为 cellSelection adapter 能为其派发 didSelectRow")
}

@Test("capability resolver 非 cell 子树 view 不靠 cell 子树声明 tap") @MainActor
func capabilityResolverDoesNotDeclareTapForNonCellSubtreeView() {
    let context = UIKitTestHost.context { root in
        let view = UIView(frame: CGRect(x: 10, y: 10, width: 100, height: 100))
        view.isUserInteractionEnabled = true
        root.addSubview(view)
    }
    let view = context.rootView.subviews.first!
    let availability = UIKitActionCapabilityResolver.resolve(view: view, rootView: context.rootView)
    #expect(!availability.actions.contains(.tap),
           "普通 UIView（非 cell 子树、无默认激活路由）不应声明 tap")
}

// MARK: - 测试辅助类型

/// 测试用 UITableViewDataSource：返回 1 行 TestTableViewCell。
@MainActor
private final class TestTableViewDataSource: NSObject, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 1 }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        tableView.dequeueReusableCell(withIdentifier: "TestCell", for: indexPath)
    }
}

/// 测试用 UICollectionViewDataSource：返回 1 个 TestCollectionViewCell。
@MainActor
private final class TestCollectionViewDataSource: NSObject, UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { 1 }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        collectionView.dequeueReusableCell(withReuseIdentifier: "TestCell", for: indexPath)
    }
}

/// 用 view 树遍历找到 view 在 root 中的整数索引 path（供 executor 的 .path locator 使用）。
///
/// 这是对 `UIKitLocatorResolver.LocatedView.pathString` 的逆操作简化版，仅用于测试构造 path 输入。
@MainActor
private func locatePath(of view: UIView, in root: UIView) throws -> [Int] {
    var path: [Int] = []
    var current: UIView? = view
    while let node = current, node !== root {
        guard let superview = node.superview else {
            Issue.record("view not in root subtree")
            return []
        }
        guard let index = superview.subviews.firstIndex(where: { $0 === node }) else {
            Issue.record("view not found in superview.subviews")
            return []
        }
        path.insert(index, at: 0)
        current = superview
    }
    return path
}
#endif
