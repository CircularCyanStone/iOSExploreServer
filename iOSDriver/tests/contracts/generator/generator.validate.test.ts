import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, test } from "vitest";
import { loadContractBundle } from "../../../src/contracts/generator/loadBundle.js";
import { validateContractBundle } from "../../../src/contracts/generator/validateBundle.js";

const temporaryRoots: string[] = [];

afterEach(() => {
  for (const root of temporaryRoots.splice(0)) rmSync(root, { force: true, recursive: true });
});

describe("contract bundle validator", () => {
  test("rejects an unknown local ref", () => {
    const root = makeBundle({ inputSchema: { $ref: "definitions/missing.json" } });
    expectValidationCode(root, "unknown_ref");
  });

  test("rejects a required field absent from properties", () => {
    const root = makeBundle({
      inputSchema: {
        type: "object",
        properties: { known: { type: "string" } },
        required: ["missing"],
        additionalProperties: false
      }
    });
    expectValidationCode(root, "required_property_missing");
  });

  test("rejects an enum value incompatible with its schema type", () => {
    const root = makeBundle({ inputSchema: { type: "integer", enum: [1, "two"] } });
    expectValidationCode(root, "enum_type_mismatch");
  });

  test("rejects an unknown schema keyword", () => {
    const root = makeBundle({ inputSchema: { type: "string", pattern: "^[a-z]+$" } });
    expectValidationCode(root, "unknown_schema_keyword");
  });

  test("rejects an error code absent from errors.json", () => {
    const root = makeBundle({ errors: ["not_registered"] });
    expectValidationCode(root, "unknown_error_code");
  });

  test("rejects a cycle across local definition refs", () => {
    const root = makeBundle({
      inputSchema: { $ref: "definitions/first.json" },
      definitions: {
        "first.json": { $ref: "./second.json" },
        "second.json": { $ref: "./first.json" }
      }
    });
    expectValidationCode(root, "cyclic_ref");
  });

  test("accepts every keyword in the controlled schema subset", () => {
    const root = makeBundle({
      inputSchema: {
        type: "object",
        description: "All supported schema keywords",
        properties: {
          mode: {
            type: "string",
            enum: ["fast", "safe"],
            default: "safe",
            oneOf: [{ type: "string" }, { type: "null" }],
            allOf: [{ type: "string" }],
            not: { type: "number" },
            description: "Execution mode",
            "x-iosExplore-constraints": { mutuallyExclusiveWith: ["count"] }
          },
          values: {
            type: "array",
            items: { type: "integer" },
            minItems: 1,
            maxItems: 3,
            uniqueItems: true
          },
          ratio: {
            type: "number",
            minimum: 0,
            maximum: 1,
            exclusiveMinimum: -1,
            exclusiveMaximum: 2
          },
          enabled: { type: "boolean" },
          empty: { type: "null" },
          locator: { $ref: "definitions/locator.json" }
        },
        required: ["mode", "values"],
        additionalProperties: { type: "string" }
      },
      definitions: {
        "locator.json": {
          type: "object",
          properties: { path: { type: "string" } },
          required: ["path"],
          additionalProperties: false
        }
      }
    });

    expect(() => validateContractBundle(loadContractBundle(root))).not.toThrow();
  });
});

type JSONValue = null | boolean | number | string | JSONValue[] | { [key: string]: JSONValue };

function makeBundle(overrides: {
  inputSchema?: Record<string, JSONValue>;
  errors?: string[];
  definitions?: Record<string, Record<string, JSONValue>>;
}): string {
  const root = mkdtempSync(join(tmpdir(), "ios-driver-contract-"));
  temporaryRoots.push(root);
  mkdirSync(join(root, "contracts", "device-actions"), { recursive: true });
  mkdirSync(join(root, "contracts", "definitions"), { recursive: true });
  writeJSON(join(root, "contracts", "bundle.json"), {
    protocolVersion: "1",
    contractVersion: "1.0.0",
    generatorVersion: "1",
    files: ["device-actions/test.json"]
  });
  writeJSON(join(root, "contracts", "errors.json"), {
    invalid_data: { source: "appEnvelope", retryable: false, terminal: true }
  });
  writeJSON(join(root, "contracts", "device-actions", "test.json"), {
    kind: "deviceAction",
    action: "test.action",
    description: "Test action",
    provider: "core",
    stability: "internal",
    inputSchema: overrides.inputSchema ?? {
      type: "object",
      properties: {},
      required: [],
      additionalProperties: false
    },
    result: { kind: "json" },
    errors: overrides.errors ?? ["invalid_data"],
    idempotency: "readOnly",
    timeoutClass: "standard"
  });
  for (const [name, schema] of Object.entries(overrides.definitions ?? {})) {
    writeJSON(join(root, "contracts", "definitions", name), schema);
  }
  return root;
}

function expectValidationCode(root: string, code: string): void {
  expect(() => validateContractBundle(loadContractBundle(root))).toThrow(
    expect.objectContaining({ code })
  );
}

function writeJSON(path: string, value: JSONValue): void {
  writeFileSync(path, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}
