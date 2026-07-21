import { describe, expect, test } from "vitest";
import { ToolRegistry } from "../src/toolRegistry.js";
import { IOSExploreStructuredError } from "../src/errors.js";
import type { JSONObject } from "../src/types.js";

// 帮助命令的最小返回结构，便于在多个 case 里复用构造 fake help。
type HelpCommand = {
  action: string;
  description: string;
  inputSchema: JSONObject;
};

type FakeClient = {
  call(action: string, data?: JSONObject): Promise<JSONObject>;
};

// 构造一个 fake help client，列出指定 commands。
function fakeHelpClient(commands: HelpCommand[]): FakeClient {
  return {
    call: async (action: string) => {
      expect(action).toBe("help");
      return { commands } as unknown as JSONObject;
    }
  };
}

describe("ToolRegistry", () => {
  test("refreshes tools from help", async () => {
    const registry = new ToolRegistry({
      fixedToolNames: new Set(["health_check"]),
      client: fakeHelpClient([
        {
          action: "ui.inspect",
          description: "inspect targets",
          inputSchema: { type: "object", properties: {} }
        }
      ])
    });

    const result = await registry.refresh();
    expect(result.toolCount).toBe(1);
    expect(result.conflicts).toEqual([]);
    expect(registry.tools()[0]).toMatchObject({
      name: "ui_inspect",
      action: "ui.inspect"
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

  // ui.input 是批量字段数组；工具 description 必须显式点名 fields[]，避免 Agent 按旧单字段形态传参。
  test('appends "fields" array hint to ui.input description', async () => {
    const registry = new ToolRegistry({
      fixedToolNames: new Set(),
      client: fakeHelpClient([
        {
          action: "ui.input",
          description: "向 UITextField/UITextView 批量注入文本",
          inputSchema: {
            type: "object",
            properties: {
              fields: {
                type: "array",
                items: {
                  type: "object",
                  properties: {
                    text: { type: "string" }
                  },
                  required: ["text"]
                }
              }
            },
            required: ["fields"]
          }
        }
      ])
    });

    await registry.refresh();
    const desc = registry.tools()[0].description ?? "";
    expect(desc).toContain("向 UITextField/UITextView 批量注入文本");
    expect(desc).toContain("fields 数组");
    expect(desc).toContain("accessibilityIdentifier/path 二选一");
    expect(desc).toContain("必填 text");
    expect(desc).toContain("单字段输入也必须放入数组");
  });

  // scrollToElement 的 "value" 字段名同样反直觉，老提交 4de3775 已加 suffix；
  // 这里固化这条契约，避免后续重构误删。
  test('appends "value" field hint to ui.scrollToElement description', async () => {
    const registry = new ToolRegistry({
      fixedToolNames: new Set(),
      client: fakeHelpClient([
        {
          action: "ui.scrollToElement",
          description: "滚动到包含指定文本/identifier 的元素可见",
          inputSchema: {
            type: "object",
            properties: {
              value: { type: "string", description: "匹配值: text 片段或 accessibilityIdentifier" }
            },
            required: ["value"]
          }
        }
      ])
    });

    await registry.refresh();
    const desc = registry.tools()[0].description ?? "";
    expect(desc).toContain("滚动到包含指定文本/identifier 的元素可见");
    expect(desc).toContain('"value"');
    expect(desc.toLowerCase()).toContain("accessibilityidentifier");
  });

  // 非 ui.input / ui.scrollToElement 的工具不应被额外注入 ⚠️ field-hint 噪声。
  // 注意 mapInputSchema 会给所有工具追加 "Original iOSExplore action: ..." 后缀，
  // 此处只断言 ⚠️ field-hint 不出现，不限制其他 descriptionSuffix 内容。
  test("does not append field hint to unrelated tools", async () => {
    const registry = new ToolRegistry({
      fixedToolNames: new Set(),
      client: fakeHelpClient([
        {
          action: "ui.inspect",
          description: "返回 targets",
          inputSchema: { type: "object", properties: {} }
        }
      ])
    });

    await registry.refresh();
    const desc = registry.tools()[0].description ?? "";
    expect(desc).toContain("返回 targets");
    expect(desc).not.toContain("⚠️");
  });
});
