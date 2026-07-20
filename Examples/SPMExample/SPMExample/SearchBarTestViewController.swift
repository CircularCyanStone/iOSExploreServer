//
//  SearchBarTestViewController.swift
//  SPMExample
//
//  Created for UISearchBar E2E testing with iOSExploreServer
//

import UIKit
import OSLog

/// UISearchBar 测试页面，展示搜索框的典型场景供 `ui.input` 和相关命令验证。
///
/// 本页面覆盖以下场景：
/// - 基础搜索框（带搜索按钮）
/// - 带取消按钮的搜索框
/// - 搜索结果动态过滤
/// - 清空按钮交互
/// - 搜索状态日志记录
final class SearchBarTestViewController: UIViewController {
    private let logger = Logger(subsystem: "com.coo.SPMExample", category: "SearchBar")

    // MARK: - 场景 1: 基础搜索框
    private let basicSearchBar = UISearchBar()
    private let basicResultLabel = UILabel()

    // MARK: - 场景 2: 带取消按钮的搜索框
    private let cancelableSearchBar = UISearchBar()
    private let cancelableResultLabel = UILabel()

    // MARK: - 场景 3: 搜索结果列表
    private let listSearchBar = UISearchBar()
    private let resultTableView = UITableView()
    private let searchStatusLabel = UILabel()

    // 模拟数据源
    private let allItems = [
        "苹果 Apple", "香蕉 Banana", "橙子 Orange", "葡萄 Grape",
        "草莓 Strawberry", "西瓜 Watermelon", "芒果 Mango", "樱桃 Cherry",
        "柠檬 Lemon", "桃子 Peach", "梨子 Pear", "菠萝 Pineapple",
        "猕猴桃 Kiwi", "蓝莓 Blueberry", "树莓 Raspberry", "椰子 Coconut",
        "石榴 Pomegranate", "无花果 Fig", "木瓜 Papaya", "荔枝 Lychee"
    ]
    private var filteredItems: [String] = []
    private var currentSearchText: String = ""

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "UISearchBar 测试"

        setupLayout()
        filteredItems = allItems // 初始显示全部

        logger.info("SearchBarTestViewController loaded")
    }

    private func setupLayout() {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        let contentView = UIView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
        ])

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 24
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
        ])

        // 场景 1: 基础搜索框
        stack.addArrangedSubview(createBasicSearchSection())

        // 场景 2: 带取消按钮的搜索框
        stack.addArrangedSubview(createCancelableSearchSection())

        // 场景 3: 搜索结果列表
        stack.addArrangedSubview(createListSearchSection())
    }

    // MARK: - 场景 1: 基础搜索框
    private func createBasicSearchSection() -> UIView {
        let container = UIView()
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        let titleLabel = UILabel()
        titleLabel.text = "场景 1: 基础搜索框"
        titleLabel.font = .boldSystemFont(ofSize: 18)
        stack.addArrangedSubview(titleLabel)

        let descLabel = UILabel()
        descLabel.text = "带搜索按钮，点击搜索按钮或收键盘触发搜索"
        descLabel.font = .systemFont(ofSize: 14)
        descLabel.textColor = .secondaryLabel
        descLabel.numberOfLines = 0
        stack.addArrangedSubview(descLabel)

        basicSearchBar.placeholder = "输入搜索关键词..."
        basicSearchBar.accessibilityIdentifier = "searchBar_basic"
        basicSearchBar.delegate = self
        basicSearchBar.searchBarStyle = .minimal
        basicSearchBar.enablesReturnKeyAutomatically = false
        stack.addArrangedSubview(basicSearchBar)

        basicResultLabel.text = "搜索结果: (未搜索)"
        basicResultLabel.font = .systemFont(ofSize: 14)
        basicResultLabel.textColor = .systemGreen
        basicResultLabel.numberOfLines = 0
        basicResultLabel.accessibilityIdentifier = "searchBar_basic_result"
        stack.addArrangedSubview(basicResultLabel)

        return container
    }

    // MARK: - 场景 2: 带取消按钮的搜索框
    private func createCancelableSearchSection() -> UIView {
        let container = UIView()
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        let titleLabel = UILabel()
        titleLabel.text = "场景 2: 带取消按钮"
        titleLabel.font = .boldSystemFont(ofSize: 18)
        stack.addArrangedSubview(titleLabel)

        let descLabel = UILabel()
        descLabel.text = "点击输入框显示取消按钮，点击取消清空并退出编辑"
        descLabel.font = .systemFont(ofSize: 14)
        descLabel.textColor = .secondaryLabel
        descLabel.numberOfLines = 0
        stack.addArrangedSubview(descLabel)

        cancelableSearchBar.placeholder = "搜索..."
        cancelableSearchBar.accessibilityIdentifier = "searchBar_cancelable"
        cancelableSearchBar.delegate = self
        cancelableSearchBar.searchBarStyle = .minimal
        cancelableSearchBar.showsCancelButton = false // 默认隐藏，获得焦点时显示
        stack.addArrangedSubview(cancelableSearchBar)

        cancelableResultLabel.text = "搜索结果: (未搜索)"
        cancelableResultLabel.font = .systemFont(ofSize: 14)
        cancelableResultLabel.textColor = .systemBlue
        cancelableResultLabel.numberOfLines = 0
        cancelableResultLabel.accessibilityIdentifier = "searchBar_cancelable_result"
        stack.addArrangedSubview(cancelableResultLabel)

        return container
    }

    // MARK: - 场景 3: 搜索结果列表
    private func createListSearchSection() -> UIView {
        let container = UIView()
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        let titleLabel = UILabel()
        titleLabel.text = "场景 3: 动态搜索结果"
        titleLabel.font = .boldSystemFont(ofSize: 18)
        stack.addArrangedSubview(titleLabel)

        let descLabel = UILabel()
        descLabel.text = "实时过滤列表，展示搜索结果数量和状态"
        descLabel.font = .systemFont(ofSize: 14)
        descLabel.textColor = .secondaryLabel
        descLabel.numberOfLines = 0
        stack.addArrangedSubview(descLabel)

        listSearchBar.placeholder = "输入关键词过滤列表..."
        listSearchBar.accessibilityIdentifier = "searchBar_list"
        listSearchBar.delegate = self
        listSearchBar.searchBarStyle = .minimal
        listSearchBar.showsCancelButton = true
        stack.addArrangedSubview(listSearchBar)

        searchStatusLabel.text = "显示: 全部 \(allItems.count) 项"
        searchStatusLabel.font = .systemFont(ofSize: 13)
        searchStatusLabel.textColor = .secondaryLabel
        searchStatusLabel.accessibilityIdentifier = "searchBar_list_status"
        stack.addArrangedSubview(searchStatusLabel)

        resultTableView.dataSource = self
        resultTableView.delegate = self
        resultTableView.register(UITableViewCell.self, forCellReuseIdentifier: "resultCell")
        resultTableView.layer.borderWidth = 1
        resultTableView.layer.borderColor = UIColor.systemGray4.cgColor
        resultTableView.layer.cornerRadius = 8
        resultTableView.translatesAutoresizingMaskIntoConstraints = false
        resultTableView.accessibilityIdentifier = "searchBar_result_table"
        stack.addArrangedSubview(resultTableView)

        resultTableView.heightAnchor.constraint(equalToConstant: 300).isActive = true

        return container
    }

    // MARK: - 搜索逻辑
    private func performSearch(for searchBar: UISearchBar, text: String?) {
        let searchText = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        switch searchBar {
        case basicSearchBar:
            if searchText.isEmpty {
                basicResultLabel.text = "搜索结果: (未输入关键词)"
                logger.info("basicSearchBar: empty search")
            } else {
                let count = allItems.filter { $0.localizedCaseInsensitiveContains(searchText) }.count
                basicResultLabel.text = "搜索结果: 找到 \(count) 项匹配 '\(searchText)'"
                logger.info("basicSearchBar: searched for '\(searchText)', found \(count) items")
            }

        case cancelableSearchBar:
            if searchText.isEmpty {
                cancelableResultLabel.text = "搜索结果: (未输入关键词)"
                logger.info("cancelableSearchBar: empty search")
            } else {
                let count = allItems.filter { $0.localizedCaseInsensitiveContains(searchText) }.count
                cancelableResultLabel.text = "搜索结果: 找到 \(count) 项匹配 '\(searchText)'"
                logger.info("cancelableSearchBar: searched for '\(searchText)', found \(count) items")
            }

        case listSearchBar:
            currentSearchText = searchText
            if searchText.isEmpty {
                filteredItems = allItems
                searchStatusLabel.text = "显示: 全部 \(allItems.count) 项"
                logger.info("listSearchBar: showing all items")
            } else {
                filteredItems = allItems.filter { $0.localizedCaseInsensitiveContains(searchText) }
                searchStatusLabel.text = "显示: \(self.filteredItems.count) 项（搜索 '\(searchText)'）"
                logger.info("listSearchBar: filtered to \(self.filteredItems.count) items for '\(searchText)'")
            }
            resultTableView.reloadData()

        default:
            break
        }
    }

    private func clearSearch(for searchBar: UISearchBar) {
        searchBar.text = ""
        performSearch(for: searchBar, text: "")

        let identifier = searchBar.accessibilityIdentifier ?? "unknown"
        logger.info("\(identifier): search cleared")
    }
}

// MARK: - UISearchBarDelegate
extension SearchBarTestViewController: UISearchBarDelegate {
    /// 用户点击搜索按钮（键盘的 Search 键）
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        performSearch(for: searchBar, text: searchBar.text)
        searchBar.resignFirstResponder()

        let identifier = searchBar.accessibilityIdentifier ?? "unknown"
        logger.info("\(identifier): search button clicked")
    }

    /// 用户点击取消按钮
    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        clearSearch(for: searchBar)
        searchBar.resignFirstResponder()
        searchBar.showsCancelButton = false

        let identifier = searchBar.accessibilityIdentifier ?? "unknown"
        logger.info("\(identifier): cancel button clicked")
    }

    /// 搜索框获得焦点（开始编辑）
    func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
        if searchBar == cancelableSearchBar {
            searchBar.showsCancelButton = true
        }

        let identifier = searchBar.accessibilityIdentifier ?? "unknown"
        logger.info("\(identifier): began editing")
    }

    /// 搜索框失去焦点（结束编辑）
    func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
        let identifier = searchBar.accessibilityIdentifier ?? "unknown"
        logger.info("\(identifier): ended editing")
    }

    /// 文本实时变化（场景 3 使用）
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        if searchBar == listSearchBar {
            // 实时过滤
            performSearch(for: searchBar, text: searchText)
        }
    }

    /// 用户点击清空按钮（搜索框内的 ✕ 按钮）
    func searchBar(_ searchBar: UISearchBar, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        // 检测清空操作
        if text.isEmpty && range.length > 0 {
            let identifier = searchBar.accessibilityIdentifier ?? "unknown"
            logger.info("\(identifier): text being cleared (range: \(range))")
        }
        return true
    }
}

// MARK: - UITableViewDataSource & UITableViewDelegate
extension SearchBarTestViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return filteredItems.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "resultCell", for: indexPath)
        let item = filteredItems[indexPath.row]

        var config = cell.defaultContentConfiguration()
        config.text = item

        // 高亮搜索关键词（视觉提示）
        if !currentSearchText.isEmpty {
            let attributedString = NSMutableAttributedString(string: item)
            if let range = item.range(of: currentSearchText, options: .caseInsensitive) {
                let nsRange = NSRange(range, in: item)
                attributedString.addAttribute(.backgroundColor, value: UIColor.systemYellow.withAlphaComponent(0.3), range: nsRange)
            }
            config.attributedText = attributedString
        }

        cell.contentConfiguration = config
        cell.accessibilityIdentifier = "searchResult_\(indexPath.row)"
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let item = filteredItems[indexPath.row]
        logger.info("selected search result: \(item) at index \(indexPath.row)")
    }
}
