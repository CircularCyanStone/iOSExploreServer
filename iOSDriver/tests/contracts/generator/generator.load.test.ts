import { describe, expect, test } from "vitest";
import { loadContractBundle } from "../../../src/contracts/generator/loadBundle.js";

describe("contract bundle loader", () => {
  test("loads the repository bundle metadata and its minimum real fixtures", () => {
    const bundle = loadContractBundle();

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
    expect(() => loadContractBundle(new URL("./fixtures/missing-file/", import.meta.url))).toThrow(
      /contract file does not exist/
    );
  });
});
