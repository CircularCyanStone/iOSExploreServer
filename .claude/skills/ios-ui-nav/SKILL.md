---
name: ios-navigation
description: |
  iOS App automation for screen navigation and traversal.
  
  Use this skill when the user needs to navigate between screens, go back to previous
  screens, tap navigation bar buttons, or traverse the iOS app's screen hierarchy.
  
  Must explicitly mention iOS, iPhone, iPad, or mobile app navigation to trigger.
  
  Based on iOSDriver MCP Server with 100% command coverage and full navigation testing.
---

# iOS Navigation & Screen Traversal

## Purpose

Navigate through iOS app screens, handle navigation bars, tap navigation buttons, go back to previous screens, and verify navigation state.

## When to Use

Use this skill when you need to:
- Navigate to different screens by tapping buttons, cells, or links
- Go back to the previous screen using back button
- Tap navigation bar buttons (left/right buttons)
- Detect current screen by navigation bar title
- Track navigation history and paths
- Verify expected screen was reached after navigation
- Take screenshots before/after navigation for verification

## Prerequisites

- **iOSDriver MCP Server** connected and active
- **iOS App** running on simulator or physical device
- **Port 38321** accessible
- App must have navigation structure (UINavigationController)

## Commands Used

| Command | Purpose | Performance |
|---------|---------|-------------|
| `ui.inspect` | Get navigation bar state and current screen | 100-200ms |
| `ui_tap_and_inspect` | Tap navigation elements and verify state | ~50ms + wait + inspect |
| `ui.navigation.back` | Go back to previous screen | 50-100ms |
| `ui.navigation.tapBarButton` | Tap navigation bar buttons (left/right) | 304-305ms |
| `ui.screenshot` | Capture screen state for verification | 200-500ms |

> **MCP tool availability:** All commands have native `mcp__iOSDriver__*` tools
> (`ui.inspect`, `ui_tap_and_inspect`, `ui.navigation.back`, `ui.navigation.tapBarButton`, `ui.screenshot`).
> If issues occur, use fallback: `call_action(action:"ui.tap", data:{...})`.
> 
> **Performance tip:** Use `ui_tap_and_inspect` for navigation taps to combine the tap
> and state verification in one call, reducing agent reasoning time by 2-3 seconds.

**Screen transition time:** 200-500ms (including animation)

## Capabilities

### 1. Screen Navigation

**Tap to Navigate:**
Use `ui_tap_and_inspect` to tap navigation elements and verify the resulting state:
- Navigation list cells
- Action buttons
- Tab bar items
- Links and text buttons

This combines the tap action with automatic state verification, reducing the need for
separate inspect calls and saving 2-3 seconds of agent reasoning time.

**Navigation Detection:**
```bash
# Get current navigation bar state
curl -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}' | jq '.data.navigationBar'
```

Response:
```json
{
  "navigationBar": {
    "title": "Settings",
    "backAvailable": true,
    "backButtonTitle": "Home",
    "leftButtons": [
      {
        "index": 0,
        "title": "编辑",
        "accessibilityIdentifier": "nav.left.edit",
        "placement": "left"
      }
    ],
    "rightButtons": [
      {
        "index": 0,
        "title": "分享",
        "accessibilityIdentifier": "nav.right.share",
        "placement": "right"
      }
    ]
  }
}
```

### 2. Back Navigation

**Using ui.navigation.back (no args = auto strategy):**
```bash
curl -X POST http://localhost:38321/ -d '{"action":"ui.navigation.back"}'
```

**Dismiss a modal explicitly:**
```bash
curl -X POST http://localhost:38321/ -d '{
  "action": "ui.navigation.back",
  "data": { "strategy": "dismiss" }
}'
```

Response:
```json
{
  "code": "ok",
  "data": {
    "performed": true,
    "strategy": "dismiss",
    "topBefore": "ModalViewController",
    "topAfter": "ListViewController"
  }
}
```

`strategy` in the response is the **strategy that actually took effect** (under `auto`,
it reflects whether dismiss or navigationController was used).

**Verify Back Button Available:**
```bash
curl -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}' | jq '.data.navigationBar.backAvailable'
# Returns: true or false
```

### 3. Navigation Bar Button Tapping

**Tap Left/Right Buttons:**

By index:
```bash
curl -X POST http://localhost:38321/ -d '{
  "action": "ui.navigation.tapBarButton",
  "data": {
    "placement": "left",
    "index": 0
  }
}'
```

By accessibility identifier:
```bash
curl -X POST http://localhost:38321/ -d '{
  "action": "ui.navigation.tapBarButton",
  "data": {
    "placement": "right",
    "accessibilityIdentifier": "nav.right.share"
  }
}'
```

With title verification:
```bash
curl -X POST http://localhost:38321/ -d '{
  "action": "ui.navigation.tapBarButton",
  "data": {
    "placement": "left",
    "index": 0,
    "title": "编辑"
  }
}'
```

Response:
```json
{
  "code": "ok",
  "data": {
    "performed": true,
    "placement": "left",
    "index": 0,
    "title": "编辑",
    "accessibilityIdentifier": "nav.left.edit",
    "topBefore": "SettingsViewController",
    "topAfter": "SettingsViewController"
  }
}
```

### 4. Path Tracking

Track navigation history to enable intelligent back navigation:

```bash
#!/bin/bash
NAVIGATION_STACK=()

# Function to track navigation
navigate_to() {
  local target=$1
  local current_screen=$(curl -s -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}' | jq -r '.data.navigationBar.title')
  NAVIGATION_STACK+=("$current_screen")
  
  # Perform navigation (tap button/cell)
  # ... navigation code ...
  
  echo "Navigated from $current_screen to $target"
}

# Function to go back
go_back() {
  curl -X POST http://localhost:38321/ -d '{"action":"ui.navigation.back"}'
  local previous_screen=${NAVIGATION_STACK[-1]}
  unset 'NAVIGATION_STACK[-1]'
  echo "Went back to $previous_screen"
}
```

## Usage Examples

### Example 1: Navigate to Settings Screen

```bash
# Step 1: Get current state
INSPECT=$(curl -s -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}')
SNAPSHOT_ID=$(echo $INSPECT | jq -r '.data.viewSnapshotID')
CURRENT_TITLE=$(echo $INSPECT | jq -r '.data.navigationBar.title')

echo "Current screen: $CURRENT_TITLE"

# Step 2: Find Settings button/cell
SETTINGS_PATH=$(echo $INSPECT | jq -r '.data.targets[] | select(.text | contains("Settings")) | .path')

# Step 3: Tap to navigate
curl -X POST http://localhost:38321/ -d "{
  \"action\": \"ui.tap\",
  \"data\": {
    \"path\": \"$SETTINGS_PATH\",
    \"viewSnapshotID\": \"$SNAPSHOT_ID\"
  }
}"

# Step 4: Wait for transition
sleep 0.5

# Step 5: Verify navigation
NEW_TITLE=$(curl -s -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}' | jq -r '.data.navigationBar.title')
echo "Navigated to: $NEW_TITLE"

if [ "$NEW_TITLE" = "Settings" ]; then
  echo "✅ Navigation successful"
else
  echo "❌ Navigation failed: expected 'Settings', got '$NEW_TITLE'"
fi
```

### Example 2: Navigate Deep and Back

```bash
# Navigate: Home → Settings → Account → Privacy
echo "Starting from Home"

# Navigate to Settings
curl -X POST http://localhost:38321/ -d '{"action":"ui.tap","data":{...}}'
sleep 0.5
echo "Current: $(curl -s -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}' | jq -r '.data.navigationBar.title')"

# Navigate to Account
curl -X POST http://localhost:38321/ -d '{"action":"ui.tap","data":{...}}'
sleep 0.5
echo "Current: $(curl -s -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}' | jq -r '.data.navigationBar.title')"

# Navigate to Privacy
curl -X POST http://localhost:38321/ -d '{"action":"ui.tap","data":{...}}'
sleep 0.5
echo "Current: $(curl -s -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}' | jq -r '.data.navigationBar.title')"

# Go back: Privacy → Account → Settings → Home
for i in {1..3}; do
  curl -X POST http://localhost:38321/ -d '{"action":"ui.navigation.back"}'
  sleep 0.5
  echo "Went back to: $(curl -s -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}' | jq -r '.data.navigationBar.title')"
done
```

### Example 3: Tap Navigation Bar Edit Button

```bash
# Step 1: Check if edit button exists
INSPECT=$(curl -s -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}')
LEFT_BUTTONS=$(echo $INSPECT | jq '.data.navigationBar.leftButtons')

if [ "$(echo $LEFT_BUTTONS | jq 'length')" -gt 0 ]; then
  echo "Found left navigation buttons"
  
  # Step 2: Tap first left button (index 0)
  curl -X POST http://localhost:38321/ -d '{
    "action": "ui.navigation.tapBarButton",
    "data": {
      "placement": "left",
      "index": 0
    }
  }'
  
  # Step 3: Verify action performed
  echo "Edit button tapped"
else
  echo "No left navigation buttons found"
fi
```

### Example 4: Screenshot Before/After Navigation

```bash
# Capture before navigation
BEFORE=$(curl -s -X POST http://localhost:38321/ -d '{"action":"ui.screenshot"}' | jq -r '.data.image')
echo $BEFORE | base64 -d > before_navigation.png

# Navigate
curl -X POST http://localhost:38321/ -d '{"action":"ui.tap","data":{...}}'
sleep 0.5

# Capture after navigation
AFTER=$(curl -s -X POST http://localhost:38321/ -d '{"action":"ui.screenshot"}' | jq -r '.data.image')
echo $AFTER | base64 -d > after_navigation.png

echo "Screenshots saved: before_navigation.png, after_navigation.png"
```

### Example 5: Smart Navigation with Verification

```bash
#!/bin/bash
navigate_and_verify() {
  local target_title=$1
  local tap_text=$2
  
  # Get current state
  INSPECT=$(curl -s -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}')
  SNAPSHOT_ID=$(echo $INSPECT | jq -r '.data.viewSnapshotID')
  
  # Find element by text
  TARGET_PATH=$(echo $INSPECT | jq -r ".data.targets[] | select(.text == \"$tap_text\") | .path")
  
  if [ -z "$TARGET_PATH" ]; then
    echo "❌ Element not found: $tap_text"
    return 1
  fi
  
  # Tap element
  curl -s -X POST http://localhost:38321/ -d "{
    \"action\": \"ui.tap\",
    \"data\": {
      \"path\": \"$TARGET_PATH\",
      \"viewSnapshotID\": \"$SNAPSHOT_ID\"
    }
  }" > /dev/null
  
  # Wait for transition
  sleep 0.5
  
  # Verify title
  ACTUAL_TITLE=$(curl -s -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}' | jq -r '.data.navigationBar.title')
  
  if [ "$ACTUAL_TITLE" = "$target_title" ]; then
    echo "✅ Successfully navigated to $target_title"
    return 0
  else
    echo "❌ Navigation failed: expected '$target_title', got '$ACTUAL_TITLE'"
    return 1
  fi
}

# Usage
navigate_and_verify "Settings" "Settings"
navigate_and_verify "Account" "Account"
```

### Example 6: Modal View Dismissal

```bash
#!/bin/bash
# Dismiss modal view by tapping close button

# Check if modal is present (no back button, but has close/cancel button)
INSPECT=$(curl -s -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}')
BACK_AVAILABLE=$(echo $INSPECT | jq -r '.data.navigationBar.backAvailable')
LEFT_BUTTONS=$(echo $INSPECT | jq '.data.navigationBar.leftButtons')

if [ "$BACK_AVAILABLE" = "false" ] && [ "$(echo $LEFT_BUTTONS | jq 'length')" -gt 0 ]; then
  echo "Modal view detected (no back button, has left button)"
  
  # Look for Cancel/Close button
  CANCEL_BUTTON=$(echo $LEFT_BUTTONS | jq -r '.[0] | select(.title == "取消" or .title == "Cancel" or .title == "Close")')
  
  if [ -n "$CANCEL_BUTTON" ]; then
    # Tap cancel/close button to dismiss modal
    curl -s -X POST http://localhost:38321/ -d '{
      "action": "ui.navigation.tapBarButton",
      "data": {
        "placement": "left",
        "index": 0
      }
    }' > /dev/null
    
    sleep 0.5
    echo "✅ Modal dismissed"
  else
    echo "⚠️ Modal detected but no cancel/close button found"
  fi
else
  echo "Not a modal view"
fi
```

### Example 7: TabBar Navigation Pattern

```bash
#!/bin/bash
# Navigate using tab bar (not navigation stack)

switch_to_tab() {
  local tab_name=$1
  
  # Find tab bar item
  INSPECT=$(curl -s -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}')
  SNAPSHOT_ID=$(echo $INSPECT | jq -r '.data.viewSnapshotID')
  
  # Look for tab with specific text
  TAB_PATH=$(echo $INSPECT | jq -r ".data.targets[] | select(.type == \"UITabBarButton\" and (.text == \"$tab_name\" or .accessibilityIdentifier | contains(\"$tab_name\"))) | .path")
  
  if [ -n "$TAB_PATH" ]; then
    curl -s -X POST http://localhost:38321/ -d "{
      \"action\": \"ui.tap\",
      \"data\": {
        \"path\": \"$TAB_PATH\",
        \"viewSnapshotID\": \"$SNAPSHOT_ID\"
      }
    }" > /dev/null
    
    sleep 0.5
    
    # Verify tab switch
    NEW_TITLE=$(curl -s -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}' | jq -r '.data.navigationBar.title')
    echo "✅ Switched to tab: $tab_name (screen: $NEW_TITLE)"
  else
    echo "❌ Tab not found: $tab_name"
  fi
}

# Usage: switch between tabs
switch_to_tab "Home"
switch_to_tab "Settings"
switch_to_tab "Profile"
```

## Parameters Reference

### ui.navigation.back

All parameters optional — calling with no `data` uses the `auto` strategy.

```json
{
  "strategy": "auto",       // Optional: "auto" (default) / "navigationController" / "dismiss"
  "animated": false,        // Optional: default false (disabled to reduce transition wait)
  "waitAfterMs": 300        // Optional: 0...3000, default 300 — settle wait before reading UI
}
```

- `auto` (default): try `dismiss` first, then `navigationController` pop.
- `navigationController`: only `popViewController` (fails if no nav stack).
- `dismiss`: only `dismiss` (fails if nothing is presented) — **this IS how you dismiss a modal**.

**Response:**
```json
{
  "code": "ok",
  "data": {
    "performed": true,
    "strategy": "navigationController",
    "topBefore": "DetailViewController",
    "topAfter": "ListViewController"
  }
}
```

> `strategy` in the response is the strategy that actually took effect (under `auto`,
> reflects dismiss vs navigationController). Source: `Sources/iOSExploreUIKit/Commands/
> Navigation/UINavigationBackModels.swift`. (The old `mode` field never existed.)

### ui.navigation.tapBarButton

**By Index:**
```json
{
  "placement": "left",  // Required: "left" or "right"
  "index": 0            // Required: 0-based button index
}
```

**By Accessibility Identifier:**
```json
{
  "placement": "right",
  "accessibilityIdentifier": "nav.right.share"
}
```

**With Title Verification:**
```json
{
  "placement": "left",
  "index": 0,
  "title": "编辑"  // Optional: verify button title matches
}
```

**Response:**
```json
{
  "code": "ok",
  "data": {
    "performed": true,
    "placement": "right",
    "index": 0,
    "title": "分享",
    "accessibilityIdentifier": "nav.right.share",
    "topBefore": "NavigationTestViewController",
    "topAfter": "NavigationTestViewController"
  }
}
```

## Error Handling

### Common Errors

#### 1. `back_button_unavailable`
**Cause:** No back button available (at root screen)

**Solution:**
- Check `navigationBar.backAvailable` before calling `ui.navigation.back`
- Verify not at root of navigation stack
- Use `ui.inspect` to confirm navigation state

**Example:**
```bash
BACK_AVAILABLE=$(curl -s -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}' | jq -r '.data.navigationBar.backAvailable')

if [ "$BACK_AVAILABLE" = "true" ]; then
  curl -X POST http://localhost:38321/ -d '{"action":"ui.navigation.back"}'
else
  echo "Cannot go back - at root screen"
fi
```

#### 2. `target_not_found`
**Cause:** Navigation element not found (wrong path or off-screen)

**Solution:**
- Re-inspect to get fresh snapshot and paths
- Use `ui.scrollToElement` if element is off-screen
- Verify element exists on current screen

#### 3. `invalid_data` (navigation bar button)
**Cause:** Invalid placement, index out of range, or button not found

**Solution:**
- Verify `placement` is "left" or "right"
- Check button count in `navigationBar.leftButtons` or `rightButtons`
- Use valid index (0 to button count - 1)
- Verify accessibility identifier exists

**Example:**
```bash
# Check button count first
LEFT_COUNT=$(curl -s -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}' | jq '.data.navigationBar.leftButtons | length')
echo "Left buttons available: $LEFT_COUNT"

if [ "$LEFT_COUNT" -gt 0 ]; then
  # Safe to tap index 0
  curl -X POST http://localhost:38321/ -d '{"action":"ui.navigation.tapBarButton","data":{"placement":"left","index":0}}'
fi
```

#### 4. Navigation Not Completing
**Cause:** Insufficient wait time after navigation

**Solution:**
- Always wait 500ms after navigation for animation
- Poll `ui.inspect` to detect when title changes
- Use longer wait for complex screens (up to 1 second)

**Example:**
```bash
# Tap navigation element
curl -X POST http://localhost:38321/ -d '{"action":"ui.tap","data":{...}}'

# Poll for title change (up to 2 seconds)
for i in {1..10}; do
  TITLE=$(curl -s -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}' | jq -r '.data.navigationBar.title')
  if [ "$TITLE" = "Settings" ]; then
    echo "Navigation complete after $((i * 200))ms"
    break
  fi
  sleep 0.2
done
```

## Performance Characteristics

Based on automated tests:

| Operation | Duration | Notes |
|-----------|----------|-------|
| **ui.tap (navigation)** | 50-100ms | Fast tap action |
| **Screen transition** | 200-500ms | iOS animation time |
| **ui.navigation.back** | 50-100ms | Fast back action |
| **ui.navigation.tapBarButton** | 304-305ms | Includes button tap + verification |
| **Total navigation** | 300-600ms | Tap + animation |

**Recommended wait time:** 500ms after any navigation action

## Best Practices

### 1. Always Wait After Navigation

```bash
# Good: Wait for animation to complete
curl -X POST http://localhost:38321/ -d '{"action":"ui.tap","data":{...}}'
sleep 0.5  # Wait for screen transition
curl -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}'

# Bad: No wait - may get stale state
curl -X POST http://localhost:38321/ -d '{"action":"ui.tap","data":{...}}'
curl -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}'  # Too soon!
```

### 2. Verify Navigation Success

```bash
# Good: Verify expected screen reached
EXPECTED="Settings"
ACTUAL=$(curl -s -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}' | jq -r '.data.navigationBar.title')

if [ "$ACTUAL" = "$EXPECTED" ]; then
  echo "✅ On correct screen"
else
  echo "❌ Navigation failed: expected $EXPECTED, got $ACTUAL"
fi
```

### 3. Check Back Button Before Going Back

```bash
# Good: Check before going back
if [ "$(curl -s -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}' | jq -r '.data.navigationBar.backAvailable')" = "true" ]; then
  curl -X POST http://localhost:38321/ -d '{"action":"ui.navigation.back"}'
else
  echo "Cannot go back - at root"
fi
```

### 4. Use Screenshots for Debugging

```bash
# Capture evidence of navigation flow
curl -X POST http://localhost:38321/ -d '{"action":"ui.screenshot"}' | jq -r '.data.image' | base64 -d > step1.png
curl -X POST http://localhost:38321/ -d '{"action":"ui.tap","data":{...}}'
sleep 0.5
curl -X POST http://localhost:38321/ -d '{"action":"ui.screenshot"}' | jq -r '.data.image' | base64 -d > step2.png
```

### 5. Track Navigation Depth

```bash
DEPTH=0

navigate_forward() {
  curl -X POST http://localhost:38321/ -d '{"action":"ui.tap","data":{...}}'
  sleep 0.5
  ((DEPTH++))
  echo "Navigation depth: $DEPTH"
}

navigate_back() {
  curl -X POST http://localhost:38321/ -d '{"action":"ui.navigation.back"}'
  sleep 0.5
  ((DEPTH--))
  echo "Navigation depth: $DEPTH"
}
```

## Limitations

### Known Limitations

1. **Modal Presentations:** `ui.navigation.back` **can** dismiss modals — pass
   `"strategy": "dismiss"`. The default `auto` strategy also tries dismiss before
   navigation pop, so it handles both pushed and presented controllers. (Earlier docs
   claiming "only works for push navigation, not modal dismissal" were wrong.)

2. **Tab Bar Navigation:** Changing tabs requires `ui.tap` on tab bar items, not navigation commands.

3. **Custom Navigation:** Apps with custom navigation (not UINavigationController) may not populate `navigationBar` data correctly.

4. **Animation Timing:** Must wait for navigation animations (200-500ms). Cannot be skipped or detected automatically.

5. **Split View Controllers:** iPad split views may have complex navigation hierarchies requiring special handling.

## Related Skills

- **ios-list-interaction** - Navigate by tapping list items
- **ios-screenshot** - Capture navigation states
- **ios-alert-handling** - Handle alerts during navigation
- **ios-form-filling** - Fill forms after navigation

## Test Coverage

**Commands Tested:**
- ✅ ui.navigation.back (core functionality)
- ✅ ui.navigation.tapBarButton (4 scenarios, 100% pass rate)
- ✅ ui.tap for navigation (implicit in all navigation tests)

**Test Report:** `docs/final-two-commands-test-report.json`（路径相对于**仓库根**，非本 skill 目录）

**Tested Scenarios:**
- ✅ Tap left navigation button by index
- ✅ Tap right navigation button by index
- ✅ Tap left button with title verification
- ✅ Tap right button by accessibilityIdentifier
- ✅ Error: Non-existent button (index 99)
- ✅ Back navigation (tested in integration scenarios)

## Production Readiness

✅ **Production Ready**

All navigation commands are fully tested with 100% success rate. Navigation bar button tapping verified across multiple selection methods (index, identifier, title verification). Safe for production use in automated testing and app navigation workflows.

## controller 层级检查(`ui.controllers`)

> **⚠️ EXPERIMENTAL STATUS**
> The `ui.controllers` command is NOT fully tested. This section is migrated verbatim
> from the deleted `ios-controller-navigation` skill. For practical navigation needs,
> prefer the navigation commands above (`ui.navigation.back`, `ui.navigation.tapBarButton`,
> `ui.inspect` for navigation bar state). Only use `ui.controllers` when you specifically
> need view controller hierarchy inspection and are willing to test thoroughly.

### Purpose

Inspect and understand iOS app's view controller hierarchy, including navigation controllers, tab bar controllers, and modal presentations.

### When to Use

Use this section when you need to:
- Understand app's controller structure
- Identify current view controller
- Debug navigation issues
- Find controller by class name
- Inspect navigation stack depth
- Detect modal presentations

### Command

| Command | Purpose | Status |
|---------|---------|--------|
| `ui.controllers` | Get controller hierarchy tree | ⚠️ Not fully tested |
| `ui.inspect` | Get navigation bar info (indirect) | ✅ Tested |

**Get Controller Tree (NOT FULLY TESTED):**
```bash
curl -X POST http://localhost:38321/ -d '{"action":"ui.controllers"}'
```

Expected response format:
```json
{
  "code": "ok",
  "data": {
    "root": "UINavigationController",
    "topmost": "DetailViewController",
    "stack": [
      "ListViewController",
      "DetailViewController"
    ]
  }
}
```

### Parameters

```json
{
  "maxDepth": 0    // Optional: maximum recursion depth; 0 means root node only
}
```

### Indirect Controller Detection

**Via Navigation Bar:**
```bash
curl -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}' | jq '.data.navigationBar'
```

Navigation bar title often corresponds to current view controller.

**Detect Current Screen:**
```bash
# Get navigation bar title as proxy for controller
TITLE=$(curl -s -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}' | jq -r '.data.navigationBar.title')
echo "Current screen: $TITLE"
```

**Check Navigation Depth:**
```bash
# Back button available = not at root
BACK_AVAILABLE=$(curl -s -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}' | jq -r '.data.navigationBar.backAvailable')

if [ "$BACK_AVAILABLE" = "true" ]; then
  echo "In navigation stack (depth > 1)"
else
  echo "At root controller"
fi
```

### Limitations

⚠️ **Very Low Test Coverage**

- `ui.controllers` command is NOT fully tested
- No direct controller hierarchy inspection available yet
- Must rely on navigation bar state for indirect detection
- Cannot programmatically identify controller class names

### Workaround

Use `ui.inspect` to infer controller state:
- Navigation bar title → current screen
- Back button availability → navigation depth
- Alert presence → modal state
- Tab bar → tab-based navigation

> Source: migrated from `.claude/skills/ios-controller-navigation/SKILL.md` (deleted in this commit).
> `ui.controllers` MCP tool: `mcp__iOSDriver__ui_controllers` (optional `maxDepth` parameter).
