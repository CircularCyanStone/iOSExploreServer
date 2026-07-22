# Picker 调用示例

仅在需要构造 picker 参数时读取。占位符必须替换为当前 `ui_inspect` 观察值。

## 设置完整日期

```javascript
await mcp__iOSDriver__ui_datePicker_setDate({
  accessibilityIdentifier: "<date-picker-id>",
  date: "2030-05-20T09:30:00Z"
})
```

## 只修改日期分量

```javascript
await mcp__iOSDriver__ui_datePicker_setDate({
  accessibilityIdentifier: "<date-picker-id>",
  year: 2030,
  month: 5,
  day: 20
})
```

## 按索引选择行

```javascript
await mcp__iOSDriver__ui_picker_selectRow({
  accessibilityIdentifier: "<picker-id>",
  component: 0,
  row: 2
})
```

## 按标题选择行

```javascript
await mcp__iOSDriver__ui_picker_selectRow({
  accessibilityIdentifier: "<picker-id>",
  component: 0,
  title: "<exact-row-title>"
})
```

没有稳定 identifier 时，把定位替换为当次 inspect 的 `path`，并同时传 `viewSnapshotID`。
