# iOS Automation - 完整真机测试流程示例

## 场景：真机查看登录页面状态

本示例展示了应用两个优化后的完整自动化流程。

## 前置条件

- ✅ 真机已通过 USB 连接到 Mac
- ✅ 设备已解锁并信任此电脑
- ✅ App 已通过 Xcode 编译安装到真机（首次需要）
- ⚠️ 开发者证书可能需要在设备上信任（首次需要）

## 完整执行流程

### Agent 自动执行部分

```typescript
// 用户输入
"查看真机 SPMExample App 的登录页面状态"

// Agent 执行流程
async function handleDeviceTest() {
  
  // ========== 步骤 1：启动 iproxy ==========
  console.log('📱 步骤 1/5: 启动 iproxy...')
  await bash('./.claude/skills/ios-automation/scripts/iproxy-manager.sh start')
  // 输出：
  // ✅ 检测到设备: 00008030-000D459601D2802E
  // ✅ iproxy 已启动 (PID 50226)
  
  
  // ========== 步骤 2：自动同步设备 ID（优化 1）==========
  console.log('🔄 步骤 2/5: 自动同步设备 ID...')
  
  const devicesResult = await mcp__XcodeBuildMCP__list_devices()
  const devices = devicesResult.data.devices
  
  const connectedIOSDevices = devices.filter(d => 
    d.platform === 'iOS' && 
    d.state === 'connected' && 
    d.isAvailable === true
  )
  
  if (connectedIOSDevices.length === 0) {
    throw new Error('未检测到 USB 连接的 iOS 设备')
  }
  
  const targetDevice = connectedIOSDevices[0]
  console.log(`✅ 检测到设备: ${targetDevice.name} (iOS ${targetDevice.osVersion})`)
  
  await mcp__XcodeBuildMCP__session_set_defaults({
    deviceId: targetDevice.deviceId
  })
  console.log('✅ 设备 ID 已自动同步')
  
  
  // ========== 步骤 3：智能 App 启动（优化 2）==========
  console.log('🔍 步骤 3/5: 检查 App 运行状态...')
  
  let healthResult = await mcp__iOSDriver__health_check()
  
  if (healthResult.ok) {
    console.log('✅ App 已运行')
  } else {
    console.log('⚠️  App 未运行，尝试自动启动...')
    
    try {
      await mcp__XcodeBuildMCP__launch_app_device()
      console.log('📱 启动命令已发送，等待 App 启动...')
      
      // 轮询等待（最多 30 秒）
      const delays = [500, 500, 1000, 1000, 2000, 2000, 3000, 3000, 5000, 5000]
      for (let i = 0; i < delays.length; i++) {
        await sleep(delays[i])
        
        healthResult = await mcp__iOSDriver__health_check()
        if (healthResult.ok) {
          console.log(`✅ App 已成功启动`)
          break
        }
        
        console.log(`⏳ 等待中... (${i + 1}/${delays.length})`)
      }
      
      if (!healthResult.ok) {
        throw new Error('App 启动超时')
      }
      
    } catch (error) {
      // 错误处理
      const errorMessage = error.message
      
      if (errorMessage.includes('invalid code signature') ||
          errorMessage.includes('not been explicitly trusted')) {
        
        console.log(`
❌ 开发者证书未信任

需要人工操作：
1. 在设备上打开"设置"
2. 进入"通用" → "VPN 与设备管理"
3. 找到开发者证书
4. 点击"信任该开发者"

完成后，请重新运行此任务
        `)
        
        return // 中断流程，等待用户信任证书
      }
      
      throw error // 其他错误继续抛出
    }
  }
  
  
  // ========== 步骤 4：获取 UI 状态 ==========
  console.log('📸 步骤 4/5: 获取登录页面状态...')
  
  const inspectResult = await mcp__iOSDriver__ui_inspect({
    maxDepth: 3,
    maxTargets: 50
  })
  
  const snapshot = inspectResult.observation
  
  console.log(`
✅ UI 快照已获取：
- 屏幕尺寸: ${snapshot.screen.width}x${snapshot.screen.height}
- 可交互元素: ${snapshot.targets.length} 个
- viewSnapshotID: ${snapshot.viewSnapshotID}
  `)
  
  
  // ========== 步骤 5：分析登录页面 ==========
  console.log('🔍 步骤 5/5: 分析登录页面...')
  
  const usernameField = snapshot.targets.find(t => 
    t.identifier === 'username_field' || 
    t.placeholder?.includes('用户名')
  )
  
  const passwordField = snapshot.targets.find(t => 
    t.identifier === 'password_field' || 
    t.placeholder?.includes('密码')
  )
  
  const loginButton = snapshot.targets.find(t => 
    t.label?.includes('登录') || 
    t.identifier === 'login_button'
  )
  
  console.log(`
✅ 登录页面状态分析：

📝 用户名输入框：
   - 路径: ${usernameField?.path || '未找到'}
   - 占位符: ${usernameField?.placeholder || '无'}
   - 当前值: ${usernameField?.value || '空'}

🔒 密码输入框：
   - 路径: ${passwordField?.path || '未找到'}
   - 占位符: ${passwordField?.placeholder || '无'}
   - 当前值: ${passwordField?.value ? '***' : '空'}

🔘 登录按钮：
   - 路径: ${loginButton?.path || '未找到'}
   - 标题: ${loginButton?.label || '未找到'}
   - 可点击: ${loginButton?.availableActions?.includes('tap') ? '是' : '否'}

📊 页面完整性检查：
   - 用户名框: ${usernameField ? '✅' : '❌'}
   - 密码框: ${passwordField ? '✅' : '❌'}
   - 登录按钮: ${loginButton ? '✅' : '❌'}
  `)
}
```

## 执行结果示例

### 场景 A：App 已运行且证书已信任

```
📱 步骤 1/5: 启动 iproxy...
✅ 检测到设备: 00008030-000D459601D2802E
✅ iproxy 已启动 (PID 50226)

🔄 步骤 2/5: 自动同步设备 ID...
✅ 检测到设备: zzdiPhone (iOS 26.4)
✅ 设备 ID 已自动同步

🔍 步骤 3/5: 检查 App 运行状态...
✅ App 已运行

📸 步骤 4/5: 获取登录页面状态...
✅ UI 快照已获取：
- 屏幕尺寸: 393x852
- 可交互元素: 12 个
- viewSnapshotID: snap_abc123

🔍 步骤 5/5: 分析登录页面...
✅ 登录页面状态分析：

📝 用户名输入框：
   - 路径: root/0/2/0
   - 占位符: 请输入用户名
   - 当前值: 空

🔒 密码输入框：
   - 路径: root/0/2/1
   - 占位符: 请输入密码
   - 当前值: 空

🔘 登录按钮：
   - 路径: root/0/2/2
   - 标题: 登录
   - 可点击: 是

📊 页面完整性检查：
   - 用户名框: ✅
   - 密码框: ✅
   - 登录按钮: ✅

⏱️ 总耗时: 3.2 秒
```

### 场景 B：App 未运行但证书已信任

```
📱 步骤 1/5: 启动 iproxy...
✅ iproxy 已启动

🔄 步骤 2/5: 自动同步设备 ID...
✅ 设备 ID 已自动同步

🔍 步骤 3/5: 检查 App 运行状态...
⚠️  App 未运行，尝试自动启动...
📱 启动命令已发送，等待 App 启动...
⏳ 等待中... (1/10)
⏳ 等待中... (2/10)
✅ App 已成功启动

📸 步骤 4/5: 获取登录页面状态...
✅ UI 快照已获取

🔍 步骤 5/5: 分析登录页面...
✅ 登录页面状态分析
   [详细信息...]

⏱️ 总耗时: 5.8 秒
```

### 场景 C：证书未信任（需要人工干预）

```
📱 步骤 1/5: 启动 iproxy...
✅ iproxy 已启动

🔄 步骤 2/5: 自动同步设备 ID...
✅ 设备 ID 已自动同步

🔍 步骤 3/5: 检查 App 运行状态...
⚠️  App 未运行，尝试自动启动...
📱 启动命令已发送，等待 App 启动...

❌ 开发者证书未信任

需要人工操作：
1. 在设备上打开"设置"
2. 进入"通用" → "VPN 与设备管理"
3. 找到开发者证书
4. 点击"信任该开发者"

完成后，请重新运行此任务

⏱️ 总耗时: 2.1 秒
```

### 场景 D：App 未安装

```
📱 步骤 1/5: 启动 iproxy...
✅ iproxy 已启动

🔄 步骤 2/5: 自动同步设备 ID...
✅ 设备 ID 已自动同步

🔍 步骤 3/5: 检查 App 运行状态...
⚠️  App 未运行，尝试自动启动...

❌ App 未安装在设备上

请先通过以下方式之一安装 App：
1. Xcode 直接运行到真机
2. 使用 build_run_device 编译并安装

注意：首次安装后需要在设备上信任开发者证书

⏱️ 总耗时: 1.5 秒
```

## 改进效果对比

### 改进前（手动操作）

```bash
# 1. 启动 iproxy
$ iproxy 38321 38321 -u 00008030-000D459601D2802E
# 需要记住 USB UDID

# 2. 查找设备
$ # 使用 XcodeBuildMCP list_devices
# 手动在一堆设备中找到 state: "connected" 的

# 3. 复制设备 ID
$ # 复制: 72ADA202-B489-54A1-81BF-1911261B6AF3

# 4. 更新配置
$ # 使用 XcodeBuildMCP session_set_defaults

# 5. 检查 App 状态
$ curl -X POST http://localhost:38321/ -d '{"action":"ping"}'
# 发现连接失败

# 6. 启动 App
$ # 使用 XcodeBuildMCP launch_app_device

# 7. 发现证书未信任
# 看到一堆英文错误信息，需要自己判断

# 8. 在设备上信任证书
# 手动操作

# 9. 再次启动 App
$ # 重复步骤 6

# 10. 获取 UI 状态
$ # 使用 iOSDriver ui_inspect

总计：10 步，需要理解两套 ID 体系，需要判断错误类型
```

### 改进后（自动化）

```bash
# 用户输入
"查看真机登录页面状态"

# Agent 自动执行：
# 1. 启动 iproxy ✓
# 2. 同步设备 ID ✓
# 3. 检查 App 状态 ✓
# 4. 尝试启动 App ✓
# 5. 识别证书问题 ✓
# 6. 给出中文操作指引 ✓

# 用户操作（仅在需要时）：
# - 在设备上信任证书（首次）

# Agent 继续：
# 7. 启动 App ✓
# 8. 获取 UI 状态 ✓
# 9. 分析并展示结果 ✓

总计：1 次用户输入 + 1 次人工操作（首次），其余全自动
```

## 关键改进点

| 维度 | 改进前 | 改进后 | 提升 |
|---|---|---|---|
| **手动步骤** | 10 步 | 1 步（+ 首次信任证书） | **90% 减少** |
| **技术门槛** | 需要理解 USB UDID vs CoreDevice ID | 完全透明 | **完全消除** |
| **错误诊断** | 看原始英文错误日志 | 中文提示 + 操作步骤 | **显著提升** |
| **平均耗时** | ~5 分钟（含手动操作） | ~5 秒（自动） + 首次信任 | **98% 节省** |
| **出错概率** | 高（复制错 ID、判断错误误） | 低（自动化） | **显著降低** |

## 技术实现

两个优化协同工作：

### 优化 1：自动同步设备 ID
- **触发时机**：每次真机测试开始时
- **实现方式**：`list_devices` + 过滤 `state: "connected"` + `session_set_defaults`
- **收益**：避免"设备 ID 不匹配"错误，节省 3 个手动步骤

### 优化 2：智能 App 启动
- **触发时机**：检测到 App 未运行时
- **实现方式**：`health_check` + `launch_app_device` + 轮询等待 + 错误匹配
- **收益**：自动尝试启动 App，给出清晰的失败原因和操作指引

## 相关文档

- [优化 1 实施指南](./optimization-1-implementation-guide.md)
- [优化 2 实施指南](./optimization-2-implementation-guide.md)
- [优化方案可行性分析](./automation-optimization-analysis.md)
- [ios-automation SKILL.md](../../.claude/skills/ios-automation/SKILL.md)
