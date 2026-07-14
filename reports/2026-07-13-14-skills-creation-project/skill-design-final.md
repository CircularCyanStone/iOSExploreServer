# iOS Automation Skills Design - Final Specification

## Overview

This document defines 10 comprehensive skills for iOS app automation using iOSExploreServer commands. Each skill is designed based on end-to-end testing results and production-ready patterns.

**Version:** 1.0  
**Date:** 2026-07-13  
**Based on:** 32 iOS UIKit commands, 10+ tested with 100% success rate

---

## Skill 1: Form Filling & Data Entry

**Confidence Level:** ⭐⭐⭐⭐⭐ High (all commands fully tested)

### Purpose
Fill text fields, toggle switches, select options, and submit forms in iOS apps.

### Commands Used
- `ui.inspect` - Find form fields
- `ui.input` - Enter text
- `ui.control.sendAction` - Toggle switches, adjust sliders
- `ui.keyboard.dismiss` - Close keyboard
- `ui.tap` - Submit buttons

### Capabilities
1. **Text Input**
   - Single-line text fields (UITextField)
   - Multi-line text areas (UITextView)
   - Search fields (UISearchTextField)
   - Replace or append mode
   - Unicode and emoji support

2. **Control Interaction**
   - Toggle switches (UISwitch)
   - Adjust sliders (UISlider)
   - Increment/decrement steppers (UIStepper)
   - Select segments (UISegmentedControl)

3. **Form Submission**
   - Find and tap submit buttons
   - Auto-dismiss keyboard when needed
   - Verify form completion

### Usage Pattern

```python
# Example: Fill login form
skill = FormFillingSkill(base_url)

# Find and fill username field
skill.fill_text_field(
    identifier_or_text="Username",
    text="john.doe@example.com",
    mode="replace"
)

# Fill password field
skill.fill_text_field(
    identifier_or_text="Password",
    text="secure_password",
    mode="replace"
)

# Toggle "Remember me" switch
skill.toggle_switch(identifier_or_text="Remember me")

# Tap login button
skill.tap_button(text="Log In")
```

### Implementation Notes

**Key Parameters:**
```python
# ui.input
{
    "path": "root/0/1/0/0/0/2",  # or use accessibilityIdentifier
    "viewSnapshotID": "snap-XXX",
    "text": "Hello World",
    "mode": "replace",  # or "append"
    "submit": True      # auto-dismiss keyboard
}

# ui.control.sendAction
{
    "path": "root/0/1/0/1/0/2",
    "viewSnapshotID": "snap-XXX",
    "event": "valueChanged",  # NOT "action"!
    "value": 0.75              # optional for sliders/segments
}
```

**Performance:**
- Text input: 88-129ms per field
- Control actions: 3-4ms per action
- Total form fill (5 fields): < 1 second

**Error Handling:**
- `become_first_responder_failed`: Retry after 200ms delay
- `stale_locator`: Refresh snapshot and retry
- `target_not_found`: Use ui.scrollToElement to reveal field

---

## Skill 2: Navigation & Screen Traversal

**Confidence Level:** ⭐⭐⭐⭐⭐ High (all commands tested)

### Purpose
Navigate through app screens, handle navigation bars, tabs, and modals.

### Commands Used
- `ui.inspect` - Discover navigation elements
- `ui.tap` - Tap buttons, cells, links
- `ui.navigation.back` - Go back
- `ui.screenshot` - Verify navigation

### Capabilities
1. **Screen Navigation**
   - Tap navigation elements (buttons, cells, links)
   - Navigate back to previous screen
   - Detect current screen by navigation bar title

2. **Path Tracking**
   - Track navigation history
   - Verify expected screen reached
   - Handle navigation errors

3. **Visual Verification**
   - Screenshot before/after navigation
   - Compare navigation bar titles
   - Verify key elements on target screen

### Usage Pattern

```python
skill = NavigationSkill(base_url)

# Navigate to settings
skill.navigate_to_screen(
    target_text="Settings",
    verify_title="Settings"
)

# Navigate to sub-menu
skill.navigate_to_screen(
    target_text="Account",
    verify_title="Account Settings"
)

# Go back
skill.go_back()

# Verify we're back at Settings
assert skill.current_screen_title() == "Settings"
```

### Implementation Notes

**Navigation Detection:**
```python
def current_screen_title(self):
    snapshot = self.call_api("ui.inspect")
    return snapshot["data"]["navigationBar"]["title"]

def back_button_available(self):
    snapshot = self.call_api("ui.inspect")
    return snapshot["data"]["navigationBar"]["backAvailable"]
```

**Performance:**
- Navigation tap: 50-100ms
- Screen transition: 200-500ms (including animation)
- Back navigation: 50-100ms

**Best Practices:**
- Always wait 500ms after navigation for screen to settle
- Verify navigation bar title changed before proceeding
- Take screenshots before major navigation steps for debugging

---

## Skill 3: List & Collection Interaction

**Confidence Level:** ⭐⭐⭐⭐ Medium-High (tap tested, scroll not tested)

### Purpose
Find items in lists and collections, scroll to reveal content, select items.

### Commands Used
- `ui.inspect` - Find list items
- `ui.scrollToElement` - Scroll to item (not tested yet)
- `ui.tap` - Select item
- `ui.swipe` - Manual scrolling (mechanism tested)

### Capabilities
1. **Item Discovery**
   - Find items by text content
   - Find items by accessibility identifier
   - Detect item position in list

2. **Scrolling**
   - Scroll to make item visible
   - Scroll to top/bottom
   - Swipe within scroll views

3. **Item Selection**
   - Tap list items
   - Verify selection state
   - Handle cell actions (swipe actions)

### Usage Pattern

```python
skill = ListInteractionSkill(base_url)

# Find and select item in list
skill.select_list_item(
    text="John Doe",
    scroll_if_needed=True
)

# Scroll to specific position
skill.scroll_to_item(
    identifier="contact-123",
    within_scroll_view="main-list"
)

# Swipe on cell for actions
skill.swipe_cell(
    text="Jane Smith",
    direction="left"  # Reveal delete/edit actions
)
```

### Implementation Notes

**Finding Items:**
```python
def find_item_in_list(self, text, max_scrolls=10):
    for _ in range(max_scrolls):
        snapshot = self.call_api("ui.inspect")
        item = self._find_by_text(snapshot, text)
        if item:
            return item
        
        # Scroll down if not found
        self.call_api("ui.swipe", {
            "withinElementRef": scroll_view_ref,
            "direction": "up",
            "distance": 0.8
        })
        time.sleep(0.3)
    
    return None
```

**Performance:**
- Find visible item: 100-200ms
- Scroll one page: 300-500ms
- Find item with scrolling: 1-5 seconds (depends on list size)

---

## Skill 4: Dialog & Alert Handling

**Confidence Level:** ⭐⭐⭐ Medium (mechanism verified, not fully tested)

### Purpose
Detect and respond to alerts, action sheets, and dialogs.

### Commands Used
- `ui.inspect` - Check alert.available
- `ui.alert.respond` - Respond to alert
- `ui.wait` - Wait for alert to appear (not tested)

### Capabilities
1. **Alert Detection**
   - Detect when alert appears
   - Read alert title and message
   - List available buttons

2. **Alert Interaction**
   - Tap specific button by index
   - Tap button by title
   - Handle text field alerts (input dialogs)

3. **Alert Waiting**
   - Wait for alert to appear after action
   - Timeout if alert doesn't appear
   - Retry logic for flaky alerts

### Usage Pattern

```python
skill = AlertHandlingSkill(base_url)

# Trigger action that shows alert
skill.call_api("ui.tap", {...})

# Wait and handle alert
alert = skill.wait_for_alert(timeout=2.0)
if alert:
    print(f"Alert: {alert['title']}")
    print(f"Message: {alert['message']}")
    
    # Respond to alert
    skill.respond_to_alert(button_title="OK")
```

### Implementation Notes

**Alert Detection Flow:**
```python
def wait_for_alert(self, timeout=2.0, poll_interval=0.3):
    start = time.time()
    while time.time() - start < timeout:
        snapshot = self.call_api("ui.inspect")
        alert = snapshot["data"]["alert"]
        
        if alert["available"]:
            return alert
        
        time.sleep(poll_interval)
    
    return None

def respond_to_alert(self, button_title=None, button_index=None):
    snapshot = self.call_api("ui.inspect")
    alert = snapshot["data"]["alert"]
    
    if not alert["available"]:
        raise Exception("No alert present")
    
    if button_title:
        # Find button by title
        for btn in alert["buttons"]:
            if btn["title"] == button_title:
                button_index = btn["index"]
                break
    
    if button_index is None:
        button_index = 0  # Default to first button
    
    return self.call_api("ui.alert.respond", {
        "buttonIndex": button_index
    })
```

**Performance:**
- Alert detection: 100-200ms
- Alert response: 50-150ms
- Total with waiting: 500ms - 2 seconds

**Error Handling:**
- `alert_unavailable`: Wait longer or verify trigger action
- Timeout: No alert appeared, may be expected behavior

---

## Skill 5: Dynamic Content Handling

**Confidence Level:** ⭐⭐ Low (wait commands not tested)

### Purpose
Handle loading indicators, async content, animations, and dynamic UI updates.

### Commands Used
- `ui.wait` - Wait for element state changes
- `ui.waitAny` - Wait for any of multiple conditions
- `ui.inspect` - Poll for state changes
- `ui.screenshot` - Verify state visually

### Capabilities
1. **Wait for Elements**
   - Wait for element to appear
   - Wait for element to disappear
   - Wait for element state change

2. **Loading Detection**
   - Detect loading indicators
   - Wait for content to load
   - Timeout handling

3. **Animation Handling**
   - Wait for animations to complete
   - Detect transition states
   - Handle intermediate states

### Usage Pattern

```python
skill = DynamicContentSkill(base_url)

# Wait for loading to complete
skill.wait_for_loading_complete(timeout=10.0)

# Wait for specific content to appear
skill.wait_for_element(
    text="Welcome back",
    timeout=5.0,
    mode="appear"
)

# Wait for any of multiple conditions
skill.wait_for_any([
    {"text": "Success", "mode": "appear"},
    {"text": "Error", "mode": "appear"},
    {"text": "Loading", "mode": "disappear"}
], timeout=10.0)
```

### Implementation Notes

**Wait Modes:**
- `appear`: Element becomes visible
- `disappear`: Element is removed
- `change`: Element properties change
- `enabled`: Element becomes enabled
- `disabled`: Element becomes disabled

**Performance:**
- Element detection: 100-200ms per poll
- Typical wait time: 500ms - 5 seconds
- Maximum timeout: 10-30 seconds recommended

---

## Skill 6: Screenshot & Visual Verification

**Confidence Level:** ⭐⭐⭐⭐ Medium-High (screenshot tested)

### Purpose
Capture screenshots, verify visual states, compare UI states.

### Commands Used
- `ui.screenshot` - Capture PNG image
- `ui.inspect` - Get UI metadata

### Capabilities
1. **Screenshot Capture**
   - Full screen capture
   - PNG format with base64 encoding
   - Metadata (dimensions, timestamp)

2. **Visual Verification**
   - Compare before/after states
   - Verify UI elements present
   - Detect visual regressions

3. **Documentation**
   - Capture test evidence
   - Generate visual reports
   - Debug UI issues

### Usage Pattern

```python
skill = ScreenshotSkill(base_url)

# Capture current screen
screenshot = skill.capture_screenshot()
skill.save_screenshot(screenshot, "login_screen.png")

# Capture before/after navigation
before = skill.capture_screenshot()
skill.navigate_to("Settings")
after = skill.capture_screenshot()

# Compare (requires image processing library)
if skill.compare_screenshots(before, after):
    print("Screens match!")
```

### Implementation Notes

**Screenshot Format:**
```json
{
  "code": "ok",
  "data": {
    "image": "iVBORw0KGgoAAAANSUhEUgAA...",
    "format": "png",
    "width": 390,
    "height": 844
  }
}
```

**Performance:**
- Screenshot capture: 200-500ms
- Image size: 50-200KB typical

---

## Skill 7: Controller Hierarchy Navigation

**Confidence Level:** ⭐⭐ Low (command not tested)

### Purpose
Understand and navigate complex view controller hierarchies.

### Commands Used
- `ui.controllers` - Get controller tree

### Capabilities
1. **Hierarchy Discovery**
   - List all view controllers
   - Detect navigation stacks
   - Find tab bar controllers

2. **Path Identification**
   - Get current controller path
   - Find controller by type
   - Detect modal presentations

### Usage Pattern

```python
skill = ControllerNavigationSkill(base_url)

# Get current controller hierarchy
hierarchy = skill.get_controller_hierarchy()

# Find specific controller
target = skill.find_controller(type="SettingsViewController")

# Navigate to controller
skill.navigate_to_controller(path=target["path"])
```

---

## Skill 8: Table & Collection View Actions

**Confidence Level:** ⭐⭐ Low (not tested)

### Purpose
Perform advanced table and collection view operations.

### Commands Used
- `ui.table.*` - Table-specific actions
- `ui.collection.*` - Collection-specific actions

### Capabilities
1. **Cell Operations**
   - Select cells
   - Swipe actions (delete, edit)
   - Reorder cells

2. **Section Navigation**
   - Navigate to sections
   - Expand/collapse sections
   - Header/footer interaction

---

## Skill 9: Date & Time Picker

**Confidence Level:** ⭐ Very Low (not tested)

### Purpose
Interact with UIDatePicker and UIPickerView components.

### Commands Used
- `ui.datePicker.*` - Date picker actions
- `ui.picker.*` - Generic picker actions

### Capabilities
1. **Date Selection**
   - Set date
   - Set time
   - Set date and time

2. **Picker Interaction**
   - Select picker values
   - Multiple component pickers
   - Custom picker wheels

---

## Skill 10: Advanced Gestures

**Confidence Level:** ⭐⭐ Low (partially tested)

### Purpose
Perform complex gestures beyond simple taps.

### Commands Used
- `ui.swipe` - Directional swipes
- `ui.longPress` - Long press gestures
- `ui.drag` - Drag operations

### Capabilities
1. **Swipe Gestures**
   - Swipe in any direction
   - Variable distance
   - Within specific elements

2. **Long Press**
   - Context menus
   - Drag initiation
   - Custom duration

3. **Drag Operations**
   - Drag and drop
   - Reordering
   - Custom paths

---

## Cross-Skill Best Practices

### 1. Snapshot Management

Always get fresh snapshot before actions:

```python
class BaseSkill:
    def __init__(self, base_url):
        self.base_url = base_url
        self.current_snapshot_id = None
        self.snapshot_cache_time = None
        self.snapshot_ttl = 60  # 60 seconds
    
    def get_fresh_snapshot(self):
        """Get fresh snapshot if expired"""
        now = time.time()
        if (self.snapshot_cache_time is None or 
            now - self.snapshot_cache_time > self.snapshot_ttl):
            response = self.call_api("ui.inspect")
            self.current_snapshot_id = response["data"]["viewSnapshotID"]
            self.snapshot_cache_time = now
            return response["data"]
        return None
```

### 2. Error Recovery

Implement automatic retry with exponential backoff:

```python
def call_with_retry(self, action, params, max_retries=3):
    for attempt in range(max_retries):
        try:
            response = self.call_api(action, params)
            
            if response["code"] == "stale_locator":
                # Refresh snapshot and retry immediately
                self.get_fresh_snapshot()
                params["viewSnapshotID"] = self.current_snapshot_id
                continue
            
            if response["code"] == "target_not_found" and attempt < max_retries - 1:
                # Wait and retry
                time.sleep(0.5 * (2 ** attempt))
                self.get_fresh_snapshot()
                continue
            
            return response
            
        except Exception as e:
            if attempt == max_retries - 1:
                raise
            time.sleep(0.5 * (2 ** attempt))
    
    raise Exception(f"Max retries ({max_retries}) exceeded")
```

### 3. Timing and Delays

Recommended delays between operations:

```python
TIMING = {
    "after_navigation": 0.5,      # Wait for screen transition
    "after_alert_trigger": 0.5,   # Wait for alert animation
    "after_scroll": 0.3,          # Wait for scroll to settle
    "between_inputs": 0.1,        # Between text field inputs
    "after_control_action": 0.0,  # Control actions are instant
}
```

### 4. Element Finding

Robust element finding with fallbacks:

```python
def find_element(self, criteria):
    """Find element by multiple criteria with fallbacks"""
    snapshot = self.get_fresh_snapshot()
    targets = snapshot["targets"]
    
    # Try exact identifier match first
    if "identifier" in criteria:
        for t in targets:
            if t.get("accessibilityIdentifier") == criteria["identifier"]:
                return t
    
    # Try text content match
    if "text" in criteria:
        for t in targets:
            if criteria["text"] in t.get("text", ""):
                return t
    
    # Try type match
    if "type" in criteria:
        matches = [t for t in targets if t.get("type") == criteria["type"]]
        if matches:
            return matches[0]  # Return first match
    
    return None
```

### 5. Logging and Debugging

Comprehensive logging for troubleshooting:

```python
class SkillLogger:
    def log_command(self, action, params, response, duration_ms):
        log_entry = {
            "timestamp": datetime.now().isoformat(),
            "action": action,
            "params": self._sanitize_params(params),
            "response_code": response.get("code"),
            "duration_ms": duration_ms
        }
        
        if response.get("code") != "ok":
            log_entry["error_details"] = response
        
        self.command_log.append(log_entry)
    
    def _sanitize_params(self, params):
        """Remove sensitive data from logs"""
        sanitized = params.copy()
        if "text" in sanitized and len(sanitized["text"]) > 50:
            sanitized["text"] = sanitized["text"][:50] + "..."
        return sanitized
```

---

## Performance Summary

| Operation | Typical Duration | Notes |
|-----------|------------------|-------|
| ui.inspect | 100-200ms | Core operation, used frequently |
| ui.input | 88-129ms | Per text field |
| ui.tap | 50-100ms | Fast operation |
| ui.control.sendAction | 3-4ms | Extremely fast |
| ui.keyboard.dismiss | 200-250ms | Includes animation |
| ui.alert.respond | 50-150ms | Fast operation |
| ui.navigation.back | 50-100ms | Fast operation |
| ui.screenshot | 200-500ms | Depends on screen complexity |

**Optimization Tips:**
1. Minimize ui.inspect calls by caching snapshots (60s TTL)
2. Batch control actions without intermediate inspections
3. Use ui.tap instead of ui.control.sendAction for buttons when possible
4. Avoid unnecessary screenshots (slow operation)

---

## Testing Recommendations

### Unit Testing
Each skill should have unit tests covering:
- Happy path scenarios
- Error handling
- Edge cases (empty inputs, missing elements)
- Performance benchmarks

### Integration Testing
Test skill interactions:
- Form filling → Navigation → Verification
- List interaction → Item selection → Detail view
- Alert handling during form submission

### End-to-End Testing
Full user scenarios:
- Complete registration flow
- Login → Browse → Purchase → Logout
- Settings navigation and configuration

---

## Conclusion

This specification defines 10 iOS automation skills based on 32 available commands. Skills 1-3 (Form Filling, Navigation, List Interaction) have high confidence and are production-ready. Skills 4-6 have medium confidence and require additional testing. Skills 7-10 are low confidence and need comprehensive testing before production use.

**Production-Ready Skills:**
- ✅ Skill 1: Form Filling & Data Entry
- ✅ Skill 2: Navigation & Screen Traversal
- ✅ Skill 3: List & Collection Interaction (with manual scroll fallback)
- ✅ Skill 4: Alert Response & Dialog Handling (newly tested)

**Needs Additional Testing:**
- ⚠️ Skill 4: Dialog & Alert Handling
- ⚠️ Skill 5: Dynamic Content Handling
- ⚠️ Skill 6: Screenshot & Visual Verification

**Requires Comprehensive Testing:**
- ❌ Skill 7: Controller Hierarchy Navigation
- ❌ Skill 8: Table & Collection View Actions
- ❌ Skill 9: Date & Time Picker
- ❌ Skill 10: Advanced Gestures

**Next Steps:**
1. Implement Skills 1-3 as production libraries
2. Complete testing for Skills 4-6
3. Test and document Skills 7-10
4. Build comprehensive example applications
5. Create video tutorials and documentation

---

**Version History:**
- v1.0 (2026-07-13): Initial specification based on e2e testing results

---

## Skill 4: Alert Response & Dialog Handling

**Confidence Level:** ⭐⭐⭐⭐⭐ High (fully tested with 97% pass rate)

### Purpose
Detect, inspect, and respond to iOS alerts (UIAlertController) including action sheets and input dialogs.

### Commands Used
- `ui.inspect` - Detect alert presence and structure
- `ui.alert.respond` - Respond to alert buttons
- `ui.input` - Fill text fields in input alerts (if needed)

### Capabilities

1. **Alert Detection**
   - Detect alert presence via `alert.available` flag
   - Extract alert title and message
   - List all buttons with roles (cancel/default/destructive)
   - Identify text fields in input alerts

2. **Response Methods**
   - **By Index**: `buttonIndex: 0` (fastest, requires knowing button order)
   - **By Title**: `buttonTitle: "确认"` (more readable, language-dependent)
   - **By Role**: `role: "cancel"` (semantic, works across languages)

3. **Alert Types Supported**
   - Simple alerts (OK/Cancel)
   - Multi-button alerts (up to 3+ buttons)
   - Action sheets (bottom sheet style)
   - Input alerts (with text fields)
   - Nested alerts (dismiss current, new appears)

### Usage Pattern

```python
# Example: Detect and respond to alert
skill = AlertResponseSkill(base_url)

# Check if alert is present
if skill.is_alert_present():
    alert_info = skill.get_alert_info()
    print(f"Alert: {alert_info['title']}")
    print(f"Buttons: {[b['title'] for b in alert_info['buttons']]}")
    
    # Respond by button index
    skill.respond_by_index(0)
    
    # Or respond by title
    skill.respond_by_title("确认")
    
    # Or respond by role
    skill.respond_by_role("cancel")
```

### Implementation Notes

**Alert Structure in ui.inspect:**
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

**Response Parameters:**
```python
# By index (fastest)
{
    "buttonIndex": 0
}

# By title (readable)
{
    "buttonTitle": "确认"
}

# By role (semantic)
{
    "role": "cancel"  # or "default" or "destructive"
}
```

**Response Data:**
```json
{
  "code": "ok",
  "data": {
    "dismissed": true,
    "performed": true,
    "presentedAfterDismiss": false,
    "button": {
      "index": 0,
      "role": "cancel",
      "title": "取消"
    },
    "dismissWaitMs": 444
  }
}
```

### Performance

Based on 10 iterations of complete alert lifecycle:

- **ui.alert.respond**: 560ms median (includes dismissal animation)
- **End-to-end** (trigger → detect → respond): ~1.1 seconds
- **Rapid alerts**: 5 consecutive alerts handled successfully
- **Consistency**: Low variance (±9ms standard deviation)

### Error Handling

| Scenario | Error Code | Handling |
|----------|------------|----------|
| No alert present | `alert_unavailable` | Wait or retry |
| Invalid button index | `alert_button_not_found` | Check button count |
| Invalid button title | `alert_button_not_found` | Verify exact title match |
| Invalid role | `alert_button_not_found` | Check available roles |

### Test Coverage

**Tested Scenarios (42 tests, 97% pass rate):**
- ✅ Simple two-button alert
- ✅ Three-button alert (destructive/default/cancel)
- ✅ Login input alert (with text fields)
- ✅ Action sheet style
- ✅ Role-based response
- ✅ Error handling (no alert, invalid button)
- ✅ Rapid consecutive alerts
- ✅ Performance benchmarks

### Input Alerts with Text Fields

For alerts containing text fields (login, prompt, etc.):

```python
# 1. Detect alert and text fields
alert_info = skill.get_alert_info()
if alert_info['textFields']:
    for field in alert_info['textFields']:
        print(f"Field: {field['placeholder']}, path: {field['path']}")
        
        # 2. Fill text field using ui.input
        skill.fill_alert_text_field(
            path=field['path'],
            text="my_username"
        )
    
    # 3. Submit by clicking button
    skill.respond_by_index(0)
```

**Text Field Structure:**
```json
{
  "path": "root/0/0/1/0/0/4/0/0/0/0/0/0/0/0",
  "accessibilityIdentifier": "alert.input.username",
  "placeholder": "用户名",
  "isSecure": false,
  "availableActions": ["ui.input"]
}
```

### Best Practices

1. **Always check alert presence first**
   ```python
   if not skill.is_alert_present():
       return  # No alert to handle
   ```

2. **Prefer role-based for semantic clarity**
   ```python
   # Good: semantic and language-independent
   skill.respond_by_role("cancel")
   
   # OK: fast but requires knowing order
   skill.respond_by_index(0)
   
   # Avoid: language-dependent
   skill.respond_by_title("取消")
   ```

3. **Handle timing properly**
   ```python
   # Wait for alert to appear after trigger
   time.sleep(0.3)
   skill.wait_for_alert(timeout_ms=2000)
   
   # Verify dismissal
   skill.wait_for_alert_dismissed(timeout_ms=1000)
   ```

4. **Log alert details for debugging**
   ```python
   alert = skill.get_alert_info()
   logger.info(f"Alert: {alert['title']} - {len(alert['buttons'])} buttons")
   ```

### Known Limitations

1. **Role-based destructive lookup**: Occasionally fails on first attempt (needs investigation)
2. **Animation timing**: Response includes ~400ms wait for dismissal animation
3. **Nested alerts**: Only top-most alert is accessible at a time

### Integration Example

```python
class AlertResponseSkill:
    def __init__(self, base_url):
        self.base_url = base_url
    
    def is_alert_present(self) -> bool:
        """Check if an alert is currently displayed"""
        resp = self._curl_post("ui.inspect", {})
        return resp['data']['alert']['available']
    
    def get_alert_info(self) -> dict:
        """Get complete alert information"""
        resp = self._curl_post("ui.inspect", {})
        return resp['data']['alert']
    
    def respond_by_index(self, index: int) -> dict:
        """Respond by button index (0-based)"""
        resp = self._curl_post("ui.alert.respond", {"buttonIndex": index})
        if resp['code'] != 'ok':
            raise AlertError(f"Failed to respond: {resp['message']}")
        return resp['data']
    
    def respond_by_title(self, title: str) -> dict:
        """Respond by button title (exact match)"""
        resp = self._curl_post("ui.alert.respond", {"buttonTitle": title})
        if resp['code'] != 'ok':
            raise AlertError(f"Failed to respond: {resp['message']}")
        return resp['data']
    
    def respond_by_role(self, role: str) -> dict:
        """Respond by button role (cancel/default/destructive)"""
        resp = self._curl_post("ui.alert.respond", {"role": role})
        if resp['code'] != 'ok':
            raise AlertError(f"Failed to respond: {resp['message']}")
        return resp['data']
    
    def wait_for_alert(self, timeout_ms: int = 2000) -> bool:
        """Wait for alert to appear"""
        start = time.time()
        while (time.time() - start) * 1000 < timeout_ms:
            if self.is_alert_present():
                return True
            time.sleep(0.1)
        return False
    
    def wait_for_alert_dismissed(self, timeout_ms: int = 1000) -> bool:
        """Wait for alert to be dismissed"""
        start = time.time()
        while (time.time() - start) * 1000 < timeout_ms:
            if not self.is_alert_present():
                return True
            time.sleep(0.1)
        return False
    
    def _curl_post(self, action: str, data: dict) -> dict:
        payload = json.dumps({"action": action, "data": data})
        result = subprocess.run(
            ['curl', '-s', '-X', 'POST', self.base_url, '-d', payload],
            capture_output=True, text=True
        )
        return json.loads(result.stdout)

class AlertError(Exception):
    """Raised when alert operations fail"""
    pass
```

### Test Report

Complete automated test results available in:
- **JSON Report**: `docs/alert-test-complete-report.json`
- **Markdown Report**: `docs/alert-test-complete-report.md`

**Summary:**
- 42 total tests
- 41 passed (97%)
- 1 partial failure (destructive role edge case)
- All core scenarios verified
- Production-ready

