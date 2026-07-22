import { createServer, type Server as HTTPServer } from "node:http";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";
import { afterEach, describe, expect, test } from "vitest";
import { STATIC_TOOL_NAMES } from "../src/staticTools.js";

const clients: Client[] = [];
const httpServers: HTTPServer[] = [];

afterEach(async () => {
  await Promise.all(clients.splice(0).map(client => client.close()));
  await Promise.all(httpServers.splice(0).map(server => new Promise<void>(resolve => server.close(() => resolve()))));
});

describe("stdio startup", () => {
  test("App 不可达时仍返回完整静态工具集合，且不声明 listChanged", async () => {
    const client = await connectClient("http://127.0.0.1:1/");
    const first = await client.listTools();
    const second = await client.listTools();
    expect(first).toEqual(second);
    expect(first.tools.map(tool => tool.name).sort()).toEqual([...STATIC_TOOL_NAMES].sort());
    expect(client.getServerCapabilities()?.tools?.listChanged).not.toBe(true);
  });

  test("App 启动前后 tools/list 完全一致", async () => {
    const client = await connectClient(await startHelpServer());
    const before = await client.listTools();
    await client.callTool({ name: "health_check", arguments: {} });
    const after = await client.listTools();
    expect(after).toEqual(before);
  });
});

async function connectClient(baseURL: string): Promise<Client> {
  const client = new Client({ name: "ios-driver-startup-test", version: "1.0.0" }, { capabilities: {} });
  clients.push(client);
  await client.connect(new StdioClientTransport({
    command: process.execPath, args: ["dist/index.js"], cwd: process.cwd(),
    env: { IOS_EXPLORE_BASE_URL: baseURL, IOS_EXPLORE_REQUEST_TIMEOUT_MS: "250" }, stderr: "pipe"
  }));
  return client;
}

async function startHelpServer(): Promise<string> {
  const server = createServer((request, response) => {
    request.resume();
    response.writeHead(200, { "Content-Type": "application/json" });
    response.end(JSON.stringify({ code: "ok", data: { commands: [] } }));
  });
  httpServers.push(server);
  await new Promise<void>((resolve, reject) => { server.once("error", reject); server.listen(0, "127.0.0.1", resolve); });
  const address = server.address();
  if (!address || typeof address === "string") throw new Error("failed to allocate HTTP test port");
  return `http://127.0.0.1:${address.port}/`;
}
