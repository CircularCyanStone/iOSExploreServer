---
name: ios-ui-webview
description: iOS WKWebView 中的 JavaScript 执行与轻量 Web 状态读取。用于简单 DOM 查询/点击/赋值、JSBridge 调用、localStorage 读取和 iOS 14+ async function；复杂多页 Web 自动化、网络拦截、性能分析和 DOM 视觉回归不适用。触发词包括 WKWebView、JavaScript、JS、DOM、JSBridge、hybrid、ui.webView.eval、ui_webView_eval。
---

# WKWebView JavaScript 执行

使用 `ui_webView_eval` 在已定位的 `WKWebView` 中执行最小 JavaScript 原语。`ui_inspect` 只看到 WKWebView 容器，看不到内部 DOM，因此 Native 定位与 DOM 查询要分开处理。

需要构造常见脚本时读取 [javascript-patterns.md](references/javascript-patterns.md)。

## 选择模式

| 需求 | 参数 | 语义 |
|---|---|---|
| 简单表达式、同步 DOM 操作 | `script` | 调用 `evaluateJavaScript`，支持表达式返回值，不支持顶层 `await` |
| Promise/await、需要命名参数 | `function` | iOS 14+ 调用 `callAsyncJavaScript` |

`script` 与 `function` 必须且只能提供一个。`arguments` 是 object，且只能与 `function` 一起使用；其 key 会作为函数体中的命名变量，例如传 `{userId:10}` 后直接写 `return userId * 2`，不要读取 `arguments[0]`。

`timeout` 单位为秒，默认 `5`，范围 `1...30`。

## 执行流程

1. 用 `ui_inspect` 找到 WKWebView 的唯一 `accessibilityIdentifier` 或当前 path。
2. identifier 不唯一或只能使用 path 时，携带本次 `viewSnapshotID` 做陈旧校验。
3. 选择 `script` 或 `function` 并调用 `ui_webView_eval`。
4. 读取返回的 `result/resultType/mode/executionTime/iosVersion`。
5. JS 触发 Native 导航或页面状态变化时，使用相应 UI skill 重新观察终态。

`resultType` 可能为 `null/boolean/number/string/array/object`。DOM node、Function、Symbol 等不可序列化结果会被收敛为 `result:null`，不要直接返回这些对象；改为返回文本、布尔值或普通 JSON。

## iOS 版本降级

`function` 在 iOS 14 以下会把函数体当作普通 script 执行，不是完整 async polyfill。含顶层 `return`、`await` 或依赖命名 arguments 的 function 可能失败。需要兼容 iOS 14 以下时，显式使用 `script` 并避免异步语法；不要依赖自动降级保持同一行为。

## 安全与边界

- 遵守 WKWebView 页面上下文和同源限制；不能借此访问受限跨域 iframe。
- 不把真实 token、密码或用户数据写进通用脚本示例、日志或报告。
- 简单 DOM 操作后返回明确布尔/文本，不把“JavaScript 没抛错”当作业务成功。
- 多请求竞态、网络 mock、拦截、复杂多页流程和性能分析应使用专门 Web 自动化环境；本 skill 不扩展成 Web DSL。

## 失败分诊

| code/现象 | 原因 | 动作 |
|---|---|---|
| `target_not_found` | WKWebView locator 已变化或页面未出现 | 重新 inspect，必要时先等待 |
| `invalid_data` 且目标类型不符 | locator 指向非 WKWebView | 核对控件类型 |
| `invalid_data` 且 JS error | 语法、页面 API 或降级模式不兼容 | 简化脚本并核对模式 |
| `invalid_data` 且 timed out | JS/Promise 未在 timeout 内完成 | 优先修正终止条件，再在 `1...30` 内调整 timeout |
| `stale_locator` | 携带的 snapshot 与当前 view 不一致 | 重新 inspect 后重试 |
| `result:null` + object type | 返回值不可序列化 | 转成普通 JSON/字符串再返回 |

WKWebView 导致的 Native 页面切换归 `ios-ui-nav`，整体画面取证归 `ios-ui-shot`，Native 侧长时终态等待归 `ios-ui-wait`。
