---
name: ios-alert-handling
description: |
  iOS App automation for detecting and responding to alerts, action sheets, and dialogs.
  
  Use this skill when the user needs to handle UIAlertController popups, respond to
  alert buttons, dismiss dialogs, or interact with alerts in iOS applications.
  
  Must explicitly mention iOS, iPhone, iPad, alerts, dialogs, or popups to trigger.
  
  Based on iOSDriver MCP Server with 97% test success rate across 42 automated tests.
---

# iOS Alert & Dialog Handling

## Purpose

Detect, inspect, and respond to iOS alerts (UIAlertController) including simple alerts, multi-button alerts, action sheets, and input dialogs with text fields.

## When to Use

Use this skill when you need to:
- Detect when an alert appears after triggering an action
- Read alert title, message, and button labels
- Respond to alerts by tapping specific buttons
- Handle confirmation dialogs (OK/Cancel)
- Handle destructive actions (Delete/Cancel)
- Handle action sheets (bottom sheet style)
- Fill text fields in login/input alerts
- Wait for alerts to appear or dismiss

## Prerequisites

- **iOSDriver MCP Server** connected and active
- **iOS App** running on simulator or physical device
- **Port 38321** accessible
- App must have triggered an alert or be ready to trigger one

## Commands Used

| Command | Purpose | Performance | Native MCP tool? |
|---------|---------|-------------|------------------|
| `ui.inspect` | Detect alert presence and read alert structure | 21ms median | ✅ `mcp__iOSDriver__ui_inspect` |
| `ui.alert.respond` | Respond to alert by tapping a button | 560ms median (includes animation) | ✅ `mcp__iOSDriver__ui_alert_respond` |
| `ui.input` | Fill text fields in input alerts (if needed) | 88-129ms | ✅ `mcp__iOSDriver__ui_input` |
| `ui.tap` | Trigger an action that produces an alert | ~22ms | ✅ `mcp__iOSDriver__ui_tap` |

> **MCP tool availability:** All commands have native `mcp__iOSDriver__*` tools.
> If issues occur, use fallback: `call_action(action:"ui.tap", data:{...})`.

**End-to-end alert handling:** ~1.1 seconds (trigger → detect → respond)

## Capabilities

### 1. Alert Detection

Check if an alert is present:
```bash
curl -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}' | jq '.data.alert.available'
# Returns: true or false
```

Alert structure in response:
```json
{
  "alert": {
    "available": true,
    "title": "确认操作",
    "message": "是否继续执行此操作？",
    "buttons": [
      {
        "index": 0,
        "title": "取消",
        "role": "cancel",
        "availableActions": ["ui.alert.respond"]
      },
      {
        "index": 1,
        "title": "确认",
        "role": "default",
        "availableActions": ["ui.alert.respond"]
      }
    ],
    "textFields": []
  }
}
```

### 2. Response Methods

Three ways to respond to alerts:

**By Index (Fastest):**
```json
{"buttonIndex": 0}
```
Use when you know button order. Index is 0-based.

**By Title (Readable):**
```json
{"buttonTitle": "确认"}
```
Use for clarity. Requires exact title match (case-sensitive, language-dependent).

**By Role (Semantic):**
```json
{"role": "cancel"}
```
Use for semantic clarity and language independence. Roles: `cancel`, `default`, `destructive`.

### 3. Alert Types Supported

**Simple Alerts (OK/Cancel):**
- 2 buttons: Cancel (role: cancel) + Confirm (role: default)
- Use case: Confirmation dialogs

**Three-Button Alerts:**
- 3 buttons: Destructive + Default + Cancel
- Example: Delete/Save/Cancel
- Use case: Destructive actions with save option

**Action Sheets:**
- Bottom sheet style (UIAlertController.Style.actionSheet)
- Multiple action buttons + Cancel
- Use case: Photo picker, share sheet

**Input Alerts:**
- Contains text fields (username, password, etc.)
- Use `ui.input` to fill fields before responding
- Text fields exposed in `alert.textFields` array

**Nested Alerts:**
- Alert dismissed, new alert appears immediately
- Response includes `presentedAfterDismiss: true`

## Usage Examples

### Example 1: Simple Two-Button Alert

```bash
# Step 1: Trigger alert (e.g., tap delete button)
curl -X POST http://localhost:38321/ -d '{
  "action": "ui.tap",
  "data": {
    "path": "root/0/1/0/3",
    "viewSnapshotID": "snap-abc123"
  }
}'

# Step 2: Wait for alert to appear
sleep 0.3

# Step 3: Check if alert is present
ALERT_CHECK=$(curl -s -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}')
echo $ALERT_CHECK | jq '.data.alert'

# Step 4: Respond by button index
curl -X POST http://localhost:38321/ -d '{
  "action": "ui.alert.respond",
  "data": {
    "buttonIndex": 1
  }
}'
```

**Response:**
```json
{
  "code": "ok",
  "data": {
    "dismissed": true,
    "performed": true,
    "presentedAfterDismiss": false,
    "button": {
      "index": 1,
      "role": "default",
      "title": "确认"
    },
    "dismissWaitMs": 444
  }
}
```

### Example 2: Three-Button Alert with Destructive Action

```bash
# Respond by role (language-independent)
curl -X POST http://localhost:38321/ -d '{
  "action": "ui.alert.respond",
  "data": {
    "role": "destructive"
  }
}'
```

### Example 3: Action Sheet

```bash
# Respond by title (readable)
curl -X POST http://localhost:38321/ -d '{
  "action": "ui.alert.respond",
  "data": {
    "buttonTitle": "拍照"
  }
}'
```

### Example 4: Input Alert (Login Dialog)

```bash
# Step 1: Inspect to see alert structure
INSPECT=$(curl -s -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}')
echo $INSPECT | jq '.data.alert.textFields'
# Output: [{"path": "root/0/0/1/0/0/4/0/0/0/0/0/0/0/0", "placeholder": "用户名", ...}]

# Step 2: Fill username field
curl -X POST http://localhost:38321/ -d '{
  "action": "ui.input",
  "data": {
    "path": "root/0/0/1/0/0/4/0/0/0/0/0/0/0/0",
    "viewSnapshotID": "snap-xyz789",
    "text": "my_username",
    "mode": "replace"
  }
}'

# Step 3: Fill password field
curl -X POST http://localhost:38321/ -d '{
  "action": "ui.input",
  "data": {
    "path": "root/0/0/1/0/0/4/0/0/0/0/0/0/0/1",
    "viewSnapshotID": "snap-xyz789",
    "text": "my_password",
    "mode": "replace"
  }
}'

# Step 4: Submit by tapping login button
curl -X POST http://localhost:38321/ -d '{
  "action": "ui.alert.respond",
  "data": {
    "buttonIndex": 0
  }
}'
```

### Example 5: Wait for Alert with Timeout

```bash
#!/bin/bash
# Wait up to 2 seconds for alert to appear

timeout=2.0
interval=0.1
elapsed=0

while (( $(echo "$elapsed < $timeout" | bc -l) )); do
  INSPECT=$(curl -s -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}')
  AVAILABLE=$(echo $INSPECT | jq -r '.data.alert.available')
  
  if [ "$AVAILABLE" = "true" ]; then
    echo "Alert appeared after ${elapsed}s"
    break
  fi
  
  sleep $interval
  elapsed=$(echo "$elapsed + $interval" | bc)
done

if [ "$AVAILABLE" != "true" ]; then
  echo "Timeout: No alert appeared within ${timeout}s"
fi
```

### Example 6: Rapid Consecutive Alerts

```bash
# Handle 5 consecutive alerts
for i in {1..5}; do
  # Trigger alert
  curl -X POST http://localhost:38321/ -d '{"action":"ui.tap","data":{...}}'
  sleep 0.3
  
  # Respond to alert
  curl -X POST http://localhost:38321/ -d '{"action":"ui.alert.respond","data":{"buttonIndex":0}}'
  sleep 0.2
done
# Success rate: 100% (5/5 tested)
```

## Parameters Reference

### ui.alert.respond Parameters

**Method 1: By Index**
```json
{
  "buttonIndex": 0  // Required: 0-based button index
}
```

**Method 2: By Title**
```json
{
  "buttonTitle": "确认"  // Required: exact button title (case-sensitive)
}
```

**Method 3: By Role**
```json
{
  "role": "cancel"  // Required: "cancel", "default", or "destructive"
}
```

**Response:**
```json
{
  "code": "ok",
  "data": {
    "dismissed": true,              // Alert was dismissed
    "performed": true,              // Button action was performed
    "presentedAfterDismiss": false, // New alert appeared after dismissal
    "button": {
      "index": 0,
      "role": "cancel",
      "title": "取消"
    },
    "dismissWaitMs": 444            // Time waited for dismissal animation
  }
}
```

### Alert Structure in ui.inspect

**Text Fields in Input Alerts:**
```json
{
  "textFields": [
    {
      "path": "root/0/0/1/0/0/4/0/0/0/0/0/0/0/0",
      "accessibilityIdentifier": "alert.input.username",
      "placeholder": "用户名",
      "isSecure": false,
      "availableActions": ["ui.input"]
    },
    {
      "path": "root/0/0/1/0/0/4/0/0/0/0/0/0/0/1",
      "accessibilityIdentifier": "alert.input.password",
      "placeholder": "密码",
      "isSecure": true,
      "availableActions": ["ui.input"]
    }
  ]
}
```

## Error Handling

### Common Errors

#### 1. `alert_unavailable`
**Cause:** No alert is currently displayed

**Solution:**
- Wait longer after triggering action (try 500ms)
- Verify trigger action succeeded
- Check if alert was already dismissed
- May be expected behavior (no alert triggered)

**Example:**
```bash
# Trigger action
curl -X POST http://localhost:38321/ -d '{"action":"ui.tap","data":{...}}'
# Wait for alert animation
sleep 0.5
# Now try responding
curl -X POST http://localhost:38321/ -d '{"action":"ui.alert.respond","data":{"buttonIndex":0}}'
```

#### 2. `alert_button_not_found`
**Cause:** Button index, title, or role not found

**Solution for Index:**
- Check button count in `ui.inspect` response
- Use valid index (0 to button count - 1)

**Solution for Title:**
- Verify exact title match (case-sensitive)
- Check for extra spaces or special characters
- Use `ui.inspect` to see exact button titles

**Solution for Role:**
- Verify role is "cancel", "default", or "destructive"
- Some buttons may not have explicit roles
- Fallback to index or title if role fails

**Example:**
```bash
# Check available buttons first
curl -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}' | jq '.data.alert.buttons'
# Output shows exact titles and roles
```

> **Role lookup reliability (F-39 核对结论):** `destructive` role 查找与
> `cancel`/`default` 完全一致——`UIAlertRespondExecutor.selectAction` 对三种 role
> 统一用 `$0.role == parsedRole` 等值匹配（`UIAlertAction.Style` 映射），无特殊失败
> 分支。早期文档声称的"destructive 偶发失败 (1 of 42)"是把测试报告里**唯一的**失败
> 用例（test #42「Invalid button index」——传 index=99 期望 `invalid_button_index`
> 实得 `alert_button_not_found`，与 role 无关）误植到 destructive role 上。结论：
> **不需要为 destructive role 套 retry/fallback 逻辑**，按需用 role/title/index 任
> 一即可。

#### 3. Invalid Button Index
**Cause:** buttonIndex > 20 or < 0

**Solution:**
- Use valid index between 0 and button count - 1
- Most alerts have 2-3 buttons

## Performance Characteristics

Based on 42 automated tests (97% pass rate):

| Operation | Mean | Median | Std Dev | Notes |
|-----------|------|--------|---------|-------|
| **ui.inspect** | 21.9ms | 21.3ms | - | Fast detection |
| **ui.tap (trigger)** | 21.8ms | 22.0ms | - | Trigger action |
| **ui.alert.respond** | 562.1ms | 560.7ms | ±9ms | Includes dismissal animation |
| **End-to-end** | 1114.3ms | 1111.1ms | - | Trigger → detect → respond |

**Consistency:** Very low variance (±9ms standard deviation) across 10 iterations.

**Rapid Alerts:** 5 consecutive alerts handled successfully with 100% success rate.

## Best Practices

### 1. Always Check Alert Presence First

```bash
# Good: Check before responding
INSPECT=$(curl -s -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}')
AVAILABLE=$(echo $INSPECT | jq -r '.data.alert.available')

if [ "$AVAILABLE" = "true" ]; then
  curl -X POST http://localhost:38321/ -d '{"action":"ui.alert.respond","data":{"buttonIndex":0}}'
else
  echo "No alert present"
fi
```

### 2. Prefer Role-Based or Index-Based Response

```bash
# Best: language-independent semantic selection (role works the same for
# cancel / default / destructive — no special retry needed)
curl -X POST http://localhost:38321/ -d '{"action":"ui.alert.respond","data":{"role":"cancel"}}'

# Or by index when button order is known
# {"buttonIndex": 1}

# Or by exact title when order/role is unknown (case-sensitive)
# {"buttonTitle": "确认"}
```

### 3. Handle Timing Properly

```bash
# Trigger action that shows alert
curl -X POST http://localhost:38321/ -d '{"action":"ui.tap","data":{...}}'

# Wait for alert animation to complete
sleep 0.3

# Now detect and respond
# ... alert handling code ...

# After responding, verify dismissal
sleep 0.2
curl -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}' | jq '.data.alert.available'
# Should be false
```

### 4. Log Alert Details for Debugging

```bash
ALERT_INFO=$(curl -s -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}' | jq '.data.alert')
echo "Alert title: $(echo $ALERT_INFO | jq -r '.title')"
echo "Alert message: $(echo $ALERT_INFO | jq -r '.message')"
echo "Buttons: $(echo $ALERT_INFO | jq -r '.buttons | length')"
echo $ALERT_INFO | jq '.buttons[] | {index, title, role}'
```

### 5. Handle Input Alerts Properly

```bash
# 1. Detect alert and text fields
INSPECT=$(curl -s -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}')
FIELDS=$(echo $INSPECT | jq -r '.data.alert.textFields')

# 2. Fill each text field
for field_path in $(echo $FIELDS | jq -r '.[].path'); do
  curl -X POST http://localhost:38321/ -d "{\"action\":\"ui.input\",\"data\":{\"path\":\"$field_path\",\"text\":\"value\"}}"
done

# 3. Submit
curl -X POST http://localhost:38321/ -d '{"action":"ui.alert.respond","data":{"buttonIndex":0}}'
```

## Alert Lifecycle

Complete lifecycle verification (all steps tested):

1. ✅ `alert.available = false` before trigger
2. ✅ Trigger action (ui.tap)
3. ✅ `alert.available = true` after trigger
4. ✅ `alert.buttons` array populated correctly
5. ✅ `alert.title` and `alert.message` captured
6. ✅ `alert.textFields` array populated for input alerts
7. ✅ Button roles (cancel/default/destructive) identified
8. ✅ `ui.alert.respond` executes button action
9. ✅ `alert.available = false` after response
10. ✅ Response includes button details and timing

## Response Fields

All response fields verified:

```json
{
  "dismissed": true,              // ✅ Alert was dismissed
  "performed": true,              // ✅ Button action executed
  "presentedAfterDismiss": false, // ✅ No nested alert appeared
  "button": {
    "index": 0,                   // ✅ Button index
    "role": "cancel",             // ✅ Button role
    "title": "取消"               // ✅ Button title
  },
  "dismissWaitMs": 444            // ✅ Animation timing
}
```

## Limitations

### Known Limitations

1. **Animation Timing:** Response includes ~400-500ms wait for dismissal animation. Cannot be skipped.

2. **Nested Alerts:** Only top-most alert is accessible. If multiple alerts are stacked, must dismiss current alert before accessing next.

3. **System Alerts:** Cannot handle system alerts (permissions, notifications) - only UIAlertController alerts within the app.

4. **Custom Alert Views:** Only works with UIAlertController. Custom modal views require other skills (ios-navigation, ios-gestures).

## Related Skills

- **ios-form-filling** - Fill text fields in input alerts
- **ios-navigation** - Trigger alerts via navigation actions
- **ios-screenshot** - Capture alert appearance for debugging
- **ios-dynamic-content** - Wait for alerts with complex timing

## Test Coverage

**Total Tests:** 42  
**Passed:** 41  
**Failed:** 1 (invalid button index error-code mismatch — sent index 99, expected `invalid_button_index`, got `alert_button_not_found`; unrelated to role lookup)  
**Success Rate:** 97%  
**Test Report:** `docs/alert-test-complete-report.json`

**Tested Scenarios:**
- ✅ Simple two-button alert (OK/Cancel)
- ✅ Three-button alert (Destructive/Default/Cancel)
- ✅ Login input alert (with text fields)
- ✅ Action sheet style
- ✅ Response by index
- ✅ Response by title
- ✅ Response by role
- ✅ Error handling (no alert, invalid button)
- ✅ Rapid consecutive alerts (5 alerts in sequence)
- ✅ Performance benchmarks (10 iterations)

> **F-39 核对结论**：报告 `scenarios_tested` 里有条手写备注"Role 'destructive'
> failed - needs investigation"，但该 scenario 整体标 PASS，且 42 条 `detailed_results`
> 里**没有任何**role/destructive 相关的失败用例——唯一失败是 test #42 invalid button
> index（见上）。源码 `UIAlertRespondExecutor.selectAction` 对三种 role 等值匹配，
> destructive 无特殊失败路径。因此 skill 不再保留"destructive 偶发失败"声明。

## Production Readiness

✅ **Production Ready**

This skill is 97% tested across 42 scenarios including all alert types, response methods, and error cases. Core functionality is solid. Role-based response (`cancel`/`default`/`destructive`) is handled uniformly in the executor — no known role-specific failure mode. The single failed test is an invalid-button-index error-code mismatch (error code naming, not a functional defect). Safe for production use with proper error handling.
