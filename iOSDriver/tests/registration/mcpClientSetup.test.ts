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

  test("Claude 不存在配置时通过官方 CLI 创建 local 注册，并完整透传启动参数", async () => {
    const calls: Array<{ command: string; args: readonly string[] }> = [];
    const runner: MCPSetupCommandRunner = async (command, args) => {
      calls.push({ command, args });
      if (args[1] === "get") {
        return { exitCode: 1, stdout: "No MCP server named \"iOSDriver\". Configured servers: none", stderr: "" };
      }
      return { exitCode: 0, stdout: "Added stdio MCP server iOSDriver", stderr: "" };
    };

    await expect(setupMCPClient(input("claude"), { runCommand: runner })).resolves.toMatchObject({
      client: "claude",
      scope: "local",
      status: "created",
      operation: "create",
      manager: "claude-cli"
    });
    expect(calls).toEqual([
      { command: "claude", args: ["mcp", "get", "iOSDriver"] },
      {
        command: "claude",
        args: [
          "mcp", "add", "--transport", "stdio", "--scope", "local", "iOSDriver", "--",
          launch.command, ...launch.args
        ]
      }
    ]);
  });

  test("Claude 配置相同时保持幂等，不执行 add 或 remove", async () => {
    const calls: string[][] = [];
    const runner: MCPSetupCommandRunner = async (_command, args) => {
      calls.push([...args]);
      return {
        exitCode: 0,
        stdout: [
          "iOSDriver:",
          "  Scope: User config (available in all your projects)",
          "  Status: ✔ Connected",
          "  Type: stdio",
          `  Command: ${launch.command}`,
          `  Args: ${launch.args.join(" ")}`,
          "  Environment:"
        ].join("\n"),
        stderr: ""
      };
    };

    await expect(setupMCPClient(input("claude", { scope: "user" }), { runCommand: runner })).resolves.toMatchObject({
      scope: "user",
      status: "unchanged",
      operation: "none",
      manager: "claude-cli"
    });
    expect(calls).toEqual([["mcp", "get", "iOSDriver"]]);
  });

  test("Claude 冲突默认拒绝，force dry-run 只返回更新计划", async () => {
    const calls: string[][] = [];
    const runner: MCPSetupCommandRunner = async (_command, args) => {
      calls.push([...args]);
      return {
        exitCode: 0,
        stdout: "iOSDriver:\n  Type: stdio\n  Command: other\n  Args: other.js\n  Environment:",
        stderr: ""
      };
    };

    await expect(setupMCPClient(input("claude"), { runCommand: runner })).rejects.toThrow("--force");
    calls.length = 0;
    await expect(setupMCPClient(input("claude", { force: true, dryRun: true }), { runCommand: runner })).resolves.toMatchObject({
      status: "planned",
      operation: "update",
      manager: "claude-cli"
    });
    expect(calls).toEqual([["mcp", "get", "iOSDriver"]]);
  });

  test("Claude force 更新按 get、remove、add 顺序调用官方 CLI", async () => {
    const calls: string[][] = [];
    const runner: MCPSetupCommandRunner = async (_command, args) => {
      calls.push([...args]);
      if (args[1] === "get") {
        return {
          exitCode: 0,
          stdout: "iOSDriver:\n  Type: stdio\n  Command: other\n  Args: other.js\n  Environment:",
          stderr: ""
        };
      }
      return { exitCode: 0, stdout: "ok", stderr: "" };
    };

    await expect(setupMCPClient(input("claude", { scope: "project", force: true }), { runCommand: runner })).resolves.toMatchObject({
      scope: "project",
      status: "updated",
      operation: "update"
    });
    expect(calls).toEqual([
      ["mcp", "get", "iOSDriver"],
      ["mcp", "remove", "iOSDriver", "--scope", "project"],
      [
        "mcp", "add", "--transport", "stdio", "--scope", "project", "iOSDriver", "--",
        launch.command, ...launch.args
      ]
    ]);
  });

  test("Claude get 输出不可解析或 remove/add 失败时返回 setup 错误", async () => {
    await expect(setupMCPClient(input("claude"), {
      runCommand: async () => ({ exitCode: 0, stdout: "iOSDriver: malformed", stderr: "" })
    })).rejects.toThrow("无法解析");

    const failingRunner = (failure: "remove" | "add"): MCPSetupCommandRunner => async (_command, args) => {
      if (args[1] === "get") {
        return {
          exitCode: 0,
          stdout: "iOSDriver:\n  Type: stdio\n  Command: other\n  Args: other.js\n  Environment:",
          stderr: ""
        };
      }
      if (args[1] === failure) return { exitCode: 9, stdout: "", stderr: `${failure} failed` };
      return { exitCode: 0, stdout: "ok", stderr: "" };
    };

    await expect(setupMCPClient(input("claude", { force: true }), {
      runCommand: failingRunner("remove")
    })).rejects.toThrow("claude mcp remove");
    await expect(setupMCPClient(input("claude", { force: true }), {
      runCommand: failingRunner("add")
    })).rejects.toThrow("claude mcp add");
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

  test("Codex 拒绝 local/project scope，TRAE 拒绝 local/user scope", async () => {
    await expect(setupMCPClient(input("codex", { scope: "project" }), {
      runCommand: async () => ({ exitCode: 0, stdout: "", stderr: "" })
    })).rejects.toThrow("user scope");
    await expect(setupMCPClient(input("codex", { scope: "local" }), {
      runCommand: async () => ({ exitCode: 0, stdout: "", stderr: "" })
    })).rejects.toThrow("user scope");
    await expect(setupMCPClient(input("trae", { scope: "local" }), {
      fileSystem: memoryFileSystem()
    })).rejects.toThrow("project scope");
  });
});
