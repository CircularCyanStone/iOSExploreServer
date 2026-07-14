---
name: ios-date-picker
description: |
  iOS App automation for date and time picker interactions.
  
  ⚠️ NOT TESTED - All picker commands require comprehensive testing before use.
  
  Use this skill when the user needs to select dates, times, or use picker wheels
  in iOS applications (UIDatePicker, UIPickerView).
  
  Must explicitly mention iOS, iPhone, iPad, date picker, time picker, or picker view to trigger.
  
  Based on iOSDriver MCP Server. Note: Picker commands not tested yet.
---

# iOS Date & Time Picker

> **⚠️ NOT PRODUCTION READY**  
> All date picker and picker view commands in this skill are UNTESTED.  
> Do not use in production environments without thorough testing first.  
> Consider using manual workarounds (swipe/tap) or alternative UI patterns until testing is complete.

## Purpose

Interact with iOS date pickers (UIDatePicker) and generic picker views (UIPickerView) to select dates, times, and custom picker values.

## When to Use

Use this skill when you need to:
- Select a date from UIDatePicker
- Select a time from time picker
- Select date and time together
- Interact with custom UIPickerView wheels
- Set picker values programmatically

## Prerequisites

- **iOSDriver MCP Server** connected and active
- **iOS App** with UIDatePicker or UIPickerView
- **Port 38321** accessible

## Commands Used

| Command | Purpose | Status |
|---------|---------|--------|
| `ui.datePicker.*` | Date picker operations | ❌ Not tested |
| `ui.picker.*` | Generic picker operations | ❌ Not tested |
| `ui.swipe` | Manual picker wheel scrolling | ✅ Tested (workaround) |

## Capabilities (Theoretical)

### 1. Date Selection

**Set Date (NOT TESTED):**
```bash
curl -X POST http://localhost:38321/ -d '{
  "action": "ui.datePicker.setDate",
  "data": {
    "path": "picker_path",
    "date": "2026-12-25"
  }
}'
```

### 2. Time Selection

**Set Time (NOT TESTED):**
```bash
curl -X POST http://localhost:38321/ -d '{
  "action": "ui.datePicker.setTime",
  "data": {
    "path": "picker_path",
    "time": "14:30"
  }
}'
```

### 3. Picker View Selection

**Select Component Value (NOT TESTED):**
```bash
curl -X POST http://localhost:38321/ -d '{
  "action": "ui.picker.selectValue",
  "data": {
    "path": "picker_path",
    "component": 0,
    "value": "Option 3"
  }
}'
```

## Workaround: Manual Interaction

Since picker commands are not tested, use manual approaches:

### Approach 1: Swipe on Picker Wheel

```bash
# Find picker wheel element
INSPECT=$(curl -s -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}')
PICKER_REF=$(echo $INSPECT | jq -r '.data.targets[] | select(.type == "UIPickerView") | .elementRef')

# Swipe up to scroll picker down (select higher value)
curl -X POST http://localhost:38321/ -d "{
  \"action\": \"ui.swipe\",
  \"data\": {
    \"withinElementRef\": \"$PICKER_REF\",
    \"direction\": \"up\",
    \"distance\": 0.3
  }
}"
```

### Approach 2: Tap Picker Values

```bash
# If picker displays as list, tap the desired value
INSPECT=$(curl -s -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}')
SNAPSHOT_ID=$(echo $INSPECT | jq -r '.data.viewSnapshotID')
VALUE_PATH=$(echo $INSPECT | jq -r '.data.targets[] | select(.text == "December") | .path')

curl -X POST http://localhost:38321/ -d "{
  \"action\": \"ui.tap\",
  \"data\": {
    \"path\": \"$VALUE_PATH\",
    \"viewSnapshotID\": \"$SNAPSHOT_ID\"
  }
}"
```

## Limitations

❌ **No Test Coverage**

- All `ui.datePicker.*` commands are UNTESTED
- All `ui.picker.*` commands are UNTESTED
- No reliable pattern for programmatic picker interaction
- Must use manual swipe/tap workarounds
- Cannot verify selected values easily

## Recommendation

**Do not use this skill in production** until comprehensive testing is performed. For date/time selection, consider:

1. Using alternative UI patterns (text input with date validation)
2. Manual testing with real device
3. Implementing custom test support in app code

## Related Skills

- **ios-gestures** - Swipe workaround for pickers
- **ios-form-filling** - Alternative input methods

## Production Readiness

❌ **Not Production Ready**

Requires comprehensive testing of all picker commands before any production use. Current state: experimental only.
