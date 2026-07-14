#!/usr/bin/env python3
"""
Comprehensive end-to-end testing for ui.input, ui.alert.respond, and ui.control.sendAction
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

        # Navigate to alert test page
        self.log("Navigating to Alert test page...")
        response, _ = self.call_api("ui.inspect")
        snapshot_id = response.get("data", {}).get("viewSnapshotID")

        # Tap alert test cell (root/5/6/1)
        response, duration = self.call_api("ui.tap", {
            "path": "root/5/6/1",
            "viewSnapshotID": snapshot_id
        })
        self.log(f"Navigation result: {response.get('code')}")

        time.sleep(1)

        # Inspect alert page
        response, _ = self.call_api("ui.inspect")
        snapshot_id = response.get("data", {}).get("viewSnapshotID")
        targets = response.get("data", {}).get("targets", [])

        # Find alert trigger buttons
        buttons = [t for t in targets if t.get("type") == "UIButton" and t.get("title")]
        self.log(f"Found {len(buttons)} alert trigger buttons")

        for i, button in enumerate(buttons[:5]):  # Test first 5 alerts
            title = button.get("title", "Unknown")
            path = button.get("path")

            self.log(f"Test Alert {i+1}: {title}")

            # Trigger alert
            response, tap_duration = self.call_api("ui.tap", {
                "path": path,
                "viewSnapshotID": snapshot_id
            })

            time.sleep(0.5)

            # Check for alert
            response, _ = self.call_api("ui.inspect")
            alert = response.get("data", {}).get("alert", {})

            if alert.get("available"):
                alert_title = alert.get("title", "")
                alert_buttons = alert.get("buttons", [])
                self.log(f"  Alert: {alert_title}, Buttons: {len(alert_buttons)}")

                # Test responding to different buttons
                for btn_idx, btn in enumerate(alert_buttons):
                    if btn_idx > 0:  # Re-trigger alert for subsequent buttons
                        self.call_api("ui.tap", {"path": path, "viewSnapshotID": snapshot_id})
                        time.sleep(0.5)

                    btn_title = btn.get("title", "")
                    btn_index = btn.get("index", 0)

                    response, duration = self.call_api("ui.alert.respond", {
                        "buttonIndex": btn_index
                    })
                    code = response.get("code")

                    self.add_result(
                        f"Alert: {title} - Button: {btn_title}",
                        "ui.alert.respond",
                        duration,
                        code,
                        response
                    )
                    self.log(f"  Button '{btn_title}': {code} ({duration}ms)")

                    time.sleep(0.3)
            else:
                self.log(f"  No alert appeared")
                self.add_result(
                    f"Alert: {title} (no alert)",
                    "ui.tap",
                    tap_duration,
                    "no_alert",
                    {"message": "Alert did not appear"}
                )

        # Navigate back
        self.call_api("ui.navigation.back")
        self.log("=== Alert Tests Complete ===")

    def test_controls(self):
        """Test ui.control.sendAction"""
        self.log("=== Starting Control Tests ===")

        # Navigate to control test page
        response, _ = self.call_api("ui.inspect")
        snapshot_id = response.get("data", {}).get("viewSnapshotID")

        # Tap control test cell (root/5/5/1)
        response, _ = self.call_api("ui.tap", {
            "path": "root/5/5/1",
            "viewSnapshotID": snapshot_id
        })
        self.log(f"Navigation result: {response.get('code')}")

        time.sleep(1)

        # Inspect control page
        response, _ = self.call_api("ui.inspect")
        snapshot_id = response.get("data", {}).get("viewSnapshotID")
        targets = response.get("data", {}).get("targets", [])

        # Find controls (UISwitch, UISlider, UIStepper, UISegmentedControl)
        control_types = ["UISwitch", "UISlider", "UIStepper", "UISegmentedControl"]
        controls = [t for t in targets if t.get("type") in control_types]

        self.log(f"Found {len(controls)} controls")

        for control in controls:
            control_type = control.get("type")
            path = control.get("path")

            if control_type == "UISwitch":
                # Test switch toggle
                actions = ["valueChanged"]
                for action in actions:
                    response, duration = self.call_api("ui.control.sendAction", {
                        "path": path,
                        "viewSnapshotID": snapshot_id,
                        "action": action
                    })
                    code = response.get("code")
                    self.add_result(
                        f"UISwitch {action}",
                        "ui.control.sendAction",
                        duration,
                        code,
                        response
                    )
                    self.log(f"  UISwitch.{action}: {code} ({duration}ms)")
                    time.sleep(0.2)

            elif control_type == "UISlider":
                # Test slider setValue
                response, duration = self.call_api("ui.control.sendAction", {
                    "path": path,
                    "viewSnapshotID": snapshot_id,
                    "action": "valueChanged",
                    "value": 0.7
                })
                code = response.get("code")
                self.add_result(
                    "UISlider setValue to 0.7",
                    "ui.control.sendAction",
                    duration,
                    code,
                    response
                )
                self.log(f"  UISlider.setValue: {code} ({duration}ms)")

            elif control_type == "UIStepper":
                # Test stepper increment
                response, duration = self.call_api("ui.control.sendAction", {
                    "path": path,
                    "viewSnapshotID": snapshot_id,
                    "action": "valueChanged"
                })
                code = response.get("code")
                self.add_result(
                    "UIStepper valueChanged",
                    "ui.control.sendAction",
                    duration,
                    code,
                    response
                )
                self.log(f"  UIStepper.valueChanged: {code} ({duration}ms)")

            elif control_type == "UISegmentedControl":
                # Test segment selection
                response, duration = self.call_api("ui.control.sendAction", {
                    "path": path,
                    "viewSnapshotID": snapshot_id,
                    "action": "valueChanged",
                    "selectedSegmentIndex": 1
                })
                code = response.get("code")
                self.add_result(
                    "UISegmentedControl select segment 1",
                    "ui.control.sendAction",
                    duration,
                    code,
                    response
                )
                self.log(f"  UISegmentedControl.select: {code} ({duration}ms)")

        # Navigate back
        self.call_api("ui.navigation.back")
        self.log("=== Control Tests Complete ===")

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
    print("\n=== Test Summary ===")
    total = len(runner.results)
    success = sum(1 for r in runner.results if r["code"] == "ok")
    print(f"Total tests: {total}")
    print(f"Successful: {success}")
    print(f"Failed: {total - success}")

    # Show failed tests
    failed = [r for r in runner.results if r["code"] != "ok"]
    if failed:
        print(f"\nFailed tests:")
        for r in failed:
            print(f"  - {r['name']}: {r['code']}")

if __name__ == "__main__":
    main()
