import { describe, expect, test } from "vitest";
import { configPathFor, initCLIConfig, resolveCLIConfig, type ConfigFileSystem } from "../../../src/adapters/cli/config.js";

function memoryFS(initial: Record<string, string> = {}): ConfigFileSystem & { files: Record<string, string>; renames: number } {
  const files = { ...initial };
  const state = { files, renames: 0 };
  return {
    files,
    get renames() { return state.renames; },
    async readFile(path) {
      if (!(path in files)) throw Object.assign(new Error("missing"), { code: "ENOENT" });
      return files[path]!;
    },
    async mkdir() {},
    async writeFile(path, data) { files[path] = data; },
    async rename(from, to) { files[to] = files[from]!; delete files[from]; state.renames += 1; }
  };
}

describe("CLI config", () => {
  test("优先级为命令行 > 环境 > 文件 > 默认值，并计算配置路径", async () => {
    const fs = memoryFS({ "/tmp/config.json": JSON.stringify({ baseURL: "http://file:1", requestTimeoutMs: 100 }) });
    const config = await resolveCLIConfig(
      { configPath: "/tmp/config.json", baseURL: "http://cli:2", requestTimeoutMs: 300 },
      { IOS_EXPLORE_BASE_URL: "http://env:3", IOS_EXPLORE_REQUEST_TIMEOUT_MS: "200" },
      fs
    );
    expect(config.baseURL).toBe("http://cli:2/");
    expect(config.requestTimeoutMs).toBe(300);

    const environmentConfig = await resolveCLIConfig(
      { configPath: "/tmp/config.json" },
      { IOS_EXPLORE_BASE_URL: "http://env:3", IOS_EXPLORE_REQUEST_TIMEOUT_MS: "200" },
      fs
    );
    expect(environmentConfig.baseURL).toBe("http://env:3/");
    expect(environmentConfig.requestTimeoutMs).toBe(200);
    expect(configPathFor({ XDG_CONFIG_HOME: "/tmp/xdg" }, "/home/u")).toBe("/tmp/xdg/iosdriver/config.json");
  });

  test("init 原子且幂等，保留未知字段和用户值", async () => {
    const fs = memoryFS({ "/tmp/config.json": JSON.stringify({ baseURL: "http://user:1", custom: true }) });
    const first = await initCLIConfig({ configPath: "/tmp/config.json" }, {}, fs);
    const second = await initCLIConfig({ configPath: "/tmp/config.json" }, {}, fs);
    expect(first.config.baseURL).toBe("http://user:1/");
    expect(JSON.parse(fs.files["/tmp/config.json"]!)).toMatchObject({ baseURL: "http://user:1", custom: true, requestTimeoutMs: 10000 });
    expect(first.configChanged).toBe(true);
    expect(second.configChanged).toBe(false);
    expect(fs.renames).toBe(1);
  });
});
