import { describe, expect, test } from "vitest";
import { executeCLICommand, type CLICommandContext } from "../../../src/adapters/cli/commands.js";
import type { CLIConfig, ConfigFileSystem } from "../../../src/adapters/cli/config.js";
import type { InvocationPolicy } from "../../../src/runtime/driverRuntime.js";
import type { InvocationResult } from "../../../src/runtime/types.js";
import type { JSONObject } from "../../../src/types.js";
import { hostLogRecorder } from "../../support/hostLogRecorder.js";

const config: CLIConfig = Object.freeze({ baseURL: "http://localhost:38321/", requestTimeoutMs: 10000, configPath: "/tmp/config.json", fileValues: {} });

function fixture(
  result: InvocationResult,
  report: Record<string, unknown> = { connection: "reachable", ping: { status: "ok" }, help: { status: "available" }, contractCompatibility: "exact" },
  policy?: InvocationPolicy
) {
  const stdout: string[] = [];
  const stderr: string[] = [];
  const artifactWrites: Array<{ path: string; data: Uint8Array }> = [];
  const runtimeCalls: Array<{ action: string; data: JSONObject; options: unknown }> = [];
  const doctorSignals: Array<AbortSignal | undefined> = [];
  let doctorCalls = 0;
  const recorded = hostLogRecorder();
  const context: CLICommandContext = {
    config,
    output: { stdout: value => stdout.push(value), stderr: value => stderr.push(value) },
    runtime: { async invoke(action, data = {}, options = {}) { runtimeCalls.push({ action, data, options }); return result; } },
    capabilityProbe: {
      async doctor(options?: { readonly signal?: AbortSignal }) {
        doctorCalls += 1;
        doctorSignals.push(options?.signal);
        return report as never;
      },
      invocationPolicy(action: string) { return action.startsWith("extension.") ? policy : undefined; }
    },
    workflowRunner: { async run() { return result; } },
    startMCP: async () => { stdout.push("mcp-frame\n"); },
    readFile: async () => "{}",
    writeArtifact: async (path, data) => { artifactWrites.push({ path, data }); },
    logger: recorded.logger
  };
  return {
    context,
    stdout,
    stderr,
    artifactWrites,
    runtimeCalls,
    getDoctorCalls: () => doctorCalls,
    getDoctorSignals: () => doctorSignals,
    logLines: recorded.lines,
    logEntries: recorded.entries
  };
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

  test("call 只校验 call_action wrapper，不在 CLI 重复校验 device action data", async () => {
    const state = fixture({ ok: true, data: {}, artifacts: [], elapsedMs: 0, attempts: 1 });
    const data = { unsupportedFutureField: true, maxDepth: "invalid-for-swift" };

    expect(await executeCLICommand("call", state.context, {
      action: " ui.inspect ",
      data: JSON.stringify(data)
    })).toBe(0);

    expect(state.runtimeCalls).toEqual([{ action: "ui.inspect", data, options: {} }]);
    expect(state.getDoctorCalls()).toBe(0);
  });

  test("call 对 extension action 使用 capability probe 发布的 invocation policy", async () => {
    const policy: InvocationPolicy = { idempotency: "readOnly", timeoutClass: "wait" };
    const state = fixture({ ok: true, data: {}, artifacts: [], elapsedMs: 0, attempts: 1 }, undefined, policy);

    expect(await executeCLICommand("call", state.context, {
      action: "extension.wait",
      data: "{}"
    })).toBe(0);

    expect(state.getDoctorCalls()).toBe(1);
    expect(state.runtimeCalls).toEqual([
      { action: "extension.wait", data: {}, options: { policy } }
    ]);
  });

  test("call 对 extension action 的 capability probe 传递 AbortSignal", async () => {
    const controller = new AbortController();
    const policy: InvocationPolicy = { idempotency: "readOnly", timeoutClass: "wait" };
    const state = fixture({ ok: true, data: {}, artifacts: [], elapsedMs: 0, attempts: 1 }, undefined, policy);

    expect(await executeCLICommand("call", { ...state.context, signal: controller.signal }, {
      action: "extension.wait",
      data: "{}"
    })).toBe(0);

    expect(state.getDoctorSignals()).toEqual([controller.signal]);
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
      { connection: "reachable", ping: { status: "failed", error: { source: "appEnvelope", code: "busy", message: "busy" } }, help: { status: "available" }, contractCompatibility: "exact" }
    );
    expect(await executeCLICommand("doctor", appFailure.context)).toBe(1);

    const transportFailure = fixture(
      { ok: true, data: {}, artifacts: [], elapsedMs: 0, attempts: 1 },
      { connection: "unreachable", ping: { status: "failed", error: { source: "transport", code: "transport_unavailable", message: "offline" } }, help: { status: "unknown" }, contractCompatibility: "unknown" }
    );
    expect(await executeCLICommand("doctor", transportFailure.context)).toBe(3);
  });

  test("doctor 输出合同 bundle 一致性和版本/hash 比较", async () => {
    const state = fixture(
      { ok: true, data: {}, artifacts: [], elapsedMs: 0, attempts: 1 },
      {
        connection: "reachable",
        ping: { status: "ok" },
        help: { status: "available" },
        contractCompatibility: "exact",
        metadata: { protocolVersionMatches: true, contractVersionMatches: true, hashMatches: true }
      }
    );

    expect(await executeCLICommand("doctor", state.context)).toBe(0);
    expect(JSON.parse(state.stdout.join(""))).toMatchObject({
      contractCompatibility: "exact",
      metadata: { protocolVersionMatches: true, contractVersionMatches: true, hashMatches: true }
    });
  });

  test("doctor 向 capability probe 传递 AbortSignal", async () => {
    const controller = new AbortController();
    const state = fixture({ ok: true, data: {}, artifacts: [], elapsedMs: 0, attempts: 1 });

    expect(await executeCLICommand("doctor", { ...state.context, signal: controller.signal })).toBe(0);

    expect(state.getDoctorSignals()).toEqual([controller.signal]);
  });

  test("doctor 将合同 bundle 不匹配视为 App 失败，将协议版本不匹配视为 protocol 失败", async () => {
    const success = { ok: true, data: {}, artifacts: [], elapsedMs: 0, attempts: 1 } as const;
    const mismatch = fixture(success, {
      connection: "reachable",
      ping: { status: "ok" },
      help: { status: "available" },
      contractCompatibility: "mismatch",
      metadata: { contractVersionMatches: false, hashMatches: false, protocolVersionMatches: true }
    });
    expect(await executeCLICommand("doctor", mismatch.context)).toBe(1);

    const unknown = fixture(success, {
      connection: "reachable",
      ping: { status: "ok" },
      help: { status: "available" },
      contractCompatibility: "unknown"
    });
    expect(await executeCLICommand("doctor", unknown.context)).toBe(1);

    const protocolMismatch = fixture(success, {
      connection: "reachable",
      ping: { status: "ok" },
      help: { status: "available" },
      contractCompatibility: "mismatch",
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
