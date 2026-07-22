import { createServer, type Server as HTTPServer } from "node:http";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";
import { ToolListChangedNotificationSchema } from "@modelcontextprotocol/sdk/types.js";
import { afterEach, describe, expect, test } from "vitest";

const clients: Client[] = [];
const httpServers: HTTPServer[] = [];

afterEach(async () => {
  await Promise.all(clients.splice(0).map(client => client.close()));
  await Promise.all(httpServers.splice(0).map(server => new Promise<void>(resolve => server.close(() => resolve()))));
});

describe("stdio startup", () => {
  test("App 不可达时仍立即暴露静态工具", async () => {
    const startedAt = Date.now();
    const client = await connectClient("http://127.0.0.1:1/");

    const listed = await client.listTools();
    const names = listed.tools.map(tool => tool.name);

    expect(Date.now() - startedAt).toBeLessThan(1_000);
    expect(names).toContain("health_check");
    expect(names).toContain("call_action");
    expect(names).not.toContain("greet");
  });

  test("初始化后动态列表变化会通知客户端重新读取 tools/list", async () => {
    const baseURL = await startHelpServer();
    let resolveNotification: (() => void) | undefined;
    const notification = new Promise<void>(resolve => { resolveNotification = resolve; });
    const client = new Client({ name: "ios-driver-startup-test", version: "1.0.0" }, { capabilities: {} });
    clients.push(client);
    client.setNotificationHandler(ToolListChangedNotificationSchema, async () => {
      resolveNotification?.();
    });

    await client.connect(createTransport(baseURL));
    await Promise.race([
      notification,
      new Promise<never>((_, reject) => setTimeout(() => reject(new Error("tools/list_changed timeout")), 2_000))
    ]);

    expect(client.getServerCapabilities()?.tools?.listChanged).toBe(true);
    const listed = await client.listTools();
    const names = listed.tools.map(tool => tool.name);
    expect(names).toContain("health_check");
    expect(names).toContain("greet");
  });
});

async function connectClient(baseURL: string): Promise<Client> {
  const client = new Client({ name: "ios-driver-startup-test", version: "1.0.0" }, { capabilities: {} });
  clients.push(client);
  await client.connect(createTransport(baseURL));
  return client;
}

function createTransport(baseURL: string): StdioClientTransport {
  return new StdioClientTransport({
    command: process.execPath,
    args: ["dist/index.js"],
    cwd: process.cwd(),
    env: {
      IOS_EXPLORE_BASE_URL: baseURL,
      IOS_EXPLORE_REQUEST_TIMEOUT_MS: "250"
    },
    stderr: "pipe"
  });
}

async function startHelpServer(): Promise<string> {
  const server = createServer((request, response) => {
    request.resume();
    response.writeHead(200, { "Content-Type": "application/json" });
    response.end(JSON.stringify({
      code: "ok",
      data: {
        commands: [
          {
            action: "greet",
            description: "按 name 打招呼",
            inputSchema: { type: "object", properties: { name: { type: "string" } } }
          }
        ]
      }
    }));
  });
  httpServers.push(server);
  await new Promise<void>((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", resolve);
  });
  const address = server.address();
  if (!address || typeof address === "string") {
    throw new Error("failed to allocate HTTP test port");
  }
  return `http://127.0.0.1:${address.port}/`;
}
