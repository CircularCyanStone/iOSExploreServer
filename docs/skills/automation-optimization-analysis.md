# iOS Automation Skill 优化方案可行性分析

> 分析时间：2026-07-20  
> 目标：评估两个 `ios-automation` skill 优化方案的技术可行性

## 执行摘要

**优化 1（自动同步设备 ID）**：✅ **可行**，实施简单，边界清晰  
**优化 2（智能 App 启动）**：⚠️ **部分可行**，需要修改实现逻辑，当前 `health_check` 行为不支持直接判断

---

## 优化 1：自动同步设备 ID

### 1.1 可行性评估：✅ 完全可行

#### MCP 工具验证

**`list_devices` 返回结构**（基于工具定义和文档证据）：
```typescript
{
  devices: [
    {
      id: "3AC0C7D6-22F6-572B-8368-4047A14BAB52",  // CoreDevice ID
      name: "李奇奇的iPhone",
      platform: "iOS",
      osVersion: "26.5",
      state: "connected",  // ✅ 关键字段
      // ... 其他字段
    }
  ]
}
```

**关键发现**：
- `state: "connected"` 字段准确反映当前 USB 连接状态（文档 `mcp-realdevice-e2e-issues.md` 第 5 行确认）
- `id` 是 CoreDevice identifier，直接用于 `session_set_defaults({ deviceId })`
- 与 `iproxy -u` 使用的 USB UDID 是两套体系（AGENTS.md 已明确警告）

#### 实现逻辑

```typescript
// 伪代码示例
async function autoSyncDeviceId() {
  const result = await mcp__XcodeBuildMCP__list_devices();
  
  // 1. 筛选 connected 设备
  const connectedDevices = result.devices.filter(d => d.state === "connected");
  
  // 2. 边界情况处理
  if (connectedDevices.length === 0) {
    return { 
      success: false, 
      reason: "no_device_connected",
      message: "没有检测到 USB 连接的设备，请确认设备已连接并信任此电脑"
    };
  }
  
  if (connectedDevices.length > 1) {
    // 多设备场景：优先选择当前 profile 的平台匹配设备
    const currentDefaults = await session_show_defaults();
    const targetPlatform = currentDefaults.platform || "iOS";
    
    const matched = connectedDevices.filter(d => d.platform === targetPlatform);
    
    if (matched.length === 1) {
      // 唯一平台匹配，自动选择
      await session_set_defaults({ deviceId: matched[0].id });
      return { success: true, device: matched[0] };
    } else {
      // 多设备且无法自动选择，列出供用户选择
      return {
        success: false,
        reason: "multiple_devices",
        devices: connectedDevices,
        message: "检测到多个连接设备，请明确指定 deviceId"
      };
    }
  }
  
  // 3. 单设备场景：直接更新
  const device = connectedDevices[0];
  await session_set_defaults({ deviceId: device.id });
  
  return { 
    success: true, 
    device,
    message: `已自动设置设备：${device.name} (${device.platform} ${device.osVersion})`
  };
}
```

#### 边界情况处理

| 场景 | 检测条件 | 处理策略 |
|------|---------|---------|
| **无设备连接** | `connectedDevices.length === 0` | 返回失败 + 提示用户检查 USB 连接和信任 |
| **单设备连接** | `connectedDevices.length === 1` | ✅ 自动更新 `deviceId` |
| **多设备同平台** | 多个 `platform === "iOS"` 设备 | 列出设备，要求用户明确选择（或选择第一个 + 警告）|
| **多设备跨平台** | iOS + watchOS + tvOS 混合 | 按 profile 的 `platform` 字段过滤，匹配唯一则选择 |
| **设备平台不匹配** | 连接的是 watchOS，profile 是 iOS | 返回警告，建议用户检查配置或切换 profile |

#### 额外校验建议

在同步后增加一次"握手验证"：
```typescript
// 同步后验证
const result = await autoSyncDeviceId();
if (result.success) {
  // 可选：测试 iproxy 连通性（如果是真机场景）
  const proxyCheck = await checkIproxyConnection(); // 执行 lsof -iTCP:38321
  if (!proxyCheck.ok) {
    return {
      ...result,
      warning: "设备 ID 已更新，但 iproxy 未在 38321 端口监听，请先启动 iproxy"
    };
  }
}
```

### 1.2 实施建议

#### 在 skill 中的集成位置

在 `ios-automation` skill 的**真机检测流程**开始时调用：

```markdown
## 设备连接检测（真机）

1. **自动同步设备 ID**
   - 调用 `list_devices` 获取当前连接设备
   - 筛选 `state: "connected"` 的设备
   - 单设备场景：自动更新 `session_set_defaults({ deviceId })`
   - 多设备场景：列出供用户选择
   - 验证：设备平台与 profile 一致

2. **验证 iproxy 状态**
   - 检查 38321 端口监听进程
   - 确认是 `iproxy` 而非残留的 `SPMExampl` 进程
```

#### 文档更新点

需要在以下位置说明此行为：
- `~/.claude/skills/ios-automation/SKILL.md` — 在"设备连接检测"章节
- `AGENTS.md` — 在"XcodeBuildMCP 运行配置"章节补充自动同步说明
- `docs/skills/inventory.md` — 更新 `ios-automation` 能力描述

---

## 优化 2：智能 App 启动

### 2.1 可行性评估：⚠️ 部分可行（需修改实现）

#### 当前 `health_check` 行为分析

**实际实现**（`iOSDriver/src/staticTools.ts:46-61`）：

```typescript
health_check: {
  handler: async () => {
    try {
      const ping = await client.call("ping");        // ← 关键：直接调用 ping
      await client.call("help");
      await registry.refresh();
      return jsonResult({ 
        ok: true, 
        ping, 
        dynamicToolCount: registry.tools().length 
      });
    } catch (error) {
      return jsonResult({ 
        ok: false, 
        error: normalizeError(error), 
        dynamicToolCount: registry.tools().length 
      }, false);  // ← 注意：第二参数 false 表示 isError
    }
  }
}
```

**关键发现**：

1. **`health_check` 在 App 未运行时的行为**：
   - `client.call("ping")` 会向 `http://localhost:38321/` 发起 `fetch`
   - **App 未运行** → iproxy 转发失败 → `fetch` 抛出异常
   - 异常被包装成 `IOSExploreStructuredError({ source: "transport", code: "connection_failed" })`
   - `health_check` 捕获后返回 `{ ok: false, error: {...} }`（**不抛出异常**）

2. **返回结构区分**：
   ```typescript
   // App 运行中
   { ok: true, ping: {...}, dynamicToolCount: 42 }
   
   // App 未运行
   { 
     ok: false, 
     error: { 
       source: "transport", 
       code: "connection_failed", 
       message: "fetch failed" 
     },
     dynamicToolCount: 0  // 因为之前 refresh 失败
   }
   ```

3. **不会超时挂起**：`fetch` 有默认超时（`IOSExploreClient` 配置的 `timeoutMs`），失败时快速返回错误，不会无限等待

#### `launch_app_device` 错误类型

**工具定义中无明确错误码文档**，但从 XcodeBuildMCP 的通用行为推断：

```typescript
// 可能的失败场景
{
  // App 未安装
  error: "App not installed on device",
  // 或更结构化的
  code: "app_not_found",
  
  // 证书/签名问题
  error: "Code signing error",
  
  // 设备锁定
  error: "Device is locked",
  
  // 其他运行时错误
  error: "Failed to launch app: ..."
}
```

**问题**：XcodeBuildMCP 工具返回的错误**没有统一的错误码规范**，需要通过**字符串匹配**判断失败原因，这不够健壮。

### 2.2 修改后的实现方案

#### 方案 A：基于 `health_check` 的智能启动（推荐）

```typescript
async function ensureAppRunning() {
  // 1. 检查 App 是否运行
  const healthResult = await mcp__iOSDriver__health_check();
  
  if (healthResult.ok) {
    // App 已运行，直接返回
    return { 
      alreadyRunning: true, 
      message: "App 已在运行，无需启动" 
    };
  }
  
  // 2. App 未运行，尝试启动
  const error = healthResult.error;
  
  if (error.source === "transport" && error.code === "connection_failed") {
    // 确认是连接失败（App 未运行），而非其他错误
    console.log("检测到 App 未运行，尝试启动...");
    
    try {
      // 3. 启动 App（真机）
      const launchResult = await mcp__XcodeBuildMCP__launch_app_device({
        env: { IOS_EXPLORE_AUTOSTART: "1" },
        launchArgs: []  // 根据需要添加
      });
      
      // 4. 等待 App 启动并验证连接
      await sleep(2000);  // 给 App 启动时间
      
      // 5. 重新验证连接
      for (let attempt = 0; attempt < 5; attempt++) {
        const recheck = await mcp__iOSDriver__health_check();
        if (recheck.ok) {
          // ✅ 加载动态工具
          await mcp__iOSDriver__refresh_tools();
          return { 
            success: true, 
            launched: true,
            dynamicToolCount: recheck.dynamicToolCount,
            message: "App 已成功启动并连接" 
          };
        }
        await sleep(1000);  // 每次间隔 1 秒
      }
      
      // 启动了但连接失败
      return {
        success: false,
        reason: "launch_succeeded_but_connection_failed",
        message: "App 已启动但无法建立连接，请检查 iproxy 是否正常运行",
        troubleshooting: [
          "检查 iproxy 是否在 38321 端口监听：lsof -iTCP:38321",
          "确认 iproxy 监听的是正确的设备 UDID",
          "手动测试连接：curl -X POST http://localhost:38321/ -d '{\"action\":\"ping\"}'"
        ]
      };
      
    } catch (launchError) {
      // 6. 启动失败，分析原因
      const errorMsg = String(launchError);
      
      if (errorMsg.includes("not installed") || errorMsg.includes("not found")) {
        return {
          success: false,
          reason: "app_not_installed",
          message: "App 未安装在设备上，请先运行 build_run_device 进行安装",
          nextSteps: [
            "1. 调用 build_run_device() 构建并安装 App",
            "2. 或使用 install_app_device() 安装已有的 .app"
          ]
        };
      }
      
      if (errorMsg.includes("code sign") || errorMsg.includes("provisioning")) {
        return {
          success: false,
          reason: "code_signing_error",
          message: "代码签名或描述文件问题",
          error: errorMsg
        };
      }
      
      // 未知错误
      return {
        success: false,
        reason: "launch_failed",
        message: "启动失败",
        error: errorMsg
      };
    }
  }
  
  // 其他类型的错误（非 transport），直接返回
  return {
    success: false,
    reason: "unexpected_error",
    error: healthResult.error
  };
}
```

#### 方案 B：轮询等待策略（更健壮）

针对"等待 2 秒可能不够"的问题，使用**轮询 + 指数退避**：

```typescript
async function waitForConnection(maxAttempts = 10, initialDelayMs = 500) {
  let delay = initialDelayMs;
  
  for (let i = 0; i < maxAttempts; i++) {
    const health = await mcp__iOSDriver__health_check();
    
    if (health.ok) {
      return { connected: true, attempts: i + 1 };
    }
    
    // 指数退避：500ms → 750ms → 1125ms → ...，最大 3000ms
    await sleep(delay);
    delay = Math.min(delay * 1.5, 3000);
  }
  
  return { connected: false, attempts: maxAttempts };
}

// 使用
const launchResult = await launch_app_device(...);
const connectionResult = await waitForConnection(10, 500);

if (!connectionResult.connected) {
  return { 
    error: "连接超时",
    troubleshooting: [...] 
  };
}
```

### 2.3 边界情况处理

| 场景 | 检测方式 | 处理策略 |
|------|---------|---------|
| **App 已运行** | `health_check.ok === true` | 跳过启动，直接返回 |
| **App 未安装** | `launch_app_device` 错误信息匹配 | 提示用户先运行 `build_run_device` |
| **App 启动但连接超时** | 轮询 10 次仍 `ok === false` | 提示检查 iproxy，给出诊断命令 |
| **证书/签名错误** | `launch_app_device` 错误信息匹配 | 返回错误详情，建议检查 Xcode 设置 |
| **设备锁定** | `launch_app_device` 失败 | 提示解锁设备 |
| **iproxy 未运行** | `health_check` 失败且启动后仍失败 | 提示启动 iproxy：`./scripts/proxy.sh` |
| **iproxy 端口被占用** | 连接到了错误的进程（模拟器残留）| 见 AGENTS.md 坑 #4，提示用 `lsof` 检查 |

### 2.4 实施建议

#### 集成到 skill 的位置

在 `ios-automation` 的**连接建立阶段**：

```markdown
## 连接建立流程

### 真机场景

1. **自动同步设备 ID**（优化 1）
2. **验证 iproxy 状态**
   - 检查 38321 端口监听进程
3. **智能 App 启动**（优化 2）
   - 调用 `health_check` 检测 App 状态
   - 未运行则自动 `launch_app_device`
   - 轮询等待连接建立（最多 10 次）
   - 失败时给出具体诊断建议
4. **加载动态工具**
   - `refresh_tools` 确保工具列表最新
```

#### 前置条件校验

在执行优化 2 之前，必须确保：

```typescript
// 前置条件检查清单
const preconditions = {
  // 1. session defaults 已配置
  hasDefaults: await checkSessionDefaults(),
  
  // 2. bundleId 已知
  hasBundleId: defaults.bundleId !== undefined,
  
  // 3. iproxy 正在运行（真机场景）
  hasIproxy: await checkIproxyRunning(),
  
  // 4. 设备已连接
  deviceConnected: await checkDeviceConnected()
};

if (!preconditions.hasBundleId) {
  // 尝试自动获取
  const appPath = await get_device_app_path();
  const bundleId = await get_app_bundle_id({ appPath });
  await session_set_defaults({ bundleId });
}
```

---

## 优化方案对比总结

| 维度 | 优化 1：自动同步设备 ID | 优化 2：智能 App 启动 |
|------|---------------------|-------------------|
| **技术可行性** | ✅ 完全可行 | ⚠️ 部分可行（需修改） |
| **实施复杂度** | 🟢 低（单次 API 调用 + 过滤） | 🟡 中（需轮询 + 错误匹配） |
| **边界情况** | 🟢 清晰（单/多设备） | 🟡 较多（未安装/证书/iproxy） |
| **用户体验提升** | 🟢 显著（免手动配置） | 🟢 显著（免手动启动） |
| **风险** | 🟢 低（只读 + 更新配置） | 🟡 中（可能误启动 App） |
| **依赖工具行为** | ✅ `list_devices` 稳定 | ⚠️ 依赖 `launch_app_device` 错误信息 |
| **推荐优先级** | **P0 立即实施** | **P1 谨慎实施** |

---

## 实施路线图

### 第一阶段：优化 1（立即实施）

**工作量**：1-2 小时

1. 在 `ios-automation` skill 添加 `autoSyncDeviceId()` 函数
2. 集成到真机检测流程开始处
3. 添加单/多设备场景的处理逻辑
4. 更新文档说明此行为

**验证方式**：
```bash
# 连接一台真机
# 调用 ios-automation skill
# 观察是否自动更新 deviceId
# 检查 session_show_defaults 输出
```

### 第二阶段：优化 2（谨慎实施）

**工作量**：3-4 小时

1. 实现 `ensureAppRunning()` 函数（含轮询等待）
2. 实现错误信息匹配逻辑（需实测多种失败场景）
3. 添加前置条件校验
4. 集成到 skill 的连接建立流程
5. 大量真机测试，覆盖：
   - App 已运行
   - App 未运行但已安装
   - App 未安装
   - iproxy 未运行
   - iproxy 端口被占用（模拟器残留）
   - 设备锁定
   - 证书错误

**验证方式**：
```bash
# 测试矩阵
1. App 已运行 → 应跳过启动
2. 停止 App → 应自动启动并连接
3. 卸载 App → 应提示先安装
4. 停止 iproxy → 应提示启动 iproxy
5. 模拟器残留占用 38321 → 应检测并提示清理
```

---

## 风险与缓解

### 优化 1 的风险

| 风险 | 影响 | 缓解措施 |
|------|------|---------|
| 多设备时自动选错 | 连接到错误设备 | 提供明确列表让用户确认，或仅在单设备时自动 |
| `list_devices` API 变化 | 功能失效 | 添加字段存在性校验，优雅降级 |

### 优化 2 的风险

| 风险 | 影响 | 缓解措施 |
|------|------|---------|
| 误启动 App（用户正在手动调试）| 打断用户工作流 | 添加配置开关 `autoLaunch: false` 禁用 |
| 启动后连接超时（实际已启动）| 误报失败 | 增加轮询次数，给出"App 可能已启动，请手动验证"提示 |
| 错误信息匹配不准确 | 误诊断 | 保留原始错误信息，让用户可查看完整输出 |
| XcodeBuildMCP 错误格式变化 | 判断失效 | 使用宽松匹配（关键词），而非严格相等 |

---

## 推荐决策

### 立即实施：优化 1

**理由**：
- ✅ 技术成熟，边界清晰
- ✅ 用户体验提升明显（免记 deviceId）
- ✅ 风险低，易回滚
- ✅ 实施成本低

### 谨慎实施：优化 2

**建议**：
1. **先实现一个简化版本**：只处理"App 未运行 → 启动"的 happy path
2. **添加配置开关**：默认关闭，用户明确启用后才自动启动
3. **充分测试后**再默认开启
4. **保留手动启动路径**：即使自动启动失败，也能让用户手动执行

**配置示例**：
```yaml
# ~/.claude/skills/ios-automation/config.yaml
autoLaunch:
  enabled: false  # 默认关闭
  maxWaitSeconds: 15
  retryAttempts: 10
```

---

## 附录：关键代码位置

### 相关 MCP 工具

- `mcp__XcodeBuildMCP__list_devices` — 获取设备列表
- `mcp__XcodeBuildMCP__session_set_defaults` — 更新会话配置
- `mcp__XcodeBuildMCP__session_show_defaults` — 查看当前配置
- `mcp__XcodeBuildMCP__launch_app_device` — 启动真机 App
- `mcp__iOSDriver__health_check` — 检测 App 连接状态
- `mcp__iOSDriver__refresh_tools` — 刷新动态工具列表

### 参考文档

- `AGENTS.md` — XcodeBuildMCP 运行配置 + 四个必须记住的差异
- `docs/investigations/mcp-realdevice-e2e-issues.md` — 真机测试问题全集（问题 4 详细分析了 transport 失败场景）
- `docs/skills/l0-build-debug.md` — XcodeBuildMCP 工具能力矩阵
- `iOSDriver/src/staticTools.ts` — `health_check` 实现
- `iOSDriver/src/errors.ts` — 错误规范化逻辑

### 测试验证脚本位置

- `iOSDriver/scripts/e2e-comprehensive.mjs` — 综合端到端测试
- `iOSDriver/tests/staticTools.test.ts` — `health_check` 单元测试

---

## 总结

两个优化方案都能显著提升 `ios-automation` skill 的易用性：

- **优化 1（自动同步设备 ID）**：技术成熟，建议**立即实施**
- **优化 2（智能 App 启动）**：需要额外工程，建议**分阶段实施**（先简化版 + 配置开关，充分测试后再默认开启）

实施顺序：
1. ✅ 先做优化 1（低风险，高收益）
2. ⚠️ 再谨慎尝试优化 2（中风险，高收益，需充分测试）
3. 📊 收集用户反馈，迭代优化

两个优化组合后，真机自动化测试的启动流程将从"7 步手动配置"简化为"1 步自动检测"，用户体验提升显著。
