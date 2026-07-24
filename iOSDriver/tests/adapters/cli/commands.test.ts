import { describe, expect, test } from "vitest";
import { executeCLICommand, type CLICommandContext } from "../../../src/adapters/cli/commands.js";
import type { CLIConfig, ConfigFileSystem } from "../../../src/adapters/cli/config.js";
import type { InvocationResult } from "../../../src/runtime/types.js";

const config: CLIConfig = Object.freeze({ baseURL: "http://localhost:38321/", requestTimeoutMs: 10000, configPath: "/tmp/config.json", fileValues: {} });

function fixture(result: InvocationResult, report: Record<string, unknown> = { connection: "reachable", ping: { status: "ok" }, help: { status: "available" }, schemaCompatibility: "exact" }) {
  const stdout: string[] = [];
  const stderr: string[] = [];
  const artifactWrites: Array<{ path: string; data: Uint8Array }> = [];
  const context: CLICommandContext = {
    config,
    output: { stdout: value => stdout.push(value), stderr: value => stderr.push(value) },
    runtime: { async invoke() { return result; } },
    capabilityProbe: { async doctor() { return report as never; } },
    workflowRunner: { async run() { return result; } },
    startMCP: async () => { stdout.push("mcp-frame\n"); },
    readFile: async () => "{}",
    writeArtifact: async (path, data) => { artifactWrites.push({ path, data }); }
  };
  return { context, stdout, stderr, artifactWrites };
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
    expect(JSON.parse(state.stdout.join(""))).toMatchObject({ mcp: { command: "iosdriver", args: ["mcp"] } });
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

  test("mcp 不写业务 stdout，直接使用注入的 stdio 启动器", async () => {
    const state = fixture({ ok: true, data: {}, artifacts: [], elapsedMs: 0, attempts: 1 });
    state.stdout.length = 0;
    state.context.startMCP = async () => {};
    expect(await executeCLICommand("mcp", state.context)).toBe(0);
    expect(state.stderr).toEqual([]);
  });
});
