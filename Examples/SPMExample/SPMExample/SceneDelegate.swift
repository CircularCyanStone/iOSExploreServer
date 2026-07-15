//
//  SceneDelegate.swift
//  SPMExample
//
//  Created by 李奇奇 on 2026/6/21.
//

import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?


    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = (scene as? UIWindowScene) else { return }

        // 创建窗口
        let window = UIWindow(windowScene: windowScene)

        // 检查启动参数，决定显示哪个界面
        // ⚠️ UserDefaults 读取说明（仅测试工程用，集成到真实项目时务必删除此分支）：
        // 此 key 一旦被置 true（测试脚本/手动写入），会在模拟器/真机数据容器内跨启动持久——
        // 后续每次 launch 都进登录流程，且源码只读不写、状态对审计者不可见（无法从 App 内得知
        // 当前值）。仅用于测试工程快速进入登录场景。集成到真实项目时删除此 UserDefaults 读取，
        // 仅保留下面的启动参数（--ios-explore-show-login）与环境变量（IOS_EXPLORE_SHOW_LOGIN）方式。
        let shouldShowLoginFlow = UserDefaults.standard.bool(forKey: "ios_explore_show_login")
            || ProcessInfo.processInfo.environment["IOS_EXPLORE_SHOW_LOGIN"] == "1"
            || ProcessInfo.processInfo.arguments.contains("--ios-explore-show-login")

        if shouldShowLoginFlow {
            // 显示登录流程
            let loginVC = LoginViewController()
            let navController = UINavigationController(rootViewController: loginVC)
            window.rootViewController = navController
        } else {
            // 显示原有的测试界面，包装在 UINavigationController 中以支持菜单导航
            let viewController = ViewController()
            let navController = UINavigationController(rootViewController: viewController)
            window.rootViewController = navController
        }

        self.window = window
        window.makeKeyAndVisible()
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        // Called as the scene is being released by the system.
        // This occurs shortly after the scene enters the background, or when its session is discarded.
        // Release any resources associated with this scene that can be re-created the next time the scene connects.
        // The scene may re-connect later, as its session was not necessarily discarded (see `application:didDiscardSceneSessions` instead).
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        // Called when the scene has moved from an inactive state to an active state.
        // Use this method to restart any tasks that were paused (or not yet started) when the scene was inactive.
    }

    func sceneWillResignActive(_ scene: UIScene) {
        // Called when the scene will move from an active state to an inactive state.
        // This may occur due to temporary interruptions (ex. an incoming phone call).
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        // Called as the scene transitions from the background to the foreground.
        // Use this method to undo the changes made on entering the background.
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        // Called as the scene transitions from the foreground to the background.
        // Use this method to save data, release shared resources, and store enough scene-specific state information
        // to restore the scene back to its current state.
    }


}

