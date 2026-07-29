import { describe, expect, test } from "vitest";
import { main } from "../../../src/adapters/cli/main.js";
import { noopHostLogger } from "../../../src/runtime/hostLogger.js";
import type { MCPClientSetupInput, MCPClientSetupResult } from "../../../src/registration/mcpClientSetup.js";

function outputFixture() {
  const stdout: string[] = [];
  const stderr: string[] = [];
  return {
    stdout,
    stderr,
    output: { stdout: (value: string) => stdout.push(value), stderr: (value: string) => stderr.push(value) }
  };
}

describe("CLI main", () => {
  test("mcp setup 在 App 配置解析和 runtime 构造前分流", async () => {
    const streams = outputFixture();
    let received: MCPClientSetupInput | undefined;
    const setup = async (input: MCPClientSetupInput): Promise<MCPClientSetupResult> => {
      received = input;
      return {
        client: input.client,
        scope: "user",
        status: "planned",
        operation: "create",
        registrationName: "iOSDriver",
        manager: "codex-cli",
        launch: input.launch
      };
    };

    const exitCode = await main(
      ["mcp", "setup", "codex", "--dry-run", "--config", "configs/broken.json", "--project-dir", ".."],
      {
        output: streams.output,
        env: { IOS_EXPLORE_BASE_URL: "not a URL" },
        cwd: "/workspace/app",
        homeDir: "/home/u",
        nodePath: "/node/bin/node",
        cliEntryPath: "/opt/iosdriver/main.js",
        setupMCPClient: setup,
        logger: noopHostLogger
      }
    );

    expect(exitCode).toBe(0);
    expect(received).toMatchObject({
      client: "codex",
      dryRun: true,
      force: false,
      cwd: "/workspace",
      launch: {
        command: "/node/bin/node",
        args: ["/opt/iosdriver/main.js", "mcp", "--config", "/workspace/app/configs/broken.json"]
      }
    });
    expect(streams.stderr).toEqual([]);
    expect(JSON.parse(streams.stdout.join(""))).toMatchObject({ status: "planned" });
  });

  test("mcp setup 校验 client、scope 和未知参数", async () => {
    for (const argv of [
      ["mcp", "setup"],
      ["mcp", "setup", "unknown"],
      ["mcp", "setup", "claude", "--scope", "local"],
      ["mcp", "setup", "trae", "--unknown"]
    ]) {
      const streams = outputFixture();
      expect(await main(argv, { output: streams.output, logger: noopHostLogger })).toBe(2);
      expect(streams.stderr.join("").length).toBeGreaterThan(0);
    }
  });
});
