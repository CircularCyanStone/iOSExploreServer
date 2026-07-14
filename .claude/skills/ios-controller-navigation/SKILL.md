---
name: ios-controller-navigation
description: |
  iOS App automation for understanding view controller hierarchies.
  
  ⚠️ EXPERIMENTAL - ui.controllers command not fully tested.
  Consider using ios-navigation skill for most navigation use cases.
  
  Use this skill when the user needs to inspect the iOS app's view controller structure,
  understand navigation stacks, or identify current controller hierarchy.
  
  Must explicitly mention iOS, iPhone, iPad, view controllers, or controller hierarchy to trigger.
  
  Based on iOSDriver MCP Server. Note: ui.controllers command not fully tested yet.
---

# iOS Controller Hierarchy Navigation

> **⚠️ EXPERIMENTAL STATUS**  
> The `ui.controllers` command is NOT fully tested. This skill provides theoretical approaches  
> and workarounds using tested commands. For practical navigation needs, use the **ios-navigation** skill instead.  
> Only use this skill if you specifically need view controller hierarchy inspection and are willing to test thoroughly.

## Purpose

Inspect and understand iOS app's view controller hierarchy, including navigation controllers, tab bar controllers, and modal presentations.

## When to Use

Use this skill when you need to:
- Understand app's controller structure
- Identify current view controller
- Debug navigation issues
- Find controller by class name
- Inspect navigation stack depth
- Detect modal presentations

## Prerequisites

- **iOSDriver MCP Server** connected and active
- **iOS App** running with UIViewController hierarchy
- **Port 38321** accessible

## Commands Used

| Command | Purpose | Status |
|---------|---------|--------|
| `ui.controllers` | Get controller hierarchy tree | ⚠️ Not tested |
| `ui.inspect` | Get navigation bar info (indirect) | ✅ Tested |

## Capabilities

### 1. Controller Hierarchy

**Get Controller Tree (NOT TESTED):**
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

### 2. Indirect Controller Detection

**Via Navigation Bar:**
```bash
curl -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}' | jq '.data.navigationBar'
```

Navigation bar title often corresponds to current view controller.

## Usage Examples

### Example 1: Detect Current Screen

```bash
# Get navigation bar title as proxy for controller
TITLE=$(curl -s -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}' | jq -r '.data.navigationBar.title')
echo "Current screen: $TITLE"
```

### Example 2: Check Navigation Depth

```bash
# Back button available = not at root
BACK_AVAILABLE=$(curl -s -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}' | jq -r '.data.navigationBar.backAvailable')

if [ "$BACK_AVAILABLE" = "true" ]; then
  echo "In navigation stack (depth > 1)"
else
  echo "At root controller"
fi
```

## Limitations

⚠️ **Very Low Test Coverage**

- `ui.controllers` command is NOT tested
- No direct controller hierarchy inspection available yet
- Must rely on navigation bar state for indirect detection
- Cannot programmatically identify controller class names

## Workaround

Use `ui.inspect` to infer controller state:
- Navigation bar title → current screen
- Back button availability → navigation depth
- Alert presence → modal state
- Tab bar → tab-based navigation

## Related Skills

- **ios-navigation** - Navigate between controllers
- **ios-screenshot** - Visual verification of controller state

## Production Readiness

❌ **Not Production Ready**

Requires comprehensive testing of `ui.controllers` command before production use. Currently rely on `ios-navigation` skill for practical controller navigation needs.
