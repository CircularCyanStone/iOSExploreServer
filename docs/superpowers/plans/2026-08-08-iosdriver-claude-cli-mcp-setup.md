# Claude CLI MCP Setup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make `iosdriver mcp setup claude` register `iOSDriver` through Claude Code's official `claude mcp get/add/remove` commands with local/user/project scopes and Codex-compatible wrapper semantics.

**Architecture:** Keep the existing injected `MCPSetupCommandRunner` boundary. Route `codex` to the existing CLI adapter, `claude` to a new Claude CLI adapter, and `trae` to the existing JSON adapter. Claude's `--dry-run` remains a preflight-only operation; `--force` performs official `remove` followed by official `add` because Claude's `add` rejects duplicate names.

**Tech Stack:** TypeScript, Node `child_process.spawn`, Vitest, generated CLI distribution, Markdown documentation.

---

### Task 1: Extend scope and result contracts

**Files:**
- Modify: `iOSDriver/src/registration/mcpClientSetupTypes.ts`
- Modify: `iOSDriver/src/adapters/cli/arguments.ts`
- Test: `iOSDriver/tests/adapters/cli/arguments.test.ts`

- [ ] **Step 1: Write the failing parser tests**

Add coverage that accepts `--scope local` for Claude setup and rejects `local` for Codex/Trae through runtime scope validation. Update the expected setup usage text to list `local|user|project`.

```ts
expect(parseCLIArguments(["mcp", "setup", "claude", "--scope", "local"])).toMatchObject({
  kind: "mcpSetup",
  client: "claude",
  scope: "local"
});
```

- [ ] **Step 2: Run the focused parser test**

Run: `cd iOSDriver && npx vitest run tests/adapters/cli/arguments.test.ts`

Expected: FAIL because the parser currently only accepts `user` and `project`.

- [ ] **Step 3: Implement the type and parser changes**

Change `MCPRegistrationScope` to `"local" | "user" | "project"`; accept all three strings in `parseMCPSetupArguments`; keep client-specific scope validation in the registration runtime. Expand `MCPClientSetupResult.manager` with `"claude-cli"`.

- [ ] **Step 4: Re-run parser tests**

Run: `cd iOSDriver && npx vitest run tests/adapters/cli/arguments.test.ts`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add iOSDriver/src/registration/mcpClientSetupTypes.ts iOSDriver/src/adapters/cli/arguments.ts iOSDriver/tests/adapters/cli/arguments.test.ts
git commit -m "feat: add Claude local MCP scope"
```

### Task 2: Add Claude official CLI setup adapter

**Files:**
- Modify: `iOSDriver/src/registration/mcpClientSetupRuntime.ts`
- Test: `iOSDriver/tests/registration/mcpClientSetup.test.ts`

- [ ] **Step 1: Add failing Claude CLI tests**

Use the existing injected runner pattern. Cover:

```ts
const claudeGetMissing: MCPSetupCommandRunner = async (_command, args) => {
  if (args[0] === "mcp" && args[1] === "get") {
    return { exitCode: 1, stdout: "No MCP server named \"iOSDriver\".", stderr: "" };
  }
  throw new Error(`unexpected command: ${args.join(" ")}`);
};
```

Assert creation invokes exactly:

```ts
["mcp", "add", "--transport", "stdio", "--scope", "local", "iOSDriver", "--", launch.command, ...launch.args]
```

Add separate tests for unchanged configuration, conflict without `force`, `dryRun` without add/remove, force ordering (`get`, `remove`, `add`), missing-server detection, malformed `get` output, and non-zero remove/add failures.

- [ ] **Step 2: Run registration tests to verify failure**

Run: `cd iOSDriver && npx vitest run tests/registration/mcpClientSetup.test.ts`

Expected: FAIL because Claude is still routed to the JSON adapter and `local` is not supported.

- [ ] **Step 3: Implement scope routing and Claude CLI commands**

Update `resolvedScope` so Claude defaults to `local`, accepts `local|user|project`, Codex remains `user`, and Trae remains `project`. Route `input.client === "claude"` to `setupClaude`.

Implement these helpers in `mcpClientSetupRuntime.ts`:

```ts
async function setupClaude(
  input: MCPClientSetupInput,
  scope: MCPRegistrationScope,
  run: MCPSetupCommandRunner
): Promise<MCPClientSetupResult>
```

`setupClaude` must:

1. Run `claude mcp get iOSDriver` with `{ cwd: input.cwd, env: input.env }`.
2. Treat the exact missing-server message (`No MCP server named "iOSDriver"`) as absent.
3. Parse the human-readable `Command:` and `Args:` lines into `{ command, args }`; reject successful output that cannot be parsed.
4. Return `unchanged` when the parsed launch matches `input.launch`.
5. Return a conflict error when launches differ and `force !== true`.
6. Return `planned` before any mutation when `dryRun === true`.
7. For create/update, invoke `claude mcp add --transport stdio --scope <scope> iOSDriver -- <command> ...args`.
8. For forced update, invoke `claude mcp remove iOSDriver --scope <scope>` and then the add command; propagate either command failure as `MCPClientSetupError`.

Use a dedicated parser that accepts the current output format:

```text
Command: /absolute/node
Args: /absolute/main.js mcp --config /absolute/config.json
```

Split only the `Args:` suffix on whitespace because the generated launch paths are absolute non-space paths in the current contract. If either line is missing, throw a setup error rather than guessing.

- [ ] **Step 4: Run registration tests**

Run: `cd iOSDriver && npx vitest run tests/registration/mcpClientSetup.test.ts`

Expected: PASS, including the pre-existing Codex and TRAE cases.

- [ ] **Step 5: Commit**

```bash
git add iOSDriver/src/registration/mcpClientSetupRuntime.ts iOSDriver/tests/registration/mcpClientSetup.test.ts
git commit -m "feat: register Claude MCP servers through official CLI"
```

### Task 3: Update CLI integration and application tests

**Files:**
- Modify: `iOSDriver/src/adapters/cli/application/applicationRuntime.ts`
- Modify: `iOSDriver/tests/adapters/cli/main.test.ts`

- [ ] **Step 1: Add failing integration assertions**

Update setup result fixtures to allow `manager: "claude-cli"`, add a local-scope Claude invocation, and assert that `mcp setup` remains host-only without resolving App config or creating a runtime.

- [ ] **Step 2: Implement only required fixture/type updates**

Keep `applicationRuntime.ts` behavior unchanged except for any narrowed manager union or scope fixture needed by the new registration result. Do not move setup into the App runtime path.

- [ ] **Step 3: Run CLI tests**

Run: `cd iOSDriver && npx vitest run tests/adapters/cli/main.test.ts tests/adapters/cli/arguments.test.ts`

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add iOSDriver/src/adapters/cli/application/applicationRuntime.ts iOSDriver/tests/adapters/cli/main.test.ts
git commit -m "test: cover Claude CLI setup routing"
```

### Task 4: Synchronize user-facing documentation

**Files:**
- Modify: `iOSDriver/README.md`
- Modify: `iOSDriver/docs/cli-reference.md`
- Modify: `iOSDriver/docs/mcp-cli-design-discussion.md`
- Modify: `docs/cli/README.md`

- [ ] **Step 1: Update scope and manager descriptions**

Document Claude's default `local` scope and the three scope locations. Replace the statement that Claude is managed by `json-file` with the official `claude mcp get/add/remove` flow. State that `--dry-run` and `--force` are iOSDriver wrapper options, not Claude CLI options; forced Claude updates execute remove then add and are not atomic.

- [ ] **Step 2: Add the verified passthrough example**

Include this command shape:

```bash
iosdriver mcp setup claude --scope local
```

and show the resulting official command contract with `--` before the Node executable and `mcp --config` arguments.

- [ ] **Step 3: Run documentation consistency checks**

Run: `rg -n "claude.*json-file|Claude.*project|scope user\\|project|manager.*json-file" iOSDriver/README.md iOSDriver/docs/cli-reference.md iOSDriver/docs/mcp-cli-design-discussion.md docs/cli/README.md`

Expected: no stale claim that Claude setup always writes JSON or only supports `user/project`; remaining `json-file` references must describe TRAE only.

- [ ] **Step 4: Commit**

```bash
git add iOSDriver/README.md iOSDriver/docs/cli-reference.md iOSDriver/docs/mcp-cli-design-discussion.md docs/cli/README.md
git commit -m "docs: document Claude CLI MCP setup"
```

### Task 5: Full verification and real CLI smoke test

**Files:**
- Test only; no source changes expected.

- [ ] **Step 1: Run type checking and focused tests**

Run: `cd iOSDriver && npm run typecheck && npx vitest run tests/registration/mcpClientSetup.test.ts tests/adapters/cli/arguments.test.ts tests/adapters/cli/main.test.ts`

Expected: PASS.

- [ ] **Step 2: Run the full package test suite**

Run: `cd iOSDriver && npm test`

Expected: build, contract check, and all Vitest tests pass.

- [ ] **Step 3: Verify the installed Claude CLI with an isolated config**

Use a temporary `CLAUDE_CONFIG_DIR` and temporary working directory. Execute:

```bash
claude mcp add --transport stdio --scope local iOSDriver -- \
  "$(command -v node)" /tmp/iosdriver-main.js mcp --config /tmp/iosdriver-config.json
claude mcp get iOSDriver
```

Expected: `get` reports `Scope: Local config`, the Node executable under `Command:`, and all four trailing arguments including `--config`.

- [ ] **Step 4: Commit verification metadata only if needed**

Do not commit temporary Claude config files or generated telemetry. Report the commands and outcomes in the final response.

## Self-review

- Scope coverage: Tasks 1-2 implement all three Claude scopes, CLI routing, passthrough, dry-run, force, idempotence, and errors; Tasks 3-4 cover public CLI integration and documentation; Task 5 covers package and real CLI verification.
- Placeholder scan: no TODO/TBD steps; every implementation step names files, commands, and expected outcomes.
- Type consistency: `MCPRegistrationScope` and `MCPClientSetupResult.manager` are extended before Claude runtime routing; tests and application fixtures consume the same names.
