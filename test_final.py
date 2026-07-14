#!/usr/bin/env python3
"""
Final comprehensive end-to-end testing for ui.input, ui.alert.respond, and ui.control.sendAction
"""

import json
import time
import requests
from datetime import datetime
from pathlib import Path

BASE_URL = "http://localhost:38321/"
OUTPUT_DIR = Path("/Users/coo/Desktop/iOS_agent_debugger/iOSExploreServer/docs")
TEST_DATA_FILE = OUTPUT_DIR / "input-alert-control-test-data.json"

class TestRunner:
    def __init__(self):
        self.results = []

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
                # Check if this cell contains the text
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
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "details": details
        })

    def log(self, msg):
        """Log message"""
        print(f"[{datetime.now().strftime('%H:%M:%S')}] {msg}")

    def save_results(self):
        """Save results to file"""
        with open(TEST_DATA_FILE, 'w') as f:
            json.dump({"tests": self.results}, f, indent=2)
        self.log(f"Results saved to {TEST_DATA_FILE}")

    def test_alerts(self):
        """Test ui.alert.respond"""
        self.log("=== Starting Alert Tests ===")

        # Get fresh snapshot and navigate
        data = self.get_fresh_snapshot()
        snapshot_id = data.get("viewSnapshotID")
        targets = data.get("targets", [])

        # Find alert test cell
        cell_path = self.find_cell_by_text(targets, "🔔")
        if not cell_path:
            self.log("ERROR: Could not find alert test cell")
            return

        self.log(f"Found alert test cell at {cell_path}")

        # Navigate to alert page
        response, _ = self.call_api("ui.tap", {
            "path": cell_path,
            "viewSnapshotID": snapshot_id
        })
        self.log(f"Navigation result: {response.get('code')}")

        if response.get("code") != "ok":
            self.log(f"ERROR: Navigation failed: {response}")
            return

        time.sleep(1)

        # Get fresh snapshot of alert page
        data = self.get_fresh_snapshot()
        snapshot_id = data.get("viewSnapshotID")
        targets = data.get("targets", [])

        # Find alert trigger buttons
        buttons = [t for t in targets if t.get("type") == "UIButton" and t.get("title") and "Alert" in t.get("title", "")]
        self.log(f"Found {len(buttons)} alert trigger buttons")

        for i, button in enumerate(buttons[:5]):  # Test first 5 alerts
            title = button.get("title", "Unknown")
            path = button.get("path")

            self.log(f"\nTest Alert {i+1}: {title}")

            # Get fresh snapshot before tap
            data = self.get_fresh_snapshot()
            snapshot_id = data.get("viewSnapshotID")

            # Trigger alert
            response, tap_duration = self.call_api("ui.tap", {
                "path": path,
                "viewSnapshotID": snapshot_id
            })
            self.log(f"  Tap result: {response.get('code')}")

            time.sleep(0.5)

            # Check for alert
            data = self.get_fresh_snapshot()
            alert = data.get("alert", {})

            if alert.get("available"):
                alert_title = alert.get("title", "")
                alert_message = alert.get("message", "")
                alert_buttons = alert.get("buttons", [])
                self.log(f"  Alert appeared: '{alert_title}'")
                self.log(f"  Message: '{alert_message}'")
                self.log(f"  Buttons: {[b.get('title') for b in alert_buttons]}")

                # Test responding to first button
                if alert_buttons:
                    btn = alert_buttons[0]
                    btn_title = btn.get("title", "")
                    btn_index = btn.get("index", 0)

                    response, duration = self.call_api("ui.alert.respond", {
                        "buttonIndex": btn_index
                    })
                    code = response.get("code")

                    self.add_result(
                        f"Alert: {title} → {btn_title}",
                        "ui.alert.respond",
                        duration,
                        code,
                        response
                    )
                    self.log(f"  Response to '{btn_title}': {code} ({duration}ms)")

                    time.sleep(0.3)
            else:
                self.log(f"  No alert appeared")
                self.add_result(
                    f"Alert: {title} (no alert)",
                    "ui.tap",
                    tap_duration,
                    "no_alert",
                    {"message": "Alert did not appear", "response": response}
                )

        # Navigate back
        self.call_api("ui.navigation.back")
        time.sleep(0.5)
        self.log("\n=== Alert Tests Complete ===")

    def test_controls(self):
        """Test ui.control.sendAction"""
        self.log("\n=== Starting Control Tests ===")

        # Get fresh snapshot
        data = self.get_fresh_snapshot()
        snapshot_id = data.get("viewSnapshotID")
        targets = data.get("targets", [])

        # Find control test cell
        cell_path = self.find_cell_by_text(targets, "🎮")
        if not cell_path:
            self.log("ERROR: Could not find control test cell")
            return

        self.log(f"Found control test cell at {cell_path}")

        # Navigate to control page
        response, _ = self.call_api("ui.tap", {
            "path": cell_path,
            "viewSnapshotID": snapshot_id
        })
        self.log(f"Navigation result: {response.get('code')}")

        if response.get("code") != "ok":
            self.log(f"ERROR: Navigation failed: {response}")
            return

        time.sleep(1)

        # Get fresh snapshot of control page
        data = self.get_fresh_snapshot()
        snapshot_id = data.get("viewSnapshotID")
        targets = data.get("targets", [])

        # Find controls
        control_types = ["UISwitch", "UISlider", "UIStepper", "UISegmentedControl", "UIButton"]
        controls = [t for t in targets if t.get("type") in control_types]

        self.log(f"Found {len(controls)} controls")

        # Group controls by type
        by_type = {}
        for control in controls:
            ctype = control.get("type")
            if ctype not in by_type:
                by_type[ctype] = []
            by_type[ctype].append(control)

        # Test each control type
        for ctype, items in by_type.items():
            self.log(f"\n{ctype}: {len(items)} instances")

            if ctype == "UISwitch" and items:
                control = items[0]
                path = control.get("path")
                current_value = control.get("value")
                self.log(f"  Current value: {current_value}")

                # Get fresh snapshot
                data = self.get_fresh_snapshot()
                snapshot_id = data.get("viewSnapshotID")

                response, duration = self.call_api("ui.control.sendAction", {
                    "path": path,
                    "viewSnapshotID": snapshot_id,
                    "action": "valueChanged"
                })
                code = response.get("code")
                self.add_result(
                    f"{ctype} valueChanged",
                    "ui.control.sendAction",
                    duration,
                    code,
                    response
                )
                self.log(f"  Result: {code} ({duration}ms)")

            elif ctype == "UISlider" and items:
                control = items[0]
                path = control.get("path")

                # Get fresh snapshot
                data = self.get_fresh_snapshot()
                snapshot_id = data.get("viewSnapshotID")

                response, duration = self.call_api("ui.control.sendAction", {
                    "path": path,
                    "viewSnapshotID": snapshot_id,
                    "action": "valueChanged",
                    "value": 0.75
                })
                code = response.get("code")
                self.add_result(
                    f"{ctype} setValue to 0.75",
                    "ui.control.sendAction",
                    duration,
                    code,
                    response
                )
                self.log(f"  Result: {code} ({duration}ms)")

            elif ctype == "UIStepper" and items:
                control = items[0]
                path = control.get("path")

                # Get fresh snapshot
                data = self.get_fresh_snapshot()
                snapshot_id = data.get("viewSnapshotID")

                response, duration = self.call_api("ui.control.sendAction", {
                    "path": path,
                    "viewSnapshotID": snapshot_id,
                    "action": "valueChanged"
                })
                code = response.get("code")
                self.add_result(
                    f"{ctype} valueChanged",
                    "ui.control.sendAction",
                    duration,
                    code,
                    response
                )
                self.log(f"  Result: {code} ({duration}ms)")

            elif ctype == "UISegmentedControl" and items:
                control = items[0]
                path = control.get("path")

                # Get fresh snapshot
                data = self.get_fresh_snapshot()
                snapshot_id = data.get("viewSnapshotID")

                response, duration = self.call_api("ui.control.sendAction", {
                    "path": path,
                    "viewSnapshotID": snapshot_id,
                    "action": "valueChanged",
                    "selectedSegmentIndex": 1
                })
                code = response.get("code")
                self.add_result(
                    f"{ctype} select segment 1",
                    "ui.control.sendAction",
                    duration,
                    code,
                    response
                )
                self.log(f"  Result: {code} ({duration}ms)")

            elif ctype == "UIButton" and items:
                # Test button tap using ui.control.sendAction
                button = items[0]
                path = button.get("path")
                title = button.get("title", "")

                # Get fresh snapshot
                data = self.get_fresh_snapshot()
                snapshot_id = data.get("viewSnapshotID")

                response, duration = self.call_api("ui.control.sendAction", {
                    "path": path,
                    "viewSnapshotID": snapshot_id,
                    "action": "touchUpInside"
                })
                code = response.get("code")
                self.add_result(
                    f"{ctype} touchUpInside: {title}",
                    "ui.control.sendAction",
                    duration,
                    code,
                    response
                )
                self.log(f"  Button '{title}': {code} ({duration}ms)")

        # Navigate back
        self.call_api("ui.navigation.back")
        self.log("\n=== Control Tests Complete ===")

def main():
    runner = TestRunner()

    # Load existing results if any
    if TEST_DATA_FILE.exists():
        with open(TEST_DATA_FILE) as f:
            existing = json.load(f)
            runner.results = existing.get("tests", [])

    try:
        runner.test_alerts()
        runner.test_controls()
    finally:
        runner.save_results()

    # Print summary
    print("\n" + "="*60)
    print("=== Test Summary ===")
    print("="*60)
    total = len(runner.results)
    success = sum(1 for r in runner.results if r["code"] == "ok")
    print(f"Total tests: {total}")
    print(f"Successful: {success}")
    print(f"Failed: {total - success}")
    print(f"Success rate: {success/total*100:.1f}%")

    # Group by action
    by_action = {}
    for r in runner.results:
        action = r["action"]
        if action not in by_action:
            by_action[action] = {"ok": 0, "failed": 0}
        if r["code"] == "ok":
            by_action[action]["ok"] += 1
        else:
            by_action[action]["failed"] += 1

    print("\nBy action:")
    for action, counts in sorted(by_action.items()):
        total_action = counts["ok"] + counts["failed"]
        print(f"  {action}: {counts['ok']}/{total_action} passed")

    # Show failed tests
    failed = [r for r in runner.results if r["code"] != "ok"]
    if failed:
        print(f"\nFailed tests ({len(failed)}):")
        for r in failed:
            print(f"  - {r['name']}: {r['code']}")

if __name__ == "__main__":
    main()
