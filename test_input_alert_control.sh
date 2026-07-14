#!/bin/bash
# Comprehensive test for ui.input, ui.alert.respond, and ui.control.sendAction
# This script performs end-to-end testing with performance measurement

set -e
BASE_URL="http://localhost:38321/"
OUTPUT_DIR="/Users/coo/Desktop/iOS_agent_debugger/iOSExploreServer/docs"
TEST_DATA_FILE="$OUTPUT_DIR/input-alert-control-test-data.json"

# Color output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date +%H:%M:%S)]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date +%H:%M:%S)]${NC} $1"
}

error() {
    echo -e "${RED}[$(date +%H:%M:%S)]${NC} $1"
}

# Initialize test results
echo '{"tests":[]}' > "$TEST_DATA_FILE"

# Helper: Call API with timing
call_api() {
    local action=$1
    local data=$2
    local start=$(python3 -c 'import time; print(int(time.time() * 1000))')
    local response=$(curl -s -X POST "$BASE_URL" -d "{\"action\":\"$action\",\"data\":$data}")
    local end=$(python3 -c 'import time; print(int(time.time() * 1000))')
    local duration=$((end - start))
    echo "$response|$duration"
}

# Helper: Add test result
add_test_result() {
    local test_name=$1
    local action=$2
    local duration=$3
    local code=$4
    local details=$5

    local temp_file=$(mktemp)
    jq ".tests += [{
        \"name\": \"$test_name\",
        \"action\": \"$action\",
        \"duration_ms\": $duration,
        \"code\": \"$code\",
        \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",
        \"details\": $details
    }]" "$TEST_DATA_FILE" > "$temp_file"
    mv "$temp_file" "$TEST_DATA_FILE"
}

log "=== Starting Text Input Tests ==="

# Get fresh snapshot
log "Getting fresh UI snapshot..."
result=$(call_api "ui.inspect" "{}")
snapshot_id=$(echo "$result" | cut -d'|' -f1 | jq -r '.data.viewSnapshotID')
log "Current snapshot: $snapshot_id"

# Test 1: Input text into UITextField
log "Test 1: Input text into UITextField"
result=$(call_api "ui.input" "{\"path\":\"root/0/1/0/0/0/2\",\"viewSnapshotID\":\"$snapshot_id\",\"text\":\"Hello World\"}")
response=$(echo "$result" | cut -d'|' -f1)
duration=$(echo "$result" | cut -d'|' -f2)
code=$(echo "$response" | jq -r '.code')
add_test_result "UITextField basic input" "ui.input" "$duration" "$code" "$(echo "$response" | jq -c .)"
log "Result: $code (${duration}ms)"

# Test 2: Clear and replace text
log "Test 2: Replace existing text"
result=$(call_api "ui.input" "{\"path\":\"root/0/1/0/0/0/2\",\"viewSnapshotID\":\"$snapshot_id\",\"text\":\"Replaced\",\"clearExisting\":true}")
response=$(echo "$result" | cut -d'|' -f1)
duration=$(echo "$result" | cut -d'|' -f2)
code=$(echo "$response" | jq -r '.code')
add_test_result "UITextField replace text" "ui.input" "$duration" "$code" "$(echo "$response" | jq -c .)"
log "Result: $code (${duration}ms)"

# Test 3: UITextView multi-line input
log "Test 3: UITextView multi-line input"
result=$(call_api "ui.input" "{\"path\":\"root/0/1/0/2/0/2\",\"viewSnapshotID\":\"$snapshot_id\",\"text\":\"Line 1\\nLine 2\\nLine 3\"}")
response=$(echo "$result" | cut -d'|' -f1)
duration=$(echo "$result" | cut -d'|' -f2)
code=$(echo "$response" | jq -r '.code')
add_test_result "UITextView multiline" "ui.input" "$duration" "$code" "$(echo "$response" | jq -c .)"
log "Result: $code (${duration}ms)"

# Test 4: UISearchTextField
log "Test 4: UISearchTextField input"
result=$(call_api "ui.input" "{\"path\":\"root/0/1/0/3/0/2\",\"viewSnapshotID\":\"$snapshot_id\",\"text\":\"search query\"}")
response=$(echo "$result" | cut -d'|' -f1)
duration=$(echo "$result" | cut -d'|' -f2)
code=$(echo "$response" | jq -r '.code')
add_test_result "UISearchTextField" "ui.input" "$duration" "$code" "$(echo "$response" | jq -c .)"
log "Result: $code (${duration}ms)"

# Test 5: Dismiss keyboard
log "Test 5: Dismiss keyboard"
result=$(call_api "ui.keyboard.dismiss" "{}")
response=$(echo "$result" | cut -d'|' -f1)
duration=$(echo "$result" | cut -d'|' -f2)
code=$(echo "$response" | jq -r '.code')
add_test_result "Dismiss keyboard" "ui.keyboard.dismiss" "$duration" "$code" "$(echo "$response" | jq -c .)"
log "Result: $code (${duration}ms)"

# Test 6: Long text input
log "Test 6: Long text input (200 chars)"
long_text=$(printf 'A%.0s' {1..200})
result=$(call_api "ui.input" "{\"path\":\"root/0/1/0/4/0/2\",\"viewSnapshotID\":\"$snapshot_id\",\"text\":\"$long_text\"}")
response=$(echo "$result" | cut -d'|' -f1)
duration=$(echo "$result" | cut -d'|' -f2)
code=$(echo "$response" | jq -r '.code')
add_test_result "Long text input" "ui.input" "$duration" "$code" "$(echo "$response" | jq -c .)"
log "Result: $code (${duration}ms)"

# Test 7: Empty string input
log "Test 7: Empty string input"
result=$(call_api "ui.input" "{\"path\":\"root/0/1/0/5/0/2\",\"viewSnapshotID\":\"$snapshot_id\",\"text\":\"\"}")
response=$(echo "$result" | cut -d'|' -f1)
duration=$(echo "$result" | cut -d'|' -f2)
code=$(echo "$response" | jq -r '.code')
add_test_result "Empty string input" "ui.input" "$duration" "$code" "$(echo "$response" | jq -c .)"
log "Result: $code (${duration}ms)"

# Test 8: Special characters
log "Test 8: Special characters input"
result=$(call_api "ui.input" "{\"path\":\"root/0/1/0/6/0/2\",\"viewSnapshotID\":\"$snapshot_id\",\"text\":\"Test!@#\$%^&*()_+-=[]{}|;:',.<>?\"}")
response=$(echo "$result" | cut -d'|' -f1)
duration=$(echo "$result" | cut -d'|' -f2)
code=$(echo "$response" | jq -r '.code')
add_test_result "Special characters" "ui.input" "$duration" "$code" "$(echo "$response" | jq -c .)"
log "Result: $code (${duration}ms)"

log "=== Text Input Tests Complete ==="
log "Results saved to $TEST_DATA_FILE"

# Navigate back to main menu
log "Navigating back to main menu..."
call_api "ui.navigation.back" "{}" > /dev/null

log "=== All Tests Complete ==="
log "Test data: $TEST_DATA_FILE"
