# XCUITest 设置清单

本文档提供创建 SPMExample UITests target 的详细步骤。

---

## 当前状态

✅ **已完成**：
- 测试文件已创建：
  - `Examples/SPMExample/SPMExampleUITests/LoginFlowTests.swift`
  - `Examples/SPMExample/SPMExampleUITests/SystemAlertMonitorTests.swift`
- 运行脚本已创建：`scripts/run-uitests.sh`
- 使用文档已创建：`docs/testing/xcuitest-guide.md`

❌ **待完成**：
- 在 Xcode 中创建 UITests target（需要 GUI 操作）

---

## 在 Xcode 中创建 UITests Target

### 步骤 1：打开项目

```bash
open Examples/SPMExample/SPMExample.xcodeproj
```

### 步骤 2：创建 UI Test Target

1. 选择菜单：**File → New → Target...**

   ![Step 1](https://docs-assets.developer.apple.com/published/new-target-menu.png)

2. 在模板选择窗口：
   - 左侧选择：**iOS**
   - 中间选择：**UI Testing Bundle**
   - 点击 **Next**

3. 配置 target：
   ```
   Product Name:              SPMExampleUITests
   Team:                      [选择你的开发团队]
   Organization Identifier:   com.coo
   Bundle Identifier:         com.coo.SPMExampleUITests
   Language:                  Swift
   Project:                   SPMExample
   Target to be Tested:       SPMExample
   ```

4. 点击 **Finish**

### 步骤 3：删除默认测试文件

Xcode 会自动创建 `SPMExampleUITests.swift`，删除它：

1. 在项目导航器中找到 `SPMExampleUITests/SPMExampleUITests.swift`
2. 右键点击，选择 **Delete**
3. 选择 **Move to Trash**

### 步骤 4：添加测试文件到 Target

仓库中已经有测试文件，需要将它们添加到 target 的成员关系：

1. 在项目导航器中找到 `SPMExampleUITests/LoginFlowTests.swift`
2. 点击文件，打开右侧的 **File Inspector**（Cmd + Opt + 1）
3. 在 **Target Membership** 区域，勾选 `SPMExampleUITests`
4. 对 `SystemAlertMonitorTests.swift` 重复相同操作

**或者**：如果文件不在项目导航器中，手动添加：

1. 右键点击 `SPMExampleUITests` 组
2. 选择 **Add Files to "SPMExample"...**
3. 导航到仓库的 `Examples/SPMExample/SPMExampleUITests/` 目录
4. 选中 `LoginFlowTests.swift` 和 `SystemAlertMonitorTests.swift`
5. 确保：
   - ✅ **Copy items if needed** 未勾选（文件已在正确位置）
   - ✅ **Create groups** 已选中
   - ✅ **Add to targets**: `SPMExampleUITests` 已勾选
6. 点击 **Add**

### 步骤 5：配置签名

1. 在项目导航器中选择 **SPMExample 项目**（最顶层）
2. 在中间栏选择 **SPMExampleUITests** target
3. 选择 **Signing & Capabilities** 标签页
4. 配置：
   - ✅ **Automatically manage signing** 勾选
   - **Team**: 选择你的开发团队
   - **Bundle Identifier**: `com.coo.SPMExampleUITests`（应该自动填充）

### 步骤 6：验证配置

在终端运行：

```bash
cd Examples/SPMExample

# 验证 target 是否存在
xcodebuild -list -project SPMExample.xcodeproj

# 应该看到 SPMExampleUITests 出现在 Targets 列表中
```

构建测试：

```bash
xcodebuild build-for-testing \
    -project SPMExample.xcodeproj \
    -scheme SPMExample \
    -destination 'platform=iOS Simulator,name=iPhone 17'
```

如果构建成功，配置完成！

---

## 快速验证

### 在模拟器运行测试

```bash
./scripts/run-uitests.sh --simulator "iPhone 17"
```

预期输出：

```
ℹ️  运行 XCUITest 测试...

ℹ️  项目: /Users/cystone/Desktop/iOSExploreServer/Examples/SPMExample/SPMExample.xcodeproj
ℹ️  Scheme: SPMExample
ℹ️  目标设备: platform=iOS Simulator,name=iPhone 17

Test Suite 'All tests' started at 2026-07-19 21:30:00.000
Test Suite 'SPMExampleUITests.xctest' started at 2026-07-19 21:30:00.100
Test Suite 'LoginFlowTests' started at 2026-07-19 21:30:00.200

Test Case '-[SPMExampleUITests.LoginFlowTests testSuccessfulLogin]' started.
Test Case '-[SPMExampleUITests.LoginFlowTests testSuccessfulLogin]' passed (4.523 seconds).

...

Test Suite 'LoginFlowTests' passed at 2026-07-19 21:30:35.000.
     Executed 8 tests, with 0 failures (0 unexpected) in 32.456 seconds

✅ 测试完成！耗时: 35s
ℹ️  测试结果保存在: /tmp/SPMExample_UITest_20260719_213000.xcresult
```

### 在 Xcode 中运行

1. 打开 `Examples/SPMExample/SPMExample.xcodeproj`
2. 选择 scheme: **SPMExample**
3. 选择目标设备：**iPhone 17** (模拟器)
4. 打开 `LoginFlowTests.swift`
5. 点击 `testSuccessfulLogin` 方法左侧的 ◆ 图标
6. 观察测试运行

预期行为：
1. App 启动，显示登录界面
2. 自动输入用户名 `test` 和密码 `123456`
3. 点击登录按钮
4. 等待 1.5 秒（模拟网络延迟）
5. 跳转到首页，显示 "欢迎回来！test"
6. 测试通过 ✅

---

## 测试时间基准

基于 iPhone 17 模拟器（预估）：

| 测试用例 | 预计时间 | 说明 |
|---------|---------|------|
| `testSuccessfulLogin` | ~4.5s | 包括 1.5s 网络延迟 |
| `testLoginFailure_UserNotFound` | ~3.0s | 网络延迟 + 错误显示 |
| `testLoginFailure_WrongPassword` | ~3.0s | 网络延迟 + 错误显示 |
| `testLoginButtonLoadingState` | ~4.5s | 网络延迟 + 状态检查 |
| `testNavigateToRegister` | ~1.0s | 纯导航操作 |
| `testNavigateToResetPassword` | ~1.0s | 纯导航操作 |
| `testLogoutFlow` | ~6.0s | 登录 + 退出 |
| `testCancelLogout` | ~6.0s | 登录 + 取消退出 |
| **总计** | ~29s | 8 个测试 |

**首次启动开销**：~3-5 秒（App 冷启动 + Test 进程初始化）

**实际总时间**：~32-35 秒

---

## 真机测试

### 准备工作

1. **连接真机**：使用 USB 连接 iPhone
2. **信任电脑**：在 iPhone 上点击 "信任此电脑"
3. **开发者模式**：设置 → 隐私与安全 → 开发者模式 → 打开
4. **获取 UDID**：
   ```bash
   xcrun xctrace list devices
   # 或
   xcrun simctl list devices
   ```

### 运行测试

```bash
./scripts/run-uitests.sh --device-id 00008030-XXXXXXXXXXXX
```

### 真机注意事项

1. **系统版本**：真机 iOS 版本必须 ≥ 26.2（SPMExample 部署目标）
2. **签名**：确保 App 和 UITests target 使用相同的开发团队
3. **性能差异**：真机可能比模拟器慢，需要增加 `timeout` 值
4. **iproxy**：如果测试需要与 iOSExploreServer 通信，运行：
   ```bash
   ./scripts/proxy.sh --daemon
   ```

---

## 常见问题排查

### 问题 1：构建失败 - "No such module 'XCTest'"

**原因**：测试文件没有正确添加到 UITests target。

**解决**：
1. 选择测试文件（如 `LoginFlowTests.swift`）
2. 打开 File Inspector（Cmd + Opt + 1）
3. 在 Target Membership 勾选 `SPMExampleUITests`

### 问题 2：运行测试时 App 不启动

**原因**：UITests target 没有正确关联到 SPMExample target。

**解决**：
1. 选择 `SPMExampleUITests` target
2. 打开 **General** 标签页
3. 在 **Testing** 区域，确保 **Target Application** 设置为 `SPMExample`

### 问题 3：测试超时 - "Failed to find matching element"

**原因**：元素的 `accessibilityIdentifier` 不匹配，或元素尚未出现。

**解决**：
1. 检查元素的 `accessibilityIdentifier`（在 ViewController 代码中）
2. 增加 `waitForExistence(timeout:)` 的超时时间
3. 使用 Xcode 的 **Accessibility Inspector** 检查元素属性

### 问题 4：真机测试失败 - "Failed to install or launch"

**原因**：代码签名或设备配置问题。

**解决**：
1. 确保设备已信任此电脑
2. 确保开发者模式已启用（iOS 16+）
3. 确保 UITests target 的 Team 和 Bundle Identifier 正确配置
4. 尝试手动在 Xcode 中运行（Cmd + U）查看详细错误

### 问题 5：System Alert 测试不触发

**原因**：SPMExample 当前不请求任何系统权限。

**说明**：
- `SystemAlertMonitorTests.swift` 中的测试仅作示例
- 测试会正常通过，但不会检测到实际的系统弹窗
- 如果未来 SPMExample 添加权限请求功能，这些测试会自动生效

---

## 下一步

1. ✅ 按照本文档在 Xcode 中创建 UITests target
2. ✅ 在模拟器运行测试验证
3. ✅ 在真机运行测试验证
4. ✅ 记录测试时间和遇到的问题
5. ✅ 更新文档（如有需要）

---

## 参考文档

- [XCUITest 使用指南](./xcuitest-guide.md) - 完整的 XCUITest 架构和使用说明
- [iOSExploreServer 构建和测试](../runbooks/build-and-test.md) - 构建配置
- [调试指南](../runbooks/debugging.md) - iproxy 和端口配置
