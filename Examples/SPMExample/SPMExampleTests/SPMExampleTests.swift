//
//  SPMExampleTests.swift
//  SPMExampleTests
//
//  Created by 李奇奇 on 2026/6/21.
//

import Testing
import UIKit
@testable import SPMExample

struct SPMExampleTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }

    #if DEBUG
    /// 真机合成触摸 spike：host app（SPMExample）启动后，直接调 `SyntheticTapSpikeRunner`
    /// 在真实 key window 上跑 4 场景（gesture / plain / 遮挡 / button），结果进 test 日志。
    ///
    /// 这是 `ui.tap` realTouch spike 的真机验证入口：`xcodebuild test` 启动 SPMExample
    /// （host app，有 UIApplication / scene / gestureEnvironment）到真机，test 在该进程
    /// 直接跑合成触摸，绕过 devicectl 部署。结果通过 `print("[REAL-DEVICE-SPIKE]...")` 进日志。
    @Test("真机合成触摸 spike（host app 真实进程）") @MainActor
    func realDeviceSyntheticTapSpike() throws {
        let window = try #require(UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow })
        let root = try #require(window.rootViewController)
        window.layoutIfNeeded()
        let result = SyntheticTapSpikeRunner.runAll(in: root.view, window: window)
        print("[REAL-DEVICE-SPIKE] iOS \(UIDevice.current.systemVersion) \(result)")
    }
    #endif

}
