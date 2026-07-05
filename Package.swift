// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "iOSExploreServer",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13),
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "iOSExploreServer",
            targets: ["iOSExploreServer"]
        ),
        // UIKit 命令扩展模块：依赖 core，提供 `ui.*` 系列命令。
        // 宿主 App 通过 `ExploreServer.registerUIKitCommands()` 显式注册。
        .library(
            name: "iOSExploreUIKit",
            targets: ["iOSExploreUIKit"]
        ),
        // 进程日志诊断模块：依赖 core，提供 app.logs.* 与宿主业务日志桥接。
        .library(
            name: "iOSExploreDiagnostics",
            targets: ["iOSExploreDiagnostics"]
        ),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "iOSExploreServer"
        ),
        // UIKit 扩展 target，依赖 core。源码整体包在 `#if canImport(UIKit)` 内，
        // macOS 下编译为空壳，iOS 下提供 UIKit 命令实现。
        .target(
            name: "iOSExploreUIKit",
            dependencies: ["iOSExploreServer"]
        ),
        .target(
            name: "iOSExploreDiagnostics",
            dependencies: ["iOSExploreServer"]
        ),
        .testTarget(
            name: "iOSExploreServerTests",
            dependencies: ["iOSExploreServer", "iOSExploreUIKit", "iOSExploreDiagnostics"]
        ),
    ]
)
