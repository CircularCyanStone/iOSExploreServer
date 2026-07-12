//
//  ScrollTestViewController.swift
//  SPMExample
//
//  Created by 李奇奇 on 2026/7/8.
//

import UIKit

/// 用于验证 `ui.scrollToElement` 命令的测试页面。
///
/// 使用 UICollectionView 展示 30 个 cell，其中 item 25 有唯一文本 `Item 25 — 找我`，
/// 且该 cell 在首屏外，必须滚动才能可见。
/// 两种匹配方式均可命中：
/// - `match: "text"` → 搜索 UILabel.text = "Item 25 — 找我"
/// - `match: "accessibilityIdentifier"` → 搜索 accessibilityIdentifier = "scroll.target.25"
///
/// 新增横向滚动测试区域（底部），展示 20 个横向 item。
final class ScrollTestViewController: UIViewController {
    private let collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.translatesAutoresizingMaskIntoConstraints = false
        cv.backgroundColor = .systemBackground
        cv.accessibilityIdentifier = "scroll.vertical.container"
        return cv
    }()

    private let horizontalCollectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = 8
        layout.minimumInteritemSpacing = 0
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.translatesAutoresizingMaskIntoConstraints = false
        cv.backgroundColor = .secondarySystemBackground
        cv.accessibilityIdentifier = "scroll.horizontal.container"
        return cv
    }()

    private let horizontalLabel: UILabel = {
        let label = UILabel()
        label.text = "横向滚动测试"
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "滚动测试"
        view.backgroundColor = .systemBackground

        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(ScrollTestCell.self, forCellWithReuseIdentifier: ScrollTestCell.reuseIdentifier)

        horizontalCollectionView.dataSource = self
        horizontalCollectionView.delegate = self
        horizontalCollectionView.register(ScrollTestCell.self, forCellWithReuseIdentifier: ScrollTestCell.reuseIdentifier)

        view.addSubview(collectionView)
        view.addSubview(horizontalLabel)
        view.addSubview(horizontalCollectionView)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            collectionView.heightAnchor.constraint(equalTo: view.safeAreaLayoutGuide.heightAnchor, multiplier: 0.7),

            horizontalLabel.topAnchor.constraint(equalTo: collectionView.bottomAnchor, constant: 12),
            horizontalLabel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            horizontalLabel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),

            horizontalCollectionView.topAnchor.constraint(equalTo: horizontalLabel.bottomAnchor, constant: 8),
            horizontalCollectionView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            horizontalCollectionView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            horizontalCollectionView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])
    }
}

// MARK: - UICollectionViewDataSource

extension ScrollTestViewController: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        if collectionView == self.collectionView {
            return 30
        } else {
            return 20
        }
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ScrollTestCell.reuseIdentifier, for: indexPath) as? ScrollTestCell else {
            return UICollectionViewCell()
        }

        let item = indexPath.item

        if collectionView == self.collectionView {
            // 垂直滚动
            let text: String
            if item == 25 {
                text = "Item 25 — 找我"
            } else {
                text = "Item \(item)"
            }
            cell.label.text = text
            cell.accessibilityIdentifier = "scroll.target.\(item)"
            // 交替背景色，便于肉眼区分相邻 cell
            cell.contentView.backgroundColor = item % 2 == 0
                ? .secondarySystemBackground
                : .tertiarySystemBackground
        } else {
            // 横向滚动
            let text: String
            if item == 15 {
                text = "H-Item 15 🎯"
            } else {
                text = "H-\(item)"
            }
            cell.label.text = text
            cell.accessibilityIdentifier = "scroll.horizontal.\(item)"
            cell.contentView.backgroundColor = item % 2 == 0
                ? .systemBlue.withAlphaComponent(0.1)
                : .systemGreen.withAlphaComponent(0.1)
        }

        return cell
    }
}

// MARK: - UICollectionViewDelegateFlowLayout

extension ScrollTestViewController: UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        if collectionView == self.collectionView {
            // 垂直滚动 cell
            let width = collectionView.bounds.width
            return CGSize(width: width, height: 80)
        } else {
            // 横向滚动 cell
            return CGSize(width: 120, height: 80)
        }
    }
}

// MARK: - ScrollTestCell

final class ScrollTestCell: UICollectionViewCell {
    static let reuseIdentifier = "ScrollTestCell"

    let label: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 20, weight: .semibold)
        label.numberOfLines = 0
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(label)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
