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
      expect(swift).toContain("CommandInputDefinition(");
      expect(swift).toContain('protocolVersion = "1"');
      expect(swift).not.toContain("import UIKit");
      expect(swift).not.toContain("CommandInputSchema");
      expect(swift).not.toContain("inputSchema:");
      expect(swift).not.toContain("JSON([])");
    }
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

  test("declares terminal errors produced by host workflows and artifact decoding", () => {
    const bundle = loadAndValidateContractBundle(repositoryRoot);
    const errorsByOperation = new Map(
      bundle.hostOperations.map(operation => [operation.operation, new Set(operation.errors)])
    );

    expect(errorsByOperation.get("wait_and_inspect")).toContain("workflow_timeout");
    expect(errorsByOperation.get("tap_and_inspect")).toContain("workflow_timeout");
    expect(errorsByOperation.get("call_action")).toContain("artifact_decode_failed");
  });

  test("emits typed Swift parsers and direct wire validators from controlled schema shapes", () => {
    const artifacts = new Map(
      renderContractArtifacts(loadAndValidateContractBundle(repositoryRoot)).map(artifact => [artifact.path, artifact.content])
    );
    const uikit = requiredArtifact(artifacts, "Sources/iOSExploreUIKit/Generated/UIKitActionContracts.swift");
    const diagnostics = requiredArtifact(artifacts, "Sources/iOSExploreDiagnostics/Generated/DiagnosticsActionContracts.swift");

    expect(uikit).toContain(
      'CommandFields.optionalInt("buttonIndex", minimum: 0, maximum: 9007199254740991)'
    );
    expect(uikit).toContain(
      'CommandFields.requiredStringEnum("event", values: ["touchDown", "touchUpInside", "valueChanged", "editingChanged", "editingDidBegin", "editingDidEnd"])'
    );
    expect(uikit).toContain(
      'CommandFields.stringEnum("strategy", values: ["auto", "resignFirstResponder", "endEditing"], default: "auto")'
    );
    expect(uikit).toContain(
      'CommandFields.optionalStringEnum("placement", values: ["left", "right"])'
    );
    expect(uikit).toContain(
      'CommandFields.optionalFiniteNumber("amount", minimum: 0, exclusiveMinimum: true)'
    );
    expect(uikit).toContain(
      'CommandFields.finiteNumber("duration", default: 0.5, minimum: 0, maximum: 10, exclusiveMinimum: true)'
    );
    expect(diagnostics).toContain(
      'CommandFields.optionalStringEnumArray("sources", values: ["explore", "bridge", "stdout", "stderr", "nslog", "oslog"])'
    );
    expect(diagnostics).toContain(
      'CommandFields.optionalStringEnum("minimumLevel", values: ["debug", "info", "error", "fault", "unknown"])'
    );

    expect(diagnostics).toContain('appLogsReadAfterField = AnyCommandField(name: "after"');
    expect(uikit).toContain('uiControlSendActionValueField = AnyCommandField(name: "value"');
    expect(uikit).toContain('uiWaitAnyConditionsField = AnyCommandField(name: "conditions"');
    expect(uikit).toContain('uiWebViewEvalArgumentsField = AnyCommandField(name: "arguments"');
    expect(uikit).not.toContain("uiWaitAnyConditionsItem");

    expect(uikit).toContain(
      'uiInputFieldsItemModeField = CommandFields.stringEnum("mode", values: ["replace", "append"], default: "replace")'
    );
    expect(uikit).toContain(
      'uiInputFieldsItemInput = CommandInputDefinition(\n        fields: [uiInputFieldsItemAccessibilityIdentifierField.erased'
    );
    expect(uikit).toContain(
      'uiInputFieldsField = CommandFields.requiredArray("fields", minimumCount: 1, maximumCount: 16)'
    );
    expect(uikit).toContain(
      'try CommandWireValidation.object(object2, path: "fields[]", allowedFields: Set(["accessibilityIdentifier", "path", "text", "mode", "submit"]), additionalProperties: false)'
    );
    expect(uikit).toContain(
      'try CommandWireValidation.value(object2["text"], path: "fields[].text", required: true, types: [.string])'
    );
    expect(diagnostics).toContain(
      'try CommandWireValidation.value(object0["id"], path: "after.id", required: true, types: [.integer], minimum: 0, maximum: 9007199254740991)'
    );
  });

  test("preserves contract property declaration order in generated Swift input definitions", () => {
    const artifacts = new Map(
      renderContractArtifacts(loadAndValidateContractBundle(repositoryRoot)).map(artifact => [artifact.path, artifact.content])
    );
    const uikit = requiredArtifact(artifacts, "Sources/iOSExploreUIKit/Generated/UIKitActionContracts.swift");

    expect(uikit).toContain(
      "uiScrollInput = CommandInputDefinition(\n        fields: [uiScrollDirectionField.erased, uiScrollAmountField.erased, uiScrollAccessibilityIdentifierField.erased, uiScrollPathField.erased, uiScrollViewSnapshotIDField.erased, uiScrollAnimatedField.erased]"
    );
    expect(uikit).toContain(
      "uiInputFieldsItemInput = CommandInputDefinition(\n        fields: [uiInputFieldsItemAccessibilityIdentifierField.erased, uiInputFieldsItemPathField.erased, uiInputFieldsItemTextField.erased, uiInputFieldsItemModeField.erased, uiInputFieldsItemSubmitField.erased]"
    );
  });

  test("includes schema property declaration order in the contract hash", () => {
    const original = loadAndValidateContractBundle(repositoryRoot);
    const reordered = loadAndValidateContractBundle(repositoryRoot);
    const action = reordered.deviceActions.find(contract => contract.action === "ui.scroll");
    if (action?.inputSchema.properties === undefined) throw new Error("ui.scroll properties missing");
    action.inputSchema.properties = Object.fromEntries(
      Object.entries(action.inputSchema.properties).reverse()
    );

    expect(prepareContractBundle(reordered).hash).not.toBe(prepareContractBundle(original).hash);
  });

  test("ignores ordinary object key order in the contract hash", () => {
    const original = loadAndValidateContractBundle(repositoryRoot);
    const reordered = loadAndValidateContractBundle(repositoryRoot);
    const [code, error] = Object.entries(reordered.errors)[0] ?? [];
    if (code === undefined || error === undefined) throw new Error("contract errors missing");
    reordered.errors[code] = {
      terminal: error.terminal,
      retryable: error.retryable,
      source: error.source
    };

    expect(prepareContractBundle(reordered).hash).toBe(prepareContractBundle(original).hash);
  });
});

function requiredArtifact(artifacts: ReadonlyMap<string, string>, path: string): string {
  const content = artifacts.get(path);
  if (content === undefined) throw new Error(`missing generated artifact: ${path}`);
  return content;
}
