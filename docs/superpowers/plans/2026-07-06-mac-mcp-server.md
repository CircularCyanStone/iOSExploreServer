# Mac MCP Server Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Mac-local TypeScript MCP server that exposes the existing iOSExplore HTTP actions as MCP tools and adds Agent-friendly fixed tools for observation, action forwarding, and wait-then-observe flow.

**Architecture:** Keep the iPhone-side Swift libraries unchanged except for pre-existing contract text fixes that affect `help` output. Add a root-level `MCPServer/` Node package that talks to `http://localhost:38321/`, discovers dynamic tools from `help`, and exposes fixed MCP tools through stdio.

**Tech Stack:** Swift tests for the UIKit contract fix; Node 20+, TypeScript, `@modelcontextprotocol/sdk`, Vitest, built-in `fetch` and `http` test server.

---

## File Structure

Swift contract repair:

- Modify: `Sources/iOSExploreUIKit/Commands/Input/UIInputCommand.swift`
  - Responsibility: `help` description for `ui.input`.
- Modify: `Tests/iOSExploreServerTests/UIKitCommandInputSchemaTests.swift`
  - Responsibility: command schema and description contract assertions.

MCP server package:

- Create: `MCPServer/package.json`
  - Responsibility: Node package scripts and dependencies.
- Create: `MCPServer/tsconfig.json`
  - Responsibility: strict TypeScript compiler options.
- Create: `MCPServer/vitest.config.ts`
  - Responsibility: Vitest configuration.
- Create: `MCPServer/README.md`
  - Responsibility: local startup, environment variables, true-device `iproxy` note, recommended tool sequence.
- Create: `MCPServer/src/config.ts`
  - Responsibility: environment parsing and request timeout settings.
- Create: `MCPServer/src/types.ts`
  - Responsibility: shared JSON, envelope, tool, and result types.
- Create: `MCPServer/src/errors.ts`
  - Responsibility: structured error normalization for MCP, transport, HTTP, and iOS envelope errors.
- Create: `MCPServer/src/iosExploreClient.ts`
  - Responsibility: HTTP `POST /` client and envelope parsing.
- Create: `MCPServer/src/toolName.ts`
  - Responsibility: action-to-tool-name mapping and conflict detection.
- Create: `MCPServer/src/schemaMapper.ts`
  - Responsibility: map iOSExplore `inputSchema` into MCP-compatible JSON schema and preserve extension constraints.
- Create: `MCPServer/src/toolRegistry.ts`
  - Responsibility: call `help`, build dynamic tools, and preserve `call_action` fallback.
- Create: `MCPServer/src/result.ts`
  - Responsibility: MCP text/JSON result builders.
- Create: `MCPServer/src/staticTools.ts`
  - Responsibility: `health_check`, `refresh_tools`, `call_action`, `observe`, `wait_and_observe`.
- Create: `MCPServer/src/server.ts`
  - Responsibility: low-level MCP `tools/list` and `tools/call` handlers.
- Create: `MCPServer/src/index.ts`
  - Responsibility: stdio process entrypoint.

MCP server tests:

- Create: `MCPServer/tests/iosExploreClient.test.ts`
- Create: `MCPServer/tests/toolName.test.ts`
- Create: `MCPServer/tests/schemaMapper.test.ts`
- Create: `MCPServer/tests/toolRegistry.test.ts`
- Create: `MCPServer/tests/staticTools.test.ts`
- Create: `MCPServer/tests/server.test.ts`
- Create: `MCPServer/tests/support/mockIOSExploreServer.ts`

Docs:

- Modify: `docs/superpowers/agent-mcp-exploration/README.md`
  - Responsibility: mark first implementation state after the server lands.
- Modify: `docs/uikit/agent-command-protocol.md`
  - Responsibility: keep tool names and `ui.input` contract aligned.

## Task 1: Repair `ui.input` Help Contract

**Files:**
- Modify: `Sources/iOSExploreUIKit/Commands/Input/UIInputCommand.swift`
- Modify: `Tests/iOSExploreServerTests/UIKitCommandInputSchemaTests.swift`

- [ ] **Step 1: Write failing description contract test**

Add this test to `Tests/iOSExploreServerTests/UIKitCommandInputSchemaTests.swift` before `#endif`:

```swift
@Test("ui.input 命令 description 写明 viewSnapshotID 只与 path 搭配")
func inputCommandDescriptionExplainsViewSnapshotPathOnly() {
    let description = InputCommand().description
    #expect(description.contains("accessibilityIdentifier 或 path"))
    #expect(description.contains("viewSnapshotID 仅允许与 path 搭配"))
    #expect(description.contains("identifier 定位不能带 viewSnapshotID"))
    #expect(description.contains("必须先调 ui.viewTargets") == false)
}
```

- [ ] **Step 2: Run the focused Swift test and verify failure**

Run:

```bash
swift test --filter inputCommandDescriptionExplainsViewSnapshotPathOnly
```

Expected: FAIL because the current description still says the caller must pass the same `viewSnapshotID` for all `ui.input` calls.

- [ ] **Step 3: Update `InputCommand.description`**

In `Sources/iOSExploreUIKit/Commands/Input/UIInputCommand.swift`, replace the `description` line with:

```swift
    let description = "向 UITextField/UITextView/UISearchTextField 注入文本 (UITextInput.insertText)。目标用 accessibilityIdentifier 或 path 定位；viewSnapshotID 仅允许与 path 搭配做可选陈旧校验，identifier 定位不能带 viewSnapshotID"
```

- [ ] **Step 4: Run the focused Swift test and verify pass**

Run:

```bash
swift test --filter inputCommandDescriptionExplainsViewSnapshotPathOnly
```

Expected: PASS.

- [ ] **Step 5: Run existing input parsing tests**

Run:

```bash
swift test --filter UIInput
```

Expected: PASS. This confirms runtime parsing still rejects `viewSnapshotID` with identifier and allows optional `viewSnapshotID` with path.

- [ ] **Step 6: Commit**

```bash
git add Sources/iOSExploreUIKit/Commands/Input/UIInputCommand.swift Tests/iOSExploreServerTests/UIKitCommandInputSchemaTests.swift
git commit -m "docs(uikit): align ui.input help contract"
```

## Task 2: Scaffold `MCPServer/`

**Files:**
- Create: `MCPServer/package.json`
- Create: `MCPServer/tsconfig.json`
- Create: `MCPServer/vitest.config.ts`
- Create: `MCPServer/src/index.ts`

- [ ] **Step 1: Create `package.json`**

Create `MCPServer/package.json`:

```json
{
  "name": "ios-explore-mcp-server",
  "version": "0.1.0",
  "private": true,
  "type": "module",
  "bin": {
    "ios-explore-mcp-server": "./dist/index.js"
  },
  "scripts": {
    "build": "tsc -p tsconfig.json",
    "dev": "tsx src/index.ts",
    "test": "vitest run",
    "test:watch": "vitest",
    "typecheck": "tsc -p tsconfig.json --noEmit"
  },
  "dependencies": {
    "@modelcontextprotocol/sdk": "^1.17.0"
  },
  "devDependencies": {
    "@types/node": "^22.0.0",
    "tsx": "^4.19.0",
    "typescript": "^5.6.0",
    "vitest": "^2.1.0"
  },
  "engines": {
    "node": ">=20.0.0"
  }
}
```

- [ ] **Step 2: Create TypeScript config**

Create `MCPServer/tsconfig.json`:

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "lib": ["ES2022", "DOM"],
    "types": ["node"],
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "exactOptionalPropertyTypes": true,
    "esModuleInterop": true,
    "forceConsistentCasingInFileNames": true,
    "skipLibCheck": true,
    "outDir": "dist",
    "rootDir": "."
  },
  "include": ["src/**/*.ts", "tests/**/*.ts", "vitest.config.ts"]
}
```

- [ ] **Step 3: Create Vitest config**

Create `MCPServer/vitest.config.ts`:

```ts
import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    environment: "node",
    include: ["tests/**/*.test.ts"],
    testTimeout: 10000
  }
});
```

- [ ] **Step 4: Create temporary entrypoint**

Create `MCPServer/src/index.ts`:

```ts
console.error("ios-explore-mcp-server: scaffold ready");
```

- [ ] **Step 5: Install dependencies**

Run:

```bash
cd MCPServer
npm install
```

Expected: `package-lock.json` is created and dependencies install successfully.

- [ ] **Step 6: Verify scaffold**

Run:

```bash
cd MCPServer
npm run typecheck
npm run build
```

Expected:

- `typecheck` passes.
- `build` emits `dist/index.js`.

- [ ] **Step 7: Commit**

```bash
git add MCPServer/package.json MCPServer/package-lock.json MCPServer/tsconfig.json MCPServer/vitest.config.ts MCPServer/src/index.ts
git commit -m "feat(mcp): scaffold mac mcp server"
```

## Task 3: Implement Config, Types, and Result Helpers

**Files:**
- Create: `MCPServer/src/config.ts`
- Create: `MCPServer/src/types.ts`
- Create: `MCPServer/src/result.ts`
- Create: `MCPServer/tests/config.test.ts`
- Create: `MCPServer/tests/result.test.ts`

- [ ] **Step 1: Write config tests**

Create `MCPServer/tests/config.test.ts`:

```ts
import { describe, expect, test } from "vitest";
import { loadConfig, requestTimeoutForAction } from "../src/config.js";

describe("config", () => {
  test("uses localhost defaults", () => {
    const config = loadConfig({});
    expect(config.baseURL).toBe("http://localhost:38321/");
    expect(config.requestTimeoutMs).toBe(10000);
  });

  test("normalizes base URL trailing slash", () => {
    const config = loadConfig({ IOS_EXPLORE_BASE_URL: "http://127.0.0.1:38321" });
    expect(config.baseURL).toBe("http://127.0.0.1:38321/");
  });

  test("rejects invalid base URL", () => {
    expect(() => loadConfig({ IOS_EXPLORE_BASE_URL: "not a url" })).toThrow("IOS_EXPLORE_BASE_URL");
  });

  test("wait actions use data timeout plus grace", () => {
    const config = loadConfig({ IOS_EXPLORE_REQUEST_TIMEOUT_MS: "10000" });
    expect(requestTimeoutForAction(config, "ui.waitAny", { timeoutMs: 8000 })).toBe(13000);
    expect(requestTimeoutForAction(config, "ui.wait", { timeoutMs: 1000 })).toBe(10000);
    expect(requestTimeoutForAction(config, "ui.tap", { timeoutMs: 8000 })).toBe(10000);
  });
});
```

- [ ] **Step 2: Write result tests**

Create `MCPServer/tests/result.test.ts`:

```ts
import { describe, expect, test } from "vitest";
import { jsonResult, errorResult } from "../src/result.js";

describe("MCP result helpers", () => {
  test("jsonResult returns structured JSON text content", () => {
    const result = jsonResult({ ok: true });
    expect(result.isError).toBe(false);
    expect(result.content[0]).toEqual({
      type: "text",
      text: JSON.stringify({ ok: true }, null, 2)
    });
  });

  test("errorResult keeps structured payload", () => {
    const result = errorResult({ source: "transport", code: "connection_failed", message: "down" });
    expect(result.isError).toBe(true);
    expect(JSON.parse(result.content[0].text)).toEqual({
      source: "transport",
      code: "connection_failed",
      message: "down"
    });
  });
});
```

- [ ] **Step 3: Run tests and verify failure**

Run:

```bash
cd MCPServer
npm test -- config.test.ts result.test.ts
```

Expected: FAIL because source files do not exist.

- [ ] **Step 4: Implement shared types**

Create `MCPServer/src/types.ts`:

```ts
export type JSONPrimitive = string | number | boolean | null;
export type JSONValue = JSONPrimitive | JSONObject | JSONValue[];
export type JSONObject = { [key: string]: JSONValue };

export type IOSExploreSuccessEnvelope = {
  code: "ok";
  data?: JSONObject;
};

export type IOSExploreFailureEnvelope = {
  code: string;
  message: string;
};

export type IOSExploreEnvelope = IOSExploreSuccessEnvelope | IOSExploreFailureEnvelope;

export type CommandMetadata = {
  action: string;
  description: string;
  inputSchema: JSONObject;
};

export type ToolDefinition = {
  name: string;
  description: string;
  inputSchema: JSONObject;
  action?: string;
};

export type StructuredError = {
  source: "mcp_server" | "transport" | "http" | "ios_envelope";
  code?: string;
  message: string;
  action?: string;
  baseURL?: string;
  status?: number;
  timeoutMs?: number;
  bodySnippet?: string;
};

export type MCPTextContent = {
  type: "text";
  text: string;
};

export type MCPToolResult = {
  content: MCPTextContent[];
  isError?: boolean;
};
```

- [ ] **Step 5: Implement config**

Create `MCPServer/src/config.ts`:

```ts
import type { JSONObject } from "./types.js";

export type MCPServerConfig = {
  baseURL: string;
  requestTimeoutMs: number;
};

export function loadConfig(env: NodeJS.ProcessEnv = process.env): MCPServerConfig {
  const rawBaseURL = env.IOS_EXPLORE_BASE_URL ?? "http://localhost:38321/";
  let baseURL: URL;
  try {
    baseURL = new URL(rawBaseURL);
  } catch {
    throw new Error(`IOS_EXPLORE_BASE_URL must be a valid URL, got '${rawBaseURL}'`);
  }
  if (baseURL.protocol !== "http:" && baseURL.protocol !== "https:") {
    throw new Error(`IOS_EXPLORE_BASE_URL must use http or https, got '${rawBaseURL}'`);
  }
  if (!baseURL.pathname.endsWith("/")) {
    baseURL.pathname = `${baseURL.pathname}/`;
  }

  const timeoutRaw = env.IOS_EXPLORE_REQUEST_TIMEOUT_MS ?? "10000";
  const requestTimeoutMs = Number(timeoutRaw);
  if (!Number.isInteger(requestTimeoutMs) || requestTimeoutMs <= 0) {
    throw new Error(`IOS_EXPLORE_REQUEST_TIMEOUT_MS must be a positive integer, got '${timeoutRaw}'`);
  }

  return {
    baseURL: baseURL.toString(),
    requestTimeoutMs
  };
}

export function requestTimeoutForAction(config: MCPServerConfig, action: string, data: JSONObject = {}): number {
  if (action !== "ui.wait" && action !== "ui.waitAny") {
    return config.requestTimeoutMs;
  }
  const timeoutMs = typeof data.timeoutMs === "number" ? data.timeoutMs : 0;
  return Math.max(config.requestTimeoutMs, timeoutMs + 5000);
}
```

- [ ] **Step 6: Implement result helpers**

Create `MCPServer/src/result.ts`:

```ts
import type { JSONValue, MCPToolResult, StructuredError } from "./types.js";

export function jsonResult(value: JSONValue, isError = false): MCPToolResult {
  return {
    isError,
    content: [
      {
        type: "text",
        text: JSON.stringify(value, null, 2)
      }
    ]
  };
}

export function errorResult(error: StructuredError): MCPToolResult {
  return jsonResult(error, true);
}
```

- [ ] **Step 7: Run tests and verify pass**

Run:

```bash
cd MCPServer
npm test -- config.test.ts result.test.ts
npm run typecheck
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add MCPServer/src/config.ts MCPServer/src/types.ts MCPServer/src/result.ts MCPServer/tests/config.test.ts MCPServer/tests/result.test.ts
git commit -m "feat(mcp): add config and result helpers"
```

## Task 4: Implement Error Mapper and HTTP Client

**Files:**
- Create: `MCPServer/src/errors.ts`
- Create: `MCPServer/src/iosExploreClient.ts`
- Create: `MCPServer/tests/iosExploreClient.test.ts`
- Create: `MCPServer/tests/support/mockIOSExploreServer.ts`

- [ ] **Step 1: Write mock server helper**

Create `MCPServer/tests/support/mockIOSExploreServer.ts`:

```ts
import http from "node:http";
import type { AddressInfo } from "node:net";
import type { JSONObject, JSONValue } from "../../src/types.js";

export type RecordedRequest = {
  action: string;
  data: JSONObject;
};

export type MockRoute = (request: RecordedRequest) => {
  status?: number;
  body: JSONValue | string;
  delayMs?: number;
};

export async function withMockIOSExploreServer<T>(
  route: MockRoute,
  run: (context: { baseURL: string; requests: RecordedRequest[] }) => Promise<T>
): Promise<T> {
  const requests: RecordedRequest[] = [];
  const server = http.createServer((req, res) => {
    let body = "";
    req.setEncoding("utf8");
    req.on("data", chunk => {
      body += chunk;
    });
    req.on("end", () => {
      const parsed = JSON.parse(body) as RecordedRequest;
      requests.push(parsed);
      const response = route(parsed);
      const send = () => {
        res.statusCode = response.status ?? 200;
        res.setHeader("Content-Type", typeof response.body === "string" ? "text/plain" : "application/json");
        res.end(typeof response.body === "string" ? response.body : JSON.stringify(response.body));
      };
      if (response.delayMs && response.delayMs > 0) {
        setTimeout(send, response.delayMs);
      } else {
        send();
      }
    });
  });

  await new Promise<void>(resolve => server.listen(0, "127.0.0.1", resolve));
  const address = server.address() as AddressInfo;
  try {
    return await run({ baseURL: `http://127.0.0.1:${address.port}/`, requests });
  } finally {
    await new Promise<void>(resolve => server.close(() => resolve()));
  }
}
```

- [ ] **Step 2: Write HTTP client tests**

Create `MCPServer/tests/iosExploreClient.test.ts`:

```ts
import { describe, expect, test } from "vitest";
import { IOSExploreClient } from "../src/iosExploreClient.js";
import { withMockIOSExploreServer } from "./support/mockIOSExploreServer.js";

describe("IOSExploreClient", () => {
  test("posts action and data to POST /", async () => {
    await withMockIOSExploreServer(
      request => ({ body: { code: "ok", data: { echoed: request.data } } }),
      async ({ baseURL, requests }) => {
        const client = new IOSExploreClient({ baseURL, requestTimeoutMs: 10000 });
        const result = await client.call("echo", { name: "Ada" });
        expect(result).toEqual({ echoed: { name: "Ada" } });
        expect(requests).toEqual([{ action: "echo", data: { name: "Ada" } }]);
      }
    );
  });

  test("throws structured iOS envelope error", async () => {
    await withMockIOSExploreServer(
      () => ({ body: { code: "invalid_data", message: "bad field" } }),
      async ({ baseURL }) => {
        const client = new IOSExploreClient({ baseURL, requestTimeoutMs: 10000 });
        await expect(client.call("ui.tap", {})).rejects.toMatchObject({
          source: "ios_envelope",
          code: "invalid_data",
          action: "ui.tap",
          message: "bad field"
        });
      }
    );
  });

  test("throws structured HTTP error with body snippet", async () => {
    await withMockIOSExploreServer(
      () => ({ status: 500, body: "server exploded" }),
      async ({ baseURL }) => {
        const client = new IOSExploreClient({ baseURL, requestTimeoutMs: 10000 });
        await expect(client.call("ping", {})).rejects.toMatchObject({
          source: "http",
          status: 500,
          action: "ping",
          bodySnippet: "server exploded"
        });
      }
    );
  });

  test("wait action timeout uses command timeout plus grace", async () => {
    await withMockIOSExploreServer(
      () => ({ delayMs: 50, body: { code: "wait_timeout", message: "timeout" } }),
      async ({ baseURL }) => {
        const client = new IOSExploreClient({ baseURL, requestTimeoutMs: 10 });
        await expect(client.call("ui.waitAny", { timeoutMs: 40 })).rejects.toMatchObject({
          source: "ios_envelope",
          code: "wait_timeout",
          action: "ui.waitAny"
        });
      }
    );
  });
});
```

- [ ] **Step 3: Run tests and verify failure**

Run:

```bash
cd MCPServer
npm test -- iosExploreClient.test.ts
```

Expected: FAIL because `IOSExploreClient` does not exist.

- [ ] **Step 4: Implement error helpers**

Create `MCPServer/src/errors.ts`:

```ts
import type { StructuredError } from "./types.js";

export class IOSExploreStructuredError extends Error implements StructuredError {
  readonly source: StructuredError["source"];
  readonly code?: string;
  readonly action?: string;
  readonly baseURL?: string;
  readonly status?: number;
  readonly timeoutMs?: number;
  readonly bodySnippet?: string;

  constructor(error: StructuredError) {
    super(error.message);
    this.name = "IOSExploreStructuredError";
    this.source = error.source;
    this.code = error.code;
    this.action = error.action;
    this.baseURL = error.baseURL;
    this.status = error.status;
    this.timeoutMs = error.timeoutMs;
    this.bodySnippet = error.bodySnippet;
  }

  toJSON(): StructuredError {
    return compactError({
      source: this.source,
      code: this.code,
      message: this.message,
      action: this.action,
      baseURL: this.baseURL,
      status: this.status,
      timeoutMs: this.timeoutMs,
      bodySnippet: this.bodySnippet
    });
  }
}

export function bodySnippet(body: string): string {
  return body.length > 500 ? `${body.slice(0, 500)}...` : body;
}

function compactError(error: StructuredError): StructuredError {
  return Object.fromEntries(Object.entries(error).filter(([, value]) => value !== undefined)) as StructuredError;
}
```

- [ ] **Step 5: Implement HTTP client**

Create `MCPServer/src/iosExploreClient.ts`:

```ts
import { requestTimeoutForAction, type MCPServerConfig } from "./config.js";
import { bodySnippet, IOSExploreStructuredError } from "./errors.js";
import type { IOSExploreEnvelope, JSONObject } from "./types.js";

export class IOSExploreClient {
  constructor(private readonly config: MCPServerConfig) {}

  async call(action: string, data: JSONObject = {}): Promise<JSONObject> {
    const timeoutMs = requestTimeoutForAction(this.config, action, data);
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    let response: Response;

    try {
      response = await fetch(this.config.baseURL, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action, data }),
        signal: controller.signal
      });
    } catch (error) {
      const code = error instanceof Error && error.name === "AbortError" ? "request_timeout" : "connection_failed";
      throw new IOSExploreStructuredError({
        source: "transport",
        code,
        message: error instanceof Error ? error.message : String(error),
        action,
        baseURL: this.config.baseURL,
        timeoutMs
      });
    } finally {
      clearTimeout(timer);
    }

    const text = await response.text();
    if (!response.ok) {
      throw new IOSExploreStructuredError({
        source: "http",
        status: response.status,
        message: `HTTP ${response.status}`,
        action,
        bodySnippet: bodySnippet(text)
      });
    }

    let envelope: IOSExploreEnvelope;
    try {
      envelope = JSON.parse(text) as IOSExploreEnvelope;
    } catch {
      throw new IOSExploreStructuredError({
        source: "http",
        code: "invalid_json",
        message: "HTTP response was not valid JSON",
        action,
        bodySnippet: bodySnippet(text)
      });
    }

    if (envelope.code !== "ok") {
      throw new IOSExploreStructuredError({
        source: "ios_envelope",
        code: envelope.code,
        message: envelope.message,
        action
      });
    }

    return envelope.data ?? {};
  }
}
```

- [ ] **Step 6: Run tests and verify pass**

Run:

```bash
cd MCPServer
npm test -- iosExploreClient.test.ts
npm run typecheck
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add MCPServer/src/errors.ts MCPServer/src/iosExploreClient.ts MCPServer/tests/iosExploreClient.test.ts MCPServer/tests/support/mockIOSExploreServer.ts
git commit -m "feat(mcp): add ios explore http client"
```

## Task 5: Implement Tool Naming and Schema Mapper

**Files:**
- Create: `MCPServer/src/toolName.ts`
- Create: `MCPServer/src/schemaMapper.ts`
- Create: `MCPServer/tests/toolName.test.ts`
- Create: `MCPServer/tests/schemaMapper.test.ts`

- [ ] **Step 1: Write tool name tests**

Create `MCPServer/tests/toolName.test.ts`:

```ts
import { describe, expect, test } from "vitest";
import { toolNameForAction, buildActionToolMap } from "../src/toolName.js";

describe("toolName", () => {
  test("maps action names to stable MCP names", () => {
    expect(toolNameForAction("ui.viewTargets")).toBe("ios_ui_viewTargets");
    expect(toolNameForAction("ui.navigation.back")).toBe("ios_ui_navigation_back");
    expect(toolNameForAction("app.logs.read")).toBe("ios_app_logs_read");
  });

  test("reports conflicts and omits conflicted dynamic tool", () => {
    const map = buildActionToolMap(
      [
        { action: "a.b", description: "first", inputSchema: {} },
        { action: "a_b", description: "second", inputSchema: {} }
      ],
      new Set()
    );
    expect(map.tools).toHaveLength(0);
    expect(map.conflicts).toEqual([
      { toolName: "ios_a_b", actions: ["a.b", "a_b"] }
    ]);
  });

  test("fixed tool conflict is reported", () => {
    const map = buildActionToolMap(
      [{ action: "health.check", description: "bad", inputSchema: {} }],
      new Set(["ios_health_check"])
    );
    expect(map.tools).toHaveLength(0);
    expect(map.conflicts).toEqual([
      { toolName: "ios_health_check", actions: ["health.check"] }
    ]);
  });
});
```

- [ ] **Step 2: Write schema mapper tests**

Create `MCPServer/tests/schemaMapper.test.ts`:

```ts
import { describe, expect, test } from "vitest";
import { mapInputSchema } from "../src/schemaMapper.js";

describe("schemaMapper", () => {
  test("passes JSON schema object through", () => {
    const mapped = mapInputSchema({
      type: "object",
      properties: { name: { type: "string", description: "Name" } },
      required: ["name"]
    });
    expect(mapped.inputSchema).toEqual({
      type: "object",
      properties: { name: { type: "string", description: "Name" } },
      required: ["name"]
    });
    expect(mapped.descriptionSuffix).toBe("");
  });

  test("moves x-iosExplore constraints into description suffix", () => {
    const mapped = mapInputSchema({
      type: "object",
      properties: { conditions: { type: "array" } },
      "x-iosExplore-constraints": ["conditions[].mode 必填字段: textExists 需 text"]
    });
    expect(mapped.inputSchema).toEqual({
      type: "object",
      properties: { conditions: { type: "array" } }
    });
    expect(mapped.descriptionSuffix).toContain("iOSExplore constraints");
    expect(mapped.descriptionSuffix).toContain("textExists 需 text");
  });
});
```

- [ ] **Step 3: Run tests and verify failure**

Run:

```bash
cd MCPServer
npm test -- toolName.test.ts schemaMapper.test.ts
```

Expected: FAIL because modules do not exist.

- [ ] **Step 4: Implement tool naming**

Create `MCPServer/src/toolName.ts`:

```ts
import type { CommandMetadata, ToolDefinition } from "./types.js";

export type ToolNameConflict = {
  toolName: string;
  actions: string[];
};

export type ActionToolMap = {
  tools: ToolDefinition[];
  conflicts: ToolNameConflict[];
};

export function toolNameForAction(action: string): string {
  return `ios_${action.replace(/[^A-Za-z0-9_]/g, "_")}`;
}

export function buildActionToolMap(commands: CommandMetadata[], fixedToolNames: Set<string>): ActionToolMap {
  const grouped = new Map<string, CommandMetadata[]>();
  for (const command of commands) {
    const name = toolNameForAction(command.action);
    const existing = grouped.get(name) ?? [];
    existing.push(command);
    grouped.set(name, existing);
  }

  const tools: ToolDefinition[] = [];
  const conflicts: ToolNameConflict[] = [];
  for (const [toolName, entries] of grouped) {
    if (entries.length > 1 || fixedToolNames.has(toolName)) {
      conflicts.push({ toolName, actions: entries.map(entry => entry.action) });
      continue;
    }
    const entry = entries[0];
    if (!entry) {
      continue;
    }
    tools.push({
      name: toolName,
      description: `${entry.description}\n\nOriginal iOSExplore action: ${entry.action}`,
      inputSchema: entry.inputSchema,
      action: entry.action
    });
  }

  return { tools, conflicts };
}
```

- [ ] **Step 5: Implement schema mapper**

Create `MCPServer/src/schemaMapper.ts`:

```ts
import type { JSONObject, JSONValue } from "./types.js";

export type SchemaMapping = {
  inputSchema: JSONObject;
  descriptionSuffix: string;
};

export function mapInputSchema(schema: JSONObject): SchemaMapping {
  const inputSchema: JSONObject = {};
  const extensionLines: string[] = [];

  for (const [key, value] of Object.entries(schema)) {
    if (key.startsWith("x-iosExplore-")) {
      extensionLines.push(...extensionValueLines(key, value));
    } else {
      inputSchema[key] = value;
    }
  }

  return {
    inputSchema,
    descriptionSuffix:
      extensionLines.length === 0
        ? ""
        : `\n\niOSExplore constraints:\n${extensionLines.map(line => `- ${line}`).join("\n")}`
  };
}

function extensionValueLines(key: string, value: JSONValue): string[] {
  if (Array.isArray(value)) {
    return value.map(item => `${key}: ${String(item)}`);
  }
  return [`${key}: ${String(value)}`];
}
```

- [ ] **Step 6: Run tests and verify pass**

Run:

```bash
cd MCPServer
npm test -- toolName.test.ts schemaMapper.test.ts
npm run typecheck
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add MCPServer/src/toolName.ts MCPServer/src/schemaMapper.ts MCPServer/tests/toolName.test.ts MCPServer/tests/schemaMapper.test.ts
git commit -m "feat(mcp): map dynamic tools and schemas"
```

## Task 6: Implement Dynamic Tool Registry

**Files:**
- Create: `MCPServer/src/toolRegistry.ts`
- Create: `MCPServer/tests/toolRegistry.test.ts`

- [ ] **Step 1: Write registry tests**

Create `MCPServer/tests/toolRegistry.test.ts`:

```ts
import { describe, expect, test } from "vitest";
import { ToolRegistry } from "../src/toolRegistry.js";
import { IOSExploreStructuredError } from "../src/errors.js";
import type { JSONObject } from "../src/types.js";

describe("ToolRegistry", () => {
  test("refreshes tools from help", async () => {
    const registry = new ToolRegistry({
      fixedToolNames: new Set(["health_check"]),
      client: {
        call: async (action: string) => {
          expect(action).toBe("help");
          return {
            commands: [
              {
                action: "ui.viewTargets",
                description: "targets",
                inputSchema: { type: "object", properties: {} }
              }
            ]
          };
        }
      }
    });

    const result = await registry.refresh();
    expect(result.toolCount).toBe(1);
    expect(result.conflicts).toEqual([]);
    expect(registry.tools()[0]).toMatchObject({
      name: "ios_ui_viewTargets",
      action: "ui.viewTargets"
    });
  });

  test("keeps server usable when help fails", async () => {
    const registry = new ToolRegistry({
      fixedToolNames: new Set(),
      client: {
        call: async () => {
          throw new IOSExploreStructuredError({
            source: "transport",
            code: "connection_failed",
            message: "offline",
            action: "help"
          });
        }
      }
    });

    const result = await registry.refresh();
    expect(result.toolCount).toBe(0);
    expect(result.error).toMatchObject({ source: "transport", code: "connection_failed" });
    expect(registry.tools()).toEqual([]);
  });
});

type FakeClient = {
  call(action: string, data?: JSONObject): Promise<JSONObject>;
};
```

- [ ] **Step 2: Run test and verify failure**

Run:

```bash
cd MCPServer
npm test -- toolRegistry.test.ts
```

Expected: FAIL because `ToolRegistry` does not exist.

- [ ] **Step 3: Implement registry**

Create `MCPServer/src/toolRegistry.ts`:

```ts
import { IOSExploreStructuredError } from "./errors.js";
import { mapInputSchema } from "./schemaMapper.js";
import { buildActionToolMap, type ToolNameConflict } from "./toolName.js";
import type { CommandMetadata, JSONObject, StructuredError, ToolDefinition } from "./types.js";

export type IOSExploreCaller = {
  call(action: string, data?: JSONObject): Promise<JSONObject>;
};

export type RefreshResult = {
  toolCount: number;
  conflicts: ToolNameConflict[];
  error?: StructuredError;
};

export class ToolRegistry {
  private dynamicTools: ToolDefinition[] = [];
  private lastConflicts: ToolNameConflict[] = [];

  constructor(
    private readonly options: {
      fixedToolNames: Set<string>;
      client: IOSExploreCaller;
    }
  ) {}

  tools(): ToolDefinition[] {
    return [...this.dynamicTools];
  }

  conflicts(): ToolNameConflict[] {
    return [...this.lastConflicts];
  }

  findByName(name: string): ToolDefinition | undefined {
    return this.dynamicTools.find(tool => tool.name === name);
  }

  async refresh(): Promise<RefreshResult> {
    try {
      const help = await this.options.client.call("help");
      const commands = parseHelpCommands(help);
      const mapped = buildActionToolMap(commands, this.options.fixedToolNames);
      this.dynamicTools = mapped.tools.map(tool => {
        const schema = mapInputSchema(tool.inputSchema);
        return {
          ...tool,
          inputSchema: schema.inputSchema,
          description: `${tool.description}${schema.descriptionSuffix}`
        };
      });
      this.lastConflicts = mapped.conflicts;
      return { toolCount: this.dynamicTools.length, conflicts: this.lastConflicts };
    } catch (error) {
      this.dynamicTools = [];
      this.lastConflicts = [];
      const structured =
        error instanceof IOSExploreStructuredError
          ? error.toJSON()
          : { source: "mcp_server" as const, code: "refresh_failed", message: error instanceof Error ? error.message : String(error) };
      return { toolCount: 0, conflicts: [], error: structured };
    }
  }
}

function parseHelpCommands(help: JSONObject): CommandMetadata[] {
  const commands = help.commands;
  if (!Array.isArray(commands)) {
    throw new IOSExploreStructuredError({
      source: "mcp_server",
      code: "invalid_help_response",
      message: "help response did not contain commands array",
      action: "help"
    });
  }

  return commands.map(command => {
    if (!isObject(command)) {
      throw new Error("help command entry must be object");
    }
    const action = command.action;
    const description = command.description;
    const inputSchema = command.inputSchema;
    if (typeof action !== "string" || typeof description !== "string" || !isObject(inputSchema)) {
      throw new Error("help command entry missing action, description, or inputSchema");
    }
    return { action, description, inputSchema };
  });
}

function isObject(value: unknown): value is JSONObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
```

- [ ] **Step 4: Run tests and verify pass**

Run:

```bash
cd MCPServer
npm test -- toolRegistry.test.ts
npm run typecheck
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add MCPServer/src/toolRegistry.ts MCPServer/tests/toolRegistry.test.ts
git commit -m "feat(mcp): discover tools from help"
```

## Task 7: Implement Static Tools

**Files:**
- Create: `MCPServer/src/staticTools.ts`
- Create: `MCPServer/tests/staticTools.test.ts`

- [ ] **Step 1: Write static tool tests**

Create `MCPServer/tests/staticTools.test.ts`:

```ts
import { describe, expect, test } from "vitest";
import { createStaticTools } from "../src/staticTools.js";
import type { JSONObject } from "../src/types.js";

describe("static tools", () => {
  test("health_check reports online status", async () => {
    const calls: string[] = [];
    const tools = createStaticTools({
      client: {
        call: async action => {
          calls.push(action);
          return action === "ping" ? { pong: true } : { commands: [] };
        }
      },
      registry: fakeRegistry(3)
    });

    const result = await tools.health_check.handler({});
    expect(JSON.parse(result.content[0].text)).toMatchObject({
      ok: true,
      dynamicToolCount: 3
    });
    expect(calls).toEqual(["ping", "help"]);
  });

  test("observe calls ui.viewTargets with provided options", async () => {
    const calls: Array<{ action: string; data: JSONObject }> = [];
    const tools = createStaticTools({
      client: {
        call: async (action, data = {}) => {
          calls.push({ action, data });
          return { viewSnapshotID: "snap-1", targets: [] };
        }
      },
      registry: fakeRegistry(0)
    });

    const result = await tools.observe.handler({ maxTargets: 100 });
    expect(calls).toEqual([{ action: "ui.viewTargets", data: { maxTargets: 100 } }]);
    expect(JSON.parse(result.content[0].text).viewSnapshotID).toBe("snap-1");
  });

  test("wait_and_observe observes after wait timeout", async () => {
    const calls: string[] = [];
    const tools = createStaticTools({
      client: {
        call: async (action) => {
          calls.push(action);
          if (action === "ui.waitAny") {
            const error = new Error("timeout") as Error & { source: string; code: string; action: string };
            error.source = "ios_envelope";
            error.code = "wait_timeout";
            error.action = "ui.waitAny";
            throw error;
          }
          return { viewSnapshotID: "snap-after", targets: [] };
        }
      },
      registry: fakeRegistry(0)
    });

    const result = await tools.wait_and_observe.handler({ conditions: [{ id: "gone", mode: "textExists", text: "Done" }] });
    expect(calls).toEqual(["ui.waitAny", "ui.viewTargets"]);
    expect(JSON.parse(result.content[0].text)).toMatchObject({
      wait: { code: "wait_timeout" },
      observation: { viewSnapshotID: "snap-after" }
    });
    expect(result.isError).toBe(false);
  });
});

function fakeRegistry(toolCount: number) {
  return {
    async refresh() {
      return { toolCount, conflicts: [] };
    },
    tools() {
      return new Array(toolCount).fill(null);
    },
    conflicts() {
      return [];
    }
  };
}
```

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
cd MCPServer
npm test -- staticTools.test.ts
```

Expected: FAIL because static tools do not exist.

- [ ] **Step 3: Implement static tools**

Create `MCPServer/src/staticTools.ts`:

```ts
import { IOSExploreStructuredError } from "./errors.js";
import { errorResult, jsonResult } from "./result.js";
import type { IOSExploreCaller } from "./toolRegistry.js";
import type { JSONObject, MCPToolResult } from "./types.js";

type RegistryLike = {
  refresh(): Promise<{ toolCount: number; conflicts: unknown[]; error?: unknown }>;
  tools(): unknown[];
  conflicts(): unknown[];
};

type StaticTool = {
  name: string;
  description: string;
  inputSchema: JSONObject;
  handler(input: JSONObject): Promise<MCPToolResult>;
};

export function createStaticTools(options: { client: IOSExploreCaller; registry: RegistryLike }): Record<string, StaticTool> {
  const { client, registry } = options;
  return {
    health_check: {
      name: "health_check",
      description: "检查 Mac MCP server 是否能连到 iOSExplore App 的 ping/help。",
      inputSchema: { type: "object", properties: {} },
      handler: async () => {
        try {
          const ping = await client.call("ping");
          await client.call("help");
          return jsonResult({ ok: true, ping, dynamicToolCount: registry.tools().length, conflicts: registry.conflicts() });
        } catch (error) {
          return jsonResult({ ok: false, error: normalizeError(error), dynamicToolCount: registry.tools().length }, false);
        }
      }
    },
    refresh_tools: {
      name: "refresh_tools",
      description: "重新读取 iOSExplore help 输出并刷新动态 MCP tools。",
      inputSchema: { type: "object", properties: {} },
      handler: async () => jsonResult(await registry.refresh())
    },
    call_action: {
      name: "call_action",
      description: "兜底转发任意 iOSExplore action。优先使用固定工具或动态工具；排障时使用本工具。",
      inputSchema: {
        type: "object",
        properties: {
          action: { type: "string" },
          data: { type: "object" }
        },
        required: ["action"]
      },
      handler: async input => jsonResult(await client.call(String(input.action), objectValue(input.data)))
    },
    observe: {
      name: "observe",
      description: "默认观察入口：调用 ui.viewTargets，返回 targets、navigationBar 与新的 viewSnapshotID。",
      inputSchema: { type: "object", properties: {} },
      handler: async input => jsonResult(await client.call("ui.viewTargets", input))
    },
    wait_and_observe: {
      name: "wait_and_observe",
      description: "先调用 ui.waitAny，再调用 ui.viewTargets。wait_timeout 后仍尽量返回最新 observation。",
      inputSchema: waitAndObserveSchema(),
      handler: async input => {
        const viewTargetsOptions = objectValue(input.viewTargetsOptions);
        try {
          const wait = await client.call("ui.waitAny", withoutKey(input, "viewTargetsOptions"));
          const observation = await client.call("ui.viewTargets", viewTargetsOptions);
          return jsonResult({ wait, observation });
        } catch (error) {
          const normalized = normalizeError(error);
          if (normalized.source === "ios_envelope" && normalized.code === "wait_timeout") {
            const observation = await client.call("ui.viewTargets", viewTargetsOptions);
            return jsonResult({ wait: normalized, observation }, false);
          }
          return errorResult(normalized);
        }
      }
    }
  };
}

function waitAndObserveSchema(): JSONObject {
  return {
    type: "object",
    properties: {
      conditions: {
        type: "array",
        minItems: 1,
        maxItems: 16,
        description: "每项必须包含 id/mode；targetExists/targetGone 需要 accessibilityIdentifier 或 path；textExists 需要 text；snapshotChanged 需要 viewSnapshotID；idle 无额外字段。"
      },
      timeoutMs: { type: "number" },
      intervalMs: { type: "number" },
      stableMs: { type: "number" },
      includeHidden: { type: "boolean" },
      viewTargetsOptions: { type: "object", description: "传给 ui.viewTargets 的可选参数。" }
    },
    required: ["conditions"]
  };
}

function objectValue(value: unknown): JSONObject {
  return typeof value === "object" && value !== null && !Array.isArray(value) ? (value as JSONObject) : {};
}

function withoutKey(input: JSONObject, key: string): JSONObject {
  const copy: JSONObject = { ...input };
  delete copy[key];
  return copy;
}

function normalizeError(error: unknown) {
  if (error instanceof IOSExploreStructuredError) {
    return error.toJSON();
  }
  if (typeof error === "object" && error !== null && "source" in error && "code" in error) {
    return error as { source: "ios_envelope"; code: string; action?: string; message?: string };
  }
  return {
    source: "mcp_server" as const,
    code: "unexpected_error",
    message: error instanceof Error ? error.message : String(error)
  };
}
```

- [ ] **Step 4: Run tests and verify pass**

Run:

```bash
cd MCPServer
npm test -- staticTools.test.ts
npm run typecheck
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add MCPServer/src/staticTools.ts MCPServer/tests/staticTools.test.ts
git commit -m "feat(mcp): add fixed agent tools"
```

## Task 8: Wire MCP Stdio Server

**Files:**
- Create: `MCPServer/src/server.ts`
- Modify: `MCPServer/src/index.ts`
- Create: `MCPServer/tests/server.test.ts`

- [ ] **Step 1: Write server handler tests**

Create `MCPServer/tests/server.test.ts`:

```ts
import { describe, expect, test } from "vitest";
import { createToolHandlers } from "../src/server.js";
import type { JSONObject } from "../src/types.js";

describe("server handlers", () => {
  test("lists fixed and dynamic tools", async () => {
    const handlers = createToolHandlers({
      staticTools: {
        health_check: {
          name: "health_check",
          description: "health",
          inputSchema: { type: "object", properties: {} },
          handler: async () => ({ content: [{ type: "text", text: "{}" }] })
        }
      },
      registry: {
        tools: () => [{ name: "ios_ping", description: "ping", inputSchema: {}, action: "ping" }],
        findByName: () => undefined
      },
      client: { call: async () => ({}) }
    });

    const listed = await handlers.listTools();
    expect(listed.tools.map(tool => tool.name)).toEqual(["health_check", "ios_ping"]);
  });

  test("calls dynamic tool by original action", async () => {
    const calls: Array<{ action: string; data: JSONObject }> = [];
    const handlers = createToolHandlers({
      staticTools: {},
      registry: {
        tools: () => [],
        findByName: () => ({ name: "ios_ping", description: "ping", inputSchema: {}, action: "ping" })
      },
      client: {
        call: async (action, data = {}) => {
          calls.push({ action, data });
          return { pong: true };
        }
      }
    });

    const result = await handlers.callTool("ios_ping", { verbose: true });
    expect(calls).toEqual([{ action: "ping", data: { verbose: true } }]);
    expect(JSON.parse(result.content[0].text)).toEqual({ pong: true });
  });
});
```

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
cd MCPServer
npm test -- server.test.ts
```

Expected: FAIL because `server.ts` does not exist.

- [ ] **Step 3: Implement server handlers and stdio startup**

Create `MCPServer/src/server.ts`:

```ts
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { CallToolRequestSchema, ListToolsRequestSchema } from "@modelcontextprotocol/sdk/types.js";
import { errorResult, jsonResult } from "./result.js";
import type { IOSExploreCaller } from "./toolRegistry.js";
import type { JSONObject, MCPToolResult, ToolDefinition } from "./types.js";

type StaticToolLike = {
  name: string;
  description: string;
  inputSchema: JSONObject;
  handler(input: JSONObject): Promise<MCPToolResult>;
};

type RegistryLike = {
  tools(): ToolDefinition[];
  findByName(name: string): ToolDefinition | undefined;
};

export function createToolHandlers(options: {
  staticTools: Record<string, StaticToolLike>;
  registry: RegistryLike;
  client: IOSExploreCaller;
}) {
  return {
    async listTools() {
      return {
        tools: [
          ...Object.values(options.staticTools).map(toMCPTool),
          ...options.registry.tools().map(toMCPTool)
        ]
      };
    },
    async callTool(name: string, args: JSONObject = {}): Promise<MCPToolResult> {
      const fixed = options.staticTools[name];
      if (fixed) {
        return fixed.handler(args);
      }
      const dynamic = options.registry.findByName(name);
      if (dynamic?.action) {
        try {
          return jsonResult(await options.client.call(dynamic.action, args));
        } catch (error) {
          return errorResult(normalizeUnknownError(error));
        }
      }
      return errorResult({
        source: "mcp_server",
        code: "unknown_tool",
        message: `Unknown tool '${name}'`
      });
    }
  };
}

export async function startStdioServer(options: {
  staticTools: Record<string, StaticToolLike>;
  registry: RegistryLike;
  client: IOSExploreCaller;
}) {
  const server = new Server(
    { name: "ios-explore-mcp-server", version: "0.1.0" },
    { capabilities: { tools: {} } }
  );
  const handlers = createToolHandlers(options);

  server.setRequestHandler(ListToolsRequestSchema, async () => handlers.listTools());
  server.setRequestHandler(CallToolRequestSchema, async request => {
    const name = request.params.name;
    const args = (request.params.arguments ?? {}) as JSONObject;
    return handlers.callTool(name, args);
  });

  await server.connect(new StdioServerTransport());
}

function toMCPTool(tool: StaticToolLike | ToolDefinition) {
  return {
    name: tool.name,
    description: tool.description,
    inputSchema: tool.inputSchema
  };
}

function normalizeUnknownError(error: unknown) {
  if (typeof error === "object" && error !== null && "source" in error && "message" in error) {
    return error as { source: "mcp_server"; message: string; code?: string };
  }
  return {
    source: "mcp_server" as const,
    code: "unexpected_error",
    message: error instanceof Error ? error.message : String(error)
  };
}
```

Replace `MCPServer/src/index.ts` with:

```ts
import { loadConfig } from "./config.js";
import { IOSExploreClient } from "./iosExploreClient.js";
import { startStdioServer } from "./server.js";
import { createStaticTools } from "./staticTools.js";
import { ToolRegistry } from "./toolRegistry.js";

const config = loadConfig();
const client = new IOSExploreClient(config);
const fixedToolNames = new Set(["health_check", "refresh_tools", "call_action", "observe", "wait_and_observe"]);
const registry = new ToolRegistry({ fixedToolNames, client });
const staticTools = createStaticTools({ client, registry });

await registry.refresh();
await startStdioServer({ staticTools, registry, client });
```

- [ ] **Step 4: Run tests and verify pass**

Run:

```bash
cd MCPServer
npm test -- server.test.ts
npm run typecheck
npm run build
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add MCPServer/src/server.ts MCPServer/src/index.ts MCPServer/tests/server.test.ts
git commit -m "feat(mcp): expose tools over stdio"
```

## Task 9: Add MCPServer README and Repo Docs

**Files:**
- Create: `MCPServer/README.md`
- Modify: `docs/superpowers/agent-mcp-exploration/README.md`
- Modify: `docs/uikit/agent-command-protocol.md`

- [ ] **Step 1: Write MCPServer README**

Create `MCPServer/README.md`:

```md
# iOSExplore MCP Server

Mac 本机运行的 MCP stdio server。它把 App 内 `ExploreServer` 的 `POST /` action 包装成 MCP tools，默认连接 `http://localhost:38321/`。

## 启动前提

模拟器：App 启动并开启 `IOS_EXPLORE_AUTOSTART=1` 后，Mac 直接访问 `localhost:38321`。

真机：App 启动并开启 `IOS_EXPLORE_AUTOSTART=1` 后，先启动 `iproxy 38321 38321`。真机验收前运行：

```bash
lsof -iTCP:38321 -sTCP:LISTEN
```

`COMMAND` 必须是 `iproxy`，不能是残留的 `SPMExampl`。

## 开发命令

```bash
npm install
npm test
npm run typecheck
npm run build
```

## 配置

| 环境变量 | 默认值 | 说明 |
|---|---|---|
| `IOS_EXPLORE_BASE_URL` | `http://localhost:38321/` | iOSExplore HTTP 地址 |
| `IOS_EXPLORE_REQUEST_TIMEOUT_MS` | `10000` | 普通 action 请求超时 |

`ui.wait`、`ui.waitAny`、`wait_and_observe` 会按业务 `timeoutMs + 5000` 自动放宽 HTTP timeout。

## 推荐调用顺序

```text
health_check
→ observe
→ 动态动作工具或 call_action
→ wait_and_observe
→ 根据最新 observation 判断结果
```

日常优先使用固定工具；排障或未知 action 时使用 `call_action`。
```

- [ ] **Step 2: Update project entry docs**

In `docs/superpowers/agent-mcp-exploration/README.md`, update §6.1 status after implementation:

```md
**第一版实现位置**：`MCPServer/`。它是 TypeScript / Node stdio MCP server，默认连接 `http://localhost:38321/`，通过 `help` 动态发现 App 已注册 action，并提供 `health_check`、`refresh_tools`、`call_action`、`observe`、`wait_and_observe` 五个固定工具。
```

In `docs/uikit/agent-command-protocol.md`, add a short MCP note after the first command table:

```md
MCP 调用方优先走 `MCPServer` 的 `observe` 和 `wait_and_observe` 固定工具；需要精细控制或排障时再调用动态 `ios_*` 原子工具或 `call_action`。
```

- [ ] **Step 3: Run docs grep checks**

Run:

```bash
rg -n "18 个 action|18 个 HTTP action|ui.input.*必须.*viewSnapshotID|alert_button_required.*\\|" docs README.md Sources/iOSExploreUIKit/Commands/Input/UIInputCommand.swift
```

Expected:

- Old `18 个 action` only appears inside the historical scope file with “已过期 / 当时估算”.
- No current `ui.input` help text says `viewSnapshotID` is always required.
- `curl-json-loop-protocol.md` error table has two columns per row.

- [ ] **Step 4: Run doc diff check**

Run:

```bash
git diff --check
```

Expected: no output.

- [ ] **Step 5: Commit**

```bash
git add MCPServer/README.md docs/superpowers/agent-mcp-exploration/README.md docs/uikit/agent-command-protocol.md
git commit -m "docs(mcp): document mac mcp server usage"
```

## Task 10: Full Automated Verification

**Files:**
- No code edits expected.

- [ ] **Step 1: Run Swift test suite**

Run:

```bash
swift test
```

Expected: PASS. Current baseline is 225 macOS SPM tests.

- [ ] **Step 2: Run MCP server tests**

Run:

```bash
cd MCPServer
npm test
npm run typecheck
npm run build
```

Expected: all pass.

- [ ] **Step 3: Run whitespace check**

Run:

```bash
git diff --check
```

Expected: no output.

- [ ] **Step 4: Commit verification-only doc updates if any**

If Task 10 produced no file changes, do not commit. If docs were updated with exact command output, commit:

```bash
git add <changed-doc-files>
git commit -m "docs(mcp): record mcp verification"
```

## Task 11: Real App MCP Loop Validation

**Files:**
- No code edits expected unless validation reveals a bug.

- [ ] **Step 1: Start SPMExample with autostart**

Simulator path:

```text
session_use_defaults_profile("sim-app")
build_run_sim()
stop_app_sim()
launch_app_sim(env={"IOS_EXPLORE_AUTOSTART":"1"})
```

True-device path:

```text
session_use_defaults_profile("device-app")
build_run_device()
stop_app_device()
launch_app_device(env={"IOS_EXPLORE_AUTOSTART":"1"})
./scripts/proxy.sh
lsof -iTCP:38321 -sTCP:LISTEN
```

Expected:

- Simulator: `curl -X POST http://localhost:38321/ -d '{"action":"ping"}'` returns `{"code":"ok","data":{"pong":true}}`.
- True device: `lsof` shows `COMMAND` as `iproxy` before MCP validation.

- [ ] **Step 2: Run MCP server through an MCP inspector or Codex MCP client**

Run from `MCPServer/`:

```bash
npm run build
node dist/src/index.js
```

Expected: process starts as stdio MCP server and waits for MCP client messages. If using a client that lists tools, it shows:

- `health_check`
- `refresh_tools`
- `call_action`
- `observe`
- `wait_and_observe`
- dynamic `ios_*` tools from current App `help`

- [ ] **Step 3: Execute minimum MCP loop**

Using the MCP client, call:

```text
health_check
observe
call_action(action="ui.waitAny", data={"conditions":[{"id":"idle","mode":"idle"}],"timeoutMs":1000})
wait_and_observe({"conditions":[{"id":"idle","mode":"idle"}],"timeoutMs":1000})
```

Expected:

- `health_check.ok == true`
- `observe` returns `viewSnapshotID`
- `wait_and_observe` returns both `wait` and `observation`
- `observation.viewSnapshotID` comes from `ui.viewTargets`, not from MCP server

- [ ] **Step 4: Validate one action**

Use `observe` to identify a safe target in SPMExample, then call the dynamic `ios_ui_tap` tool or:

```text
call_action(action="ui.tap", data={"path":"<path-from-observe>","viewSnapshotID":"<snap-from-observe>"})
```

Then call:

```text
wait_and_observe({"conditions":[{"id":"changed","mode":"snapshotChanged","viewSnapshotID":"<old-snap>"}],"timeoutMs":3000})
```

Expected: MCP result goes through `MCP → HTTP → App → HTTP response → MCP result`, and the final observation reflects the current App screen.

- [ ] **Step 5: Record validation outcome**

Update `MCPServer/README.md` or `docs/superpowers/agent-mcp-exploration/README.md` only if the command sequence or prerequisites changed. Do not claim “real MCP loop complete” unless Step 3 and Step 4 both went through an MCP client, not raw curl.

- [ ] **Step 6: Commit if validation docs changed**

```bash
git add MCPServer/README.md docs/superpowers/agent-mcp-exploration/README.md
git commit -m "docs(mcp): record real app mcp validation"
```

## Self-Review Checklist

- Spec coverage:
  - A-only first version: Tasks 2-11 create a local MCP wrapper and do not implement device management or a test platform.
  - B/C roadmap preservation: Task 9 keeps entry docs aligned; no implementation task enters B/C.
  - TypeScript / Node: Tasks 2-8 create a Node package.
  - Dynamic discovery: Tasks 5-6 implement `help`-driven dynamic tools.
  - Fixed tools: Task 7 implements `health_check`, `refresh_tools`, `call_action`, `observe`, `wait_and_observe`.
  - `viewSnapshotID` source: Task 7 returns only iPhone `ui.viewTargets` observations.
  - Error mapping: Task 4 and Task 7 keep structured errors and `wait_timeout` as a recoverable result in `wait_and_observe`.
  - Timeout grace: Task 3 and Task 4 test `timeoutMs + 5000`.
  - True-device anti-false-positive check: Task 11 requires `lsof` with `iproxy`.
  - `ui.input` contract repair: Task 1.
- Placeholder scan: this plan uses concrete file paths, concrete commands, and concrete code snippets.
- Type consistency:
  - `JSONObject`, `MCPToolResult`, `StructuredError`, `IOSExploreClient`, `ToolRegistry`, `createStaticTools`, and `createToolHandlers` names are introduced before later tasks use them.
