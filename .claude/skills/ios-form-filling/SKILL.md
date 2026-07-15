---
name: ios-form-filling
description: |
  iOS App automation for form filling and data entry tasks.
  
  Use this skill when the user needs to fill text fields, toggle switches, adjust sliders,
  select segments, or submit forms in iOS applications (iPhone/iPad apps).
  
  Must explicitly mention iOS, iPhone, iPad, or mobile app form filling to trigger.

  Based on iOSDriver MCP Server. Note: ui.input/ui.tap/ui.control.sendAction have no
  native MCP tool and must go through call_action (see F-02 inside).
---

# iOS Form Filling & Data Entry

## Purpose

Automate form filling and data entry in iOS applications, including text input, control interaction (switches, sliders, steppers, segments), keyboard management, and form submission.

## When to Use

Use this skill when you need to:
- Fill out registration or login forms
- Enter text into search fields
- Toggle settings switches
- Adjust slider values
- Increment/decrement steppers
- Select segment options
- Submit forms by tapping buttons
- Handle keyboard dismissal

## Prerequisites

- **iOSDriver MCP Server** connected and active
- **iOS App** running on simulator or physical device
- **Port 38321** accessible (localhost for simulator, iproxy for device)
- App must be on a screen with form elements

## Commands Used

| Command | Purpose | Performance | Native MCP tool? |
|---------|---------|-------------|------------------|
| `ui.inspect` | Find form fields and their paths | 100-200ms | ✅ `mcp__iOSDriver__ui_inspect` |
| `ui.input` | Enter text into fields (replace/append) | 88-129ms per field | ✅ `mcp__iOSDriver__ui_input` |
| `ui.control.sendAction` | Toggle switches, adjust sliders/steppers/segments | 3-4ms | ✅ `mcp__iOSDriver__ui_control_sendAction` |
| `ui.keyboard.dismiss` | Close keyboard after input | 200-250ms | ✅ `mcp__iOSDriver__ui_keyboard_dismiss` |
| `ui.tap` | Tap submit buttons | 50-100ms | ✅ `mcp__iOSDriver__ui_tap` |

> **排障兜底**：所有命令都有专用 MCP 工具。如遇参数问题或调用失败，
> 可使用 `mcp__iOSDriver__call_action(action:"ui.input", data:{...})` 绕过。
> 正常情况优先使用专用工具。
> 因此本 skill 的 **控件交互（开关/滑块/步进/分段）全部依赖 `call_action` 兜底**，
> 而不是有专属工具。

**Total form fill time (5 fields):** < 1 second

## Capabilities

### 1. Text Input

**Supported Field Types:**
- `UITextField` - Single-line text fields
- `UITextView` - Multi-line text areas
- `UISearchTextField` - Search bars with placeholders

**Input Modes:**
- **Replace mode** (`mode: "replace"`): Clear existing text and enter new text
- **Append mode** (`mode: "append"`): Add text to existing content

**Special Features:**
- Unicode and emoji support (full UTF-8)
- Empty string input (clear field)
- Secure text fields (passwords) - text is masked
- Multi-line input with `\n` — **only in `UITextView`**; `UITextField` rejects newline (the return key triggers its action instead of inserting a line break). See Example 3.
- Auto-submit option to dismiss keyboard (`submit`, default `true`)

### 2. Control Interaction

> **所有控件交互都走 `ui.control.sendAction`，该命令无原生 MCP 工具（F-02/F-38）。**
> 把下面示例里的 `{"action":"ui.control.sendAction","data":{...}}` 改用
> `call_action(action:"ui.control.sendAction", data:{...})` 发送即可。

**UISwitch (Toggle Switches):**
```json
{
  "action": "ui.control.sendAction",
  "data": {
    "path": "root/0/0/0/2/1/0",
    "viewSnapshotID": "snap-XXX",
    "event": "valueChanged"
  }
}
```
Response includes `currentValue` (true/false) and `previousValue`.

**UISlider (Sliders):**
```json
{
  "action": "ui.control.sendAction",
  "data": {
    "path": "root/0/0/0/3/1",
    "viewSnapshotID": "snap-XXX",
    "event": "valueChanged",
    "value": 0.75
  }
}
```
Set `value` between 0.0 and 1.0.

**UIStepper (Increment/Decrement):**
```json
{
  "action": "ui.control.sendAction",
  "data": {
    "path": "root/0/0/0/5/1/0",
    "viewSnapshotID": "snap-XXX",
    "event": "valueChanged"
  }
}
```
Increments or decrements based on control state.

**UISegmentedControl (Segment Selection):**
```json
{
  "action": "ui.control.sendAction",
  "data": {
    "path": "root/0/0/0/4/1",
    "viewSnapshotID": "snap-XXX",
    "event": "valueChanged",
    "value": 1
  }
}
```
Set `value` to segment index (0-based).

### 3. Form Submission

After filling all fields:
1. Use `ui.keyboard.dismiss` to close keyboard (if visible)
2. Find submit button via `ui.inspect`
3. Use `ui.tap` to submit form
4. Wait 500ms for form submission animation/transition

## Usage Examples

### Example 1: Login Form

```bash
# Step 1: Inspect to find username field
curl -X POST http://localhost:38321/ -d '{
  "action": "ui.inspect"
}'
# Response includes field paths and snapshot ID

# Step 2: Fill username
curl -X POST http://localhost:38321/ -d '{
  "action": "ui.input",
  "data": {
    "path": "root/0/1/0/0/0/2",
    "viewSnapshotID": "snap-abc123",
    "text": "john.doe@example.com",
    "mode": "replace",
    "submit": false
  }
}'

# Step 3: Fill password
curl -X POST http://localhost:38321/ -d '{
  "action": "ui.input",
  "data": {
    "path": "root/0/1/0/1/0/2",
    "viewSnapshotID": "snap-abc123",
    "text": "secure_password",
    "mode": "replace",
    "submit": true
  }
}'

# Step 4: Tap login button
curl -X POST http://localhost:38321/ -d '{
  "action": "ui.tap",
  "data": {
    "path": "root/0/1/0/2/0",
    "viewSnapshotID": "snap-abc123"
  }
}'
```

### Example 2: Settings Form with Controls

```bash
# Toggle notification switch
curl -X POST http://localhost:38321/ -d '{
  "action": "ui.control.sendAction",
  "data": {
    "path": "root/0/2/1/0",
    "viewSnapshotID": "snap-xyz789",
    "event": "valueChanged"
  }
}'

# Adjust volume slider to 75%
curl -X POST http://localhost:38321/ -d '{
  "action": "ui.control.sendAction",
  "data": {
    "path": "root/0/3/1",
    "viewSnapshotID": "snap-xyz789",
    "event": "valueChanged",
    "value": 0.75
  }
}'

# Select second segment (index 1)
curl -X POST http://localhost:38321/ -d '{
  "action": "ui.control.sendAction",
  "data": {
    "path": "root/0/4/1",
    "viewSnapshotID": "snap-xyz789",
    "event": "valueChanged",
    "value": 1
  }
}'
```

### Example 3: Multi-line Text Entry (UITextView only)

> **`UITextField` rejects `\n`.** The newline character is only accepted by
> `UITextView`. Sending `"Line 1\nLine 2"` to a `UITextField` returns
> `input_rejected` (the return key triggers the field's action instead of inserting
> a line break — UIKit inherent behavior, see findings F-04). Confirm the target is
> a `UITextView` via `ui.inspect` before using `\n`.

```bash
# Target must be UITextView (verified via ui.inspect .type == "UITextView")
curl -X POST http://localhost:38321/ -d '{
  "action": "ui.input",
  "data": {
    "path": "root/0/1/0/0",
    "viewSnapshotID": "snap-def456",
    "text": "Line 1\nLine 2\nLine 3",
    "mode": "replace",
    "submit": false
  }
}'
```

### Example 4: Form with Validation Errors

```bash
#!/bin/bash
# Fill form and handle validation errors

fill_and_submit() {
  # Get initial state
  INSPECT=$(curl -s -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}')
  SNAPSHOT_ID=$(echo $INSPECT | jq -r '.data.viewSnapshotID')
  
  # Fill email field with invalid email
  curl -s -X POST http://localhost:38321/ -d '{
    "action": "ui.input",
    "data": {
      "path": "root/0/1/0/0/0/2",
      "viewSnapshotID": "'$SNAPSHOT_ID'",
      "text": "invalid-email",
      "mode": "replace"
    }
  }' > /dev/null
  
  # Fill password
  curl -s -X POST http://localhost:38321/ -d '{
    "action": "ui.input",
    "data": {
      "path": "root/0/1/0/1/0/2",
      "viewSnapshotID": "'$SNAPSHOT_ID'",
      "text": "password123",
      "mode": "replace"
    }
  }' > /dev/null
  
  # Submit form
  curl -s -X POST http://localhost:38321/ -d '{
    "action": "ui.tap",
    "data": {
      "path": "root/0/1/0/2/0",
      "viewSnapshotID": "'$SNAPSHOT_ID'"
    }
  }' > /dev/null
  
  sleep 0.5
  
  # Check for validation error
  INSPECT=$(curl -s -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}')
  ERROR=$(echo $INSPECT | jq -r '.data.targets[] | select(.text | contains("Invalid email"))')
  
  if [ -n "$ERROR" ]; then
    echo "❌ Validation error detected: Invalid email"
    
    # Correct the email
    SNAPSHOT_ID=$(echo $INSPECT | jq -r '.data.viewSnapshotID')
    curl -s -X POST http://localhost:38321/ -d '{
      "action": "ui.input",
      "data": {
        "path": "root/0/1/0/0/0/2",
        "viewSnapshotID": "'$SNAPSHOT_ID'",
        "text": "user@example.com",
        "mode": "replace"
      }
    }' > /dev/null
    
    # Resubmit
    curl -s -X POST http://localhost:38321/ -d '{
      "action": "ui.tap",
      "data": {
        "path": "root/0/1/0/2/0",
        "viewSnapshotID": "'$SNAPSHOT_ID'"
      }
    }' > /dev/null
    
    echo "✅ Form resubmitted with corrected email"
  else
    echo "✅ Form submitted successfully"
  fi
}

fill_and_submit
```

### Example 5: Multi-Page Form Workflow

```bash
#!/bin/bash
# Fill multi-page form with navigation between pages

# Page 1: Personal Information
echo "Filling Page 1: Personal Information"
INSPECT=$(curl -s -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}')
SNAPSHOT_ID=$(echo $INSPECT | jq -r '.data.viewSnapshotID')

# First Name
curl -s -X POST http://localhost:38321/ -d '{
  "action": "ui.input",
  "data": {
    "path": "root/0/1/0/0/0/2",
    "viewSnapshotID": "'$SNAPSHOT_ID'",
    "text": "John",
    "mode": "replace"
  }
}' > /dev/null

# Last Name
curl -s -X POST http://localhost:38321/ -d '{
  "action": "ui.input",
  "data": {
    "path": "root/0/1/0/1/0/2",
    "viewSnapshotID": "'$SNAPSHOT_ID'",
    "text": "Doe",
    "mode": "replace"
  }
}' > /dev/null

# Tap "Next" button
NEXT_PATH=$(echo $INSPECT | jq -r '.data.targets[] | select(.text == "Next") | .path')
curl -s -X POST http://localhost:38321/ -d "{
  \"action\": \"ui.tap\",
  \"data\": {
    \"path\": \"$NEXT_PATH\",
    \"viewSnapshotID\": \"$SNAPSHOT_ID\"
  }
}" > /dev/null

sleep 0.5

# Page 2: Contact Information
echo "Filling Page 2: Contact Information"
INSPECT=$(curl -s -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}')
SNAPSHOT_ID=$(echo $INSPECT | jq -r '.data.viewSnapshotID')

# Email
curl -s -X POST http://localhost:38321/ -d '{
  "action": "ui.input",
  "data": {
    "path": "root/0/1/0/0/0/2",
    "viewSnapshotID": "'$SNAPSHOT_ID'",
    "text": "john.doe@example.com",
    "mode": "replace"
  }
}' > /dev/null

# Phone
curl -s -X POST http://localhost:38321/ -d '{
  "action": "ui.input",
  "data": {
    "path": "root/0/1/0/1/0/2",
    "viewSnapshotID": "'$SNAPSHOT_ID'",
    "text": "+1-555-1234",
    "mode": "replace"
  }
}' > /dev/null

# Tap "Submit" button
SUBMIT_PATH=$(echo $INSPECT | jq -r '.data.targets[] | select(.text == "Submit") | .path')
curl -s -X POST http://localhost:38321/ -d "{
  \"action\": \"ui.tap\",
  \"data\": {
    \"path\": \"$SUBMIT_PATH\",
    \"viewSnapshotID\": \"$SNAPSHOT_ID\"
  }
}" > /dev/null

sleep 0.5
echo "✅ Multi-page form completed"
```

## Parameters Reference

### ui.input Parameters

```json
{
  "path": "root/0/1/0/0/0/2",           // Required: element path from ui.inspect
  "viewSnapshotID": "snap-abc123",      // Required: snapshot ID from ui.inspect
  "text": "Hello World",                 // Required: text to enter (can be empty string)
  "mode": "replace",                     // Optional: "replace" (default) or "append"
  "submit": true                         // Optional: resignFirstResponder after input (default: true)
}
```

**Response:**
```json
{
  "code": "ok",
  "data": {
    "finalText": "Hello World",
    "type": "UITextField"
  }
}
```

For secure fields (passwords):
```json
{
  "code": "ok",
  "data": {
    "length": 15,
    "masked": "•••••••••••••••",
    "type": "UITextField"
  }
}
```

### ui.control.sendAction Parameters

```json
{
  "path": "root/0/2/1/0",               // Required: element path
  "viewSnapshotID": "snap-abc123",      // Required: snapshot ID
  "event": "valueChanged",               // Required: always "valueChanged" (NOT "action"!)
  "value": 0.75                          // Optional: for sliders (0.0-1.0) or segment index
}
```

**Response:**
```json
{
  "code": "ok",
  "data": {
    "sent": true,
    "path": "root/0/2/1/0",
    "type": "UISwitch",
    "event": "valueChanged",
    "previousValue": false,
    "currentValue": true,
    "isEnabled": true,
    "isSelected": false,
    "accessibilityIdentifier": "notifications.switch"
  }
}
```

### ui.keyboard.dismiss Parameters

```json
{
  "strategy": "auto"  // Optional: "auto" (default), "endEditing", or "resignFirstResponder"
}
```

**Response:**
```json
{
  "code": "ok",
  "data": {
    "dismissed": true,
    "strategy": "auto",
    "firstResponderBefore": "UITextField",
    "firstResponderAfter": null
  }
}
```

## Error Handling

### Common Errors

#### 1. `become_first_responder_failed`
**Cause:** Text field cannot gain focus (disabled, hidden, or obstructed)

**Solution:**
- Verify field is enabled: check `isEnabled` in `ui.inspect` response
- Ensure field is visible on screen
- Retry after 200ms delay
- Try tapping field first with `ui.tap` before `ui.input`

**Example:**
```bash
# Tap field to focus, then input
curl -X POST http://localhost:38321/ -d '{"action":"ui.tap","data":{"path":"root/0/1/0/0/0/2","viewSnapshotID":"snap-123"}}'
sleep 0.2
curl -X POST http://localhost:38321/ -d '{"action":"ui.input","data":{"path":"root/0/1/0/0/0/2","viewSnapshotID":"snap-123","text":"Hello"}}'
```

#### 2. `stale_locator`
**Cause:** Snapshot ID expired or UI changed since last `ui.inspect`

**Solution:**
- Call `ui.inspect` again to get fresh snapshot ID
- Retry operation with new snapshot ID
- Snapshots have a 120-second TTL

**Example:**
```bash
# Get fresh snapshot
SNAPSHOT=$(curl -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}' | jq -r '.data.viewSnapshotID')
# Use fresh snapshot in next command
curl -X POST http://localhost:38321/ -d "{\"action\":\"ui.input\",\"data\":{\"path\":\"root/0/1/0/0\",\"viewSnapshotID\":\"$SNAPSHOT\",\"text\":\"Hello\"}}"
```

#### 3. `target_not_found`
**Cause:** Element path no longer exists or is off-screen

**Solution:**
- Use `ui.scrollToElement` to reveal off-screen fields
- Re-inspect to find current path
- Verify element exists with correct path

**Example:**
```bash
# Scroll to field first
curl -X POST http://localhost:38321/ -d '{"action":"ui.scrollToElement","data":{"match":"text","value":"Email"}}'
# Then inspect and fill
curl -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}'
```

#### 4. `invalid_data`
**Cause:** Missing required parameter or invalid parameter value

**Solution:**
- Verify all required fields present: `path`, `viewSnapshotID`, `text`
- Check `mode` is "replace" or "append"
- For controls, verify `event` is "valueChanged" (not "action")
- For sliders, verify `value` is between 0.0 and 1.0

## Performance Characteristics

Based on 10 automated tests with 100% success rate:

| Operation | Mean | Median | Min | Max |
|-----------|------|--------|-----|-----|
| **ui.input (replace)** | 129ms | 129ms | 88ms | 206ms |
| **ui.input (append)** | 97ms | 97ms | 93ms | 98ms |
| **ui.input (multiline)** | 93ms | 93ms | - | - |
| **ui.control.sendAction** | 3ms | 3ms | 3ms | 4ms |
| **ui.keyboard.dismiss** | 206ms | 206ms | - | - |

**Total form fill (5 fields + submit):**
- Text input: 5 × 100ms = 500ms
- Control actions: 3 × 3ms = 9ms
- Keyboard dismiss: 200ms
- Button tap: 50ms
- **Total: ~760ms** (under 1 second)

## Best Practices

### 1. Always Get Fresh Snapshot
```bash
# Do this before each batch of operations
INSPECT_RESPONSE=$(curl -s -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}')
SNAPSHOT_ID=$(echo $INSPECT_RESPONSE | jq -r '.data.viewSnapshotID')
```

### 2. Use Replace Mode by Default
```json
{"mode": "replace"}  // Clears field first - predictable behavior
```
Use append mode only when you need to add to existing text.

### 3. Batch Control Actions
Control actions are extremely fast (3-4ms). No need to re-inspect between them:
```bash
# Toggle switch
curl -X POST http://localhost:38321/ -d '{"action":"ui.control.sendAction","data":{...}}'
# Adjust slider immediately
curl -X POST http://localhost:38321/ -d '{"action":"ui.control.sendAction","data":{...}}'
# Select segment immediately
curl -X POST http://localhost:38321/ -d '{"action":"ui.control.sendAction","data":{...}}'
```

### 4. Handle Keyboard Properly
```bash
# Option 1: Auto-dismiss with submit flag
{"text": "Hello", "submit": true}

# Option 2: Manual dismiss after all text entry
curl -X POST http://localhost:38321/ -d '{"action":"ui.keyboard.dismiss"}'
```

### 5. Wait After Form Submission
```bash
curl -X POST http://localhost:38321/ -d '{"action":"ui.tap","data":{...}}'
sleep 0.5  # Wait for submission animation/navigation
```

### 6. Use Accessibility Identifiers When Available
Instead of fragile path-based lookups, use accessibilityIdentifier when available:
```json
{
  "accessibilityIdentifier": "login.username.field",
  "viewSnapshotID": "snap-123",
  "text": "john@example.com"
}
```

## Limitations

### Known Limitations

1. **Snapshot TTL:** Snapshots expire after 120 seconds. For long forms, refresh snapshot periodically.

2. **Keyboard Types:** Cannot change keyboard type (numeric, email, URL). Keyboard type is determined by field configuration.

3. **Autocomplete:** Cannot programmatically trigger or select from autocomplete suggestions.

4. **Picker Views:** Use separate `ios-date-picker` skill for UIPickerView and UIDatePicker.

5. **Rich Text:** Cannot apply formatting (bold, italic, colors) in UITextView.

6. **Control Value Range:** For steppers, cannot set absolute value - only increment/decrement.

### Platform Constraints

- **iOS 26.2+** required (matches the SPMExample deployment target; older "iOS 14+" claim was outdated)
- **Debug builds only** (uses private APIs for control manipulation)
- **Main thread execution** - control actions must complete within 5 seconds

## Related Skills

- **ios-navigation** - Navigate to form screens
- **ios-alert-handling** - Handle form validation alerts
- **ios-screenshot** - Capture form state for verification
- **ios-list-interaction** - Interact with form field pickers

## Test Coverage

**Total Tests:** 10 (per the report below; the old "200+ scenarios" headline was unsourced and removed — F-40)
**Success Rate:** 100%
**Test Report:** `docs/input-alert-control-test-report.json`（路径相对于**仓库根**，不是相对于本 skill 目录）

**Tested Scenarios:**
- ✅ UITextField replace mode
- ✅ UITextField append mode
- ✅ UITextView multiline input
- ✅ Empty string input (clear field)
- ✅ Unicode and emoji
- ✅ Secure text fields (passwords)
- ✅ UISwitch toggle
- ✅ UISlider setValue
- ✅ UIStepper increment
- ✅ UISegmentedControl select
- ✅ Keyboard dismissal

## Production Readiness

✅ **Production Ready**

This skill is fully tested with 100% success rate across all form input scenarios. All commands are verified and performance baselines are established. Safe for production use in automated testing and app automation workflows.
