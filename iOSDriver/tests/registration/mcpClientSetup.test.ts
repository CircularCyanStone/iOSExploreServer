import { describe, expect, test } from "vitest";
import {
  MCPClientSetupError,
  setupMCPClient,
  type MCPClientSetupInput,
  type MCPSetupCommandRunner,
  type MCPSetupFileSystem
} from "../../src/registration/mcpClientSetup.js";

const launch = Object.freeze({
  command: "/usr/local/bin/node",
  args: ["/opt/iosdriver/dist/adapters/cli/main.js", "mcp", "--config", "/home/u/.config/iosdriver/config.json"]
});

function input(client: MCPClientSetupInput["client"], overrides: Partial<MCPClientSetupInput> = {}): MCPClientSetupInput {
  return {
    client,
    cwd: "/workspace/app",
    homeDir: "/home/u",
    env: {},
    launch,
    ...overrides
  };
}

function memoryFileSystem(initial: Record<string, string> = {}): MCPSetupFileSystem & {
  readonly files: Record<string, string>;
  readonly writes: string[];
} {
  const files = { ...initial };
  const writes: string[] = [];
  return {
    files,
    writes,
    async readFile(path) {
      if (!(path in files)) throw Object.assign(new Error("missing"), { code: "ENOENT" });
      return files[path]!;
    },
    async mkdir() {},
    async writeFile(path, data) { files[path] = data; writes.push(path); },
    async rename(from, to) { files[to] = files[from]!; delete files[from]; }
  };
}

describe("MCP client setup", () => {
  test("Codex 不存在配置时调用官方 CLI 创建，重复配置保持幂等", async () => {
    const calls: Array<{ command: string; args: readonly string[] }> = [];
    const createRunner: MCPSetupCommandRunner = async (command, args) => {
      calls.push({ command, args });
      if (args[1] === "get") {
        return { exitCode: 1, stdout: "", stderr: "Error: No MCP server named 'iOSDriver' found." };
      }
      return { exitCode: 0, stdout: "Added global MCP server 'iOSDriver'.", stderr: "" };
    };

    await expect(setupMCPClient(input("codex"), { runCommand: createRunner })).resolves.toMatchObject({
      client: "codex",
      scope: "user",
      status: "created",
      operation: "create",
      manager: "codex-cli"
    });
    expect(calls[1]).toEqual({
      command: "codex",
      args: ["mcp", "add", "iOSDriver", "--", launch.command, ...launch.args]
    });

    const exactRunner: MCPSetupCommandRunner = async () => ({
      exitCode: 0,
      stdout: JSON.stringify({ transport: { type: "stdio", command: launch.command, args: launch.args, env: null } }),
      stderr: ""
    });
    await expect(setupMCPClient(input("codex"), { runCommand: exactRunner })).resolves.toMatchObject({
      status: "unchanged",
      operation: "none"
    });
  });

  test("Codex 同名冲突默认拒绝，force dry-run 只返回更新计划", async () => {
    const runner: MCPSetupCommandRunner = async () => ({
      exitCode: 0,
      stdout: JSON.stringify({ transport: { type: "stdio", command: "other", args: [] } }),
      stderr: ""
    });
    await expect(setupMCPClient(input("codex"), { runCommand: runner })).rejects.toThrow("--force");
    await expect(setupMCPClient(input("codex", { force: true, dryRun: true }), { runCommand: runner })).resolves.toMatchObject({
      status: "planned",
      operation: "update"
    });
  });

  test("Claude project 配置原子合并、幂等，并保留其他 MCP server", async () => {
    const path = "/workspace/app/.mcp.json";
    const fileSystem = memoryFileSystem({
      [path]: JSON.stringify({ mcpServers: { Existing: { command: "existing", args: [] } }, custom: true })
    });

    const created = await setupMCPClient(input("claude"), { fileSystem });
    expect(created).toMatchObject({ status: "created", operation: "create", configPath: path });
    expect(JSON.parse(fileSystem.files[path]!)).toEqual({
      mcpServers: {
        Existing: { command: "existing", args: [] },
        iOSDriver: { type: "stdio", command: launch.command, args: launch.args }
      },
      custom: true
    });

    const writesAfterCreate = fileSystem.writes.length;
    await expect(setupMCPClient(input("claude"), { fileSystem })).resolves.toMatchObject({ status: "unchanged" });
    expect(fileSystem.writes).toHaveLength(writesAfterCreate);
  });

  test("Claude 冲突需要 force；dry-run 不写文件", async () => {
    const path = "/home/u/.claude.json";
    const fileSystem = memoryFileSystem({
      [path]: JSON.stringify({ mcpServers: { iOSDriver: { type: "stdio", command: "other", args: [] } } })
    });
    const userInput = input("claude", { scope: "user" });

    await expect(setupMCPClient(userInput, { fileSystem })).rejects.toBeInstanceOf(MCPClientSetupError);
    await expect(setupMCPClient({ ...userInput, force: true, dryRun: true }, { fileSystem })).resolves.toMatchObject({
      status: "planned",
      operation: "update",
      configPath: path
    });
    expect(fileSystem.writes).toEqual([]);

    await expect(setupMCPClient({ ...userInput, force: true }, { fileSystem })).resolves.toMatchObject({ status: "updated" });
    expect(JSON.parse(fileSystem.files[path]!).mcpServers.iOSDriver.command).toBe(launch.command);
  });

  test("TRAE 只写项目 .trae/mcp.json，并拒绝 user scope", async () => {
    const path = "/workspace/app/.trae/mcp.json";
    const fileSystem = memoryFileSystem();
    await expect(setupMCPClient(input("trae"), { fileSystem })).resolves.toMatchObject({
      scope: "project",
      status: "created",
      configPath: path
    });
    expect(JSON.parse(fileSystem.files[path]!).mcpServers.iOSDriver).toEqual({
      command: launch.command,
      args: launch.args
    });
    await expect(setupMCPClient(input("trae", { scope: "user" }), { fileSystem })).rejects.toThrow("project scope");
  });

  test("Codex 拒绝 project scope，Claude 尊重 CLAUDE_CONFIG_DIR", async () => {
    await expect(setupMCPClient(input("codex", { scope: "project" }), {
      runCommand: async () => ({ exitCode: 0, stdout: "", stderr: "" })
    })).rejects.toThrow("user scope");

    const fileSystem = memoryFileSystem();
    const configured = input("claude", {
      scope: "user",
      env: { CLAUDE_CONFIG_DIR: "configs/claude" }
    });
    await expect(setupMCPClient(configured, { fileSystem })).resolves.toMatchObject({
      configPath: "/workspace/app/configs/claude/.claude.json"
    });
  });
});
