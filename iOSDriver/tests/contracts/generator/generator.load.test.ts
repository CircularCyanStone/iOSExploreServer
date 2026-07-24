import { mkdtempSync, mkdirSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterEach, describe, expect, test } from "vitest";
import { loadAndValidateContractBundle, loadContractBundle } from "../../../src/contracts/generator/loadBundle.js";

const temporaryRoots: string[] = [];

afterEach(() => {
  for (const root of temporaryRoots.splice(0)) rmSync(root, { force: true, recursive: true });
});

describe("contract bundle loader", () => {
  test("loads the repository bundle metadata and its minimum real fixtures", () => {
    const bundle = loadAndValidateContractBundle();

    expect(bundle.protocolVersion).toBe("1");
    expect(bundle.contractVersion).toBe("1.0.0");
    expect(bundle.generatorVersion).toBe("1");
    expect(bundle.files).toEqual([
      "device-actions/core.ping.json",
      "host-operations/health.json"
    ]);
    expect(bundle.deviceActions.map(contract => contract.action)).toEqual(["ping"]);
    expect(bundle.hostOperations.map(spec => spec.operation)).toEqual(["health"]);
    expect(Object.keys(bundle.definitions).sort()).toEqual([
      "definitions/locator.json",
      "definitions/protocol-envelope.json",
      "definitions/view-snapshot.json",
      "definitions/wait-condition.json"
    ]);
  });

  test("rejects a manifest entry whose contract file does not exist", () => {
    expectLoaderError(new URL("./fixtures/missing-file/", import.meta.url), "device-actions/not-present.json");
  });

  test("reports a malformed manifest with its relative label", () => {
    const root = makeTemporaryContractsRoot();
    writeFileSync(join(root, "contracts", "bundle.json"), "{", "utf8");

    expectLoaderError(root, "bundle.json");
  });

  test("reports a malformed definition with its relative label", () => {
    const root = makeTemporaryContractsRoot();
    writeFileSync(join(root, "contracts", "definitions", "foo.json"), "{", "utf8");

    expectLoaderError(root, "definitions/foo.json");
  });

  test.each([
    "../outside.json",
    "device-actions\\windows.json",
    "/tmp/absolute.json"
  ])("rejects an unsafe manifest path %s", manifestPath => {
    const root = makeTemporaryContractsRoot({ files: [manifestPath] });

    expectLoaderError(root, "contract manifest path must be local and relative");
  });

  test("rejects a manifest entry that is a symlink outside contracts", () => {
    const root = makeTemporaryContractsRoot({ files: ["device-actions/escaped.json"] });
    const outsidePath = join(root, "outside.json");
    writeJSON(outsidePath, validDeviceAction());
    symlinkSync(outsidePath, join(root, "contracts", "device-actions", "escaped.json"));

    expectLoaderError(root, "contract file must stay inside contracts root: device-actions/escaped.json");
  });
});

function makeTemporaryContractsRoot(options: { files?: string[] } = {}): string {
  const root = mkdtempSync(join(tmpdir(), "ios-driver-contract-loader-"));
  temporaryRoots.push(root);
  mkdirSync(join(root, "contracts", "device-actions"), { recursive: true });
  mkdirSync(join(root, "contracts", "definitions"), { recursive: true });
  writeJSON(join(root, "contracts", "bundle.json"), {
    protocolVersion: "1",
    contractVersion: "1.0.0",
    generatorVersion: "1",
    files: options.files ?? ["device-actions/test.json"]
  });
  writeJSON(join(root, "contracts", "errors.json"), {});
  writeJSON(join(root, "contracts", "device-actions", "test.json"), validDeviceAction());
  return root;
}

function validDeviceAction(): Record<string, unknown> {
  return {
    kind: "deviceAction",
    action: "test.action",
    description: "Test action",
    provider: "core",
    stability: "internal",
    inputSchema: { type: "object", properties: {}, required: [], additionalProperties: false },
    result: { kind: "json" },
    errors: [],
    idempotency: "readOnly",
    timeoutClass: "standard"
  };
}

function writeJSON(path: string, value: unknown): void {
  writeFileSync(path, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}

function expectLoaderError(root: string | URL, expectedLabel: string): void {
  try {
    loadContractBundle(root);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    expect(message).toContain(expectedLabel);
    expect(message).not.toContain(root instanceof URL ? fileURLToPath(root) : root);
    return;
  }
  throw new Error("expected contract bundle loading to fail");
}
