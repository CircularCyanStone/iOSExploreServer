import { describe, expect, test } from "vitest";
import { compareSchemas } from "../../src/runtime/schemaCompatibility.js";

const schema = (overrides: Record<string, unknown> = {}) => ({
  type: "object",
  properties: {
    name: { type: "string", enum: ["a", "b"] },
    count: { type: "integer", minimum: 1, maximum: 10 },
    tags: { type: "array", items: { type: "string" }, minItems: 1, maxItems: 3 }
  },
  required: ["name"],
  additionalProperties: false,
  ...overrides
});

describe("schema compatibility", () => {
  test("识别 exact、optional additive 和 breaking required", () => {
    expect(compareSchemas(schema(), schema()).status).toBe("exact");
    expect(compareSchemas(schema(), schema({ properties: { ...schema().properties, extra: { type: "string" } } })).status).toBe("additive");
    expect(compareSchemas(schema(), schema({ required: ["name", "count"] })).status).toBe("breaking");
  });

  test("required 移除是 additive，类型/enum/范围/数组收窄是 breaking", () => {
    expect(compareSchemas(schema(), schema({ required: [] })).status).toBe("additive");
    expect(compareSchemas(schema(), schema({ properties: { ...schema().properties, name: { type: "string" } } })).status).toBe("additive");
    expect(compareSchemas(schema(), schema({ properties: { ...schema().properties, name: { type: "string", enum: ["a", "b", "c"] } } })).status).toBe("additive");
    expect(compareSchemas(schema(), schema({ properties: { ...schema().properties, name: { type: "string", enum: ["a"] } } })).status).toBe("breaking");
    expect(compareSchemas(schema(), schema({ properties: { ...schema().properties, count: { type: "integer", minimum: 2, maximum: 9 } } })).status).toBe("breaking");
    expect(compareSchemas(schema(), schema({ properties: { ...schema().properties, tags: { type: "array", items: { type: "string" }, minItems: 2, maxItems: 2 } } })).status).toBe("breaking");
    expect(compareSchemas(schema(), schema({ additionalProperties: true })).status).toBe("additive");
    expect(compareSchemas(schema({ additionalProperties: true }), schema()).status).toBe("breaking");
  });

  test("非法或非 object schema 返回 unknown", () => {
    expect(compareSchemas(schema(), undefined).status).toBe("unknown");
    expect(compareSchemas({ type: "array" }, { type: "array" }).status).toBe("unknown");
    expect(compareSchemas(schema(), { type: "object", properties: [], additionalProperties: false }).status).toBe("unknown");
  });
});
