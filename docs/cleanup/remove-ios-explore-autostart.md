# IOS_EXPLORE_AUTOSTART 移除总结

## 背景

用户指出 `IOS_EXPLORE_AUTOSTART` 环境变量/启动参数增加了使用负担，因为：

1. **真实使用场景**：开发者集成 iOSExploreServer 时，通常直接在代码里调用 `server.start()`
2. **测试工程特殊性**：只有测试工程需要切换多个测试页面，但这不是库的核心使用模式
3. **增加认知负担**：每次都要记得传 `env={"IOS_EXPLORE_AUTOSTART":"1"}`
4. **文档矛盾**：AGENTS.md 推荐直接调用，但示例又用环境变量

## 改动内容

### 1. 代码修改

**ViewController.swift**（主要改动）：
```swift
// ❌ 旧方式（已移除）
let shouldAutostart = arguments.contains("--ios-explore-autostart")
    || environment["IOS_EXPLORE_AUTOSTART"] == "1"
if shouldAutostart {
    startServer()
}

// ✅ 新方式（直接启动）
appendLog("launch automation: start server")
startServer()
```

**改动位置**：`Examples/SPMExample/SPMExample/ViewController.swift:345-376`

### 2. 文档更新

#### AGENTS.md
- **移除**：`IOS_EXPLORE_AUTOSTART` 启动参数说明
- **更新**：示例 App 集成方式说明
- **简化**：模拟器/真机跑法示例（移除 env 参数）

**改动位置**：
- 第 57-63 行：示例 App 集成方式
- 第 77-99 行：模拟器/真机跑法

#### CLAUDE.md
- **移除**：autostart 相关说明
- **更新**：示例 App 验证方式
- **保留**：测试页面启动参数（`IOS_EXPLORE_OPEN_ALERT_TEST` 等）

**改动位置**：第 19-34 行

#### Skills 文档
- `.claude/skills/ios-automation/skill.md`：移除问题排查中的 `IOS_EXPLORE_AUTOSTART`

#### 登录流程文档（新创建的）
- `Examples/SPMExample/Examples/SPMExample/QUICKSTART.md`
- `Examples/SPMExample/Examples/SPMExample/LOGIN_MODULE_SUMMARY.md`

### 3. 保留的启动参数

这些参数仍然保留，因为它们用于**测试工程切换显示不同测试页面**：

| 参数 | 用途 |
|------|------|
| `IOS_EXPLORE_SHOW_LOGIN` | 显示登录流程测试界面 |
| `IOS_EXPLORE_OPEN_ALERT_TEST` | 自动进入弹窗测试页 |
| `IOS_EXPLORE_OPEN_SWIPE_TEST` | 自动进入滑动测试页 |
| `IOS_EXPLORE_OPEN_LONGPRESS_TEST` | 自动进入长按测试页 |

这些是**测试工程特有的需求**，不是 iOSExploreServer 库的核心 API。

## 使用方式对比

### 旧方式（已废弃）

```bash
# ❌ 需要记得传 autostart 参数
launch_app_sim(env={"IOS_EXPLORE_AUTOSTART":"1"})
launch_app_device(env={"IOS_EXPLORE_AUTOSTART":"1"})
```

### 新方式（推荐）

```bash
# ✅ 直接启动，server 自动启动（DEBUG 环境）
launch_app_sim()
launch_app_device()
```

**集成代码**：
```swift
#if DEBUG
override func viewDidLoad() {
    super.viewDidLoad()
    Task {
        try? await server.start()
    }
}
#endif
```

## 实现细节

### DEBUG 环境自动启动

`ViewController.swift` 的 `viewDidAppear` 中：

```swift
override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    #if DEBUG
    runLaunchAutomationIfNeeded()
    #endif
}

private func runLaunchAutomationIfNeeded() {
    guard !didRunLaunchAutomation else { return }
    didRunLaunchAutomation = true

    // 直接启动 server（DEBUG 环境默认行为）
    appendLog("launch automation: start server")
    startServer()

    // 检查是否需要打开特定测试页面（可选）
    // ...
}
```

### 优势

1. **简化使用**：不需要记住传环境变量
2. **符合直觉**：DEBUG 下就应该能用，不需要额外配置
3. **减少错误**：不会因为忘记传参数而导致"连接失败"
4. **文档一致**：代码实践与文档说明一致

## 影响范围

### 不受影响

- ✅ 现有的 MCP 工具调用（仍然可以传 env，只是不再需要）
- ✅ 测试页面切换功能（`IOS_EXPLORE_OPEN_*` 参数）
- ✅ 真机/模拟器测试流程
- ✅ Skills 和自动化脚本（移除 autostart 后更简洁）

### 需要注意

如果有外部脚本或文档引用了 `IOS_EXPLORE_AUTOSTART`，需要更新为：
- **移除** `env={"IOS_EXPLORE_AUTOSTART":"1"}` 参数
- **说明**：server 在 DEBUG 环境下自动启动

## 剩余工作

以下文档可能还包含 `IOS_EXPLORE_AUTOSTART` 引用，需要后续清理：

```bash
# 搜索结果显示这些文件仍有引用：
iOSDriver/README.md
iOSDriver/docs/local-mcp-test.md
iOSDriver/docs/e2e-test-findings.md
iOSDriver/docs/skill-data-summary.md
iOSDriver/scripts/validation-prompt.md
docs/QUICK_START.md
docs/investigations/mcp-spim-example-fix-report.md
docs/investigations/mcp-e2e-test.md
```

这些是 iOSDriver 子项目的文档，可以后续批量更新。

## 总结

**移除 `IOS_EXPLORE_AUTOSTART` 后**：

- ✅ 使用更简单（不需要传参数）
- ✅ 文档更清晰（符合真实使用场景）
- ✅ 减少困惑（新用户不会疑惑"为什么需要这个参数"）
- ✅ 对齐最佳实践（DEBUG 下直接调用 `server.start()`）

**核心改动**：
- 代码：1 个文件（`ViewController.swift`）
- 文档：5 个文件（AGENTS.md、CLAUDE.md、skill.md、QUICKSTART.md、LOGIN_MODULE_SUMMARY.md）
- 影响：简化了使用流程，移除了冗余的认知负担

---

**日期**：2026-07-14  
**状态**：✅ 完成  
**后续**：批量清理 iOSDriver 子项目文档中的引用
