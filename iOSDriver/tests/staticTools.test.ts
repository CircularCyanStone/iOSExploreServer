import { describe, expect, test } from "vitest";
import { createStaticTools, STATIC_ACTIONS, STATIC_TOOL_NAMES } from "../src/staticTools.js";
import { IOSExploreStructuredError } from "../src/errors.js";

const text = (result: { content: Array<{ type: string; text?: string }> }) => {
  const item = result.content.find(item => item.type === "text");
  if (!item?.text) throw new Error("expected text content");
  return JSON.parse(item.text) as Record<string, unknown>;
};

describe("static tools", () => {
  test("完整静态工具集合无重复，并覆盖所有稳定公共 action", () => {
    expect(new Set(STATIC_TOOL_NAMES).size).toBe(STATIC_TOOL_NAMES.length);
    const tools = createStaticTools({ client: { call: async () => ({}) } });
    expect(Object.keys(tools).sort()).toEqual([...STATIC_TOOL_NAMES].sort());
    for (const name of ["ui_topViewHierarchy", "ui_inspect", "ui_control_sendAction", "ui_tap", "ui_screenshot", "ui_input", "ui_keyboard_dismiss", "ui_scroll", "ui_navigation_back", "ui_navigation_tapBarButton", "ui_wait", "ui_waitAny", "ui_scrollToElement", "ui_alert_respond", "ui_controllers", "ui_swipe", "ui_longPress", "ui_tabBar_selectTab", "ui_datePicker_setDate", "ui_picker_selectRow", "ui_webView_eval", "app_logs_mark", "app_logs_read"]) {
      expect(tools[name]).toBeDefined();
    }
  });

  test("静态工具到 App action 映射正确", async () => {
    const calls: string[] = [];
    const tools = createStaticTools({ client: { call: async action => { calls.push(action); return {}; } } });
    for (const [toolName, action] of Object.entries(STATIC_ACTIONS)) await tools[toolName]!.handler({});
    expect(calls).toEqual(Object.values(STATIC_ACTIONS));
  });

  test("能力检查只调用一次 ping/help，并报告缺失模块而不改变静态集合", async () => {
    const calls: string[] = [];
    const tools = createStaticTools({ client: { call: async action => { calls.push(action); return action === "ping" ? { pong: true } : { commands: [] }; } } });
    const result = await tools.check_capabilities!.handler({});
    expect(calls).toEqual(["ping", "help"]);
    expect(text(result)).toMatchObject({ ok: false, server: { ok: true }, app: { missingStaticActions: expect.arrayContaining(["ui.inspect", "app.logs.read"]) } });
  });

  test("能力检查区分模块未注册、部分注册和完整注册", async () => {
    const uikitActions = Object.values(STATIC_ACTIONS).filter(action => action.startsWith("ui."));
    const schemaTools = createStaticTools({ client: { call: async () => ({}) } });
    const tools = createStaticTools({ client: { call: async action => action === "ping" ? { pong: true } : { commands: [
      ...uikitActions.map(action => ({ action, inputSchema: schemaTools[Object.entries(STATIC_ACTIONS).find(([, mappedAction]) => mappedAction === action)![0]]!.inputSchema })),
      { action: "app.logs.mark", inputSchema: { type: "object", properties: {}, additionalProperties: false } }
    ] } } });
    const body = text(await tools.check_capabilities!.handler({})) as any;
    expect(body.app.modules).toMatchObject({
      uikit: { status: "registered", registeredCount: uikitActions.length, missingActions: [] },
      diagnostics: { status: "partial", registeredCount: 1, missingActions: ["app.logs.read"] }
    });

    const emptyTools = createStaticTools({ client: { call: async action => action === "ping" ? { pong: true } : { commands: [] } } });
    const emptyBody = text(await emptyTools.check_capabilities!.handler({})) as any;
    expect(emptyBody.app.modules).toMatchObject({ uikit: { status: "not_registered" }, diagnostics: { status: "not_registered" } });
  });

  test("health_check 返回 server、ping、help 和缺失 action 状态", async () => {
    const tools = createStaticTools({ client: { call: async action => action === "ping" ? { pong: true } : { commands: [{ action: "ui.inspect", inputSchema: { type: "object" } }] } } });
    expect(text(await tools.health_check!.handler({}))).toMatchObject({ server: { ok: true }, app: { ping: { ok: true }, help: { ok: true } } });
  });

  test("health_check 遇到 transport 失败时返回单条连接结论和下一步", async () => {
    const tools = createStaticTools({ client: { call: async action => {
      throw new IOSExploreStructuredError({ source: "transport", code: "connection_failed", message: `${action} offline`, action });
    } } });
    const body = text(await tools.health_check!.handler({})) as any;
    expect(body.ok).toBe(false);
    expect(body.connection).toMatchObject({
      status: "app_endpoint_unreachable",
      probableCause: expect.stringContaining("HTTP 自动化端点"),
      nextSteps: expect.arrayContaining([
        expect.stringContaining("目标 App 仍在运行"),
        expect.stringContaining("localhost:38321"),
        expect.stringContaining("launch_app_device"),
        expect.stringContaining("*_sim")
      ])
    });
    expect(body.app).toMatchObject({
      ping: { ok: false, error: { source: "transport", code: "connection_failed" } },
      help: { ok: false, error: { source: "transport", code: "connection_failed" } }
    });
  });

  test("ui.screenshot 将 PNG 转为 MCP image content", async () => {
    const tools = createStaticTools({ client: { call: async () => ({ image: "base64png", format: "png", width: 10, height: 20, scale: 2 }) } });
    const result = await tools.ui_screenshot!.handler({});
    expect(result.content).toEqual([
      { type: "image", data: "base64png", mimeType: "image/png" },
      { type: "text", text: JSON.stringify({ format: "png", width: 10, height: 20, scale: 2 }) }
    ]);
  });

  test("ui.waitAny 暴露完整 condition schema，日志 schema有边界", () => {
    const tools = createStaticTools({ client: { call: async () => ({}) } });
    const waitSchema = tools.ui_waitAny!.inputSchema as any;
    expect(waitSchema.required).toEqual(["conditions"]);
    expect(waitSchema.properties.conditions.items.required).toEqual(["id", "mode"]);
    expect(waitSchema.properties.conditions.items.properties.mode.enum).toEqual(["idle", "targetExists", "targetGone", "textExists", "snapshotChanged"]);
    const logs = tools.app_logs_read!.inputSchema as any;
    expect(logs.properties.limit).toMatchObject({ minimum: 1, maximum: 500, default: 100 });
    expect(logs.properties.sources.items.enum).toEqual(["explore", "bridge", "stdout", "stderr", "nslog", "oslog"]);
  });

  test("公共 schema 的关键范围、默认值和约束与 Swift parser 对齐", () => {
    const tools = createStaticTools({ client: { call: async () => ({}) } });
    expect((tools.ui_inspect!.inputSchema as any).properties).toMatchObject({
      textLimit: { minimum: 1, maximum: 200, default: 80 },
      maxTargets: { minimum: 1, maximum: 512, default: 200 },
      maxVisitedNodes: { minimum: 100, maximum: 20000, default: 2000 }
    });
    expect((tools.ui_control_sendAction!.inputSchema as any).properties.event.enum).toContain("touchDown");
    expect((tools.ui_scrollToElement!.inputSchema as any).properties).toEqual(expect.objectContaining({
      match: expect.objectContaining({ default: "text" }),
      value: expect.any(Object),
      accessibilityIdentifier: expect.any(Object),
      path: expect.any(Object),
      animated: expect.objectContaining({ default: false })
    }));
    expect((tools.ui_swipe!.inputSchema as any).properties).toEqual(expect.objectContaining({
      distance: expect.any(Object), cellAccessibilityIdentifier: expect.any(Object), cellPath: expect.any(Object), actionTitle: expect.any(Object)
    }));
    expect((tools.ui_longPress!.inputSchema as any).required).toBeUndefined();
    expect((tools.ui_keyboard_dismiss!.inputSchema as any).properties.waitAfterMs).toMatchObject({ minimum: 0, maximum: 3000, default: 200 });
  });

  test("表单静态工具暴露批量输入与数值控件关键约束", () => {
    const tools = createStaticTools({ client: { call: async () => ({}) } });
    const input = tools.ui_input!.inputSchema as any;
    expect(input.required).toEqual(["fields"]);
    expect(input.properties.fields).toMatchObject({ minItems: 1, maxItems: 16 });
    expect(input.properties.fields.items.properties).toMatchObject({
      mode: { enum: ["replace", "append"], default: "replace" },
      submit: { type: "boolean", default: false }
    });

    const control = tools.ui_control_sendAction!.inputSchema as any;
    expect(control.required).toEqual(["event", "viewSnapshotID"]);
    expect(control.properties.value.type).toBe("number");
    expect(control.properties.event.enum).toContain("valueChanged");
  });

  test("wait_and_inspect schema 与返回值保留 wait 和 observation 两层", async () => {
    const calls: Array<{ action: string; data: Record<string, unknown> }> = [];
    const tools = createStaticTools({ client: { call: async (action, data) => {
      calls.push({ action, data });
      if (action === "ui.waitAny") return { satisfied: true, matchedID: "success" };
      if (action === "ui.inspect") return { targets: [{ path: "root/0" }] };
      return {};
    } } });

    const schema = tools.wait_and_inspect!.inputSchema as any;
    expect(schema.required).toEqual(["conditions"]);
    expect(Object.keys(schema.properties.inspectOptions.properties).sort()).toEqual([
      "accessibilityIdentifier",
      "accessibilityIdentifierPrefix",
      "includeHidden",
      "maxDepth",
      "maxTargets",
      "maxVisitedNodes",
      "textLimit"
    ]);

    const result = await tools.wait_and_inspect!.handler({
      conditions: [{ id: "success", mode: "targetExists", accessibilityIdentifier: "result" }],
      timeoutMs: 1000,
      inspectOptions: { maxDepth: 4, maxTargets: 20 }
    });
    expect(text(result)).toEqual({
      wait: { satisfied: true, matchedID: "success" },
      observation: { targets: [{ path: "root/0" }] }
    });
    expect(calls).toEqual([
      {
        action: "ui.waitAny",
        data: {
          conditions: [{ id: "success", mode: "targetExists", accessibilityIdentifier: "result" }],
          timeoutMs: 1000
        }
      },
      { action: "ui.inspect", data: { maxDepth: 4, maxTargets: 20 } }
    ]);
  });

  test("ui_tap_and_inspect 把提交后 inspect 结果放在 stateAfter", async () => {
    const tools = createStaticTools({ client: { call: async action => {
      if (action === "ui.tap") return { tapped: true };
      if (action === "ui.inspect") return { targets: [{ accessibilityIdentifier: "validation-result" }] };
      return { satisfied: true };
    } } });

    const result = await tools.ui_tap_and_inspect!.handler({
      accessibilityIdentifier: "submit",
      viewSnapshotID: "snapshot",
      waitForStable: false,
      inspectDepth: 4,
      inspectMaxTargets: 20
    });
    expect(text(result)).toMatchObject({
      tap: { tapped: true },
      stateAfter: { targets: [{ accessibilityIdentifier: "validation-result" }] },
      timing: expect.any(Object)
    });
  });

  test("静态工具转发 App unknown_action 时保留业务结果语义", async () => {
    const tools = createStaticTools({ client: { call: async () => {
      throw new IOSExploreStructuredError({ source: "ios_envelope", code: "unknown_action", message: "not registered" });
    } } });
    const result = await tools.ui_inspect!.handler({});
    expect(result.isError).toBe(true);
    expect(text(result)).toMatchObject({
      source: "ios_envelope",
      code: "unknown_action",
      nextSteps: expect.arrayContaining([expect.stringContaining("check_capabilities")])
    });
  });

  test("静态工具保留 App 失败 data 并补充下一步建议", async () => {
    const tools = createStaticTools({ client: { call: async () => {
      throw new IOSExploreStructuredError({
        source: "ios_envelope",
        code: "wait_timeout",
        message: "wait timed out mode=any",
        data: { elapsedMs: 1200, attempts: 12 }
      });
    } } });
    const result = await tools.ui_waitAny!.handler({ conditions: [{ id: "done", mode: "textExists", text: "Done" }] });
    expect(result.isError).toBe(false);
    expect(text(result)).toMatchObject({
      source: "ios_envelope",
      code: "wait_timeout",
      data: { elapsedMs: 1200, attempts: 12 },
      nextSteps: expect.arrayContaining([expect.stringContaining("wait_and_inspect")])
    });
  });

  test("能力检查无法读取 help 时不伪造缺失 action，并报告模块状态 unknown", async () => {
    const tools = createStaticTools({ client: { call: async action => {
      throw new IOSExploreStructuredError({ source: "transport", code: "connection_failed", message: `${action} offline` });
    } } });
    const body = text(await tools.check_capabilities!.handler({}));
    expect(body.app).toMatchObject({ missingStaticActions: [], modules: { uikit: { status: "unknown" }, diagnostics: { status: "unknown" } } });
    expect(body.ok).toBe(false);
  });

  test("能力检查会报告静态 schema 与 help 的字段不兼容", async () => {
    const tools = createStaticTools({ client: { call: async action => action === "ping" ? { pong: true } : { commands: [
      { action: "ui.inspect", inputSchema: { type: "object", properties: { wrongField: { type: "string" } }, additionalProperties: false } }
    ] } } });
    const body = text(await tools.check_capabilities!.handler({})) as any;
    expect(body.app.schemaIncompatibilities).toEqual(expect.arrayContaining([expect.stringContaining("ui.inspect: properties")]));
  });

  test("能力检查会报告 action 缺少合法 inputSchema", async () => {
    const tools = createStaticTools({ client: { call: async action => action === "ping" ? { pong: true } : { commands: [
      { action: "ui.inspect", inputSchema: "invalid" }
    ] } } });
    const body = text(await tools.check_capabilities!.handler({})) as any;
    expect(body.app.schemaIncompatibilities).toContain("ui.inspect: inputSchema missing or invalid");
  });

  test("malformed help 不会被误报为成功", async () => {
    const tools = createStaticTools({ client: { call: async action => action === "ping" ? { pong: true } : {} } });
    const body = text(await tools.health_check!.handler({})) as any;
    expect(body.ok).toBe(false);
    expect(body.app.help).toMatchObject({ ok: false, status: "unknown", error: { code: "invalid_help_response" } });
    expect(body.app.missingStaticActions).toEqual([]);
  });

  test("call_action 的 unknown_action 保持可解析业务结果", async () => {
    const tools = createStaticTools({ client: { call: async () => {
      throw new IOSExploreStructuredError({ source: "ios_envelope", code: "unknown_action", message: "custom action missing" });
    } } });
    const result = await tools.call_action!.handler({ action: "debug.missing" });
    expect(result.isError).toBe(false);
    expect(text(result)).toMatchObject({
      code: "unknown_action",
      nextSteps: expect.arrayContaining([expect.stringContaining("health_check")])
    });
  });

  test("call_action transport 重试失败后返回 retry 和 healthCheck", async () => {
    const calls: string[] = [];
    const tools = createStaticTools({ client: { call: async action => {
      calls.push(action);
      throw new IOSExploreStructuredError({ source: "transport", code: "connection_failed", message: "offline", action });
    } } });
    const result = await tools.call_action!.handler({ action: "debug.custom" });
    expect(result.isError).toBe(true);
    expect(calls).toEqual(["debug.custom", "debug.custom", "ping"]);
    expect(text(result)).toMatchObject({
      retry: { attempted: true, succeeded: false },
      healthCheck: { ok: false },
      connection: { status: "app_endpoint_unreachable" }
    });
  });

  test("call_action 保留自定义 action 转发和 transport 重试", async () => {
    const calls: string[] = [];
    const tools = createStaticTools({ client: { call: async action => { calls.push(action); if (calls.length === 1) throw new IOSExploreStructuredError({ source: "transport", code: "connection_failed", message: "offline", action }); return { custom: true }; } } });
    expect(text(await tools.call_action!.handler({ action: "debug.custom", data: { value: 1 } }))).toEqual({ custom: true });
    expect(calls).toEqual(["debug.custom", "debug.custom"]);
  });
});
