import { describe, expect, test } from "vitest";
import { executeCLICommand, type CLICommandContext } from "../../../src/adapters/cli/commands.js";
import type { CLIConfig, ConfigFileSystem } from "../../../src/adapters/cli/config.js";
import type { InvocationResult } from "../../../src/runtime/types.js";
import { hostLogRecorder } from "../../support/hostLogRecorder.js";

const config: CLIConfig = Object.freeze({ baseURL: "http://localhost:38321/", requestTimeoutMs: 10000, configPath: "/tmp/config.json", fileValues: {} });

function fixture(result: InvocationResult, report: Record<string, unknown> = { connection: "reachable", ping: { status: "ok" }, help: { status: "available" }, schemaCompatibility: "exact" }) {
  const stdout: string[] = [];
  const stderr: string[] = [];
  const artifactWrites: Array<{ path: string; data: Uint8Array }> = [];
  const recorded = hostLogRecorder();
  const context: CLICommandContext = {
    config,
    output: { stdout: value => stdout.push(value), stderr: value => stderr.push(value) },
    runtime: { async invoke() { return result; } },
    capabilityProbe: { async doctor() { return report as never; } },
    workflowRunner: { async run() { return result; } },
    startMCP: async () => { stdout.push("mcp-frame\n"); },
    readFile: async () => "{}",
    writeArtifact: async (path, data) => { artifactWrites.push({ path, data }); },
    logger: recorded.logger
  };
  return { context, stdout, stderr, artifactWrites, logLines: recorded.lines, logEntries: recorded.entries };
}

describe("CLI commands", () => {
  test("call 支持 @file，成功 JSON 在 stdout，image artifact 写入 output", async () => {
    const image = { kind: "image" as const, mimeType: "image/png", data: Buffer.from("png"), metadata: {} };
    const fixtureState = fixture({ ok: true, data: { width: 1 }, artifacts: [image], elapsedMs: 0, attempts: 1 });
    const code = await executeCLICommand("call", fixtureState.context, { action: "ui.screenshot", data: "@/tmp/data.json", output: "/tmp/image.png" });
    expect(code).toBe(0);
    expect(fixtureState.stderr).toEqual([]);
    expect(fixtureState.stdout.join(" ")).toContain("artifact");
    expect(fixtureState.artifactWrites).toEqual([{ path: "/tmp/image.png", data: image.data }]);

    fixtureState.stdout.length = 0;
    await executeCLICommand("call", fixtureState.context, { action: "ui.screenshot" });
    expect(fixtureState.stdout.join(" ")).not.toContain(image.data.toString("base64"));
    expect(fixtureState.artifactWrites).toHaveLength(1);
  });

  test("init 只写配置并输出 iosdriver mcp 片段", async () => {
    const state = fixture({ ok: true, data: {}, artifacts: [], elapsedMs: 0, attempts: 1 });
    const files: Record<string, string> = {};
    const fileSystem: ConfigFileSystem = {
      async readFile(path) {
        if (!(path in files)) throw Object.assign(new Error("missing"), { code: "ENOENT" });
        return files[path]!;
      },
      async mkdir() {},
      async writeFile(path, data) { files[path] = data; },
      async rename(from, to) { files[to] = files[from]!; delete files[from]; }
    };
    state.context.fileSystem = fileSystem;
    state.context.env = {};

    expect(await executeCLICommand("init", state.context)).toBe(0);
    expect(JSON.parse(state.stdout.join(""))).toMatchObject({
      configChanged: true,
      mcp: { command: "iosdriver", args: ["mcp"] }
    });
    expect(JSON.parse(state.stdout.join(""))).not.toHaveProperty("created");
    expect(JSON.parse(files[config.configPath]!)).toMatchObject({ baseURL: config.baseURL, requestTimeoutMs: config.requestTimeoutMs });
    expect(state.stderr).toEqual([]);
  });

  test("业务失败 exit 1 且错误只写 stderr", async () => {
    const state = fixture({ ok: false, error: { source: "appEnvelope", code: "invalid_data", message: "bad" }, elapsedMs: 0, attempts: 1 });
    const code = await executeCLICommand("call", state.context, { action: "ui.tap", data: "{}" });
    expect(code).toBe(1);
    expect(state.stdout).toEqual([]);
    expect(state.stderr.join(" ")).toContain("invalid_data");
  });

  test("transport/protocol 失败 exit 3，非法输入 exit 2", async () => {
    const transport = fixture({ ok: false, error: { source: "transport", code: "transport_unavailable", message: "offline" }, elapsedMs: 0, attempts: 1 });
    expect(await executeCLICommand("call", transport.context, { action: "ping", data: "{}" })).toBe(3);
    const invalid = fixture({ ok: true, data: {}, artifacts: [], elapsedMs: 0, attempts: 1 });
    expect(await executeCLICommand("call", invalid.context, { action: "ping", data: "[]" })).toBe(2);
  });

  test("call 失败在 stderr 保留完整 DriverError，且不输出结果 payload", async () => {
    const error = {
      source: "protocol" as const,
      code: "protocol_error",
      message: "invalid envelope",
      action: "help",
      baseURL: "http://localhost:38321/",
      status: 200,
      timeoutMs: 10000,
      bodySnippet: "{\"code\":",
      data: { reason: "missing data" },
      transportPhase: "unknown" as const,
      protocolIssue: "invalid_envelope" as const
    };
    const state = fixture({
      ok: false,
      error,
      data: { privatePayload: "must-not-leak" },
      elapsedMs: 5,
      attempts: 1
    });

    expect(await executeCLICommand("call", state.context, { action: "help", data: "{}" })).toBe(3);
    expect(state.stdout).toEqual([]);
    expect(JSON.parse(state.stderr.join(""))).toEqual(error);
  });

  test("doctor 按底层稳定错误来源映射退出码", async () => {
    const appFailure = fixture(
      { ok: true, data: {}, artifacts: [], elapsedMs: 0, attempts: 1 },
      { connection: "reachable", ping: { status: "failed", error: { source: "appEnvelope", code: "busy", message: "busy" } }, help: { status: "available" }, schemaCompatibility: "exact" }
    );
    expect(await executeCLICommand("doctor", appFailure.context)).toBe(1);

    const transportFailure = fixture(
      { ok: true, data: {}, artifacts: [], elapsedMs: 0, attempts: 1 },
      { connection: "unreachable", ping: { status: "failed", error: { source: "transport", code: "transport_unavailable", message: "offline" } }, help: { status: "unknown" }, schemaCompatibility: "unknown" }
    );
    expect(await executeCLICommand("doctor", transportFailure.context)).toBe(3);
  });

  test("doctor 输出 schemaDifferences，additive 和元数据差异只报告不失败", async () => {
    const schemaDifferences = [{ action: "echo", status: "additive", differences: ["optional field added"] }];
    const state = fixture(
      { ok: true, data: {}, artifacts: [], elapsedMs: 0, attempts: 1 },
      {
        connection: "reachable",
        ping: { status: "ok" },
        help: { status: "available" },
        schemaCompatibility: "additive",
        schemaDifferences,
        metadata: { contractVersionMatches: false, hashMatches: false }
      }
    );

    expect(await executeCLICommand("doctor", state.context)).toBe(0);
    expect(JSON.parse(state.stdout.join(""))).toMatchObject({
      schemaCompatibility: "additive",
      schemaDifferences,
      metadata: { contractVersionMatches: false, hashMatches: false }
    });
  });

  test("doctor 仅将 breaking 视为合同不兼容，将协议版本不匹配视为 protocol 失败", async () => {
    const success = { ok: true, data: {}, artifacts: [], elapsedMs: 0, attempts: 1 } as const;
    const breaking = fixture(success, {
      connection: "reachable",
      ping: { status: "ok" },
      help: { status: "available" },
      schemaCompatibility: "breaking",
      schemaDifferences: [{ action: "echo", status: "breaking", differences: ["required field added"] }],
      metadata: { contractVersionMatches: false, hashMatches: false, protocolVersionMatches: true }
    });
    expect(await executeCLICommand("doctor", breaking.context)).toBe(1);

    const protocolMismatch = fixture(success, {
      connection: "reachable",
      ping: { status: "ok" },
      help: { status: "available" },
      schemaCompatibility: "exact",
      schemaDifferences: [],
      metadata: { contractVersionMatches: true, hashMatches: true, protocolVersionMatches: false }
    });
    expect(await executeCLICommand("doctor", protocolMismatch.context)).toBe(3);

    const oldNode = fixture(success);
    oldNode.context.nodeVersion = "18.20.0";
    expect(await executeCLICommand("doctor", oldNode.context)).toBe(2);
  });

  test("mcp 不写业务 stdout，直接使用注入的 stdio 启动器", async () => {
    const state = fixture({ ok: true, data: {}, artifacts: [], elapsedMs: 0, attempts: 1 });
    state.stdout.length = 0;
    state.context.startMCP = async () => {};
    expect(await executeCLICommand("mcp", state.context)).toBe(0);
    expect(state.stderr).toEqual([]);
    expect(state.stdout).toEqual([]);
    expect(state.logEntries().map(entry => entry.event)).toEqual(["cli.command.start", "cli.command.complete"]);
  });

  test("失败命令记录稳定退出码且不记录 data 或错误全文", async () => {
    const state = fixture({
      ok: false,
      error: { source: "appEnvelope", code: "invalid_data", message: "private error" },
      elapsedMs: 0,
      attempts: 1
    });

    await executeCLICommand("call", state.context, {
      action: "ui.tap",
      data: JSON.stringify({ password: "123456", token: "secret-token" })
    });

    expect(state.logEntries()).toEqual([
      expect.objectContaining({ event: "cli.command.start", command: "call" }),
      expect.objectContaining({ event: "cli.command.error", command: "call", exitCode: 1 })
    ]);
    expect(state.logLines.join("")).not.toMatch(/123456|secret-token|private error|password/);
  });
});
