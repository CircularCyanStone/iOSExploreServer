import { describe, expect, test } from "vitest";
import {
  knownCLICommand,
  parseCLIArguments
} from "../../../src/adapters/cli/arguments.js";
import { CLIConfigError } from "../../../src/adapters/cli/config.js";

describe("CLI arguments", () => {
  test("解析 call 的 action、配置覆盖项和输出参数", () => {
    expect(parseCLIArguments([
      "call",
      "ui.inspect",
      "--data",
      "{\"snapshot\":true}",
      "--output",
      "screen.png",
      "--base-url",
      "http://localhost:39000",
      "--timeout",
      "2500"
    ])).toEqual({
      kind: "operational",
      command: "call",
      config: {
        baseURL: "http://localhost:39000",
        requestTimeoutMs: 2500
      },
      human: false,
      call: {
        action: "ui.inspect",
        data: "{\"snapshot\":true}",
        output: "screen.png"
      }
    });
  });

  test("解析 mcp setup 时不混入普通 App 命令参数", () => {
    expect(parseCLIArguments([
      "mcp",
      "setup",
      "claude",
      "--scope",
      "project",
      "--project-dir",
      "packages/app",
      "--config",
      "configs/iosdriver.json",
      "--dry-run",
      "--force"
    ])).toEqual({
      kind: "mcpSetup",
      client: "claude",
      scope: "project",
      projectDir: "packages/app",
      configPath: "configs/iosdriver.json",
      dryRun: true,
      force: true
    });
  });

  test("在任何 IO 前拒绝未知命令、缺失 flag 值和非法 timeout", () => {
    for (const argv of [
      [],
      ["unknown"],
      ["doctor", "--config", "--human"],
      ["call", "ping", "--timeout", "0"],
      ["call", "ping", "--timeout", "1.5"]
    ]) {
      expect(() => parseCLIArguments(argv)).toThrow(CLIConfigError);
    }
  });

  test("日志命令名只返回白名单，不暴露未知 argv", () => {
    expect(knownCLICommand(["mcp", "setup", "codex"])).toBe("mcp.setup");
    expect(knownCLICommand(["call", "ui.inspect", "--data", "secret"])).toBe("call");
    expect(knownCLICommand(["private-command", "secret"])).toBe("unknown");
  });
});
