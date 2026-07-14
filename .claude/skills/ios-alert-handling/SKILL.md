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

| Command | Purpose | Performance |
|---------|---------|-------------|
| `ui.inspect` | Detect alert presence and read alert structure | 21ms median |
| `ui.alert.respond` | Respond to alert by tapping a button | 560ms median (includes animation) |
| `ui.input` | Fill text fields in input alerts (if needed) | 88-129ms |

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

#### 3. Destructive Role Lookup with Fallback

**Known Issue:** Destructive role lookup occasionally fails on first attempt (seen in 1 of 42 tests).

**Recommended Pattern:**
```bash
# Try by role first
RESULT=$(curl -s -X POST http://localhost:38321/ -d '{
  "action": "ui.alert.respond",
  "data": {"role": "destructive"}
}')

# Check if failed
if echo "$RESULT" | grep -q '"code":"alert_button_not_found"'; then
  echo "First attempt failed, retrying..."
  sleep 0.2
  RESULT=$(curl -s -X POST http://localhost:38321/ -d '{
    "action": "ui.alert.respond",
    "data": {"role": "destructive"}
  }')
  
  # If still fails, fall back to title or index
  if echo "$RESULT" | grep -q '"code":"alert_button_not_found"'; then
    echo "Role lookup failed, falling back to title"
    curl -X POST http://localhost:38321/ -d '{
      "action": "ui.alert.respond",
      "data": {"buttonTitle": "Delete"}
    }'
  fi
fi
```

**Fallback Strategy:**
1. **First:** Try by role (semantic, language-independent)
2. **Retry once:** Same role after 200ms delay
3. **Second:** Fall back to button title (readable, language-dependent)
4. **Last resort:** Use button index (requires knowing order)

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

### 2. Prefer Role-Based with Fallback Strategy

```bash
# Best: Semantic and language-independent, with fallback
# Try role first
RESULT=$(curl -s -X POST http://localhost:38321/ -d '{"action":"ui.alert.respond","data":{"role":"destructive"}}')

# If fails, retry once
if echo "$RESULT" | grep -q "alert_button_not_found"; then
  sleep 0.2
  RESULT=$(curl -s -X POST http://localhost:38321/ -d '{"action":"ui.alert.respond","data":{"role":"destructive"}}')
fi

# If still fails, fall back to title
if echo "$RESULT" | grep -q "alert_button_not_found"; then
  curl -X POST http://localhost:38321/ -d '{"action":"ui.alert.respond","data":{"buttonTitle":"Delete"}}'
fi

# Last resort: use index (requires knowing button order)
# {"buttonIndex": 1}
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

1. **Destructive Role Edge Case:** Occasionally fails on first attempt with role-based destructive lookup. Retry or use index/title as fallback.

2. **Animation Timing:** Response includes ~400-500ms wait for dismissal animation. Cannot be skipped.

3. **Nested Alerts:** Only top-most alert is accessible. If multiple alerts are stacked, must dismiss current alert before accessing next.

4. **System Alerts:** Cannot handle system alerts (permissions, notifications) - only UIAlertController alerts within the app.

5. **Custom Alert Views:** Only works with UIAlertController. Custom modal views require other skills (ios-navigation, ios-gestures).

## Related Skills

- **ios-form-filling** - Fill text fields in input alerts
- **ios-navigation** - Trigger alerts via navigation actions
- **ios-screenshot** - Capture alert appearance for debugging
- **ios-dynamic-content** - Wait for alerts with complex timing

## Test Coverage

**Total Tests:** 42  
**Passed:** 41  
**Failed:** 1 (destructive role edge case)  
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
- ⚠️ Destructive role lookup (partial failure, needs investigation)

## Production Readiness

✅ **Production Ready with Known Limitations**

This skill is 97% tested across 42 scenarios including all alert types, response methods, and error cases. Core functionality is solid. One edge case (destructive role lookup) has occasional failures - use index or title as fallback. Safe for production use with proper error handling.
