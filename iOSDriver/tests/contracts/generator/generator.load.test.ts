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
  test("loads the repository bundle metadata and its full contract set", () => {
    const bundle = loadAndValidateContractBundle();

    expect(bundle.protocolVersion).toBe("1");
    expect(bundle.contractVersion).toBe("1.0.0");
    expect(bundle.generatorVersion).toBe("1");
    expect(bundle.files).toEqual([
      "device-actions/core.ping.json",
      "device-actions/core.echo.json",
      "device-actions/core.info.json",
      "device-actions/core.help.json",
      "device-actions/uikit.top-view-hierarchy.json",
      "device-actions/uikit.inspect.json",
      "device-actions/uikit.control-send-action.json",
      "device-actions/uikit.tap.json",
      "device-actions/uikit.screenshot.json",
      "device-actions/uikit.input.json",
      "device-actions/uikit.keyboard-dismiss.json",
      "device-actions/uikit.scroll.json",
      "device-actions/uikit.navigation-back.json",
      "device-actions/uikit.navigation-tap-bar-button.json",
      "device-actions/uikit.wait.json",
      "device-actions/uikit.wait-any.json",
      "device-actions/uikit.scroll-to-element.json",
      "device-actions/uikit.alert-respond.json",
      "device-actions/uikit.controllers.json",
      "device-actions/uikit.swipe.json",
      "device-actions/uikit.long-press.json",
      "device-actions/uikit.tab-bar-select-tab.json",
      "device-actions/uikit.date-picker-set-date.json",
      "device-actions/uikit.picker-select-row.json",
      "device-actions/uikit.web-view-eval.json",
      "device-actions/diagnostics.app-logs-mark.json",
      "device-actions/diagnostics.app-logs-read.json",
      "host-operations/health.json",
      "host-operations/capabilities.json",
      "host-operations/call-action.json",
      "host-operations/wait-and-inspect.json",
      "host-operations/tap-and-inspect.json"
    ]);
    expect(bundle.deviceActions).toHaveLength(27);
    expect(bundle.hostOperations).toHaveLength(5);
    expect(bundle.deviceActions.map(contract => contract.action).sort()).toEqual([
      "app.logs.mark",
      "app.logs.read",
      "echo",
      "help",
      "info",
      "ping",
      "ui.alert.respond",
      "ui.control.sendAction",
      "ui.controllers",
      "ui.datePicker.setDate",
      "ui.input",
      "ui.inspect",
      "ui.keyboard.dismiss",
      "ui.longPress",
      "ui.navigation.back",
      "ui.navigation.tapBarButton",
      "ui.picker.selectRow",
      "ui.screenshot",
      "ui.scroll",
      "ui.scrollToElement",
      "ui.swipe",
      "ui.tabBar.selectTab",
      "ui.tap",
      "ui.topViewHierarchy",
      "ui.wait",
      "ui.waitAny",
      "ui.webView.eval"
    ]);
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

  test("rejects a bundle manifest symlink outside contracts", () => {
    const root = makeTemporaryContractsRoot();
    const bundlePath = join(root, "contracts", "bundle.json");
    const outsidePath = join(root, "outside-bundle.json");
    writeJSON(outsidePath, validManifest());
    rmSync(bundlePath);
    symlinkSync(outsidePath, bundlePath);

    expectLoaderError(root, "contract file must stay inside contracts root: bundle.json");
  });

  test("rejects an errors file symlink outside contracts", () => {
    const root = makeTemporaryContractsRoot();
    const errorsPath = join(root, "contracts", "errors.json");
    const outsidePath = join(root, "outside-errors.json");
    writeJSON(outsidePath, {});
    rmSync(errorsPath);
    symlinkSync(outsidePath, errorsPath);

    expectLoaderError(root, "contract file must stay inside contracts root: errors.json");
  });
});

function makeTemporaryContractsRoot(options: { files?: string[] } = {}): string {
  const root = mkdtempSync(join(tmpdir(), "ios-driver-contract-loader-"));
  temporaryRoots.push(root);
  mkdirSync(join(root, "contracts", "device-actions"), { recursive: true });
  mkdirSync(join(root, "contracts", "definitions"), { recursive: true });
  writeJSON(join(root, "contracts", "bundle.json"), validManifest(options.files));
  writeJSON(join(root, "contracts", "errors.json"), {});
  writeJSON(join(root, "contracts", "device-actions", "test.json"), validDeviceAction());
  return root;
}

function validManifest(files: string[] = ["device-actions/test.json"]): Record<string, unknown> {
  return {
    protocolVersion: "1",
    contractVersion: "1.0.0",
    generatorVersion: "1",
    files
  };
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
    const rootPath = root instanceof URL ? fileURLToPath(root) : root;
    expect(message).not.toContain(rootPath);
    if (error instanceof Error && error.cause instanceof Error) {
      expect(error.cause.message).not.toContain(rootPath);
    }
    return;
  }
  throw new Error("expected contract bundle loading to fail");
}
