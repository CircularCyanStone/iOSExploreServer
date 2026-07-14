# iOSDriver

**iOS App 自动化测试驱动服务器**

## 产品定位

iOSDriver 是一款专业的 iOS 应用自动化测试工具，提供 HTTP 接口和 MCP (Model Context Protocol) 集成，用于驱动 iOS App 的 UI 交互、表单填写、Alert 处理等操作。

## 核心特性

- ✅ **100% UIKit 命令覆盖** - 支持所有 32 个 UI 操作命令
- ✅ **HTTP JSON-RPC 接口** - 标准化的请求/响应协议
- ✅ **真机和模拟器支持** - 通过 iproxy 支持 USB 连接的真机
- ✅ **实时 UI 检查** - 动态解析和操作 UI 元素
- ✅ **完整的 MCP 集成** - 原生支持 Claude Code 和其他 MCP 客户端
- ✅ **11 个专业 Skills** - 预置的自动化场景和最佳实践

## 命令分类

### 基础命令 (6个)
- `ping` - 健康检查
- `device.info` - 设备信息
- `app.info` - 应用信息
- `app.logs.mark` - 日志标记
- `app.logs.read` - 日志读取
- `network.stats` - 网络统计

### UI 操作命令 (32个)
- **检查**: `ui.inspect`, `ui.snapshot`
- **交互**: `ui.tap`, `ui.longPress`, `ui.swipe`, `ui.drag`
- **导航**: `ui.navigation.push`, `ui.navigation.pop`, `ui.navigation.dismiss`
- **表单**: `ui.textField.input`, `ui.textField.clear`, `ui.control.sendAction`
- **列表**: `ui.tableView.scrollToRow`, `ui.collectionView.scrollToItem`
- **Alert**: `ui.alert.respond`, `ui.alert.list`
- **其他**: `ui.screenshot`, `ui.switch.toggle`, `ui.slider.setValue`, `ui.segmentedControl.selectSegment`, `ui.stepper.increment`, `ui.stepper.decrement`, `ui.pageControl.setPage`, `ui.datePicker.setDate`, `ui.pickerView.selectRow`, `ui.refresh.trigger`, `ui.scrollView.scrollTo`

## 命名理念

**iOSDriver** 命名借鉴业界成功经验：

- **iOS** - 明确技术栈和平台
- **Driver** - 体现驱动和控制能力，与 WebDriver/Appium 一脉相承
- **专业性** - 适合企业级自动化测试场景
- **易推广** - 业界熟悉的命名模式，降低学习成本

## 技术架构

### 核心模块
- **iOSExploreServer** - HTTP 服务器核心，基于 NWListener
- **iOSExploreUIKit** - UIKit 命令实现
- **iOSExploreDiagnostics** - 日志和诊断功能

### MCP 集成
- **Node.js MCP Server** - 将 HTTP 接口适配为 MCP 工具
- **11 个 Skills** - 封装常见自动化场景
- **Claude Code 原生支持** - 无缝集成到开发工作流

## 使用场景

1. **UI 自动化测试** - 替代手动点击，自动化回归测试
2. **表单填写测试** - 快速验证输入、验证和提交流程
3. **导航测试** - 自动化页面跳转和返回流程
4. **Alert 处理** - 批量处理系统弹窗和应用弹窗
5. **截图对比** - 自动化 UI 一致性检查
6. **日志分析** - 实时捕获和分析应用日志

## 版本历史

- **v1.0** (2026-07-14) - 正式发布为 iOSDriver
  - 品牌升级，面向生产环境
  - 完整的文档和 Skills 支持
  - 100% 命令覆盖率

- **v0.x** (2026-07-13 及之前) - 前身为 MCPServer
  - 完成核心功能开发
  - 完成端到端测试
  - 建立测试框架

## 与同类工具对比

| 特性 | iOSDriver | Appium | XCUITest |
|------|-----------|--------|----------|
| HTTP 接口 | ✅ | ✅ | ❌ |
| MCP 集成 | ✅ | ❌ | ❌ |
| 真机支持 | ✅ | ✅ | ✅ |
| 模拟器支持 | ✅ | ✅ | ✅ |
| 学习曲线 | 低 | 中 | 高 |
| Claude AI 集成 | ✅ | ❌ | ❌ |
| Skills 预置 | ✅ | ❌ | ❌ |

## 快速开始

### 安装

```bash
cd iOSDriver
npm install
npm run build
```

### 配置 MCP

```json
{
  "mcpServers": {
    "iOSDriver": {
      "command": "node",
      "args": ["/path/to/iOSDriver/dist/index.js"],
      "description": "iOS App automation driver server"
    }
  }
}
```

### 验证安装

```bash
# 启动示例 App (自动启动 server)
cd Examples/SPMExample
# ... 构建和运行 ...

# 测试连接
curl -X POST http://localhost:38321/ -d '{"action":"ping"}'
# 预期响应: {"code":"ok","data":{"pong":true}}
```

## 文档资源

- [README.md](README.md) - 项目概述和快速开始
- [MIGRATION.md](MIGRATION.md) - 从 MCPServer 迁移指南
- [docs/](docs/) - 完整技术文档
- [.claude/skills/](../.claude/skills/) - 11 个预置 Skills

## 支持和反馈

本项目是 iOSExploreServer 生态的一部分，提供专业的 iOS 自动化测试解决方案。

## 许可证

参见主项目的许可证说明。
