import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { dirname, isAbsolute, join, posix, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";
import type {
  DeviceActionContract,
  DriverContractBundle,
  ErrorContract,
  HostOperationSpec,
  JsonSchema
} from "./model.js";

/** Load the repository contract bundle without contacting a running App. */
export function loadContractBundle(root?: string | URL): DriverContractBundle {
  const repositoryRoot = root === undefined ? discoverRepositoryRoot() : normalizeRoot(root);
  const contractsRoot = join(repositoryRoot, "contracts");
  const manifest = readJSONObject(join(contractsRoot, "bundle.json"));
  const protocolVersion = requiredString(manifest, "protocolVersion", "bundle.json");
  const contractVersion = requiredString(manifest, "contractVersion", "bundle.json");
  const generatorVersion = requiredString(manifest, "generatorVersion", "bundle.json");
  const files = requiredStringArray(manifest, "files", "bundle.json");
  const errors = readJSONObject(join(contractsRoot, "errors.json")) as Record<string, ErrorContract>;
  const definitions = readDefinitions(contractsRoot);
  const deviceActions: DeviceActionContract[] = [];
  const hostOperations: HostOperationSpec[] = [];
  const sourceFiles = new Map<DeviceActionContract | HostOperationSpec, string>();

  for (const manifestPath of files) {
    assertSafeManifestPath(manifestPath);
    const absolutePath = join(contractsRoot, manifestPath);
    if (!existsSync(absolutePath) || !statSync(absolutePath).isFile()) {
      throw new Error(`contract file does not exist: ${manifestPath}`);
    }
    const contract = readJSONObject(absolutePath);
    if (contract.kind === "deviceAction") {
      const typed = contract as unknown as DeviceActionContract;
      deviceActions.push(typed);
      sourceFiles.set(typed, manifestPath);
    } else if (contract.kind === "hostOperation") {
      const typed = contract as unknown as HostOperationSpec;
      hostOperations.push(typed);
      sourceFiles.set(typed, manifestPath);
    } else {
      throw new Error(`contract file has unknown kind: ${manifestPath}`);
    }
  }

  return {
    protocolVersion,
    contractVersion,
    generatorVersion,
    files,
    deviceActions,
    hostOperations,
    errors,
    definitions,
    sourceFiles
  };
}

function discoverRepositoryRoot(): string {
  let current = dirname(fileURLToPath(import.meta.url));
  while (true) {
    if (existsSync(join(current, "contracts", "bundle.json"))) return current;
    const parent = dirname(current);
    if (parent === current) throw new Error("unable to locate contracts/bundle.json from module location");
    current = parent;
  }
}

function normalizeRoot(root: string | URL): string {
  const path = root instanceof URL ? fileURLToPath(root) : root;
  const absolute = resolve(path);
  if (existsSync(join(absolute, "contracts", "bundle.json"))) return absolute;
  if (absolute.endsWith(`${sep}contracts`) && existsSync(join(absolute, "bundle.json"))) return dirname(absolute);
  return absolute;
}

function assertSafeManifestPath(path: string): void {
  if (isAbsolute(path) || path.includes("\\") || posix.normalize(path) !== path) {
    throw new Error(`contract manifest path must be local and relative: ${path}`);
  }
  if (!path.startsWith("device-actions/") && !path.startsWith("host-operations/")) {
    throw new Error(`contract manifest path has unsupported directory: ${path}`);
  }
}

function readDefinitions(contractsRoot: string): Record<string, JsonSchema> {
  const directory = join(contractsRoot, "definitions");
  if (!existsSync(directory)) return {};
  const definitions: Record<string, JsonSchema> = {};
  for (const name of readdirSync(directory).sort()) {
    const path = join(directory, name);
    if (!name.endsWith(".json") || !statSync(path).isFile()) continue;
    definitions[`definitions/${name}`] = readJSONObject(path) as unknown as JsonSchema;
  }
  return definitions;
}

function readJSONObject(path: string): Record<string, unknown> {
  let parsed: unknown;
  try {
    parsed = JSON.parse(readFileSync(path, "utf8"));
  } catch (error) {
    const reason = error instanceof Error ? error.message : String(error);
    throw new Error(`failed to read contract JSON ${path}: ${reason}`);
  }
  if (!isRecord(parsed)) throw new Error(`contract JSON must contain an object: ${path}`);
  return parsed;
}

function requiredString(object: Record<string, unknown>, key: string, file: string): string {
  const value = object[key];
  if (typeof value !== "string" || value.length === 0) throw new Error(`${file}.${key} must be a non-empty string`);
  return value;
}

function requiredStringArray(object: Record<string, unknown>, key: string, file: string): string[] {
  const value = object[key];
  if (!Array.isArray(value) || value.some(item => typeof item !== "string")) {
    throw new Error(`${file}.${key} must be an array of strings`);
  }
  return value as string[];
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
