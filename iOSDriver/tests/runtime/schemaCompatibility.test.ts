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

  test("递归比较 default，新增、删除或值变化均为 breaking", () => {
    const withDefault = schema({
      properties: {
        ...schema().properties,
        options: {
          type: "object",
          properties: {
            mode: { type: "string", default: "compact" },
            filters: {
              type: "array",
              items: { type: "string" },
              default: ["enabled", "visible"]
            }
          },
          default: { mode: "compact", filters: ["enabled", "visible"] }
        }
      }
    });
    const reorderedDefault = schema({
      properties: {
        ...schema().properties,
        options: {
          type: "object",
          properties: {
            mode: { type: "string", default: "compact" },
            filters: {
              type: "array",
              items: { type: "string" },
              default: ["enabled", "visible"]
            }
          },
          default: { filters: ["enabled", "visible"], mode: "compact" }
        }
      }
    });
    const changedNestedDefault = schema({
      properties: {
        ...schema().properties,
        options: {
          type: "object",
          properties: {
            mode: { type: "string", default: "expanded" },
            filters: {
              type: "array",
              items: { type: "string" },
              default: ["enabled", "visible"]
            }
          },
          default: { mode: "compact", filters: ["enabled", "visible"] }
        }
      }
    });
    const withoutNestedDefault = schema({
      properties: {
        ...schema().properties,
        options: {
          type: "object",
          properties: {
            mode: { type: "string" },
            filters: {
              type: "array",
              items: { type: "string" },
              default: ["enabled", "visible"]
            }
          },
          default: { mode: "compact", filters: ["enabled", "visible"] }
        }
      }
    });

    expect(compareSchemas(withDefault, reorderedDefault).status).toBe("exact");
    expect(compareSchemas(withDefault, changedNestedDefault).status).toBe("breaking");
    expect(compareSchemas(withDefault, withoutNestedDefault).status).toBe("breaking");
    expect(compareSchemas(withoutNestedDefault, withDefault).status).toBe("breaking");
  });

  test("integer 到 number 是扩宽，number 到 integer 是收窄，并保留 null 联合语义", () => {
    const withValueType = (type: string | string[]) => schema({
      properties: { ...schema().properties, value: { type } }
    });

    expect(compareSchemas(withValueType("integer"), withValueType("number")).status).toBe("additive");
    expect(compareSchemas(withValueType("number"), withValueType("integer")).status).toBe("breaking");
    expect(compareSchemas(withValueType(["integer", "null"]), withValueType(["number", "null"])).status).toBe("additive");
    expect(compareSchemas(withValueType(["number", "null"]), withValueType(["integer", "null"])).status).toBe("breaking");
    expect(compareSchemas(withValueType(["number", "integer", "null"]), withValueType(["number", "null"])).status).toBe("exact");
  });

  test("非法约束值和明显冲突的边界返回 unknown 与 invalid 差异", () => {
    const resultFor = (property: Record<string, unknown>) => compareSchemas(schema(), schema({
      properties: { ...schema().properties, count: property }
    }));

    for (const property of [
      { type: "integer", minimum: "1", maximum: 10 },
      { type: "integer", minimum: Number.POSITIVE_INFINITY, maximum: 10 },
      { type: "integer", minimum: 1, maximum: Number.NaN },
      { type: "integer", exclusiveMinimum: "1", maximum: 10 },
      { type: "integer", minimum: 1, exclusiveMaximum: Number.NEGATIVE_INFINITY },
      { type: "integer", minimum: 11, maximum: 10 },
      { type: "array", items: { type: "string" }, minItems: -1, maxItems: 3 },
      { type: "array", items: { type: "string" }, minItems: 1.5, maxItems: 3 },
      { type: "array", items: { type: "string" }, minItems: 1, maxItems: -1 },
      { type: "array", items: { type: "string" }, minItems: 1, maxItems: 3.5 },
      { type: "array", items: { type: "string" }, minItems: 4, maxItems: 3 }
    ]) {
      const result = resultFor(property);
      expect(result.status).toBe("unknown");
      expect(result.differences.some(difference => difference.kind === "invalid")).toBe(true);
    }

    const invalidContract = compareSchemas(schema({
      properties: { ...schema().properties, count: { type: "integer", minimum: "1", maximum: 10 } }
    }), schema());
    expect(invalidContract.status).toBe("unknown");
    expect(invalidContract.differences.some(difference => difference.kind === "invalid")).toBe(true);
  });
});
