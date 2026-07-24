import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { emitDocs } from "./emitDocs.js";
import { emitSwift } from "./emitSwift.js";
import {
  emitTypeScript,
  prepareContractBundle,
  type GeneratedArtifact
} from "./emitTypeScript.js";
import { loadAndValidateContractBundle } from "./loadBundle.js";
import type { DriverContractBundle } from "./model.js";

export { emitDocs } from "./emitDocs.js";
export { emitSwift } from "./emitSwift.js";
export {
  emitTypeScript,
  prepareContractBundle,
  stableNormalize,
  type CanonicalContractBundle,
  type GeneratedArtifact,
  type PreparedContractBundle
} from "./emitTypeScript.js";
export { loadAndValidateContractBundle, loadContractBundle } from "./loadBundle.js";
export {
  ContractValidationError,
  validateContractBundle,
  type ContractValidationCode
} from "./validateBundle.js";
export type {
  ContractIdempotency,
  ContractJSONValue,
  ContractProvider,
  ContractStability,
  ContractTimeoutClass,
  DeviceActionContract,
  DriverContractBundle,
  ErrorContract,
  HostOperationSpec,
  JsonSchema,
  JsonSchemaType,
  RawContractDocument,
  RawDriverContractBundle,
  ResultSpec
} from "./model.js";

/** Render every checked-in contract artifact without touching the file system. */
export function renderContractArtifacts(bundle: DriverContractBundle): GeneratedArtifact[] {
  const prepared = prepareContractBundle(bundle);
  return [...emitTypeScript(prepared), ...emitSwift(prepared), emitDocs(prepared)];
}

/** Generate or check all contract artifacts in a repository. */
export function runContractGenerator(command: "generate" | "check", repositoryRoot = discoverRepositoryRoot()): void {
  const artifacts = renderContractArtifacts(loadAndValidateContractBundle(repositoryRoot));
  if (command === "generate") {
    for (const artifact of artifacts) {
      const target = resolve(repositoryRoot, artifact.path);
      mkdirSync(dirname(target), { recursive: true });
      writeFileSync(target, artifact.content, "utf8");
    }
    return;
  }

  const drifted: string[] = [];
  for (const artifact of artifacts) {
    const target = resolve(repositoryRoot, artifact.path);
    if (!existsSync(target) || readFileSync(target, "utf8") !== artifact.content) drifted.push(artifact.path);
  }
  if (drifted.length > 0) {
    throw new Error(`generated contract files are out of date:\n${drifted.map(path => `- ${path}`).join("\n")}`);
  }
}

function discoverRepositoryRoot(): string {
  return resolve(dirname(fileURLToPath(import.meta.url)), "../../../..");
}

function isMainModule(): boolean {
  const entry = process.argv[1];
  return entry !== undefined && import.meta.url === pathToFileURL(resolve(entry)).href;
}

if (isMainModule()) {
  const command = process.argv[2];
  if (command !== "generate" && command !== "check") {
    console.error("usage: tsx src/contracts/generator/index.ts <generate|check>");
    process.exitCode = 2;
  } else {
    try {
      runContractGenerator(command);
    } catch (error) {
      console.error(error instanceof Error ? error.message : String(error));
      process.exitCode = 1;
    }
  }
}
