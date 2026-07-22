# WKWebView JavaScript 模式

仅在需要构造 JavaScript 时读取。选择器和参数都应来自当前页面，不要把业务凭据写入脚本。

## 读取文本

```javascript
await mcp__iOSDriver__ui_webView_eval({
  accessibilityIdentifier: "<webview-id>",
  script: "document.querySelector('<selector>')?.textContent ?? null"
})
```

## 点击并返回是否命中

```javascript
await mcp__iOSDriver__ui_webView_eval({
  accessibilityIdentifier: "<webview-id>",
  script: "(()=>{const el=document.querySelector('<selector>'); if(!el) return false; el.click(); return true;})()"
})
```

## 设置输入并派发事件

```javascript
await mcp__iOSDriver__ui_webView_eval({
  accessibilityIdentifier: "<webview-id>",
  function: "const el=document.querySelector(selector); if(!el) return false; el.value=value; el.dispatchEvent(new Event('input',{bubbles:true})); el.dispatchEvent(new Event('change',{bubbles:true})); return true;",
  arguments: {
    selector: "<selector>",
    value: "<value>"
  }
})
```

`selector` 和 `value` 是命名参数，函数体中直接引用。

## 有界等待 DOM 条件

```javascript
await mcp__iOSDriver__ui_webView_eval({
  accessibilityIdentifier: "<webview-id>",
  function: "const deadline=Date.now()+waitMs; while(Date.now()<deadline){const el=document.querySelector(selector); if(el) return el.textContent; await new Promise(r=>setTimeout(r,100));} throw new Error('DOM condition timed out');",
  arguments: {
    selector: "<selector>",
    waitMs: 3000
  },
  timeout: 5
})
```

仅对单一、明确的 DOM 条件使用此模式。复杂异步流程应切换到专门 Web 自动化工具。
