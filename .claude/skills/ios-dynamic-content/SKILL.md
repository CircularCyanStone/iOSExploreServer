---
name: ios-dynamic-content
description: |
  iOS App automation for handling dynamic content, loading states, and async updates.
  
  Use this skill when the user needs to wait for content to load, handle loading indicators,
  or wait for UI state changes in iOS applications.
  
  Must explicitly mention iOS, iPhone, iPad, loading, waiting, or dynamic content to trigger.
  
  Based on iOSDriver MCP Server. Note: ui.wait commands not fully tested yet.
---

# iOS Dynamic Content Handling

## Purpose

Handle loading indicators, wait for asynchronous content to appear or disappear, and manage dynamic UI state changes in iOS applications.

## When to Use

Use this skill when you need to:
- Wait for loading indicators to disappear
- Wait for content to load after network requests
- Wait for animations to complete
- Wait for elements to appear or disappear
- Handle time-dependent UI changes
- Detect when async operations complete

## Prerequisites

- **iOSDriver MCP Server** connected and active
- **iOS App** with dynamic or async content
- **Port 38321** accessible

## Commands Used

| Command | Purpose | Status |
|---------|---------|--------|
| `ui.wait` | Wait for element state change | ⚠️ Not tested |
| `ui.waitAny` | Wait for any of multiple conditions | ⚠️ Not tested |
| `ui.inspect` | Poll for state changes | ✅ Tested |

## Capabilities

### 1. Polling with ui.inspect

**Manual Polling Loop:**
```bash
#!/bin/bash
# Wait for loading indicator to disappear

timeout=10.0
interval=0.3
elapsed=0

while (( $(echo "$elapsed < $timeout" | bc -l) )); do
  INSPECT=$(curl -s -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}')
  LOADING=$(echo $INSPECT | jq -r '.data.targets[] | select(.text == "Loading...") | .text')
  
  if [ -z "$LOADING" ]; then
    echo "✅ Loading complete after ${elapsed}s"
    break
  fi
  
  sleep $interval
  elapsed=$(echo "$elapsed + $interval" | bc)
done
```

### 2. Wait for Element to Appear

```bash
wait_for_element() {
  local target_text=$1
  local timeout=${2:-10.0}
  local interval=0.5
  local elapsed=0
  
  while (( $(echo "$elapsed < $timeout" | bc -l) )); do
    INSPECT=$(curl -s -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}')
    FOUND=$(echo $INSPECT | jq -r ".data.targets[] | select(.text | contains(\"$target_text\")) | .text")
    
    if [ -n "$FOUND" ]; then
      echo "✅ Element appeared: $target_text"
      return 0
    fi
    
    sleep $interval
    elapsed=$(echo "$elapsed + $interval" | bc)
  done
  
  echo "❌ Timeout: Element did not appear within ${timeout}s"
  return 1
}

# Usage
wait_for_element "Welcome back" 5.0
```

### 3. Wait for Element to Disappear

```bash
wait_for_element_gone() {
  local target_text=$1
  local timeout=${2:-10.0}
  local interval=0.3
  local elapsed=0
  
  while (( $(echo "$elapsed < $timeout" | bc -l) )); do
    INSPECT=$(curl -s -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}')
    FOUND=$(echo $INSPECT | jq -r ".data.targets[] | select(.text | contains(\"$target_text\")) | .text")
    
    if [ -z "$FOUND" ]; then
      echo "✅ Element disappeared: $target_text"
      return 0
    fi
    
    sleep $interval
    elapsed=$(echo "$elapsed + $interval" | bc)
  done
  
  echo "❌ Timeout: Element still present after ${timeout}s"
  return 1
}

# Usage
wait_for_element_gone "Loading..." 10.0
```

## Usage Examples

### Example 1: Wait for Network Request to Complete

```bash
# Trigger refresh
curl -X POST http://localhost:38321/ -d '{"action":"ui.tap","data":{...}}'

# Wait for loading spinner to disappear
wait_for_element_gone "Loading..." 10.0

# Verify content loaded
INSPECT=$(curl -s -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}')
CONTENT=$(echo $INSPECT | jq -r '.data.targets[] | select(.text | contains("Updated"))')

if [ -n "$CONTENT" ]; then
  echo "✅ Content loaded successfully"
else
  echo "❌ Content did not load"
fi
```

### Example 2: Wait for Any of Multiple Outcomes

```bash
# Wait for either Success or Error message
timeout=10.0
interval=0.5
elapsed=0
result=""

while (( $(echo "$elapsed < $timeout" | bc -l) )); do
  INSPECT=$(curl -s -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}')
  
  SUCCESS=$(echo $INSPECT | jq -r '.data.targets[] | select(.text == "Success") | .text')
  ERROR=$(echo $INSPECT | jq -r '.data.targets[] | select(.text == "Error") | .text')
  
  if [ -n "$SUCCESS" ]; then
    result="success"
    break
  elif [ -n "$ERROR" ]; then
    result="error"
    break
  fi
  
  sleep $interval
  elapsed=$(echo "$elapsed + $interval" | bc)
done

echo "Result: $result"
```

## Best Practices

1. **Use Reasonable Timeouts:** 5-10 seconds for most operations, 30 seconds for slow network
2. **Poll Interval:** 300-500ms is good balance between responsiveness and load
3. **Verify Result:** Always check final state after waiting
4. **Handle Timeouts:** Provide clear error messages when timeouts occur

## Built-in Wait Commands (Not Fully Tested)

iOSExploreServer provides built-in wait commands that may offer better performance than manual polling. However, these are NOT fully tested yet.

### ui.wait

Single condition wait with configurable timeout:

```bash
curl -X POST http://localhost:38321/ -d '{
  "action": "ui.wait",
  "data": {
    "mode": "idle",
    "timeoutMs": 5000,
    "intervalMs": 300
  }
}'
```

**Available modes:**
- `"idle"` - Wait for UI to become idle (no animations)
- `"targetExists"` - Wait for specific element to appear
- `"targetGone"` - Wait for specific element to disappear
- `"textExists"` - Wait for text to appear in any element
- `"textGone"` - Wait for text to disappear

**With target specification:**
```bash
curl -X POST http://localhost:38321/ -d '{
  "action": "ui.wait",
  "data": {
    "mode": "targetExists",
    "accessibilityIdentifier": "content.loaded",
    "timeoutMs": 10000,
    "intervalMs": 500
  }
}'
```

### ui.waitAny

Wait for any of multiple conditions (first match wins):

```bash
curl -X POST http://localhost:38321/ -d '{
  "action": "ui.waitAny",
  "data": {
    "conditions": [
      {
        "id": "success",
        "mode": "textExists",
        "text": "Success"
      },
      {
        "id": "error",
        "mode": "textExists",
        "text": "Error"
      },
      {
        "id": "loading_done",
        "mode": "targetGone",
        "accessibilityIdentifier": "loading.spinner"
      }
    ],
    "timeoutMs": 15000,
    "intervalMs": 300
  }
}'
```

**Expected response:**
```json
{
  "code": "ok",
  "data": {
    "matched": true,
    "matchedConditionId": "success",
    "elapsedMs": 2340
  }
}
```

### Performance Comparison

**Manual polling (tested):**
- Full control over polling logic
- Requires bash loop and jq parsing
- ~100-200ms per iteration (ui.inspect call)
- Flexible condition checking

**Built-in wait (not tested):**
- Single command, simpler syntax
- Potentially faster (server-side polling)
- May reduce network overhead
- Limited to predefined wait modes

**Recommendation:** Use manual polling for production until `ui.wait` commands are comprehensively tested. Manual polling provides proven reliability and full control.

## When to Use Each Approach

### Use Manual Polling When:
- Production reliability is critical
- Custom complex conditions needed
- Multiple state checks required
- Full control over retry logic needed

### Consider Built-in Wait When:
- Testing in development environment
- Simple wait conditions (element appears/disappears)
- Willing to test thoroughly first
- Performance optimization needed

## Limitations

⚠️ **Low Test Coverage**

- `ui.wait` and `ui.waitAny` commands are NOT tested yet
- Manual polling with `ui.inspect` is the recommended approach
- No automatic detection of loading states - must specify what to wait for
- Built-in commands may have undiscovered edge cases

## Related Skills

- **ios-alert-handling** - Wait for alerts to appear
- **ios-navigation** - Wait for screen transitions
- **ios-list-interaction** - Wait for list data to load

## Production Readiness

⚠️ **Use with Caution**

Manual polling with `ui.inspect` is tested and safe. Built-in `ui.wait` and `ui.waitAny` commands require comprehensive testing before production use. Recommended to implement custom wait logic using `ui.inspect` polling pattern until built-in commands are fully validated.
