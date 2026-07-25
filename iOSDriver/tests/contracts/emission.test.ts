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

  test("declares terminal errors produced by host workflows and artifact decoding", () => {
    const bundle = loadAndValidateContractBundle(repositoryRoot);
    const errorsByOperation = new Map(
      bundle.hostOperations.map(operation => [operation.operation, new Set(operation.errors)])
    );

    expect(errorsByOperation.get("wait_and_inspect")).toContain("workflow_timeout");
    expect(errorsByOperation.get("tap_and_inspect")).toContain("workflow_timeout");
    expect(errorsByOperation.get("call_action")).toContain("artifact_decode_failed");
  });

  test("emits typed Swift fields only for controlled schema shapes", () => {
    const artifacts = new Map(
      renderContractArtifacts(loadAndValidateContractBundle(repositoryRoot)).map(artifact => [artifact.path, artifact.content])
    );
    const uikit = requiredArtifact(artifacts, "Sources/iOSExploreUIKit/Generated/UIKitActionContracts.swift");
    const diagnostics = requiredArtifact(artifacts, "Sources/iOSExploreDiagnostics/Generated/DiagnosticsActionContracts.swift");

    expect(uikit).toContain(
      'CommandFields.optionalInt("buttonIndex", minimum: 0, maximum: 9007199254740991, description: "要触发的按钮下标。")'
    );
    expect(uikit).toContain(
      'CommandFields.requiredStringEnum("event", values: ["touchDown", "touchUpInside", "valueChanged", "editingChanged", "editingDidBegin", "editingDidEnd"], description: "事件名。")'
    );
    expect(uikit).toContain(
      'CommandFields.stringEnum("strategy", values: ["auto", "resignFirstResponder", "endEditing"], default: "auto", description: "键盘收起策略。")'
    );
    expect(uikit).toContain(
      'CommandFields.optionalStringEnum("placement", values: ["left", "right"], description: "导航栏按钮位置。")'
    );
    expect(uikit).toContain(
      'CommandFields.optionalFiniteNumber("amount", minimum: 0, exclusiveMinimum: true, description: "滚动距离（pt），必须 > 0；省略或传 null 时按目标可见区的一半计算。")'
    );
    expect(uikit).toContain(
      'CommandFields.finiteNumber("duration", default: 0.5, minimum: 0, maximum: 10, exclusiveMinimum: true, description: "长按持续时间（秒）；省略或传 null 时使用 0.5，范围 (0, 10]。")'
    );
    expect(diagnostics).toContain(
      'CommandFields.optionalStringEnumArray("sources", values: ["explore", "bridge", "stdout", "stderr", "nslog", "oslog"], itemDescription: "日志来源。", description: "日志来源过滤。")'
    );
    expect(diagnostics).toContain(
      'CommandFields.optionalStringEnum("minimumLevel", values: ["debug", "info", "error", "fault", "unknown"], description: "最低日志等级。")'
    );

    expect(diagnostics).toContain('appLogsReadAfterField = AnyCommandField(name: "after"');
    expect(uikit).toContain('uiControlSendActionValueField = AnyCommandField(name: "value"');
    expect(uikit).toContain('uiWaitAnyConditionsField = AnyCommandField(name: "conditions"');
    expect(uikit).toContain('uiWebViewEvalArgumentsField = AnyCommandField(name: "arguments"');
    expect(uikit).not.toContain("uiWaitAnyConditionsItem");

    expect(uikit).toContain(
      'uiInputFieldsItemModeField = CommandFields.stringEnum("mode", values: ["replace", "append"], default: "replace", description: "写入模式。")'
    );
    expect(uikit).toContain(
      'uiInputFieldsItemInputSchema = CommandInputSchema(fields: [uiInputFieldsItemAccessibilityIdentifierField.erased'
    );
    expect(uikit).toContain(
      'uiInputFieldsField = CommandFields.requiredArray("fields", description: "按顺序执行的字段数组。", itemsSchema: JSON('
    );
    expect(uikit).toContain('"description": .string("单个字段输入。")');
    expect(uikit).toContain('"x-iosExplore-constraints": .object(JSON(');
  });

  test("preserves contract property declaration order in generated Swift schemas", () => {
    const artifacts = new Map(
      renderContractArtifacts(loadAndValidateContractBundle(repositoryRoot)).map(artifact => [artifact.path, artifact.content])
    );
    const uikit = requiredArtifact(artifacts, "Sources/iOSExploreUIKit/Generated/UIKitActionContracts.swift");

    expect(uikit).toContain(
      "uiScrollInputSchema = CommandInputSchema(fields: [uiScrollDirectionField.erased, uiScrollAmountField.erased, uiScrollAccessibilityIdentifierField.erased, uiScrollPathField.erased, uiScrollViewSnapshotIDField.erased, uiScrollAnimatedField.erased]"
    );
    expect(uikit).toContain(
      "uiInputFieldsItemInputSchema = CommandInputSchema(fields: [uiInputFieldsItemAccessibilityIdentifierField.erased, uiInputFieldsItemPathField.erased, uiInputFieldsItemTextField.erased, uiInputFieldsItemModeField.erased, uiInputFieldsItemSubmitField.erased]"
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
