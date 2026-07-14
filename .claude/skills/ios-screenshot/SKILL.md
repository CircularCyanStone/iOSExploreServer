---
name: ios-screenshot
description: |
  iOS App automation for capturing screenshots and visual verification.
  
  Use this skill when the user needs to capture app screenshots, verify visual states,
  compare before/after UI changes, or document test results in iOS applications.
  
  Must explicitly mention iOS, iPhone, iPad, screenshots, or visual verification to trigger.
  
  Based on iOSDriver MCP Server with full screenshot capability testing.
---

# iOS Screenshot & Visual Verification

## Purpose

Capture screenshots of iOS app screens in PNG format for visual verification, test documentation, debugging, and UI state comparison.

## When to Use

Use this skill when you need to:
- Capture current app screen state
- Document test execution steps visually
- Compare before/after states of UI changes
- Verify visual regressions
- Debug UI layout issues
- Generate visual reports
- Capture evidence of bugs or unexpected states

## Prerequisites

- **iOSDriver MCP Server** connected and active
- **iOS App** running on simulator or physical device
- **Port 38321** accessible
- Sufficient disk space for PNG images (50-200KB per screenshot)

## Commands Used

| Command | Purpose | Performance |
|---------|---------|-------------|
| `ui.screenshot` | Capture PNG screenshot with base64 encoding | 200-500ms |
| `ui.inspect` | Get UI metadata for context | 100-200ms |

## Capabilities

### 1. Screenshot Capture

**Capture Current Screen:**
```bash
curl -X POST http://localhost:38321/ -d '{"action":"ui.screenshot"}'
```

**Response:**
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

**Save to File:**
```bash
curl -s -X POST http://localhost:38321/ -d '{"action":"ui.screenshot"}' | jq -r '.data.image' | base64 -d > screenshot.png
```

### 2. Visual Verification

Capture screenshots at key points:
- Before navigation
- After form submission
- After alert dismissal
- During animation (mid-state)
- Error states
- Success confirmations

### 3. Screenshot Metadata

Each screenshot includes:
- **Format:** Always PNG (lossless)
- **Width:** Device screen width in pixels
- **Height:** Device screen height in pixels
- **Encoding:** Base64 string for easy transmission

## Usage Examples

### Example 1: Single Screenshot

```bash
#!/bin/bash
# Capture and save screenshot

echo "Capturing screenshot..."
RESULT=$(curl -s -X POST http://localhost:38321/ -d '{"action":"ui.screenshot"}')

# Extract image data
IMAGE=$(echo $RESULT | jq -r '.data.image')
WIDTH=$(echo $RESULT | jq -r '.data.width')
HEIGHT=$(echo $RESULT | jq -r '.data.height')

# Save to file
echo $IMAGE | base64 -d > screenshot.png

echo "✅ Saved screenshot.png (${WIDTH}x${HEIGHT})"
```

### Example 2: Before/After Comparison

```bash
#!/bin/bash
# Capture screenshots before and after an action

# Capture before state
echo "Capturing BEFORE state..."
curl -s -X POST http://localhost:38321/ -d '{"action":"ui.screenshot"}' | \
  jq -r '.data.image' | base64 -d > before.png

# Perform action (e.g., toggle switch)
echo "Performing action..."
curl -s -X POST http://localhost:38321/ -d '{
  "action": "ui.control.sendAction",
  "data": {
    "path": "root/0/2/1/0",
    "viewSnapshotID": "snap-123",
    "event": "valueChanged"
  }
}' > /dev/null

# Small delay for UI update
sleep 0.2

# Capture after state
echo "Capturing AFTER state..."
curl -s -X POST http://localhost:38321/ -d '{"action":"ui.screenshot"}' | \
  jq -r '.data.image' | base64 -d > after.png

echo "✅ Saved before.png and after.png"
echo "Compare with: open before.png after.png"
```

### Example 3: Navigation Flow Documentation

```bash
#!/bin/bash
# Capture each step of navigation flow

capture_step() {
  local step_name=$1
  local filename="${step_name}.png"
  
  echo "📸 Capturing: $step_name"
  curl -s -X POST http://localhost:38321/ -d '{"action":"ui.screenshot"}' | \
    jq -r '.data.image' | base64 -d > "$filename"
  echo "✅ Saved: $filename"
}

# Document complete flow
capture_step "01_home"

# Navigate to settings
curl -s -X POST http://localhost:38321/ -d '{"action":"ui.tap","data":{...}}' > /dev/null
sleep 0.5
capture_step "02_settings"

# Navigate to account
curl -s -X POST http://localhost:38321/ -d '{"action":"ui.tap","data":{...}}' > /dev/null
sleep 0.5
capture_step "03_account"

# Navigate to privacy
curl -s -X POST http://localhost:38321/ -d '{"action":"ui.tap","data":{...}}' > /dev/null
sleep 0.5
capture_step "04_privacy"

echo "✅ Flow documented with 4 screenshots"
```

### Example 4: Alert Screenshot

```bash
#!/bin/bash
# Capture alert appearance

# Trigger alert
curl -s -X POST http://localhost:38321/ -d '{"action":"ui.tap","data":{...}}' > /dev/null
sleep 0.3

# Capture alert
curl -s -X POST http://localhost:38321/ -d '{"action":"ui.screenshot"}' | \
  jq -r '.data.image' | base64 -d > alert_screenshot.png

echo "✅ Alert captured: alert_screenshot.png"
```

### Example 5: Test Evidence Collection

```bash
#!/bin/bash
# Collect screenshots for test report

TEST_NAME="login_flow"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_DIR="test_evidence/${TEST_NAME}_${TIMESTAMP}"

mkdir -p "$OUTPUT_DIR"

capture_evidence() {
  local step=$1
  local filename="${OUTPUT_DIR}/step_${step}.png"
  
  curl -s -X POST http://localhost:38321/ -d '{"action":"ui.screenshot"}' | \
    jq -r '.data.image' | base64 -d > "$filename"
  
  # Also capture UI metadata
  curl -s -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}' > "${OUTPUT_DIR}/step_${step}_metadata.json"
  
  echo "✅ Evidence collected: step $step"
}

# Test steps
capture_evidence "01_initial_state"
# ... perform test actions ...
capture_evidence "02_username_filled"
# ... perform test actions ...
capture_evidence "03_password_filled"
# ... perform test actions ...
capture_evidence "04_login_success"

echo "✅ Test evidence saved to: $OUTPUT_DIR"
```

### Example 6: Screenshot with Metadata

```bash
#!/bin/bash
# Capture screenshot with UI metadata for context

TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Capture screenshot
SCREENSHOT=$(curl -s -X POST http://localhost:38321/ -d '{"action":"ui.screenshot"}')
echo $SCREENSHOT | jq -r '.data.image' | base64 -d > "screen_${TIMESTAMP}.png"

# Capture metadata
METADATA=$(curl -s -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}')

# Extract key info
TITLE=$(echo $METADATA | jq -r '.data.navigationBar.title')
ALERT=$(echo $METADATA | jq -r '.data.alert.available')
ELEMENTS=$(echo $METADATA | jq '.data.targets | length')

# Create metadata file
cat > "screen_${TIMESTAMP}_info.json" <<EOF
{
  "timestamp": "$TIMESTAMP",
  "navigation_title": "$TITLE",
  "alert_visible": $ALERT,
  "interactive_elements": $ELEMENTS
}
EOF

echo "✅ Screenshot and metadata saved with timestamp: $TIMESTAMP"
```

### Example 7: Visual Regression Testing Workflow

```bash
#!/bin/bash
# Automated visual regression testing workflow

TEST_NAME="settings_screen"
BASELINE_DIR="test_baselines"
CURRENT_DIR="test_current"
DIFF_DIR="test_diffs"

mkdir -p "$BASELINE_DIR" "$CURRENT_DIR" "$DIFF_DIR"

# Capture current screenshot
capture_and_compare() {
  local screen_name=$1
  local baseline_file="${BASELINE_DIR}/${screen_name}.png"
  local current_file="${CURRENT_DIR}/${screen_name}.png"
  local diff_file="${DIFF_DIR}/${screen_name}_diff.png"
  
  echo "📸 Capturing: $screen_name"
  
  # Capture current state
  curl -s -X POST http://localhost:38321/ -d '{"action":"ui.screenshot"}' | \
    jq -r '.data.image' | base64 -d > "$current_file"
  
  # Check if baseline exists
  if [ -f "$baseline_file" ]; then
    echo "🔍 Comparing with baseline..."
    
    # Compare using ImageMagick (if available)
    if command -v compare &> /dev/null; then
      # Generate diff image
      compare -metric RMSE "$baseline_file" "$current_file" "$diff_file" 2>&1 | \
        tee "${DIFF_DIR}/${screen_name}_metric.txt"
      
      # Check if images are identical
      DIFF_METRIC=$(cat "${DIFF_DIR}/${screen_name}_metric.txt" | cut -d' ' -f1)
      
      if [ "$DIFF_METRIC" = "0" ]; then
        echo "✅ No visual changes detected"
        rm "$diff_file"  # Clean up identical diff
      else
        echo "⚠️ Visual differences detected: $DIFF_METRIC"
        echo "   Diff saved to: $diff_file"
      fi
    else
      echo "⚠️ ImageMagick not installed - manual comparison needed"
    fi
  else
    echo "📌 Creating baseline (first run)"
    cp "$current_file" "$baseline_file"
  fi
}

# Test flow: capture multiple screens
echo "Starting visual regression test: $TEST_NAME"

# Home screen
capture_and_compare "home"

# Navigate to settings
curl -s -X POST http://localhost:38321/ -d '{"action":"ui.tap","data":{...}}' > /dev/null
sleep 0.5

# Settings screen
capture_and_compare "settings"

# Navigate to account
curl -s -X POST http://localhost:38321/ -d '{"action":"ui.tap","data":{...}}' > /dev/null
sleep 0.5

# Account screen
capture_and_compare "account"

echo "✅ Visual regression test complete"
echo "   Baselines: $BASELINE_DIR"
echo "   Current: $CURRENT_DIR"
echo "   Diffs: $DIFF_DIR"
```

### Example 8: CI/CD Screenshot Storage

```bash
#!/bin/bash
# CI/CD-friendly screenshot capture and upload

CI_BUILD_ID="${CI_BUILD_ID:-local}"
CI_BRANCH="${CI_BRANCH:-main}"
ARTIFACT_DIR="artifacts/screenshots/${CI_BRANCH}/${CI_BUILD_ID}"

mkdir -p "$ARTIFACT_DIR"

capture_for_ci() {
  local step_name=$1
  local description=$2
  local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  
  # Capture screenshot
  local filename="${ARTIFACT_DIR}/${step_name}.png"
  curl -s -X POST http://localhost:38321/ -d '{"action":"ui.screenshot"}' | \
    jq -r '.data.image' | base64 -d > "$filename"
  
  # Capture metadata
  METADATA=$(curl -s -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}')
  
  # Generate manifest entry
  cat >> "${ARTIFACT_DIR}/manifest.json" <<EOF
{
  "step": "$step_name",
  "description": "$description",
  "timestamp": "$timestamp",
  "file": "${step_name}.png",
  "navigation_title": $(echo $METADATA | jq '.data.navigationBar.title'),
  "alert_visible": $(echo $METADATA | jq '.data.alert.available'),
  "build_id": "$CI_BUILD_ID",
  "branch": "$CI_BRANCH"
},
EOF
  
  echo "✅ Captured CI artifact: $step_name"
}

# Initialize manifest
echo "[" > "${ARTIFACT_DIR}/manifest.json"

# Capture test steps
capture_for_ci "01_launch" "App launch state"
# ... perform test actions ...
capture_for_ci "02_login" "Login screen"
# ... perform test actions ...
capture_for_ci "03_success" "Successful login"

# Close manifest array (remove trailing comma)
sed -i '' '$ s/,$//' "${ARTIFACT_DIR}/manifest.json"
echo "]" >> "${ARTIFACT_DIR}/manifest.json"

echo "✅ CI artifacts saved to: $ARTIFACT_DIR"
echo "   Upload command: aws s3 cp $ARTIFACT_DIR s3://bucket/screenshots/ --recursive"
```

## Parameters Reference

### ui.screenshot

**No parameters required.**

**Response:**
```json
{
  "code": "ok",
  "data": {
    "image": "iVBORw0KGgoAAAANSUhEUgAA...",  // Base64-encoded PNG
    "format": "png",                          // Always "png"
    "width": 390,                             // Screen width in pixels
    "height": 844                             // Screen height in pixels
  }
}
```

**Common Device Resolutions:**
- iPhone 17 Pro Max: 430×932
- iPhone 17 Pro: 393×852
- iPhone 17: 390×844
- iPad Pro 12.9": 1024×1366

## Error Handling

### Common Issues

#### 1. Large Image Data
**Issue:** Base64 strings can be large (50-200KB)

**Solution:**
- Stream directly to file instead of storing in variable
- Use `jq -r` to extract raw base64 string
- Decode immediately with `base64 -d`

**Example:**
```bash
# Good: Stream directly
curl -s -X POST http://localhost:38321/ -d '{"action":"ui.screenshot"}' | jq -r '.data.image' | base64 -d > file.png

# Bad: Store in variable (memory intensive)
IMAGE=$(curl -s -X POST http://localhost:38321/ -d '{"action":"ui.screenshot"}' | jq -r '.data.image')
echo $IMAGE | base64 -d > file.png
```

#### 2. Screenshot Timing
**Issue:** Screenshot captured during animation or transition

**Solution:**
- Wait 500ms after navigation/actions
- Ensure animations complete
- Capture at stable state

**Example:**
```bash
curl -X POST http://localhost:38321/ -d '{"action":"ui.tap","data":{...}}'
sleep 0.5  # Wait for transition
curl -X POST http://localhost:38321/ -d '{"action":"ui.screenshot"}'
```

#### 3. Disk Space
**Issue:** Many screenshots fill disk quickly

**Solution:**
- Clean up old screenshots regularly
- Compress images if needed (PNG → JPG)
- Store only essential screenshots

## Performance Characteristics

| Operation | Duration | Image Size |
|-----------|----------|------------|
| **ui.screenshot** | 200-500ms | 50-200KB typical |
| **Save to file** | 10-50ms | Depends on disk speed |
| **Base64 decode** | 5-10ms | Minimal overhead |

**Total capture + save:** ~250-550ms

**Factors affecting speed:**
- Screen complexity (more UI elements = larger file)
- Device resolution (higher resolution = larger file)
- Disk I/O speed

## Best Practices

### 1. Use Descriptive Filenames

```bash
# Good: Descriptive with timestamp
screenshot_login_success_20260714_091234.png

# OK: Sequential numbering
test_step_01.png

# Bad: Generic names (will be overwritten)
screenshot.png
```

### 2. Capture at Stable States

```bash
# Good: Wait for stability
curl -X POST http://localhost:38321/ -d '{"action":"ui.tap","data":{...}}'
sleep 0.5  # Wait for transition
curl -X POST http://localhost:38321/ -d '{"action":"ui.screenshot"}'

# Bad: Immediate capture (may catch mid-animation)
curl -X POST http://localhost:38321/ -d '{"action":"ui.tap","data":{...}}'
curl -X POST http://localhost:38321/ -d '{"action":"ui.screenshot"}'
```

### 3. Organize Screenshots

```bash
# Create organized directory structure
mkdir -p screenshots/{login,settings,alerts}
curl -s -X POST http://localhost:38321/ -d '{"action":"ui.screenshot"}' | \
  jq -r '.data.image' | base64 -d > screenshots/login/step1.png
```

### 4. Include Metadata

```bash
# Save metadata alongside screenshot
curl -s -X POST http://localhost:38321/ -d '{"action":"ui.screenshot"}' | jq -r '.data.image' | base64 -d > screen.png
curl -s -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}' > screen_metadata.json
```

### 5. Automate Cleanup

```bash
# Clean screenshots older than 7 days
find screenshots/ -name "*.png" -mtime +7 -delete
```

## Limitations

### Known Limitations

1. **Format:** Only PNG format supported (no JPG, WebP, etc.)

2. **Resolution:** Captures at device's native resolution (no scaling options)

3. **Transparency:** Status bar and system UI included (no masking options)

4. **Timing:** No automatic wait for animations - must manually delay

5. **Comparison:** No built-in image comparison (requires external tools like ImageMagick)

6. **Performance:** Screenshot capture is relatively slow (200-500ms) compared to other commands

## Image Comparison Tools

For comparing screenshots, use external tools:

**ImageMagick:**
```bash
# Compare two images
compare before.png after.png diff.png

# Get similarity metric
compare -metric RMSE before.png after.png null: 2>&1
```

**Python with Pillow:**
```python
from PIL import Image
import numpy as np

img1 = np.array(Image.open('before.png'))
img2 = np.array(Image.open('after.png'))

# Calculate difference
diff = np.sum(np.abs(img1 - img2))
print(f"Difference: {diff}")
```

## Related Skills

- **ios-navigation** - Capture screenshots during navigation flows
- **ios-alert-handling** - Capture alert appearances
- **ios-form-filling** - Document form states
- **ios-dynamic-content** - Capture loading states

## Test Coverage

**Command Tested:** ✅ ui.screenshot (tested in multiple scenarios)

**Test Scenarios:**
- ✅ Capture normal screen
- ✅ Capture with alerts visible
- ✅ Capture during navigation
- ✅ Base64 encoding/decoding
- ✅ PNG file saving
- ✅ Metadata extraction (width, height)

## Production Readiness

✅ **Production Ready**

Screenshot capability is fully functional and tested across various scenarios. PNG format ensures lossless quality. Base64 encoding provides reliable transmission over HTTP. Safe for production use in test automation, debugging, and documentation workflows.
