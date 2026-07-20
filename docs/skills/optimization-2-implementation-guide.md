# iOS Automation Skill - 优化 2 实施指南

## 优化：智能 App 启动

### 问题背景

真机测试时，skill 假设 App 已经在运行，但实际情况：
- App 可能未启动
- App 可能未安装
- App 可能需要信任开发者证书

导致用户需要手动：
1. 判断 App 状态
2. 启动 App 或安装 App
3. 处理证书信任问题

### 解决方案

在真机测试流程中，自动检测 App 是否运行，未运行则尝试启动，并给出明确的失败原因。

## Agent 执行逻辑

### 步骤 1：检查 App 是否运行

```typescript
const healthResult = await mcp__iOSDriver__health_check()
```

**返回示例**：

**场景 A：App 正在运行**
```json
{
  "ok": true,
  "ping": {
    "code": "ok",
    "data": { "pong": true }
  },
  "baseURL": "http://localhost:38321/",
  "connected": true,
  "dynamicToolCount": 32
}
```

**场景 B：App 未运行**
```json
{
  "ok": false,
  "error": {
    "source": "transport",
    "code": "connection_failed",
    "message": "Failed to connect to http://localhost:38321/"
  },
  "baseURL": "http://localhost:38321/",
  "connected": false,
  "dynamicToolCount": 0
}
```

### 步骤 2：根据状态分支

```typescript
if (healthResult.connected) {
  console.log('✅ App 已运行，开始 UI 操作')
  // 继续执行 UI 操作
  return
}

console.log('⚠️  App 未运行，尝试自动启动...')
// 进入步骤 3
```

### 步骤 3：尝试启动 App

```typescript
try {
  await mcp__XcodeBuildMCP__launch_app_device()
  console.log('✅ App 启动命令已发送')
  
  // 等待 App 启动（重要！）
  await sleep(2000)
  
  // 验证启动是否成功
  const verifyResult = await mcp__iOSDriver__health_check()
  
  if (verifyResult.connected) {
    console.log('✅ App 已成功启动')
    return
  } else {
    throw new Error('App 启动了但服务未响应，请检查 App 中的 server.start() 是否被调用')
  }
  
} catch (error) {
  // 进入步骤 4：错误处理
  handleLaunchError(error)
}
```

### 步骤 4：错误处理（关键）

根据错误信息判断失败原因：

```typescript
function handleLaunchError(error: Error) {
  const errorMessage = error.message || error.toString()
  
  // 错误类型 1：App 未安装
  if (errorMessage.includes('not installed') || 
      errorMessage.includes('is not installed')) {
    throw new Error(`
❌ App 未安装在设备上

请先通过以下方式之一安装 App：
1. Xcode 直接运行到真机
2. 使用 build_run_device 编译并安装

注意：首次安装后需要在设备上信任开发者证书
    `)
  }
  
  // 错误类型 2：证书未信任
  if (errorMessage.includes('invalid code signature') ||
      errorMessage.includes('inadequate entitlements') ||
      errorMessage.includes('not been explicitly trusted')) {
    throw new Error(`
❌ 开发者证书未信任

请在设备上手动信任：
1. 打开"设置"
2. 进入"通用" → "VPN 与设备管理"
3. 找到开发者证书（通常显示为 Apple ID）
4. 点击"信任该开发者"

信任后，App 即可正常启动
    `)
  }
  
  // 错误类型 3：设备锁屏
  if (errorMessage.includes('device is locked') ||
      errorMessage.includes('passcode')) {
    throw new Error(`
❌ 设备已锁屏

请解锁设备后重试
    `)
  }
  
  // 错误类型 4：其他未知错误
  throw new Error(`
❌ App 启动失败

错误信息：
${errorMessage}

请检查：
1. 设备是否已解锁
2. App 是否已安装
3. 开发者证书是否已信任
4. iproxy 是否正常运行
  `)
}
```

### 完整流程伪代码

```typescript
async function ensureAppRunning() {
  // 1. 检查 App 是否运行
  console.log('🔍 检查 App 运行状态...')
  let healthResult = await mcp__iOSDriver__health_check()
  
  if (healthResult.connected) {
    console.log('✅ App 已运行')
    return
  }
  
  // 2. App 未运行，尝试启动
  console.log('⚠️  App 未运行，尝试自动启动...')
  
  try {
    await mcp__XcodeBuildMCP__launch_app_device()
    console.log('📱 启动命令已发送，等待 App 启动...')
    
    // 3. 轮询等待 App 启动（最多 10 次，指数退避）
    const maxRetries = 10
    const delays = [500, 500, 1000, 1000, 2000, 2000, 3000, 3000, 5000, 5000] // 毫秒
    
    for (let i = 0; i < maxRetries; i++) {
      await sleep(delays[i])
      
      healthResult = await mcp__iOSDriver__health_check()
      
      if (healthResult.connected) {
        console.log(`✅ App 已成功启动（耗时 ${delays.slice(0, i+1).reduce((a,b)=>a+b, 0)}ms）`)
        return
      }
      
      console.log(`⏳ 等待中... (${i + 1}/${maxRetries})`)
    }
    
    // 4. 超时仍未启动
    throw new Error('App 启动超时（30 秒），但未收到错误。请手动检查 App 是否正在启动')
    
  } catch (error) {
    handleLaunchError(error)
  }
}
```

## 错误匹配规则

根据 subagent 分析报告，以下是常见错误特征字符串：

| 错误类型 | 特征字符串 | 用户操作 |
|---|---|---|
| App 未安装 | `not installed` | 先编译安装 App |
| 证书未信任 | `invalid code signature`, `not been explicitly trusted` | 在设备上信任开发者 |
| 设备锁屏 | `device is locked`, `passcode` | 解锁设备 |
| iproxy 未运行 | `connection refused`, `connection failed` | 启动 iproxy |
| 端口被占用 | 不会在这里出现（已在步骤 1 处理） | - |

## 测试场景

### 场景 1：App 已运行
```
health_check → connected: true
→ 直接执行 UI 操作
```

### 场景 2：App 未运行但已安装且已信任
```
health_check → connected: false
→ launch_app_device → 成功
→ sleep(2000)
→ health_check → connected: true
→ 执行 UI 操作
```

### 场景 3：App 未安装
```
health_check → connected: false
→ launch_app_device → 错误: "not installed"
→ 提示用户先安装 App
```

### 场景 4：证书未信任
```
health_check → connected: false
→ launch_app_device → 错误: "invalid code signature"
→ 提示用户在设备上信任证书
```

### 场景 5：设备锁屏
```
health_check → connected: false
→ launch_app_device → 错误: "device is locked"
→ 提示用户解锁设备
```

### 场景 6：App 启动慢
```
health_check → connected: false
→ launch_app_device → 成功
→ sleep(500) → health_check → connected: false
→ sleep(500) → health_check → connected: false
→ sleep(1000) → health_check → connected: true
→ 执行 UI 操作
```

## 与优化 1 的组合效果

### 完整自动化流程

```typescript
async function automatedDeviceTest() {
  // 优化 1：自动同步设备 ID
  await ensureDeviceIdSynced()
  
  // 优化 2：智能 App 启动
  await ensureAppRunning()
  
  // 执行 UI 操作
  await executeUIOperations()
}
```

### 用户体验对比

**改进前（9 步手动操作）**：
```
1. 启动 iproxy
2. list_devices 查找设备
3. 记下 deviceId
4. session_set_defaults 更新
5. health_check 检查 App
6. 发现 App 未运行
7. launch_app_device 启动
8. 发现证书未信任
9. 在设备上手动信任
```

**改进后（1 步 + 1 次人工干预）**：
```
1. Agent 自动执行：
   - 启动 iproxy ✓
   - 同步设备 ID ✓
   - 检查 App 状态 ✓
   - 尝试启动 App ✗
   - 提示："需在设备上信任证书"
   
2. 用户：在设备上信任证书

3. Agent 自动重试：
   - 启动 App ✓
   - 验证连接 ✓
   - 执行 UI 操作 ✓
```

## 风险与缓解

### 风险 1：误启动用户正在调试的 App

**场景**：用户在 Xcode 中调试 App，Agent 自动启动导致调试断开

**缓解**：
- 在启动前给出提示："检测到 App 未运行，将自动启动"
- 提供配置选项关闭自动启动（未来优化）

### 风险 2：错误信息匹配不准确

**场景**：Apple 更新错误信息格式，字符串匹配失效

**缓解**：
- 使用宽松的匹配规则（contains 而非 equals）
- 兜底错误处理（显示完整错误信息）
- 定期更新错误匹配规则

### 风险 3：启动超时判断不准确

**场景**：App 启动需要 > 30 秒（首次启动、复杂初始化）

**缓解**：
- 使用指数退避策略（总计 30 秒）
- 超时后仍给出明确提示，而非直接失败

## 实施检查清单

- [x] 更新 skill 文档（SKILL.md）
- [x] 创建实施指南（本文档）
- [ ] 在 Agent 实际执行中验证
- [ ] 测试所有错误场景
- [ ] 收集用户反馈
- [ ] 根据反馈迭代优化

## 后续优化

- [ ] 增加配置开关（允许用户关闭自动启动）
- [ ] 缓存 App 状态（避免重复检查）
- [ ] 增加更多错误类型识别
- [ ] 支持自定义等待超时时间
- [ ] 支持批量设备测试时的并发启动

## 相关文档

- [优化 1 实施指南](./optimization-1-implementation-guide.md)
- [优化方案可行性分析](./automation-optimization-analysis.md)
- [ios-automation SKILL.md](../../.claude/skills/ios-automation/SKILL.md)
