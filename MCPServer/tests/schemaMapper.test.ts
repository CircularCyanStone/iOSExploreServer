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
});
