import { describe, expect, test } from "vitest";
import {
  HostOperationInputValidationError,
  validateHostOperationInput
} from "../../src/runtime/hostOperationInput.js";

describe("host operation input validation", () => {
  test("call_action 只校验 wrapper，data 内的 device action 字段保持 opaque", () => {
    const input = {
      action: "extension.futureAction",
      data: {
        futureField: true,
        nested: [{ arbitrary: "value" }]
      }
    };

    expect(validateHostOperationInput("call_action", input)).toBe(input);
    expect(() => validateHostOperationInput("call_action", {
      action: "ui.tap",
      data: []
    })).toThrowError(/\$\.data: expected object/);
    expect(() => validateHostOperationInput("call_action", {
      action: "ui.tap",
      data: {},
      unsupported: true
    })).toThrowError(/\$: contains an unsupported field/);
  });

  test("无参数 host operation 拒绝额外字段", () => {
    expect(validateHostOperationInput("health", {})).toEqual({});
    expect(() => validateHostOperationInput("capabilities", { probe: true }))
      .toThrow(HostOperationInputValidationError);
  });

  test("tap_and_inspect 校验必填、互斥、类型和数值范围", () => {
    expect(validateHostOperationInput("tap_and_inspect", {
      path: "root/0",
      viewSnapshotID: "snapshot",
      waitForStable: false,
      stableTimeMs: 0,
      inspectDepth: 10,
      inspectMaxTargets: 512
    })).toMatchObject({ path: "root/0", viewSnapshotID: "snapshot" });

    const invalidInputs = [
      { path: "root/0" },
      { viewSnapshotID: "snapshot" },
      { path: "root/0", accessibilityIdentifier: "button", viewSnapshotID: "snapshot" },
      { path: "root/0", viewSnapshotID: "snapshot", waitForStable: "false" },
      { path: "root/0", viewSnapshotID: "snapshot", stableTimeMs: 3.5 },
      { path: "root/0", viewSnapshotID: "snapshot", stableTimeMs: 3001 },
      { path: "root/0", viewSnapshotID: "snapshot", unknown: true }
    ];

    for (const input of invalidInputs) {
      expect(() => validateHostOperationInput("tap_and_inspect", input))
        .toThrow(HostOperationInputValidationError);
    }
  });

  test("wait_and_inspect 递归校验数组元素、enum 和嵌套对象", () => {
    expect(validateHostOperationInput("wait_and_inspect", {
      conditions: [{ id: "ready", mode: "textExists", text: "Done" }],
      inspectOptions: { maxDepth: 2, maxTargets: 20 }
    })).toMatchObject({ conditions: [{ id: "ready", mode: "textExists" }] });

    const invalidInputs = [
      { conditions: [] },
      { conditions: [{ mode: "idle" }] },
      { conditions: [{ id: "ready", mode: "unsupported" }] },
      { conditions: [{ id: "ready", mode: "idle", unknown: true }] },
      { conditions: [{ id: "ready", mode: "idle" }], intervalMs: 49 },
      { conditions: [{ id: "ready", mode: "idle" }], inspectOptions: { unknown: true } }
    ];

    for (const input of invalidInputs) {
      expect(() => validateHostOperationInput("wait_and_inspect", input))
        .toThrow(HostOperationInputValidationError);
    }
  });
});
