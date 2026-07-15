---
name: ios-list-interaction
description: |
  iOS App automation for list and collection view interaction.
  
  Use this skill when the user needs to find items in lists, scroll to reveal content,
  select list items, or interact with table views and collection views in iOS apps.
  
  Must explicitly mention iOS, iPhone, iPad, or list/table/collection interaction to trigger.
  
  Based on iOSDriver MCP Server with scrollToElement tested at 100% success rate.
---

# iOS List & Collection Interaction

## Purpose

Find, scroll to, and interact with items in iOS lists (UITableView) and collection views (UICollectionView), including scrolling to reveal off-screen content and selecting items.

## When to Use

Use this skill when you need to:
- Find specific items in long lists by text or identifier
- Scroll to make off-screen items visible
- Select list items or collection view cells
- Navigate to detail views by tapping cells
- Scroll to top or bottom of lists
- Handle swipe actions on table cells
- Interact with section headers or footers

## Prerequisites

- **iOSDriver MCP Server** connected and active
- **iOS App** running with UITableView or UICollectionView
- **Port 38321** accessible
- List or collection view must be on screen

## Commands Used

| Command | Purpose | Performance |
|---------|---------|-------------|
| `ui.inspect` | Find visible list items | 100-200ms |
| `ui.scrollToElement` | Scroll to make item visible | 2-7ms (instant) |
| `ui.tap` | Select list item | 50-100ms |
| `ui.swipe` | Manual scrolling or swipe actions | 300-500ms |

> **MCP tool availability:** All commands (`ui.inspect`, `ui.tap`, `ui.scrollToElement`, `ui.swipe`)
> have native `mcp__iOSDriver__*` tools. If you encounter issues, use the fallback:
> `call_action(action: "ui.tap", data: { "path": ..., "viewSnapshotID": ... })`.

**Find item with scrolling:** 1-5 seconds (depends on list size and item position)

## Capabilities

### 1. Item Discovery

**Find Visible Items:**
```bash
curl -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}' | jq '.data.targets[] | select(.text | contains("Item 5"))'
```

Returns item if visible, otherwise needs scrolling.

**Item Structure:**
```json
{
  "path": "root/0/5/0/0",
  "type": "UILabel",
  "text": "Item 5",
  "accessibilityIdentifier": "list.item.5",
  "availableActions": ["ui.tap"]
}
```

### 2. Scroll to Element

**Scroll by Text:**
```bash
curl -X POST http://localhost:38321/ -d '{
  "action": "ui.scrollToElement",
  "data": {
    "match": "text",
    "value": "Item 5"
  }
}'
```

**Scroll by Identifier:**
```bash
curl -X POST http://localhost:38321/ -d '{
  "action": "ui.scrollToElement",
  "data": {
    "match": "accessibilityIdentifier",
    "value": "contact-123"
  }
}'
```

**With Animation:**
```bash
curl -X POST http://localhost:38321/ -d '{
  "action": "ui.scrollToElement",
  "data": {
    "match": "text",
    "value": "Item 4",
    "animated": true
  }
}'
```

**Response:**
```json
{
  "code": "ok",
  "data": {
    "found": true,
    "match": "text",
    "targetPath": "root/0/5/0/0",
    "targetType": "UILabel",
    "container": "UICollectionView"
  }
}
```

### 3. Item Selection

**Tap List Item:**
```bash
# Step 1: Scroll to item (if needed)
curl -X POST http://localhost:38321/ -d '{
  "action": "ui.scrollToElement",
  "data": {
    "match": "text",
    "value": "John Doe"
  }
}'

# Step 2: Get fresh snapshot
INSPECT=$(curl -s -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}')
SNAPSHOT_ID=$(echo $INSPECT | jq -r '.data.viewSnapshotID')
ITEM_PATH=$(echo $INSPECT | jq -r '.data.targets[] | select(.text == "John Doe") | .path')

# Step 3: Tap item
curl -X POST http://localhost:38321/ -d "{
  \"action\": \"ui.tap\",
  \"data\": {
    \"path\": \"$ITEM_PATH\",
    \"viewSnapshotID\": \"$SNAPSHOT_ID\"
  }
}"

# Step 4: Wait for navigation
sleep 0.5
```

### 4. Manual Scrolling

**Swipe to Scroll:**

`ui.swipe` locates the scroll container with `accessibilityIdentifier` or `path`
(neither is XcodeBuildMCP's `withinElementRef` — iOSExploreServer has no such
parameter). If both are omitted it swipes the keyWindow's frontmost scrollView.

```bash
# Scroll down (swipe up) — locate scrollView by accessibilityIdentifier
curl -X POST http://localhost:38321/ -d '{
  "action": "ui.swipe",
  "data": {
    "accessibilityIdentifier": "contact_list_scrollview",
    "direction": "up",
    "distance": 0.8
  }
}'

# Scroll up (swipe down)
curl -X POST http://localhost:38321/ -d '{
  "action": "ui.swipe",
  "data": {
    "accessibilityIdentifier": "contact_list_scrollview",
    "direction": "down",
    "distance": 0.8
  }
}'
```

### 5. Cell Swipe Actions

**Trigger Cell Swipe Actions:**

Cell swipe actions use `cellAccessibilityIdentifier` (or `cellPath`) to locate the
cell, plus `direction` (`left` → trailing actions, `right` → leading actions).
`actionTitle` picks a specific action; omit it to trigger the first one.

```bash
# Swipe left on a cell to trigger its trailing swipe action (e.g. delete)
curl -X POST http://localhost:38321/ -d '{
  "action": "ui.swipe",
  "data": {
    "cellAccessibilityIdentifier": "contact.cell.42",
    "direction": "left",
    "actionTitle": "删除"
  }
}'
```

## Usage Examples

### Example 1: Find and Select Contact

```bash
#!/bin/bash
BASE_URL="http://localhost:38321/"

# Function to find and select item
select_list_item() {
  local item_text=$1
  
  echo "Searching for: $item_text"
  
  # Try scrolling to item
  SCROLL_RESULT=$(curl -s -X POST $BASE_URL -d "{
    \"action\": \"ui.scrollToElement\",
    \"data\": {
      \"match\": \"text\",
      \"value\": \"$item_text\"
    }
  }")
  
  FOUND=$(echo $SCROLL_RESULT | jq -r '.data.found')
  
  if [ "$FOUND" = "true" ]; then
    echo "✅ Found: $item_text"
    
    # Get fresh snapshot and tap
    INSPECT=$(curl -s -X POST $BASE_URL -d '{"action":"ui.inspect"}')
    SNAPSHOT_ID=$(echo $INSPECT | jq -r '.data.viewSnapshotID')
    ITEM_PATH=$(echo $INSPECT | jq -r ".data.targets[] | select(.text == \"$item_text\") | .path")
    
    if [ -n "$ITEM_PATH" ]; then
      curl -s -X POST $BASE_URL -d "{
        \"action\": \"ui.tap\",
        \"data\": {
          \"path\": \"$ITEM_PATH\",
          \"viewSnapshotID\": \"$SNAPSHOT_ID\"
        }
      }" > /dev/null
      
      sleep 0.5
      echo "✅ Tapped: $item_text"
    else
      echo "❌ Path not found after scroll"
      return 1
    fi
  else
    echo "❌ Not found: $item_text"
    return 1
  fi
}

# Usage
select_list_item "John Doe"
```

### Example 2: Scroll Through Long List

```bash
#!/bin/bash
# Find item in long list with manual scrolling fallback

find_item_with_manual_scroll() {
  local target=$1
  local max_scrolls=10
  
  for i in $(seq 1 $max_scrolls); do
    echo "Attempt $i of $max_scrolls"
    
    # Check if item is visible
    INSPECT=$(curl -s -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}')
    ITEM=$(echo $INSPECT | jq ".data.targets[] | select(.text | contains(\"$target\"))")
    
    if [ -n "$ITEM" ]; then
      echo "✅ Found after $i attempts"
      echo $ITEM | jq '.'
      return 0
    fi
    
    # Try ui.scrollToElement
    SCROLL_RESULT=$(curl -s -X POST http://localhost:38321/ -d "{
      \"action\": \"ui.scrollToElement\",
      \"data\": {
        \"match\": \"text\",
        \"value\": \"$target\"
      }
    }")
    
    if [ "$(echo $SCROLL_RESULT | jq -r '.data.found')" = "true" ]; then
      echo "✅ Found via scrollToElement"
      return 0
    fi
    
    # Manual scroll as fallback (ui.swipe locates the scrollView via path)
    echo "Scrolling manually..."
    SNAPSHOT_ID=$(echo $INSPECT | jq -r '.data.viewSnapshotID')
    SCROLL_VIEW_REF=$(echo $INSPECT | jq -r '.data.targets[] | select(.type == "UICollectionView" or .type == "UITableView") | .path' | head -1)

    if [ -n "$SCROLL_VIEW_REF" ]; then
      curl -s -X POST http://localhost:38321/ -d "{
        \"action\": \"ui.swipe\",
        \"data\": {
          \"path\": \"$SCROLL_VIEW_REF\",
          \"direction\": \"up\",
          \"distance\": 0.8
        }
      }" > /dev/null
      sleep 0.3
    fi
  done
  
  echo "❌ Not found after $max_scrolls attempts"
  return 1
}

# Usage
find_item_with_manual_scroll "Item 50"
```

### Example 3: Scroll to Top/Bottom

```bash
# Scroll to top
scroll_to_top() {
  INSPECT=$(curl -s -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}')
  FIRST_ITEM=$(echo $INSPECT | jq -r '.data.targets[] | select(.type == "UILabel") | .text' | head -1)
  
  curl -X POST http://localhost:38321/ -d "{
    \"action\": \"ui.scrollToElement\",
    \"data\": {
      \"match\": \"text\",
      \"value\": \"$FIRST_ITEM\",
      \"animated\": true
    }
  }"
}

# Scroll to bottom
scroll_to_bottom() {
  # Scroll down multiple times (omit locator to swipe the frontmost scrollView)
  for i in {1..10}; do
    curl -s -X POST http://localhost:38321/ -d '{
      "action": "ui.swipe",
      "data": {
        "direction": "up",
        "distance": 0.9
      }
    }' > /dev/null
    sleep 0.3
  done
}
```

### Example 4: Select Multiple Items

```bash
#!/bin/bash
# Select multiple items from a list

items=("Item 1" "Item 5" "Item 10")

for item in "${items[@]}"; do
  echo "Selecting: $item"
  
  # Scroll to item
  curl -s -X POST http://localhost:38321/ -d "{
    \"action\": \"ui.scrollToElement\",
    \"data\": {
      \"match\": \"text\",
      \"value\": \"$item\"
    }
  }" > /dev/null
  
  # Get snapshot and tap
  INSPECT=$(curl -s -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}')
  SNAPSHOT_ID=$(echo $INSPECT | jq -r '.data.viewSnapshotID')
  ITEM_PATH=$(echo $INSPECT | jq -r ".data.targets[] | select(.text == \"$item\") | .path")
  
  if [ -n "$ITEM_PATH" ]; then
    curl -s -X POST http://localhost:38321/ -d "{
      \"action\": \"ui.tap\",
      \"data\": {
        \"path\": \"$ITEM_PATH\",
        \"viewSnapshotID\": \"$SNAPSHOT_ID\"
      }
    }" > /dev/null
    echo "✅ Selected: $item"
  else
    echo "❌ Failed to select: $item"
  fi
  
  sleep 0.5
done
```

### Example 5: Infinite Scroll Handling

```bash
#!/bin/bash
# Handle infinite scroll lists that load more content as you scroll

load_and_collect_items() {
  local max_scrolls=20
  local collected_items=()
  local previous_count=0
  local no_change_count=0
  
  for i in $(seq 1 $max_scrolls); do
    echo "Scroll attempt $i of $max_scrolls"
    
    # Get current items
    INSPECT=$(curl -s -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}')
    ITEMS=$(echo $INSPECT | jq -r '.data.targets[] | select(.type == "UILabel") | .text')
    CURRENT_COUNT=$(echo "$ITEMS" | wc -l | tr -d ' ')
    
    echo "Current item count: $CURRENT_COUNT"
    
    # Check if new items loaded
    if [ "$CURRENT_COUNT" -eq "$previous_count" ]; then
      ((no_change_count++))
      echo "No new items loaded ($no_change_count/3)"
      
      # If no new items for 3 consecutive scrolls, assume end reached
      if [ "$no_change_count" -ge 3 ]; then
        echo "✅ Reached end of list (no new items after 3 scrolls)"
        break
      fi
    else
      no_change_count=0
    fi
    
    previous_count=$CURRENT_COUNT
    
    # Scroll down to trigger loading more (inspect returns .path, not elementRef)
    SCROLL_VIEW=$(echo $INSPECT | jq -r '.data.targets[] | select(.type == "UICollectionView" or .type == "UITableView") | .path' | head -1)

    if [ -n "$SCROLL_VIEW" ]; then
      curl -s -X POST http://localhost:38321/ -d "{
        \"action\": \"ui.swipe\",
        \"data\": {
          \"path\": \"$SCROLL_VIEW\",
          \"direction\": \"up\",
          \"distance\": 0.9
        }
      }" > /dev/null
      
      # Wait for new content to load
      sleep 1.0
    else
      echo "❌ Scroll view not found"
      break
    fi
  done
  
  echo "✅ Loaded approximately $CURRENT_COUNT items"
}

load_and_collect_items
```

## Parameters Reference

### ui.scrollToElement

**By Text:**
```json
{
  "match": "text",
  "value": "Item 5",
  "animated": false  // Optional: default false
}
```

**By Accessibility Identifier:**
```json
{
  "match": "accessibilityIdentifier",
  "value": "contact-123",
  "animated": true
}
```

**Response (Success):**
```json
{
  "code": "ok",
  "data": {
    "found": true,
    "match": "text",
    "targetPath": "root/0/5/0/0",
    "targetType": "UILabel",
    "container": "UICollectionView"
  }
}
```

**Response (Not Found):**
```json
{
  "code": "target_not_found",
  "message": "scroll target not found"
}
```

### ui.swipe (for scrolling / cell swipe actions)

```json
{
  "direction": "up",                          // Required: "up", "down", "left", "right"
  "distance": 0.8,                            // Optional: (0,1], default 0.8
  "accessibilityIdentifier": "list_scroll",   // Optional: locate the scrollView/view
  "path": "root/0/5",                         // Optional: locate the scrollView/view (alt to identifier)
  "viewSnapshotID": "snap-XXX",               // Optional: staleness check
  "cellAccessibilityIdentifier": "cell.42",   // Optional: for swipe actions — locate the cell
  "cellPath": "root/0/5/0/3",                 // Optional: for swipe actions — locate the cell (alt)
  "actionTitle": "删除"                        // Optional: which swipe action to trigger (nil → first)
}
```

**Scrolling:** pass `accessibilityIdentifier`/`path` of the scroll container. Omit
both to swipe the keyWindow's frontmost scrollView. `direction: "up"` scrolls down,
`"down"` scrolls up.

**Cell swipe actions:** pass `cellAccessibilityIdentifier` (or `cellPath`) instead.
`direction: "left"` → trailing actions, `"right"` → leading actions. `actionTitle`
selects a specific action; omit to trigger the first. (See `Sources/iOSExploreUIKit/
Commands/Swipe/UISwipeModels.swift`.)

## Error Handling

### Common Errors

#### 1. `target_not_found`
**Cause:** Element with specified text/identifier not found in list

**Solution:**
- Verify exact text match (case-sensitive)
- Check accessibility identifier is correct
- Item may not exist in data source
- Try broader search terms

**Example:**
```bash
# If exact match fails, search for partial match
INSPECT=$(curl -s -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}')
echo $INSPECT | jq '.data.targets[] | select(.text | contains("John"))'
```

#### 2. `stale_locator`
**Cause:** Snapshot expired after scrolling

**Solution:**
- Call `ui.inspect` again after `ui.scrollToElement`
- Get fresh snapshot ID before tapping
- Snapshots have a 120-second TTL

**Example:**
```bash
# Scroll
curl -X POST http://localhost:38321/ -d '{"action":"ui.scrollToElement","data":{...}}'

# Get FRESH snapshot (don't reuse old one)
INSPECT=$(curl -s -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}')
SNAPSHOT_ID=$(echo $INSPECT | jq -r '.data.viewSnapshotID')

# Now tap with fresh snapshot
curl -X POST http://localhost:38321/ -d "{\"action\":\"ui.tap\",\"data\":{...,\"viewSnapshotID\":\"$SNAPSHOT_ID\"}}"
```

#### 3. Item Not Visible After Scroll
**Cause:** `scrollToElement` succeeded but item not in `ui.inspect` targets

**Solution:**
- Wait 100-300ms after scroll for layout
- Use `animated: true` for smoother scrolling
- Re-inspect to refresh targets

#### 4. Wrong Container Selected
**Cause:** Multiple scroll views on screen

**Solution:**
- Use specific accessibility identifier for container
- Find correct UITableView or UICollectionView
- Verify container type in response

## Performance Characteristics

Based on automated tests (100% success rate):

| Operation | Duration | Notes |
|-----------|----------|-------|
| **ui.scrollToElement** | 2-7ms | Extremely fast (instant scroll) |
| **ui.scrollToElement (animated)** | 5ms | Slightly slower with animation |
| **Find visible item** | 100-200ms | Via ui.inspect |
| **Manual scroll** | 300-500ms | Via ui.swipe |
| **Find with scrolling** | 1-5s | Depends on list size |

**Tested Scenarios:**
- ✅ Scroll to Item 0 (first): 2ms
- ✅ Scroll to Item 5 (middle): 2ms
- ✅ Scroll to Item 4 with animation: 5ms
- ✅ Item not found: 7ms + error

## Best Practices

### 1. Use scrollToElement First

```bash
# Good: Try scrollToElement first (extremely fast)
RESULT=$(curl -s -X POST http://localhost:38321/ -d '{
  "action": "ui.scrollToElement",
  "data": {"match": "text", "value": "Target"}
}')

if [ "$(echo $RESULT | jq -r '.code')" = "ok" ]; then
  # Item found and scrolled to
  echo "Found via scrollToElement"
else
  # Fallback to manual scrolling
  echo "Trying manual scroll"
fi
```

### 2. Always Refresh Snapshot After Scroll

```bash
# Good: Fresh snapshot after scroll
curl -X POST http://localhost:38321/ -d '{"action":"ui.scrollToElement","data":{...}}'
INSPECT=$(curl -s -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}')
SNAPSHOT_ID=$(echo $INSPECT | jq -r '.data.viewSnapshotID')
# Use fresh SNAPSHOT_ID for next action

# Bad: Reusing old snapshot
SNAPSHOT_ID="snap-old"
curl -X POST http://localhost:38321/ -d '{"action":"ui.scrollToElement","data":{...}}'
# Using snap-old here will cause stale_locator error!
```

### 3. Wait After Scroll Animation

```bash
# For manual scrolling
curl -X POST http://localhost:38321/ -d '{"action":"ui.swipe","data":{...}}'
sleep 0.3  # Wait for scroll to settle
curl -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}'
```

### 4. Use Accessibility Identifiers When Available

```bash
# Best: Stable identifiers
{"match": "accessibilityIdentifier", "value": "contact-user-123"}

# OK: Text match (but may change)
{"match": "text", "value": "John Doe"}
```

### 5. Limit Manual Scroll Attempts

```bash
MAX_SCROLLS=10
for i in $(seq 1 $MAX_SCROLLS); do
  # Try to find item
  # ... search logic ...
  # If found, break
  # If not found after MAX_SCROLLS, fail gracefully
done
```

## Limitations

### Known Limitations

1. **scrollToElement Limitation:** Only works with items that exist in the data source. Cannot scroll to items not yet loaded (infinite scroll).

2. **Manual Scroll Detection:** No automatic detection of end-of-list. Must manually limit scroll attempts.

3. **Section Headers:** Section headers may interfere with item scrolling. May need to scroll past headers first.

4. **Horizontal Scrolling:** `ui.scrollToElement` works for vertical lists. Horizontal collection views may need `ui.swipe`.

5. **Reordering:** Cannot programmatically reorder list items (requires long-press + drag gesture).

6. **Pull to Refresh:** Cannot trigger pull-to-refresh gesture programmatically.

## Related Skills

- **ios-navigation** - Navigate to detail views after selecting items
- **ios-gestures** - Advanced gestures for cell swipe actions
- **ios-dynamic-content** - Wait for list data to load
- **ios-screenshot** - Capture list state

## Test Coverage

**Commands Tested:**
- ✅ ui.scrollToElement by text (100% success rate, 4 scenarios)
- ✅ ui.scrollToElement with animation
- ✅ Error handling: target not found

**Test Report:** `docs/final-two-commands-test-report.json`（路径相对于**仓库根**，非本 skill 目录）

**Tested Scenarios:**
- ✅ Scroll to Item 5 (middle): 2ms
- ✅ Scroll to Item 0 (first): 2ms
- ✅ Scroll to Item 4 with animated=true: 5ms
- ✅ Scroll to non-existent element: 7ms + target_not_found error

## Production Readiness

✅ **Production Ready**

`ui.scrollToElement` is fully tested with 100% success rate. Extremely fast performance (2-7ms). Manual scrolling with `ui.swipe` is also tested as part of gesture commands. Safe for production use with proper error handling for items not found.
