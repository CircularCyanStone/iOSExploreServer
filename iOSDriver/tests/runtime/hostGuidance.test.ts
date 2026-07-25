import { describe, expect, test } from "vitest";

import { failurePayload } from "../../src/runtime/hostGuidance.js";

describe("host guidance", () => {
  test("按稳定错误 code 生成 nextSteps 且不依赖原始 message", () => {
    const payload = failurePayload({
      source: "appEnvelope",
      code: "stale_locator",
      message: "secret-user-locator"
    }, undefined, "deviceAction");

    expect(payload.nextSteps).toEqual([
      "重新调用 ui_inspect 获取 viewSnapshotID，并从最新快照重新选择目标。"
    ]);
    expect(JSON.stringify(payload.nextSteps)).not.toContain("secret-user-locator");
  });

  test("call_action unknown_action 使用动态 action 指引", () => {
    const payload = failurePayload({
      source: "appEnvelope",
      code: "unknown_action",
      message: "not registered"
    }, undefined, "callAction");

    expect(payload.nextSteps).toEqual([
      "运行 check_capabilities 确认 App 当前注册的 action。"
    ]);
  });
});
