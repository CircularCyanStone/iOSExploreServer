# iOSDriver 文档索引

本目录包含 iOSExplore iOSDriver 的测试报告、问题修复记录和最佳实践文档。

---

## 📚 文档分类

### 最佳实践与使用指南

#### [Navigation 命令使用注意事项](./navigation-commands-best-practices.md) ⭐️
**推荐阅读**

详细说明 `ui.navigation.*` 命令的使用方法、已知问题和最佳实践。

**重点内容**:
- ⚠️ `ui.navigation.back` dismiss 后 `topAfter` 可能不准确（推荐额外调用 `ui.inspect` 确认）
- ✅ `ui.navigation.tapBarButton` 新增全局搜索功能，可以只传 `accessibilityIdentifier`
- 📖 详细的参数说明、错误处理和代码示例

**适用场景**: 构建 Navigation 相关 Skills 时必读

---

### 端到端测试报告

#### [Screenshot & Navigation 命令端到端测试](./e2e-test-screenshot-navigation-2026-07-12.md)
**测试日期**: 2026-07-12

全面测试 `ui.screenshot` 和 `ui.navigation.*` 命令，覆盖：
- 截图功能（全尺寸 + 降采样）
- 导航栏按钮点击
- 多级 Push/Pop 导航
- Present/Dismiss 模态场景

**测试结果**: 9/10 场景通过，发现 2 个问题

---

#### [Controller Override 端到端测试](./e2e-controller-override-test.md)
**测试日期**: 2026-07-10

测试 `ui.topViewHierarchy` 的 `controller` 参数覆盖功能。

**测试结果**: 验证通过，支持指定 view controller 采集层级

---

#### [端到端测试发现汇总](./e2e-test-findings.md)
**测试日期**: 2026-07-11

汇总多次端到端测试发现的问题和改进建议。

---

### 问题修复记录

#### [Navigation 命令问题修复](./fix-navigation-issues-2026-07-12.md)
**修复日期**: 2026-07-12

详细记录了两个 Navigation 命令问题的修复过程：

1. ✅ **已修复**: `ui.navigation.tapBarButton` 的 `placement` 参数现在可选，支持只传 `accessibilityIdentifier` 全局搜索
2. ⏸️ **暂不修复**: `ui.navigation.back` dismiss 后的 `topAfter` 不准确（已在文档中说明）

**修改文件**:
- `UINavigationBarButtonModels.swift`
- `UINavigationBarInspector.swift`
- `UINavigationBarButtonExecutor.swift`
- `UIKitCommandError.swift`
- `UINavigationBarButtonInputTests.swift`

**测试覆盖**: 281 个单元测试 + 3 个端到端场景

---

### 本地测试指南

#### [本地 MCP 测试](./local-mcp-test.md)
**创建日期**: 2026-07-09

说明如何在本地测试 iOSDriver，包括：
- 环境配置
- 测试脚本使用
- 常见问题排查

---

## 🔍 快速查找

### 按问题类型

| 问题 | 相关文档 |
|------|----------|
| `ui.navigation.back` dismiss 后 `topAfter` 不准确 | [Navigation 最佳实践](./navigation-commands-best-practices.md#%EF%B8%8F-已知问题dismiss-后的-topafter-字段可能不准确) |
| `ui.navigation.tapBarButton` 如何只传 identifier | [Navigation 最佳实践](./navigation-commands-best-practices.md#2-仅-accessibilityidentifier-全局搜索-️-推荐) |
| Screenshot 降采样 | [Screenshot 测试报告](./e2e-test-screenshot-navigation-2026-07-12.md#1-uiscreenshot-基础功能) |
| 多级导航返回 | [Navigation 测试报告](./e2e-test-screenshot-navigation-2026-07-12.md#3-多级-push-导航与-uinavigationback) |

---

### 按命令

| 命令 | 最佳实践 | 测试报告 | 修复记录 |
|------|----------|----------|----------|
| `ui.navigation.back` | [✅](./navigation-commands-best-practices.md#uiNavigationback---返回上一页) | [✅](./e2e-test-screenshot-navigation-2026-07-12.md#3-多级-push-导航与-uinavigationback) | - |
| `ui.navigation.tapBarButton` | [✅](./navigation-commands-best-practices.md#uiNavigationtapbarbutton---点击导航栏按钮) | [✅](./e2e-test-screenshot-navigation-2026-07-12.md#2-uinavigationtapbarbutton-导航栏按钮) | [✅](./fix-navigation-issues-2026-07-12.md) |
| `ui.screenshot` | - | [✅](./e2e-test-screenshot-navigation-2026-07-12.md#1-uiscreenshot-基础功能) | - |
| `ui.topViewHierarchy` | - | [✅](./e2e-controller-override-test.md) | - |

---

## 📝 文档编写指南

### 新增测试报告

测试报告应包含：
1. **测试概要**: 测试范围、环境、工具
2. **测试结果汇总**: 通过/失败场景统计
3. **详细测试流程**: 每个测试场景的输入/输出/验证
4. **发现的问题**: 问题描述、重现步骤、严重性、建议修复方案
5. **测试环境信息**: 设备、系统版本、commit hash

**命名规范**: `e2e-test-{feature}-{date}.md`

---

### 新增修复记录

修复记录应包含：
1. **修复概要**: 修复了哪些问题
2. **问题描述**: 修复前的行为、影响范围
3. **修复方案**: 代码改动、实现思路
4. **测试验证**: 单元测试 + 端到端测试结果
5. **修改文件列表**: 方便代码审查

**命名规范**: `fix-{feature}-issues-{date}.md`

---

### 新增最佳实践

最佳实践文档应包含：
1. **基本用法**: 参数说明、示例代码
2. **已知问题**: 边界情况、注意事项
3. **最佳实践**: 推荐做法、常见错误
4. **错误处理**: 错误码说明、解决方案
5. **代码示例**: 实际场景的完整示例

**命名规范**: `{feature}-best-practices.md`

---

## 🔗 相关资源

- **源码**: `/Users/coo/Desktop/iOS_agent_debugger/iOSExploreServer/`
- **iOSDriver**: `/Users/coo/Desktop/iOS_agent_debugger/iOSExploreServer/iOSDriver/`
- **测试脚本**: `iOSDriver/scripts/mcp-inspector.mjs`
- **Example App**: `Examples/SPMExample/`

---

## 📅 更新日志

| 日期 | 变更 |
|------|------|
| 2026-07-12 | 新增 Navigation 最佳实践文档、修复记录、测试报告 |
| 2026-07-11 | 新增端到端测试发现汇总 |
| 2026-07-10 | 新增 Controller Override 测试报告 |
| 2026-07-09 | 新增本地 MCP 测试指南 |

---

## 💡 贡献指南

1. 每次端到端测试后，记得更新测试报告
2. 修复问题后，同步更新最佳实践文档
3. 发现新的边界情况，及时补充到相关文档
4. 保持文档结构一致，方便查找

