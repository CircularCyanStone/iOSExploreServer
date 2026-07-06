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
});
