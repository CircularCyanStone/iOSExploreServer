# iOS Automation Skills - Improvement Recommendations

**Date:** 2026-07-14  
**Purpose:** Specific, actionable recommendations for improving each iOS automation skill

---

## Production-Ready Skills

These 5 skills are production-ready but can still be improved:

### ios-form-filling

**Current Status:** ✅ Production Ready (5/5 rating)

**Improvements:**

1. **Add Field Validation Example**
   ```markdown
   ### Example 7: Handle Field Validation Errors
   
   ```bash
   # Fill email field
   curl -X POST http://localhost:38321/ -d '{
     "action": "ui.input",
     "data": {
       "path": "email_field_path",
       "text": "invalid-email",
       "mode": "replace"
     }
   }'
   
   # Try to submit
   curl -X POST http://localhost:38321/ -d '{"action":"ui.tap","data":{...}}'
   sleep 0.3
   
   # Check if validation alert appeared
   ALERT=$(curl -s -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}' | jq -r '.data.alert.available')
   
   if [ "$ALERT" = "true" ]; then
     echo "Validation error detected"
     # Handle error alert
     curl -X POST http://localhost:38321/ -d '{"action":"ui.alert.respond","data":{"buttonIndex":0}}'
     # Fix the email and retry
   fi
   ```
   ```

2. **Add Multi-Page Form Example**
   - Show pattern for form filling across multiple screens
   - Include navigation between form pages
   - Document state preservation between pages

3. **Add Common Form Patterns Section**
   - Login forms (email + password)
   - Registration forms (multiple fields)
   - Settings forms (mixed controls)
   - Search forms (with suggestions)

---

### ios-alert-handling

**Current Status:** ✅ Production Ready (4.75/5 rating - known edge case)

**Improvements:**

1. **Fix Destructive Role Lookup**
   - Add retry logic when destructive role fails:
   ```bash
   respond_to_destructive() {
     # Try role first
     RESULT=$(curl -s -X POST http://localhost:38321/ -d '{"action":"ui.alert.respond","data":{"role":"destructive"}}')
     
     if [ "$(echo $RESULT | jq -r '.code')" != "ok" ]; then
       echo "Role lookup failed, trying title fallback"
       # Fallback to title or index
       curl -X POST http://localhost:38321/ -d '{"action":"ui.alert.respond","data":{"buttonTitle":"Delete"}}'
     fi
   }
   ```

2. **Add Fallback Pattern Documentation**
   - Document recommended response order: role → title → index
   - Add decision tree for response method selection
   - Document language considerations for title-based responses

3. **Add System Alert Section**
   - Clarify which alerts are supported (UIAlertController only)
   - Document system permission alerts (not supported)
   - Suggest workarounds for system alerts

---

### ios-navigation

**Current Status:** ✅ Production Ready (5/5 rating)

**Improvements:**

1. **Add Modal Dismissal Example**
   ```markdown
   ### Example 6: Dismiss Modal Presentation
   
   Modal views don't use `ui.navigation.back`. Look for dismiss buttons:
   
   ```bash
   # Find close/done button in modal
   INSPECT=$(curl -s -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}')
   CLOSE_BUTTON=$(echo $INSPECT | jq -r '.data.targets[] | select(.text == "Close" or .text == "Done") | .path')
   
   # Tap to dismiss
   curl -X POST http://localhost:38321/ -d '{"action":"ui.tap","data":{...}}'
   sleep 0.5
   ```
   ```

2. **Add Tab Bar Navigation Example**
   - Show pattern for switching tabs
   - Document tab bar state inspection
   - Show how to combine tab switching with push navigation

3. **Add Navigation State Recovery**
   - Document how to return to known state after test
   - Add "reset to home" pattern
   - Add navigation stack depth tracking

---

### ios-list-interaction

**Current Status:** ✅ Production Ready (5/5 rating)

**Improvements:**

1. **Add Infinite Scroll Pattern**
   ```markdown
   ### Example 5: Handle Infinite Scroll Lists
   
   For lists that load more content on scroll:
   
   ```bash
   load_more_content() {
     local max_loads=5
     
     for i in $(seq 1 $max_loads); do
       # Scroll to bottom
       curl -s -X POST http://localhost:38321/ -d '{
         "action": "ui.swipe",
         "data": {
           "withinElementRef": "scroll_ref",
           "direction": "up",
           "distance": 0.9
         }
       }' > /dev/null
       
       # Wait for new content to load
       sleep 1.0
       
       # Check if target item appeared
       # ...
     done
   }
   ```
   ```

2. **Add Horizontal Collection View Section**
   - Document left/right swipe for horizontal scrolling
   - Show page-based navigation patterns
   - Add example for carousel interactions

3. **Add Section Header Interaction**
   - Show how to tap collapsible section headers
   - Document section-based navigation
   - Add index list (A-Z) sidebar interaction

---

### ios-screenshot

**Current Status:** ✅ Production Ready (5/5 rating)

**Improvements:**

1. **Add Visual Regression Testing Example**
   ```markdown
   ### Example 7: Automated Visual Regression Testing
   
   ```bash
   #!/bin/bash
   # Compare screenshots against baseline
   
   BASELINE_DIR="test_baselines"
   CURRENT_DIR="test_current"
   DIFF_DIR="test_diffs"
   
   mkdir -p "$CURRENT_DIR" "$DIFF_DIR"
   
   # Capture current screenshot
   curl -s -X POST http://localhost:38321/ -d '{"action":"ui.screenshot"}' | \
     jq -r '.data.image' | base64 -d > "$CURRENT_DIR/screen.png"
   
   # Compare with baseline
   if [ -f "$BASELINE_DIR/screen.png" ]; then
     compare -metric RMSE "$BASELINE_DIR/screen.png" "$CURRENT_DIR/screen.png" \
       "$DIFF_DIR/screen.png" 2>&1 | tee diff_metric.txt
     
     DIFF=$(cat diff_metric.txt | grep -oE '^[0-9]+')
     
     if [ "$DIFF" -gt 1000 ]; then
       echo "❌ Visual regression detected! Diff: $DIFF"
       exit 1
     else
       echo "✅ Visual regression check passed"
     fi
   else
     echo "Creating baseline"
     cp "$CURRENT_DIR/screen.png" "$BASELINE_DIR/screen.png"
   fi
   ```
   ```

2. **Add CI/CD Storage Best Practices**
   - Document artifact storage strategies
   - Add screenshot retention policies
   - Show how to upload to S3/artifact storage
   - Add screenshot naming conventions for CI

3. **Add Screenshot Annotation**
   - Show how to use ImageMagick to annotate screenshots
   - Add timestamp/metadata overlay examples
   - Show how to highlight specific UI elements

---

## Partially Ready Skills

These 2 skills need significant improvements to reach production readiness:

### ios-gestures

**Current Status:** ⚠️ Partially Ready (3.75/5 rating)

**Critical Improvements:**

1. **Test ui.drag Command**
   - Run comprehensive drag tests
   - Document drag distance and duration parameters
   - Add drag-and-drop examples
   - Measure performance

2. **Expand Documentation to 400+ Lines**
   - Add 3 more usage examples
   - Add complete error handling section
   - Add best practices section (5+ guidelines)
   - Add limitations section

3. **Add Performance Benchmarks**
   - Measure ui.swipe duration across distances
   - Measure ui.longPress duration variations
   - Document ui.drag performance (once tested)
   - Create performance comparison table

4. **Add Advanced Gesture Examples**
   ```markdown
   ### Example 4: Multi-Direction Scroll
   
   Navigate a 2D scrollable view:
   
   ```bash
   # Scroll right to reveal more columns
   curl -X POST http://localhost:38321/ -d '{
     "action": "ui.swipe",
     "data": {
       "withinElementRef": "scroll_ref",
       "direction": "left",
       "distance": 0.8
     }
   }'
   
   sleep 0.3
   
   # Scroll down to reveal more rows
   curl -X POST http://localhost:38321/ -d '{
     "action": "ui.swipe",
     "data": {
       "withinElementRef": "scroll_ref",
       "direction": "up",
       "distance": 0.8
     }
   }'
   ```
   ```

5. **Add Gesture Timing Section**
   - Document when animations settle
   - Add recommended wait times after gestures
   - Explain gesture velocity vs. duration

---

### ios-table-actions

**Current Status:** ⚠️ Partially Ready (2.75/5 rating)

**Critical Improvements:**

1. **Test ui.table.* Commands**
   - Test table edit mode activation
   - Test cell reordering commands
   - Test batch selection commands
   - Test section operations

2. **Add Edit Mode Example**
   ```markdown
   ### Example 3: Enter Table Edit Mode
   
   ```bash
   # Tap Edit button in navigation bar
   curl -X POST http://localhost:38321/ -d '{
     "action": "ui.navigation.tapBarButton",
     "data": {
       "placement": "left",
       "index": 0,
       "title": "Edit"
     }
   }'
   
   sleep 0.3
   
   # Now table is in edit mode
   # Reorder controls and delete buttons should be visible
   INSPECT=$(curl -s -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}')
   echo $INSPECT | jq '.data.targets[] | select(.type == "UIButton" and .text == "Delete")'
   ```
   ```

3. **Add Cell Reordering Example**
   - Document long-press to initiate drag
   - Show drag to new position
   - Document release and verification

4. **Add Batch Operations Section**
   - Show how to select multiple cells
   - Document bulk delete pattern
   - Add select-all functionality

5. **Expand Documentation to 400+ Lines**
   - Add error handling section
   - Add best practices section
   - Add 3 more usage examples
   - Add performance benchmarks

---

## Experimental Skills

These skills need testing before production use:

### ios-dynamic-content

**Current Status:** 🧪 Experimental (2.75/5 rating)

**Critical Improvements:**

1. **Test Built-in Wait Commands**
   - Implement and test ui.wait command
   - Implement and test ui.waitAny command
   - Compare performance vs manual polling
   - Document when to use each approach

2. **Add Performance Benchmarks**
   ```markdown
   ## Performance Characteristics
   
   Based on 20 polling tests:
   
   | Operation | Mean | Notes |
   |-----------|------|-------|
   | **Manual Polling (300ms interval)** | 1.2s | For 4-iteration wait |
   | **Manual Polling (500ms interval)** | 2.0s | For 4-iteration wait |
   | **ui.wait (if implemented)** | TBD | Needs testing |
   | **Overhead per ui.inspect** | 150ms | Average |
   ```

3. **Add Complex Wait Conditions**
   ```markdown
   ### Example 4: Wait for Complex Condition
   
   Wait for multiple elements to reach specific states:
   
   ```bash
   wait_for_ready_state() {
     # Wait for:
     # 1. Loading indicator gone
     # 2. Content visible
     # 3. No error message
     
     timeout=10.0
     interval=0.5
     elapsed=0
     
     while (( $(echo "$elapsed < $timeout" | bc -l) )); do
       INSPECT=$(curl -s -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}')
       
       LOADING=$(echo $INSPECT | jq -r '.data.targets[] | select(.text == "Loading...") | .text')
       CONTENT=$(echo $INSPECT | jq -r '.data.targets[] | select(.text == "Content") | .text')
       ERROR=$(echo $INSPECT | jq -r '.data.targets[] | select(.text == "Error") | .text')
       
       if [ -z "$LOADING" ] && [ -n "$CONTENT" ] && [ -z "$ERROR" ]; then
         echo "✅ Ready state reached"
         return 0
       fi
       
       sleep $interval
       elapsed=$(echo "$elapsed + $interval" | bc)
     done
     
     echo "❌ Timeout"
     return 1
   }
   ```
   ```

4. **Add Polling Overhead Section**
   - Document cost of excessive polling
   - Add recommended polling intervals by scenario
   - Show how to avoid polling storms

5. **Add Comparison Section**
   - Compare manual polling vs built-in wait
   - Document trade-offs of each approach
   - Provide decision matrix

---

## Not Ready Skills

These skills are not production-ready and need major work:

### ios-controller-navigation

**Current Status:** ❌ Not Ready (1.75/5 rating)

**Critical Improvements:**

1. **Test ui.controllers Command**
   - Implement comprehensive tests
   - Verify controller hierarchy output
   - Test with different navigation patterns
   - Test with modals and tabs

2. **Decide: Merge or Standalone**
   - **Option A:** Merge with ios-navigation skill
     - Add controller hierarchy inspection to navigation skill
     - Remove standalone controller-navigation skill
   - **Option B:** Keep standalone and expand
     - Add 10+ usage examples
     - Document all controller types (nav, tab, split, modal)
     - Expand to 400+ lines

3. **Add Practical Use Cases**
   - When would you need controller hierarchy?
   - How does it help debugging?
   - What navigation decisions require this info?

4. **If Keeping Standalone:**
   ```markdown
   ### Example 3: Detect Navigation Pattern
   
   ```bash
   # Get controller hierarchy
   CONTROLLERS=$(curl -s -X POST http://localhost:38321/ -d '{"action":"ui.controllers"}')
   
   ROOT=$(echo $CONTROLLERS | jq -r '.data.root')
   
   if [ "$ROOT" = "UITabBarController" ]; then
     echo "App uses tab-based navigation"
   elif [ "$ROOT" = "UINavigationController" ]; then
     echo "App uses stack-based navigation"
   elif [ "$ROOT" = "UISplitViewController" ]; then
     echo "App uses split view (iPad)"
   fi
   ```
   
   ### Example 4: Detect Modal Presentation
   
   ```bash
   CONTROLLERS=$(curl -s -X POST http://localhost:38321/ -d '{"action":"ui.controllers"}')
   MODALS=$(echo $CONTROLLERS | jq '.data.modals | length')
   
   if [ "$MODALS" -gt 0 ]; then
     echo "Modal view is presented"
     # Dismiss modal before continuing
   fi
   ```
   ```

---

### ios-date-picker

**Current Status:** ❌ Not Ready (1.75/5 rating)

**Critical Improvements:**

1. **Test All Picker Commands**
   - Test ui.datePicker.setDate
   - Test ui.datePicker.setTime
   - Test ui.datePicker.setDateTime
   - Test ui.picker.selectValue
   - Measure performance

2. **Decide: Implement or Remove**
   - **Option A:** Full implementation
     - Complete comprehensive testing
     - Document all picker modes
     - Add 6+ usage examples
     - Expand to 400+ lines
   - **Option B:** Remove skill
     - Document why pickers are not automated
     - Suggest app-side testing alternatives
     - Remove from skill list

3. **If Implementing, Add These Examples:**
   ```markdown
   ### Example 4: Select Date Range
   
   ```bash
   # Set start date picker
   curl -X POST http://localhost:38321/ -d '{
     "action": "ui.datePicker.setDate",
     "data": {
       "path": "start_picker_path",
       "date": "2026-07-01"
     }
   }'
   
   # Set end date picker
   curl -X POST http://localhost:38321/ -d '{
     "action": "ui.datePicker.setDate",
     "data": {
       "path": "end_picker_path",
       "date": "2026-07-31"
     }
   }'
   ```
   
   ### Example 5: Custom Picker (State Selection)
   
   ```bash
   # Select "California" from state picker
   curl -X POST http://localhost:38321/ -d '{
     "action": "ui.picker.selectValue",
     "data": {
       "path": "state_picker_path",
       "component": 0,
       "value": "California"
     }
   }'
   ```
   ```

4. **Add Picker Interaction Challenges Section**
   - Why pickers are difficult to automate
   - OS-level limitations
   - Alternative approaches
   - When to use manual testing

---

## General Improvements for All Skills

### 1. Add Video/GIF Demonstrations

Add links to video demonstrations for complex interactions:

```markdown
## Video Demonstrations

- [Form Filling Demo](link-to-video) - Shows complete form fill workflow
- [Alert Handling Demo](link-to-video) - Shows all 3 response methods
- [Navigation Demo](link-to-video) - Shows deep navigation and back
```

### 2. Add Troubleshooting Section

Every skill should have:

```markdown
## Troubleshooting

### Issue: Command times out
**Symptoms:** Request hangs for 30+ seconds
**Causes:**
- App frozen or unresponsive
- Network issue (for physical device)
- Invalid path or snapshot ID

**Solutions:**
1. Restart the app
2. Check iproxy connection (device only)
3. Get fresh snapshot with ui.inspect
4. Verify element exists on current screen
```

### 3. Add Quick Start Section

Add at the top of each skill:

```markdown
## Quick Start

**Minimal working example:**

```bash
# 1. Inspect current screen
curl -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}'

# 2. [Skill-specific quick example]

# 3. Verify result
```

**Common issues:** [link to troubleshooting]  
**Full examples:** [link to usage examples section]
```

### 4. Add Related Commands Cross-Reference

```markdown
## Related Commands

This skill uses these MCP commands:

| Command | Documentation | Test Report |
|---------|---------------|-------------|
| ui.inspect | [Command Docs](link) | [Test Report](link) |
| ui.tap | [Command Docs](link) | [Test Report](link) |
```

### 5. Add Performance Considerations

Every skill should document:
- Expected command duration
- When to add wait times
- How to batch operations for efficiency
- Network latency considerations (device vs simulator)

---

## Priority Matrix

### High Priority (Do First)

1. **Test ios-gestures ui.drag** - Blocks production readiness
2. **Fix ios-alert-handling destructive role** - Known bug
3. **Test ios-dynamic-content built-in commands** - Needed for production
4. **Decide ios-date-picker fate** - Test or remove
5. **Decide ios-controller-navigation fate** - Merge or remove

### Medium Priority (Do Soon)

1. **Expand ios-table-actions documentation**
2. **Add examples to all production skills**
3. **Add troubleshooting sections to all skills**
4. **Add performance benchmarks to partially-ready skills**

### Low Priority (Nice to Have)

1. **Add video demonstrations**
2. **Add quick start sections**
3. **Add visual regression example**
4. **Add CI/CD integration examples**

---

## Success Criteria

A skill is production-ready when:

- ✅ 400+ lines of documentation
- ✅ 5-6 detailed usage examples
- ✅ Complete parameter reference
- ✅ Error handling section with 4+ scenarios
- ✅ Best practices section with 5+ guidelines
- ✅ Performance benchmarks from real tests
- ✅ Test coverage: 100% of documented commands
- ✅ Test success rate: 95%+ across all scenarios
- ✅ Limitations section documenting known issues
- ✅ 3+ test cases in evals.json

---

**Report Generated:** 2026-07-14  
**Next Review:** After implementing high-priority improvements
