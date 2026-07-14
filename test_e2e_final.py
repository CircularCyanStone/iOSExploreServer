#!/usr/bin/env python3
"""
Final comprehensive end-to-end testing for ui.input, ui.alert.respond, and ui.control.sendAction
This version uses correct parameter names verified from source code.
"""

import json
import time
import requests
from datetime import datetime
from pathlib import Path

BASE_URL = "http://localhost:38321/"
OUTPUT_DIR = Path("/Users/coo/Desktop/iOS_agent_debugger/iOSExploreServer/docs")
TEST_DATA_FILE = OUTPUT_DIR / "input-alert-control-test-report.json"

class TestRunner:
    def __init__(self):
        self.results = []
        self.start_time = datetime.now()

    def call_api(self, action, data=None):
        """Call API and measure response time"""
        if data is None:
            data = {}
        start = time.time()
        try:
            response = requests.post(BASE_URL, json={"action": action, "data": data}, timeout=10)
            duration_ms = int((time.time() - start) * 1000)
            return response.json(), duration_ms
        except Exception as e:
            duration_ms = int((time.time() - start) * 1000)
            return {"code": "error", "message": str(e)}, duration_ms

    def get_fresh_snapshot(self):
        """Get fresh UI snapshot"""
        response, _ = self.call_api("ui.inspect")
        return response.get("data", {})

    def find_cell_by_text(self, targets, text):
        """Find cell by text content"""
        for target in targets:
            if target.get("type") == "UIListContentView":
                text_content = target.get("text", "")
                if text in text_content:
                    return target.get("path")
        return None

    def add_result(self, name, action, duration_ms, code, details):
        """Add test result"""
        self.results.append({
            "name": name,
            "action": action,
            "duration_ms": duration_ms,
            "code": code,
            "success": code == "ok",
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "details": details
        })

    def log(self, msg):
        """Log message"""
        print(f"[{datetime.now().strftime('%H:%M:%S')}] {msg}")

    def save_results(self):
        """Save comprehensive test results"""
        end_time = datetime.now()
        total_duration = (end_time - self.start_time).total_seconds()

        report = {
            "metadata": {
                "test_run_start": self.start_time.isoformat(),
                "test_run_end": end_time.isoformat(),
                "total_duration_seconds": total_duration,
                "total_tests": len(self.results),
                "successful_tests": sum(1 for r in self.results if r["success"]),
                "failed_tests": sum(1 for r in self.results if not r["success"])
            },
            "tests": self.results
        }

        with open(TEST_DATA_FILE, 'w') as f:
            json.dump(report, f, indent=2)
        self.log(f"Results saved to {TEST_DATA_FILE}")

    def test_text_input(self):
        """Test ui.input command"""
        self.log("\n" + "="*60)
        self.log("=== Text Input Tests (ui.input) ===")
        self.log("="*60)

        # Navigate to text input page
        data = self.get_fresh_snapshot()
        snapshot_id = data.get("viewSnapshotID")
        targets = data.get("targets", [])

        cell_path = self.find_cell_by_text(targets, "⌨️")
        if not cell_path:
            self.log("ERROR: Could not find text input test cell")
            return

        response, _ = self.call_api("ui.tap", {
            "path": cell_path,
            "viewSnapshotID": snapshot_id
        })
        self.log(f"Navigation: {response.get('code')}")
        time.sleep(1)

        # Get text fields
        data = self.get_fresh_snapshot()
        snapshot_id = data.get("viewSnapshotID")
        targets = data.get("targets", [])

        text_fields = [t for t in targets if t.get("type") in ["UITextField", "UITextView", "UISearchTextField"]]
        self.log(f"Found {len(text_fields)} text input fields")

        if text_fields:
            # Test 1: Basic text input (replace mode)
            field = text_fields[0]
            response, duration = self.call_api("ui.input", {
                "path": field["path"],
                "viewSnapshotID": snapshot_id,
                "text": "Hello World",
                "mode": "replace"
            })
            self.add_result("UITextField replace mode", "ui.input", duration, response.get("code"), response)
            self.log(f"  Test 1 - Replace: {response.get('code')} ({duration}ms)")

        if len(text_fields) > 1:
            # Test 2: Append mode
            data = self.get_fresh_snapshot()
            snapshot_id = data.get("viewSnapshotID")

            field = text_fields[1]
            response, duration = self.call_api("ui.input", {
                "path": field["path"],
                "viewSnapshotID": snapshot_id,
                "text": "First",
                "mode": "replace"
            })
            time.sleep(0.2)

            data = self.get_fresh_snapshot()
            snapshot_id = data.get("viewSnapshotID")

            response, duration = self.call_api("ui.input", {
                "path": field["path"],
                "viewSnapshotID": snapshot_id,
                "text": " Second",
                "mode": "append"
            })
            self.add_result("UITextField append mode", "ui.input", duration, response.get("code"), response)
            self.log(f"  Test 2 - Append: {response.get('code')} ({duration}ms)")

        if len(text_fields) > 2:
            # Test 3: UITextView multiline
            data = self.get_fresh_snapshot()
            snapshot_id = data.get("viewSnapshotID")

            field = [f for f in text_fields if f.get("type") == "UITextView"][0] if any(f.get("type") == "UITextView" for f in text_fields) else text_fields[2]
            response, duration = self.call_api("ui.input", {
                "path": field["path"],
                "viewSnapshotID": snapshot_id,
                "text": "Line 1\nLine 2\nLine 3"
            })
            self.add_result("UITextView multiline", "ui.input", duration, response.get("code"), response)
            self.log(f"  Test 3 - Multiline: {response.get('code')} ({duration}ms)")

        if len(text_fields) > 3:
            # Test 4: Empty string
            data = self.get_fresh_snapshot()
            snapshot_id = data.get("viewSnapshotID")

            field = text_fields[3]
            response, duration = self.call_api("ui.input", {
                "path": field["path"],
                "viewSnapshotID": snapshot_id,
                "text": ""
            })
            self.add_result("Empty string input", "ui.input", duration, response.get("code"), response)
            self.log(f"  Test 4 - Empty: {response.get('code')} ({duration}ms)")

        if len(text_fields) > 4:
            # Test 5: Unicode and emoji
            data = self.get_fresh_snapshot()
            snapshot_id = data.get("viewSnapshotID")

            field = text_fields[4]
            response, duration = self.call_api("ui.input", {
                "path": field["path"],
                "viewSnapshotID": snapshot_id,
                "text": "你好世界 🌍 مرحبا"
            })
            self.add_result("Unicode and emoji", "ui.input", duration, response.get("code"), response)
            self.log(f"  Test 5 - Unicode: {response.get('code')} ({duration}ms)")

        # Test keyboard dismiss
        response, duration = self.call_api("ui.keyboard.dismiss")
        self.add_result("Dismiss keyboard", "ui.keyboard.dismiss", duration, response.get("code"), response)
        self.log(f"  Keyboard dismiss: {response.get('code')} ({duration}ms)")

        # Navigate back
        self.call_api("ui.navigation.back")
        time.sleep(0.5)

    def test_alerts(self):
        """Test ui.alert.respond"""
        self.log("\n" + "="*60)
        self.log("=== Alert Tests (ui.alert.respond) ===")
        self.log("="*60)

        # Navigate to alert page
        data = self.get_fresh_snapshot()
        snapshot_id = data.get("viewSnapshotID")
        targets = data.get("targets", [])

        cell_path = self.find_cell_by_text(targets, "🔔")
        if not cell_path:
            self.log("ERROR: Could not find alert test cell")
            return

        response, _ = self.call_api("ui.tap", {
            "path": cell_path,
            "viewSnapshotID": snapshot_id
        })
        self.log(f"Navigation: {response.get('code')}")
        time.sleep(1)

        # Get alert page snapshot
        data = self.get_fresh_snapshot()
        snapshot_id = data.get("viewSnapshotID")
        targets = data.get("targets", [])

        # Find alert trigger buttons - look for buttons with "Alert" in title
        buttons = [t for t in targets if t.get("type") == "UIButton" and t.get("title") and ("Alert" in t.get("title", "") or "弹窗" in t.get("title", ""))]
        self.log(f"Found {len(buttons)} alert trigger buttons")

        for i, button in enumerate(buttons[:5]):
            title = button.get("title", "Unknown")
            path = button.get("path")

            self.log(f"\n  Test Alert {i+1}: {title}")

            # Get fresh snapshot
            data = self.get_fresh_snapshot()
            snapshot_id = data.get("viewSnapshotID")

            # Trigger alert
            response, tap_duration = self.call_api("ui.tap", {
                "path": path,
                "viewSnapshotID": snapshot_id
            })

            time.sleep(0.5)

            # Check for alert
            data = self.get_fresh_snapshot()
            alert = data.get("alert", {})

            if alert.get("available"):
                alert_title = alert.get("title", "")
                alert_buttons = alert.get("buttons", [])
                self.log(f"    Alert: '{alert_title}' with {len(alert_buttons)} buttons")

                if alert_buttons:
                    btn = alert_buttons[0]
                    btn_title = btn.get("title", "")
                    btn_index = btn.get("index", 0)

                    response, duration = self.call_api("ui.alert.respond", {
                        "buttonIndex": btn_index
                    })
                    code = response.get("code")

                    self.add_result(
                        f"Alert '{title}' → button '{btn_title}'",
                        "ui.alert.respond",
                        duration,
                        code,
                        response
                    )
                    self.log(f"    Response: {code} ({duration}ms)")
                    time.sleep(0.3)
            else:
                self.log(f"    No alert appeared (might be navigation button)")

        # Navigate back
        self.call_api("ui.navigation.back")
        time.sleep(0.5)

    def test_controls(self):
        """Test ui.control.sendAction"""
        self.log("\n" + "="*60)
        self.log("=== Control Tests (ui.control.sendAction) ===")
        self.log("="*60)

        # Navigate to control page
        data = self.get_fresh_snapshot()
        snapshot_id = data.get("viewSnapshotID")
        targets = data.get("targets", [])

        cell_path = self.find_cell_by_text(targets, "🎮")
        if not cell_path:
            self.log("ERROR: Could not find control test cell")
            return

        response, _ = self.call_api("ui.tap", {
            "path": cell_path,
            "viewSnapshotID": snapshot_id
        })
        self.log(f"Navigation: {response.get('code')}")
        time.sleep(1)

        # Get control page snapshot
        data = self.get_fresh_snapshot()
        snapshot_id = data.get("viewSnapshotID")
        targets = data.get("targets", [])

        # Find controls
        control_types = ["UISwitch", "UISlider", "UIStepper", "UISegmentedControl"]
        controls = [t for t in targets if t.get("type") in control_types]
        self.log(f"Found {len(controls)} controls")

        # Group by type
        by_type = {}
        for control in controls:
            ctype = control.get("type")
            if ctype not in by_type:
                by_type[ctype] = []
            by_type[ctype].append(control)

        # Test UISwitch
        if "UISwitch" in by_type and by_type["UISwitch"]:
            control = by_type["UISwitch"][0]
            path = control.get("path")

            data = self.get_fresh_snapshot()
            snapshot_id = data.get("viewSnapshotID")

            response, duration = self.call_api("ui.control.sendAction", {
                "path": path,
                "viewSnapshotID": snapshot_id,
                "event": "valueChanged"
            })
            self.add_result("UISwitch toggle", "ui.control.sendAction", duration, response.get("code"), response)
            self.log(f"  UISwitch: {response.get('code')} ({duration}ms)")

        # Test UISlider
        if "UISlider" in by_type and by_type["UISlider"]:
            control = by_type["UISlider"][0]
            path = control.get("path")

            data = self.get_fresh_snapshot()
            snapshot_id = data.get("viewSnapshotID")

            response, duration = self.call_api("ui.control.sendAction", {
                "path": path,
                "viewSnapshotID": snapshot_id,
                "event": "valueChanged",
                "value": 0.75
            })
            self.add_result("UISlider setValue", "ui.control.sendAction", duration, response.get("code"), response)
            self.log(f"  UISlider: {response.get('code')} ({duration}ms)")

        # Test UIStepper
        if "UIStepper" in by_type and by_type["UIStepper"]:
            control = by_type["UIStepper"][0]
            path = control.get("path")

            data = self.get_fresh_snapshot()
            snapshot_id = data.get("viewSnapshotID")

            response, duration = self.call_api("ui.control.sendAction", {
                "path": path,
                "viewSnapshotID": snapshot_id,
                "event": "valueChanged"
            })
            self.add_result("UIStepper increment", "ui.control.sendAction", duration, response.get("code"), response)
            self.log(f"  UIStepper: {response.get('code')} ({duration}ms)")

        # Test UISegmentedControl
        if "UISegmentedControl" in by_type and by_type["UISegmentedControl"]:
            control = by_type["UISegmentedControl"][0]
            path = control.get("path")

            data = self.get_fresh_snapshot()
            snapshot_id = data.get("viewSnapshotID")

            response, duration = self.call_api("ui.control.sendAction", {
                "path": path,
                "viewSnapshotID": snapshot_id,
                "event": "valueChanged",
                "value": 1
            })
            self.add_result("UISegmentedControl select segment", "ui.control.sendAction", duration, response.get("code"), response)
            self.log(f"  UISegmentedControl: {response.get('code')} ({duration}ms)")

        # Navigate back
        self.call_api("ui.navigation.back")

def main():
    runner = TestRunner()

    try:
        runner.test_text_input()
        runner.test_alerts()
        runner.test_controls()
    finally:
        runner.save_results()

    # Print summary
    print("\n" + "="*60)
    print("=== Final Test Summary ===")
    print("="*60)
    total = len(runner.results)
    success = sum(1 for r in runner.results if r["success"])
    print(f"Total tests: {total}")
    print(f"Successful: {success}")
    print(f"Failed: {total - success}")
    if total > 0:
        print(f"Success rate: {success/total*100:.1f}%")

    # Group by action
    by_action = {}
    for r in runner.results:
        action = r["action"]
        if action not in by_action:
            by_action[action] = {"ok": 0, "failed": 0}
        if r["success"]:
            by_action[action]["ok"] += 1
        else:
            by_action[action]["failed"] += 1

    print("\nResults by action:")
    for action, counts in sorted(by_action.items()):
        total_action = counts["ok"] + counts["failed"]
        print(f"  {action}: {counts['ok']}/{total_action} passed")

    # Show failed tests
    failed = [r for r in runner.results if not r["success"]]
    if failed:
        print(f"\nFailed tests ({len(failed)}):")
        for r in failed:
            print(f"  - {r['name']}: {r['code']}")

if __name__ == "__main__":
    main()
