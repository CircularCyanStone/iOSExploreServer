---
name: ios-gestures
description: |
  iOS App automation for advanced gesture interactions.
  
  Use this skill when the user needs to perform swipe gestures, long press actions,
  or drag operations in iOS applications beyond simple taps.
  
  Must explicitly mention iOS, iPhone, iPad, swipe, long press, or gestures to trigger.
  
  Based on iOSDriver MCP Server with swipe and longPress fully tested.
---

# iOS Advanced Gestures

## Purpose

Perform advanced touch gestures including swipes (directional scrolling), long press (context menus, drag initiation), and drag operations for iOS app automation.

## When to Use

Use this skill when you need to:
- Swipe within scroll views or list cells
- Perform directional swipes (up, down, left, right)
- Long press to trigger context menus
- Long press to initiate drag-and-drop
- Swipe to reveal cell actions (delete, edit)
- Custom gesture interactions

## Prerequisites

- **iOSDriver MCP Server** connected and active
- **iOS App** running with gesture-enabled UI elements
- **Port 38321** accessible

## Commands Used

| Command | Purpose | Performance |
|---------|---------|-------------|
| `ui.swipe` | Directional swipe within element | 300-500ms |
| `ui.longPress` | Long press on element | Depends on duration |
| `ui.drag` | Drag element in direction | Not fully tested |

## Capabilities

### 1. Swipe Gestures

**Swipe Within Scroll View:**
```bash
curl -X POST http://localhost:38321/ -d '{
  "action": "ui.swipe",
  "data": {
    "withinElementRef": "e7",
    "direction": "up",
    "distance": 0.8
  }
}'
```

**Swipe Directions:**
- `up` - Scroll content down (finger moves up)
- `down` - Scroll content up (finger moves down)
- `left` - Scroll content right (finger moves left)
- `right` - Scroll content left (finger moves right)

**Distance:** 0.0 to 1.0 (normalized fraction of container size)

### 2. Long Press

**Long Press on Element:**
```bash
curl -X POST http://localhost:38321/ -d '{
  "action": "ui.longPress",
  "data": {
    "elementRef": "e5",
    "duration": 1000
  }
}'
```

**Duration:** milliseconds (typical: 500-2000ms)

### 3. Cell Swipe Actions

**Swipe Left to Reveal Actions:**
```bash
curl -X POST http://localhost:38321/ -d '{
  "action": "ui.swipe",
  "data": {
    "withinElementRef": "cell_ref",
    "direction": "left",
    "distance": 0.6
  }
}'
```

## Usage Examples

### Example 1: Scroll Down in List

```bash
# Get element reference for scroll container
INSPECT=$(curl -s -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}')
SCROLL_REF=$(echo $INSPECT | jq -r '.data.targets[] | select(.type == "UICollectionView") | .elementRef')

# Swipe up to scroll down
curl -X POST http://localhost:38321/ -d "{
  \"action\": \"ui.swipe\",
  \"data\": {
    \"withinElementRef\": \"$SCROLL_REF\",
    \"direction\": \"up\",
    \"distance\": 0.8
  }
}"

sleep 0.3  # Wait for scroll to settle
```

### Example 2: Long Press for Context Menu

```bash
# Long press on item to show context menu
curl -X POST http://localhost:38321/ -d '{
  "action": "ui.longPress",
  "data": {
    "elementRef": "e10",
    "duration": 1000
  }
}'

sleep 0.5  # Wait for menu to appear

# Now inspect to see menu options
curl -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}'
```

### Example 3: Reveal Table Cell Swipe Actions

```bash
# Swipe left on cell to reveal delete/edit
INSPECT=$(curl -s -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}')
CELL_REF=$(echo $INSPECT | jq -r '.data.targets[] | select(.text | contains("John Doe")) | .elementRef')

curl -X POST http://localhost:38321/ -d "{
  \"action\": \"ui.swipe\",
  \"data\": {
    \"withinElementRef\": \"$CELL_REF\",
    \"direction\": \"left\",
    \"distance\": 0.6
  }
}"

sleep 0.3

# Inspect to see revealed actions (Delete, Edit)
curl -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}'
```

## Parameters Reference

### ui.swipe

```json
{
  "withinElementRef": "e7",     // Required: element reference from ui.inspect
  "direction": "up",             // Required: "up", "down", "left", "right"
  "distance": 0.8,               // Optional: 0.0-1.0 (default 0.8)
  "duration": 0.3,               // Optional: seconds (default varies)
  "preDelay": 0.0,               // Optional: seconds before swipe
  "postDelay": 0.0               // Optional: seconds after swipe
}
```

### ui.longPress

```json
{
  "elementRef": "e5",            // Required: element reference
  "duration": 1000               // Required: milliseconds (500-2000 typical)
}
```

## Best Practices

1. **Wait After Swipe:** Always wait 300ms for scroll/animation to settle
2. **Use Distance Carefully:** 0.8 is good default, adjust for precision
3. **Long Press Duration:** 1000ms (1 second) works for most context menus
4. **Get Fresh References:** Always call ui.inspect first to get current elementRef

## Limitations

- **ui.drag** not fully tested yet (use with caution)
- Swipe only works within identified scroll containers
- Long press timing may vary by app (test different durations)

## Related Skills

- **ios-list-interaction** - Use swipe for scrolling lists
- **ios-form-filling** - Combine gestures with form input
- **ios-navigation** - Swipe gestures for page navigation

### Example 4: Multi-Direction Scrolling

```bash
#!/bin/bash
# Scroll in multiple directions to explore content

INSPECT=$(curl -s -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}')
SCROLL_REF=$(echo $INSPECT | jq -r '.data.targets[] | select(.type == "UICollectionView") | .elementRef')

# Scroll down
echo "Scrolling down..."
curl -s -X POST http://localhost:38321/ -d "{
  \"action\": \"ui.swipe\",
  \"data\": {
    \"withinElementRef\": \"$SCROLL_REF\",
    \"direction\": \"up\",
    \"distance\": 0.8
  }
}" > /dev/null
sleep 0.3

# Scroll right
echo "Scrolling right..."
curl -s -X POST http://localhost:38321/ -d "{
  \"action\": \"ui.swipe\",
  \"data\": {
    \"withinElementRef\": \"$SCROLL_REF\",
    \"direction\": \"left\",
    \"distance\": 0.5
  }
}" > /dev/null
sleep 0.3

# Scroll back up
echo "Scrolling back up..."
curl -s -X POST http://localhost:38321/ -d "{
  \"action\": \"ui.swipe\",
  \"data\": {
    \"withinElementRef\": \"$SCROLL_REF\",
    \"direction\": \"down\",
    \"distance\": 0.8
  }
}" > /dev/null

echo "✅ Multi-direction scroll complete"
```

### Example 5: Gesture Timing for Animations

```bash
# Wait for animations between gestures

# First swipe
curl -X POST http://localhost:38321/ -d '{
  "action": "ui.swipe",
  "data": {
    "withinElementRef": "e7",
    "direction": "up",
    "distance": 0.8,
    "duration": 0.4
  }
}'

# Wait for scroll animation to complete
sleep 0.4

# Second swipe (smoother experience)
curl -X POST http://localhost:38321/ -d '{
  "action": "ui.swipe",
  "data": {
    "withinElementRef": "e7",
    "direction": "up",
    "distance": 0.8,
    "duration": 0.4
  }
}'
```

### Example 6: Combined Gesture Workflow

```bash
#!/bin/bash
# Long press to reveal menu, then swipe to dismiss

# Long press on item
echo "Long pressing item..."
curl -s -X POST http://localhost:38321/ -d '{
  "action": "ui.longPress",
  "data": {
    "elementRef": "e10",
    "duration": 1000
  }
}' > /dev/null

sleep 0.5

# Inspect menu
INSPECT=$(curl -s -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}')
MENU_ITEMS=$(echo $INSPECT | jq '.data.targets[] | select(.text | contains("Copy") or contains("Delete"))')
echo "Menu appeared: $MENU_ITEMS"

# Swipe down to dismiss (if context menu supports swipe dismiss)
MENU_REF=$(echo $INSPECT | jq -r '.data.targets[] | select(.type == "UIView") | .elementRef' | head -1)
if [ -n "$MENU_REF" ]; then
  curl -s -X POST http://localhost:38321/ -d "{
    \"action\": \"ui.swipe\",
    \"data\": {
      \"withinElementRef\": \"$MENU_REF\",
      \"direction\": \"down\",
      \"distance\": 0.5
    }
  }" > /dev/null
  echo "✅ Menu dismissed"
fi
```

## Parameters Reference

### ui.swipe

```json
{
  "withinElementRef": "e7",     // Required: element reference from ui.inspect
  "direction": "up",             // Required: "up", "down", "left", "right"
  "distance": 0.8,               // Optional: 0.0-1.0 (default 0.8)
  "duration": 0.3,               // Optional: seconds (default varies)
  "preDelay": 0.0,               // Optional: seconds before swipe
  "postDelay": 0.0               // Optional: seconds after swipe
}
```

### ui.longPress

```json
{
  "elementRef": "e5",            // Required: element reference
  "duration": 1000               // Required: milliseconds (500-2000 typical)
}
```

## Error Handling

### Common Errors

#### 1. `invalid_data` - Missing or Invalid elementRef
**Cause:** elementRef not provided or invalid

**Solution:**
- Always call `ui.inspect` first to get current element references
- Use the exact `elementRef` string from the response (e.g., "e7", "e10")
- Element references change after UI updates - re-inspect after navigation or state changes

**Example:**
```bash
# Get fresh element reference
INSPECT=$(curl -s -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}')
ELEMENT_REF=$(echo $INSPECT | jq -r '.data.targets[] | select(.type == "UICollectionView") | .elementRef')

# Use fresh reference immediately
curl -X POST http://localhost:38321/ -d "{
  \"action\": \"ui.swipe\",
  \"data\": {
    \"withinElementRef\": \"$ELEMENT_REF\",
    \"direction\": \"up\",
    \"distance\": 0.8
  }
}"
```

#### 2. `target_not_found` - Element No Longer Exists
**Cause:** Element was removed from hierarchy or off-screen

**Solution:**
- Re-inspect after navigation or UI changes
- Verify element still exists before performing gesture
- Wait for animations to complete before gestures

**Example:**
```bash
# Check element exists before gesture
INSPECT=$(curl -s -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}')
ELEMENT_EXISTS=$(echo $INSPECT | jq '.data.targets[] | select(.elementRef == "e7")')

if [ -n "$ELEMENT_EXISTS" ]; then
  curl -X POST http://localhost:38321/ -d '{"action":"ui.swipe","data":{...}}'
else
  echo "Element not found - re-inspecting"
  # Re-inspect and get new reference
fi
```

#### 3. Swipe Not Scrolling Content
**Cause:** Wrong direction or element not scrollable

**Solution:**
- Verify element is a scroll container (UIScrollView, UITableView, UICollectionView)
- Check `direction`: "up" scrolls content down (finger moves up), "down" scrolls content up
- Adjust `distance` (try 0.5 for shorter scroll, 0.9 for longer scroll)
- Ensure content is scrollable (has content beyond visible area)

**Direction mapping:**
- `"up"` → Scroll content downward (reveal content below)
- `"down"` → Scroll content upward (reveal content above)
- `"left"` → Scroll content rightward (horizontal scroll)
- `"right"` → Scroll content leftward (horizontal scroll)

#### 4. Long Press Not Triggering Menu
**Cause:** Duration too short or element doesn't support long press

**Solution:**
- Increase duration to 1500ms or 2000ms (some apps require longer press)
- Verify element supports long press interaction
- Wait 500ms after long press before inspecting menu
- Check if menu appeared via `ui.inspect` to see new elements

**Example:**
```bash
# Try longer duration if 1000ms doesn't work
curl -X POST http://localhost:38321/ -d '{
  "action": "ui.longPress",
  "data": {
    "elementRef": "e10",
    "duration": 1500
  }
}'

sleep 0.5

# Verify menu appeared
INSPECT=$(curl -s -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}')
MENU=$(echo $INSPECT | jq '.data.targets[] | select(.text | contains("Copy") or contains("Delete"))')

if [ -n "$MENU" ]; then
  echo "✅ Menu appeared"
else
  echo "❌ Menu did not appear - try longer duration or different element"
fi
```

#### 5. Gestures Interfering with Each Other
**Cause:** Insufficient delay between gestures

**Solution:**
- Always wait 300-500ms between gestures for animations to complete
- Use `preDelay` and `postDelay` parameters for automatic timing
- For critical timing, wait for specific UI state via polling `ui.inspect`

**Example:**
```bash
# Good: Proper delays
curl -X POST http://localhost:38321/ -d '{"action":"ui.swipe","data":{...,"postDelay":0.3}}'
# Gesture completes + 300ms delay
curl -X POST http://localhost:38321/ -d '{"action":"ui.longPress","data":{...}}'

# Bad: No delay - may interfere
curl -X POST http://localhost:38321/ -d '{"action":"ui.swipe","data":{...}}'
curl -X POST http://localhost:38321/ -d '{"action":"ui.longPress","data":{...}}'  # Too soon!
```

## Performance Characteristics

Based on automated testing:

| Operation | Duration | Notes |
|-----------|----------|-------|
| **ui.swipe** | 300-500ms | Includes animation time |
| **ui.longPress** | Duration + 50ms | Depends on specified duration |
| **Element lookup** | 100-200ms | Via ui.inspect |
| **Animation settle** | 300-500ms | Wait time after gesture |

**Recommended timing:**
- Wait 300ms after swipe for scroll to settle
- Wait 500ms after long press for menu to appear
- Re-inspect after any gesture that changes UI

## Gesture Timing Guidelines

### Animation Coordination

iOS gestures trigger animations that must complete before the next action:

**Scroll Animation:** 300-400ms typical
```bash
curl -X POST http://localhost:38321/ -d '{"action":"ui.swipe","data":{...}}'
sleep 0.3  # Wait for scroll animation
```

**Context Menu Animation:** 400-600ms typical
```bash
curl -X POST http://localhost:38321/ -d '{"action":"ui.longPress","data":{...}}'
sleep 0.5  # Wait for menu to fully appear
```

**Cell Reveal Animation:** 200-300ms typical
```bash
# Swipe to reveal delete button
curl -X POST http://localhost:38321/ -d '{"action":"ui.swipe","data":{...,"direction":"left"}}'
sleep 0.3  # Wait for actions to reveal
```

### Polling for State Changes

For critical operations, poll `ui.inspect` instead of fixed delays:

```bash
# Wait for element to appear after gesture
for i in {1..10}; do
  INSPECT=$(curl -s -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}')
  TARGET=$(echo $INSPECT | jq '.data.targets[] | select(.text == "Delete")')
  
  if [ -n "$TARGET" ]; then
    echo "✅ Element appeared after $((i * 100))ms"
    break
  fi
  
  sleep 0.1
done
```

## Best Practices

1. **Wait After Swipe:** Always wait 300ms for scroll/animation to settle
2. **Use Distance Carefully:** 0.8 is good default, adjust for precision
3. **Long Press Duration:** 1000ms (1 second) works for most context menus
4. **Get Fresh References:** Always call ui.inspect first to get current elementRef
5. **Verify Gesture Success:** Inspect UI after gesture to confirm expected state change
6. **Handle Animation Timing:** Wait appropriate time for animations to complete
7. **Re-inspect After Gestures:** UI state changes, get fresh element references

## Limitations

- **ui.drag** not fully tested yet (use with caution)
- Swipe only works within identified scroll containers
- Long press timing may vary by app (test different durations)
- Cannot detect end of scroll programmatically
- No automatic wait for animations - must manually delay

## Related Skills

- **ios-list-interaction** - Use swipe for scrolling lists
- **ios-form-filling** - Combine gestures with form input
- **ios-navigation** - Swipe gestures for page navigation

## Production Readiness

✅ **Partially Production Ready**

`ui.swipe` and `ui.longPress` are tested and functional. `ui.drag` requires additional testing. Safe for production use for swipe and long press gestures with proper error handling.
