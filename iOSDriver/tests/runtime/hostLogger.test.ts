import { describe, expect, test, vi } from "vitest";
import { createHostLogger } from "../../src/runtime/hostLogger.js";

describe("HostLogger", () => {
  test("默认生产 sink 只写 stderr，结构化事件不写 stdout", () => {
    const stderr = vi.spyOn(process.stderr, "write").mockImplementation(() => true);
    const stdout = vi.spyOn(process.stdout, "write").mockImplementation(() => true);

    createHostLogger({ now: () => new Date("2026-07-25T00:00:00.000Z") })
      .emit("info", "host.test", { action: "ping" });

    expect(stderr).toHaveBeenCalledOnce();
    expect(String(stderr.mock.calls[0]![0])).toContain('"event":"host.test"');
    expect(stdout).not.toHaveBeenCalled();
    stderr.mockRestore();
    stdout.mockRestore();
  });

  test("过滤敏感或非标量字段，且 sink 异常不改变调用方行为", () => {
    const lines: string[] = [];
    const logger = createHostLogger({
      sink: line => lines.push(line),
      now: () => new Date("2026-07-25T00:00:00.000Z")
    });
    logger.emit("warn", "runtime.invoke.failure", {
      action: "ui.tap",
      code: "invalid_data",
      message: "secret",
      payload: "base64-secret",
      bodySnippet: "private body",
      data: { password: "123456" }
    } as never);

    expect(JSON.parse(lines[0]!)).toEqual({
      timestamp: "2026-07-25T00:00:00.000Z",
      level: "warn",
      event: "runtime.invoke.failure",
      action: "ui.tap",
      code: "invalid_data"
    });

    const broken = createHostLogger({ sink: () => { throw new Error("sink unavailable"); } });
    expect(() => broken.emit("info", "host.test")).not.toThrow();
  });
});
