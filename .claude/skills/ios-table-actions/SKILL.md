---
name: ios-table-actions
description: |
  iOS App automation for advanced table and collection view operations.
  
  Use this skill when the user needs to perform table-specific actions like swipe-to-delete,
  cell reordering, section operations, or collection view batch updates in iOS apps.
  
  Must explicitly mention iOS, iPhone, iPad, table view, or collection view actions to trigger.
  
  Based on iOSDriver MCP Server. Note: Table-specific commands not fully tested yet.
---

# iOS Table & Collection View Actions

> **⚠️ LIMITED TESTING WARNING**  
> Only swipe-to-reveal actions have been comprehensively tested. Other features including:
> - Table edit mode
> - Cell reordering via drag-and-drop
> - Batch operations
> - Section-specific operations
> 
> are NOT tested yet. Use with caution and test thoroughly in your environment before relying on them.

## Purpose

Perform advanced operations on iOS table views (UITableView) and collection views (UICollectionView) beyond basic tap and scroll interactions.

## When to Use

Use this skill when you need to:
- Swipe-to-delete table cells
- Swipe-to-edit table cells
- Reorder cells via drag-and-drop
- Navigate to specific table sections
- Expand/collapse section headers
- Perform batch operations on cells
- Handle table editing mode

## Prerequisites

- **iOSDriver MCP Server** connected and active
- **iOS App** with UITableView or UICollectionView
- **Port 38321** accessible

## Commands Used

| Command | Purpose | Status |
|---------|---------|--------|
| `ui.swipe` | Reveal cell swipe actions | ✅ Tested |
| `ui_tap_and_inspect` | Tap revealed action buttons | ✅ Tested |
| `ui.table.*` | Table-specific operations | ❌ Not tested |
| `ui.collection.*` | Collection-specific operations | ❌ Not tested |

## Capabilities

### 1. Swipe Actions (Tested)

**Swipe Left to Reveal Delete/Edit:**
```bash
# Get cell reference
INSPECT=$(curl -s -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}')
CELL_REF=$(echo $INSPECT | jq -r '.data.targets[] | select(.text == "Item 5") | .elementRef')

# Swipe left on cell
curl -X POST http://localhost:38321/ -d "{
  \"action\": \"ui.swipe\",
  \"data\": {
    \"withinElementRef\": \"$CELL_REF\",
    \"direction\": \"left\",
    \"distance\": 0.6
  }
}"

# Inspect to see revealed actions
sleep 0.3
INSPECT=$(curl -s -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}')
echo $INSPECT | jq '.data.targets[] | select(.text == "Delete" or .text == "Edit")'
```

### 2. Cell Reordering (Not Tested)

Theoretical approach:
1. Long press on cell to enter drag mode
2. Drag to new position
3. Release to drop

**Not tested - use with caution.**

### 3. Section Operations (Not Tested)

Theoretical commands:
- Navigate to section by index
- Expand/collapse section
- Get section header/footer

**Not tested - no reliable pattern yet.**

## Usage Examples

### Example 1: Delete Table Cell

```bash
#!/bin/bash
# Swipe to reveal delete button, then tap it

CELL_TEXT="John Doe"

# Find and swipe cell
INSPECT=$(curl -s -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}')
CELL_REF=$(echo $INSPECT | jq -r ".data.targets[] | select(.text == \"$CELL_TEXT\") | .elementRef")

if [ -n "$CELL_REF" ]; then
  # Swipe left
  curl -s -X POST http://localhost:38321/ -d "{
    \"action\": \"ui.swipe\",
    \"data\": {
      \"withinElementRef\": \"$CELL_REF\",
      \"direction\": \"left\",
      \"distance\": 0.6
    }
  }" > /dev/null
  
  sleep 0.3
  
  # Find delete button
  INSPECT=$(curl -s -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}')
  SNAPSHOT_ID=$(echo $INSPECT | jq -r '.data.viewSnapshotID')
  DELETE_PATH=$(echo $INSPECT | jq -r '.data.targets[] | select(.text == "Delete") | .path')
  
  if [ -n "$DELETE_PATH" ]; then
    # Tap delete
    curl -s -X POST http://localhost:38321/ -d "{
      \"action\": \"ui_tap_and_inspect\",
      \"data\": {
        \"path\": \"$DELETE_PATH\",
        \"viewSnapshotID\": \"$SNAPSHOT_ID\"
      }
    }" > /dev/null
    
    echo "✅ Deleted cell: $CELL_TEXT"
  else
    echo "❌ Delete button not found"
  fi
else
  echo "❌ Cell not found: $CELL_TEXT"
fi
```

### Example 2: Edit Table Cell

```bash
# Swipe to reveal Edit button
curl -X POST http://localhost:38321/ -d '{
  "action": "ui.swipe",
  "data": {
    "withinElementRef": "cell_ref",
    "direction": "left",
    "distance": 0.6
  }
}'

sleep 0.3

# Tap Edit button
INSPECT=$(curl -s -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}')
SNAPSHOT_ID=$(echo $INSPECT | jq -r '.data.viewSnapshotID')
EDIT_PATH=$(echo $INSPECT | jq -r '.data.targets[] | select(.text == "Edit") | .path')

curl -X POST http://localhost:38321/ -d "{
  \"action\": \"ui_tap_and_inspect\",
  \"data\": {
    \"path\": \"$EDIT_PATH\",
    \"viewSnapshotID\": \"$SNAPSHOT_ID\"
  }
}"
```

## Best Practices

1. **Always wait after swipe:** 300ms for animation to complete
2. **Verify buttons appeared:** Check ui.inspect after swipe
3. **Handle missing actions:** Not all cells have swipe actions
4. **Test swipe distance:** 0.6 is typical, adjust if actions don't appear

## Limitations

⚠️ **Low Test Coverage**

- Only basic swipe-to-reveal tested
- No table editing mode support yet
- No cell reordering tested
- No section-specific operations
- Cannot programmatically enter edit mode
- Cannot batch select/delete cells

## Workaround

For operations not directly supported:
1. Use `ui.swipe` to reveal cell actions
2. Use `ui_tap_and_inspect` to interact with revealed buttons
3. Use `ui.longPress` for potential drag initiation (not tested)

## Related Skills

- **ios-gestures** - Swipe and long press operations
- **ios-list-interaction** - Basic list navigation
- **ios-alert-handling** - Confirm deletion alerts

## Production Readiness

⚠️ **Use with Caution**

Only swipe-to-reveal actions are tested. Advanced table operations require comprehensive testing. For production use, stick to tested swipe + tap pattern for cell actions.
