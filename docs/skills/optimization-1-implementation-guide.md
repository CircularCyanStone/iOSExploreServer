# iOS Automation Skill - 优化 1 实施指南

## 优化：自动同步设备 ID

### 问题背景

真机测试时，XcodeBuildMCP 的 `deviceId` 配置可能与当前连接的设备不匹配，导致：
- `launch_app_device` 失败：`Error: No provider was found`
- 需要手动执行 `list_devices` 查找正确的 deviceId
- 需要手动执行 `session_set_defaults({ deviceId: "..." })` 更新配置

### 解决方案

在真机测试流程中，自动检测当前连接的设备并更新配置。

## Agent 执行逻辑

### 步骤 1：启动 iproxy

```bash
./.claude/skills/ios-automation/scripts/iproxy-manager.sh start
```

这一步会：
- 检查 iproxy 是否已安装
- 清理端口冲突
- 自动获取 USB UDID 并启动 iproxy

### 步骤 2：自动同步设备 ID（核心优化）

#### 2.1 获取设备列表

```typescript
const result = await mcp__XcodeBuildMCP__list_devices()
const devices = result.data.devices
```

返回示例：
```json
{
  "devices": [
    {
      "name": "zzdiPhone",
      "deviceId": "72ADA202-B489-54A1-81BF-1911261B6AF3",
      "platform": "iOS",
      "state": "connected",
      "isAvailable": true,
      "osVersion": "26.4"
    },
    {
      "name": "李奇奇的iPhone",
      "deviceId": "3AC0C7D6-22F6-572B-8368-4047A14BAB52",
      "platform": "iOS",
      "state": "disconnected",
      "isAvailable": false,
      "osVersion": "26.5"
    }
  ]
}
```

#### 2.2 找到已连接的 iOS 设备

```typescript
// 过滤出 iOS 平台且状态为 connected 的设备
const connectedIOSDevices = devices.filter(d => 
  d.platform === 'iOS' && 
  d.state === 'connected' && 
  d.isAvailable === true
)
```

#### 2.3 处理不同场景

**场景 A：单个设备连接（最常见）**

```typescript
if (connectedIOSDevices.length === 1) {
  const device = connectedIOSDevices[0]
  
  console.log(`✅ 检测到已连接的设备：${device.name} (iOS ${device.osVersion})`)
  
  await mcp__XcodeBuildMCP__session_set_defaults({
    deviceId: device.deviceId
  })
  
  console.log(`✅ 已自动更新设备配置`)
}
```

**场景 B：多个设备连接**

```typescript
if (connectedIOSDevices.length > 1) {
  console.log(`⚠️  检测到 ${connectedIOSDevices.length} 个已连接的 iOS 设备：`)
  
  connectedIOSDevices.forEach((d, i) => {
    console.log(`  ${i + 1}. ${d.name} (iOS ${d.osVersion}, ${d.deviceId})`)
  })
  
  // 选项 1：使用第一个设备（简单）
  const device = connectedIOSDevices[0]
  console.log(`使用第一个设备：${device.name}`)
  
  await mcp__XcodeBuildMCP__session_set_defaults({
    deviceId: device.deviceId
  })
  
  // 选项 2：询问用户选择（更好的用户体验）
  // const choice = await askUser("选择要使用的设备")
  // await session_set_defaults({ deviceId: connectedIOSDevices[choice].deviceId })
}
```

**场景 C：无设备连接**

```typescript
if (connectedIOSDevices.length === 0) {
  throw new Error(`
❌ 未检测到 USB 连接的 iOS 设备

请检查：
1. 设备已通过 USB 连接到 Mac
2. 设备已解锁
3. 设备已"信任此电脑"（首次连接会弹窗）

验证设备连接：
  idevice_id -l  # 应输出设备 UDID
  `)
}
```

### 步骤 3：验证连接

```bash
./.claude/skills/ios-automation/scripts/iproxy-manager.sh check
```

如果失败，可能的原因：
- App 未启动（需要 `launch_app_device` 或 `build_run_device`）
- iproxy 未正常工作（检查日志）

### 步骤 4：执行 UI 操作

连接成功后，路由到对应的 `ios-ui-*` skill。

## 完整伪代码

```typescript
async function ensureDeviceConnected() {
  // 1. 启动 iproxy
  await bash('./.claude/skills/ios-automation/scripts/iproxy-manager.sh start')
  
  // 2. 自动同步设备 ID
  const devicesResult = await mcp__XcodeBuildMCP__list_devices()
  const devices = devicesResult.data.devices
  
  const connectedIOSDevices = devices.filter(d => 
    d.platform === 'iOS' && 
    d.state === 'connected' && 
    d.isAvailable === true
  )
  
  if (connectedIOSDevices.length === 0) {
    throw new Error('未检测到 USB 连接的 iOS 设备，请确保设备已连接并解锁')
  }
  
  if (connectedIOSDevices.length > 1) {
    console.log(`⚠️  检测到 ${connectedIOSDevices.length} 个已连接的设备，使用第一个：${connectedIOSDevices[0].name}`)
  }
  
  const targetDevice = connectedIOSDevices[0]
  console.log(`✅ 检测到设备：${targetDevice.name} (iOS ${targetDevice.osVersion})`)
  
  await mcp__XcodeBuildMCP__session_set_defaults({
    deviceId: targetDevice.deviceId
  })
  
  console.log(`✅ 已自动同步设备配置`)
  
  // 3. 验证连接
  const checkResult = await bash('./.claude/skills/ios-automation/scripts/iproxy-manager.sh check')
  
  if (checkResult.exitCode !== 0) {
    console.log('⚠️  连接验证失败，App 可能未启动')
    // 这里可以选择自动启动 App（优化 2）
  }
}
```

## 测试验证

### 测试场景 1：单设备连接

```bash
# 1. 连接一台 iPhone
# 2. 运行真机测试
# 预期：自动检测到设备并更新配置
```

### 测试场景 2：多设备连接

```bash
# 1. 连接两台 iPhone
# 2. 运行真机测试
# 预期：提示检测到多个设备，使用第一个
```

### 测试场景 3：无设备连接

```bash
# 1. 不连接设备
# 2. 运行真机测试
# 预期：报错提示"未检测到 USB 连接的 iOS 设备"
```

### 测试场景 4：设备切换

```bash
# 1. 连接设备 A，运行测试（成功）
# 2. 断开设备 A，连接设备 B
# 3. 再次运行测试
# 预期：自动检测到新设备并更新配置
```

## 收益

### 改进前（7 步手动操作）

```bash
# 1. 启动 iproxy
iproxy 38321 38321 -u <usb-udid>

# 2. 切换到真机配置
session_use_defaults_profile("device-app")

# 3. 尝试启动 App
launch_app_device
# ❌ 错误：设备 ID 不匹配

# 4. 列出设备
list_devices

# 5. 找到正确的设备 ID
# 手动查找 state: "connected" 的设备

# 6. 更新配置
session_set_defaults({ deviceId: "<correct-id>" })

# 7. 再次尝试
launch_app_device
```

### 改进后（1 步自动执行）

```bash
# Agent 自动执行：
# 1. 启动 iproxy
# 2. 检测设备
# 3. 更新配置
# 4. 验证连接

# 用户只需要说：
"查看真机登录页面"
```

## 注意事项

1. **设备必须已配对**：未配对的设备不会出现在 `list_devices` 中
2. **设备必须解锁**：锁屏状态下 `state` 可能不是 `connected`
3. **iproxy 必须先启动**：否则即使配置正确，连接也会失败
4. **多设备场景的优先级**：当前实现使用第一个检测到的设备，未来可以增加设备选择逻辑

## 后续优化

- [ ] 增加设备选择交互（多设备场景）
- [ ] 缓存最近使用的设备（避免每次都重新检测）
- [ ] 增加设备健康检查（电池、存储空间等）
- [ ] 与优化 2（智能 App 启动）结合，实现完全自动化

## 相关文档

- [优化方案可行性分析](./automation-optimization-analysis.md)
- [ios-automation SKILL.md](../../.claude/skills/ios-automation/SKILL.md)
- [XcodeBuildMCP 文档](../../iOSDriver/README.md)
