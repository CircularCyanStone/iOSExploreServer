import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, test } from "vitest";
import {
  loadAndValidateContractBundle,
  prepareContractBundle,
  renderContractArtifacts
} from "../../src/contracts/generator/index.js";

const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../../..");

describe("contract emission", () => {
  test("emits deterministic cross-language artifacts from the canonical source bundle", () => {
    const bundle = loadAndValidateContractBundle(repositoryRoot);
    const first = renderContractArtifacts(bundle);
    const second = renderContractArtifacts(bundle);
    const prepared = prepareContractBundle(bundle);

    expect(second).toEqual(first);
    expect(prepared.hash).toMatch(/^sha256:[0-9a-f]{64}$/);
    expect(first.map(artifact => artifact.path)).toEqual([
      "iOSDriver/src/generated/deviceActionContracts.ts",
      "iOSDriver/src/generated/hostOperationSpecs.ts",
      "iOSDriver/src/generated/contractBundle.ts",
      "Sources/iOSExploreServer/Generated/CoreActionContracts.swift",
      "Sources/iOSExploreUIKit/Generated/UIKitActionContracts.swift",
      "Sources/iOSExploreDiagnostics/Generated/DiagnosticsActionContracts.swift",
      "docs/generated/contracts.md"
    ]);

    for (const artifact of first) {
      expect(artifact.content).toContain(prepared.hash);
      expect(artifact.content).not.toMatch(/\/Users\/|\/home\/|file:\/\//);
      expect(artifact.content).not.toMatch(/20\d{2}-\d{2}-\d{2}T\d{2}:\d{2}/);
      expect(artifact.content).not.toContain('"$ref"');
      expect(readFileSync(resolve(repositoryRoot, artifact.path), "utf8")).toBe(artifact.content);
    }
  });

  test("keeps generated namespaces and Swift providers isolated", () => {
    const artifacts = new Map(
      renderContractArtifacts(loadAndValidateContractBundle(repositoryRoot)).map(artifact => [artifact.path, artifact.content])
    );
    const device = requiredArtifact(artifacts, "iOSDriver/src/generated/deviceActionContracts.ts");
    const host = requiredArtifact(artifacts, "iOSDriver/src/generated/hostOperationSpecs.ts");
    const metadata = requiredArtifact(artifacts, "iOSDriver/src/generated/contractBundle.ts");
    const core = requiredArtifact(artifacts, "Sources/iOSExploreServer/Generated/CoreActionContracts.swift");
    const uikit = requiredArtifact(artifacts, "Sources/iOSExploreUIKit/Generated/UIKitActionContracts.swift");
    const diagnostics = requiredArtifact(artifacts, "Sources/iOSExploreDiagnostics/Generated/DiagnosticsActionContracts.swift");
    const docs = requiredArtifact(artifacts, "docs/generated/contracts.md");

    expect(device).toContain('"action": "ui.inspect"');
    expect(device).toContain('"action": "app.logs.read"');
    expect(device).not.toContain("ui_inspect");
    expect(host).toContain('"operation": "wait_and_inspect"');
    expect(host).not.toContain('"kind": "deviceAction"');
    expect(metadata).toContain("CONTRACT_BUNDLE_METADATA");
    expect(metadata).toContain("CONTRACT_ERROR_INDEX");

    for (const swift of [core, uikit, diagnostics]) {
      expect(swift).toContain("CommandContract(");
      expect(swift).toContain('protocolVersion = "1"');
      expect(swift).not.toContain("import UIKit");
      expect(swift).not.toContain("JSON([])");
    }
    expect(uikit).toContain("JSON([:])");
    expect(uikit).toContain("CommandFields.bool");
    expect(uikit).toContain("CommandFields.requiredArray");
    expect(uikit).toContain(".erased");
    expect(core).toContain('action: "ping"');
    expect(core).not.toContain('action: "ui.inspect"');
    expect(uikit).toContain('action: "ui.inspect"');
    expect(uikit).not.toContain('action: "app.logs.read"');
    expect(diagnostics).toContain('action: "app.logs.read"');
    expect(diagnostics).not.toContain('action: "ui.inspect"');

    expect(docs).toContain("## Device Actions");
    expect(docs).toContain("## Host Operations");
    expect(docs).toContain("## Error Index");
    expect(docs).toContain("`ui.inspect`");
    expect(docs).toContain("`wait_and_inspect`");
  });
});

function requiredArtifact(artifacts: ReadonlyMap<string, string>, path: string): string {
  const content = artifacts.get(path);
  if (content === undefined) throw new Error(`missing generated artifact: ${path}`);
  return content;
}
