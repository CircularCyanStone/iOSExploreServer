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

  test("moves array enum onto items schema", () => {
    const mapped = mapInputSchema({
      type: "object",
      properties: {
        sources: {
          type: ["array", "null"],
          description: "日志来源过滤",
          enum: ["explore", "bridge", "stdout"]
        }
      }
    });

    expect(mapped.inputSchema).toEqual({
      type: "object",
      properties: {
        sources: {
          type: ["array", "null"],
          description: "日志来源过滤",
          items: {
            type: "string",
            enum: ["explore", "bridge", "stdout"]
          }
        }
      }
    });
  });

  test("does NOT move enum for non-array type fields", () => {
    // 非 array 类型字段（如 ["string","null"]）的 enum 是字段自身取值范围，
    // 不应迁移到 items（字段根本没有 items），必须保留在顶级。
    const mapped = mapInputSchema({
      type: "object",
      properties: {
        minimumLevel: {
          type: ["string", "null"],
          description: "最低日志等级",
          enum: ["debug", "info", "error", "fault", "unknown"]
        }
      }
    });

    expect(mapped.inputSchema).toEqual({
      type: "object",
      properties: {
        minimumLevel: {
          type: ["string", "null"],
          description: "最低日志等级",
          enum: ["debug", "info", "error", "fault", "unknown"]
        }
      }
    });
  });

  test("extracts top-level field constraints into required when property exists", () => {
    // viewSnapshotID is required 且 viewSnapshotID 确实是顶层 property → 应提升为 required。
    const mapped = mapInputSchema({
      type: "object",
      properties: {
        path: { type: ["string", "null"] },
        viewSnapshotID: { type: ["string", "null"] }
      },
      required: [],
      "x-iosExplore-constraints": ["viewSnapshotID is required and must come from ui.inspect"]
    });
    // descriptionSuffix 仍然包含原始约束文本（描述仍需要展示完整约束）。
    expect(mapped.descriptionSuffix).toContain("viewSnapshotID is required");
    // required 被提升：空数组 + 新字段 viewSnapshotID → ["viewSnapshotID"]
    expect(mapped.inputSchema.required).toEqual(["viewSnapshotID"]);
  });

  test("merges constraint-required with existing required fields", () => {
    // event 已在 required，viewSnapshotID 只在 constraints，两者都应在 required 中。
    const mapped = mapInputSchema({
      type: "object",
      properties: {
        path: { type: ["string", "null"] },
        viewSnapshotID: { type: ["string", "null"] },
        event: { type: "string" }
      },
      required: ["event"],
      "x-iosExplore-constraints": ["viewSnapshotID is required"]
    });
    expect(mapped.inputSchema.required).toEqual(expect.arrayContaining(["event", "viewSnapshotID"]));
  });

  test("ignores constraint references to non-existent top-level property", () => {
    // viewSnapshotID 出现在 constraints 但不在 properties 中 → 不应提升为 required。
    const mapped = mapInputSchema({
      type: "object",
      properties: {
        path: { type: ["string", "null"] }
      },
      "x-iosExplore-constraints": ["viewSnapshotID is required"]
    });
    expect(mapped.inputSchema.required).toBeUndefined();
  });

  test("ignores non-top-level constraint like conditions[].mode", () => {
    // "conditions[].mode 必填字段" 中的字段名是 conditions[].mode，不是顶层字段。
    const mapped = mapInputSchema({
      type: "object",
      properties: { conditions: { type: "array" } },
      "x-iosExplore-constraints": ["conditions[].mode 必填字段: textExists 需 text"]
    });
    expect(mapped.inputSchema.required).toBeUndefined();
  });

  // F-02：Claude Code 的 MCP 客户端不消化顶层 oneOf → ui.tap/ui.control.sendAction 等
  // 不会被暴露。App 用 exactlyOneOf(["accessibilityIdentifier","path"]) 产出顶层 oneOf,
  // mapInputSchema 必须把它拍平为 properties + required + 文本说明。
  test("flattens top-level oneOf into properties + description note (ui.tap shape)", () => {
    const mapped = mapInputSchema({
      type: "object",
      properties: {
        accessibilityIdentifier: { type: ["string", "null"], description: "按 identifier 定位" },
        path: { type: ["string", "null"], description: "按 path 定位" },
        viewSnapshotID: { type: ["string", "null"], description: "ui.inspect 签发的快照标识" }
      },
      required: [],
      additionalProperties: false,
      "x-iosExplore-propertyOrder": ["accessibilityIdentifier", "path", "viewSnapshotID"],
      oneOf: [
        { required: ["accessibilityIdentifier"] },
        { required: ["path"] }
      ],
      "x-iosExplore-constraints": ["viewSnapshotID is required and must come from ui.inspect"]
    });

    // 顶层组合关键字必须被消除。
    expect(mapped.inputSchema.oneOf).toBeUndefined();
    expect(mapped.inputSchema.anyOf).toBeUndefined();
    expect(mapped.inputSchema.allOf).toBeUndefined();

    // identifier 与 path 仍保留在 properties 中。
    const props = mapped.inputSchema.properties as Record<string, { description?: string }>;
    expect(props.accessibilityIdentifier).toBeDefined();
    expect(props.path).toBeDefined();
    expect(props.viewSnapshotID).toBeDefined();

    // 互斥字段不强制 required（二选一，不应两者都必填）；
    // 但从 constraint 提取的 viewSnapshotID 仍必填。
    expect(mapped.inputSchema.required).toEqual(["viewSnapshotID"]);

    // description 文本保留"二选一, 互斥"语义（工具级 + 字段级）。
    expect(mapped.descriptionSuffix).toContain("二选一");
    expect(mapped.descriptionSuffix).toContain("accessibilityIdentifier");
    expect(mapped.descriptionSuffix).toContain("path");
    expect(props.accessibilityIdentifier.description ?? "").toContain("二选一");
    expect(props.path.description ?? "").toContain("二选一");
  });

  test("leaves schemas without composition keywords unchanged", () => {
    // 回归安全：无 oneOf/anyOf/allOf 的命令不应被拍平逻辑影响。
    const mapped = mapInputSchema({
      type: "object",
      properties: { action: { type: "string" } },
      required: ["action"]
    });
    expect(mapped.inputSchema.oneOf).toBeUndefined();
    expect(mapped.inputSchema.allOf).toBeUndefined();
    expect(mapped.inputSchema.required).toEqual(["action"]);
    expect(mapped.descriptionSuffix).toBe("");
  });

  test("flattens nested oneOf inside array item schema (ui.input fields shape)", () => {
    const mapped = mapInputSchema({
      type: "object",
      properties: {
        fields: {
          type: "array",
          items: {
            type: "object",
            properties: {
              accessibilityIdentifier: { type: ["string", "null"], description: "按 identifier 定位" },
              path: { type: ["string", "null"], description: "按 path 定位" },
              text: { type: "string", description: "要输入的文本" }
            },
            required: ["text"],
            oneOf: [
              { required: ["accessibilityIdentifier"] },
              { required: ["path"] }
            ]
          }
        }
      },
      required: ["fields"]
    });

    const props = mapped.inputSchema.properties as Record<string, unknown>;
    const fields = props.fields as { items: { oneOf?: unknown; properties: Record<string, { description?: string }> } };
    expect(fields.items.oneOf).toBeUndefined();
    expect(fields.items.properties.accessibilityIdentifier.description ?? "").toContain("二选一");
    expect(fields.items.properties.path.description ?? "").toContain("二选一");
    expect(mapped.descriptionSuffix).toBe("");
  });
});
