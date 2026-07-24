import { existsSync, readdirSync, readFileSync, realpathSync, statSync } from "node:fs";
import { dirname, isAbsolute, join, posix, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { validateContractBundle } from "./validateBundle.js";
import type {
  DriverContractBundle,
  RawContractDocument,
  RawDriverContractBundle
} from "./model.js";

/**
 * 读取仓库契约文件，但不把 JSON 内容伪装为已验证模型。
 *
 * - Parameter root: 仓库根目录或 `contracts` 目录；省略时从本模块位置发现仓库。
 * - Returns: 可交给 `validateContractBundle` 校验的原始 bundle。
 * - Throws: 文件或 JSON 不可读取时，错误消息只包含 contracts 相对标签。
 */
export function loadContractBundle(root?: string | URL): RawDriverContractBundle {
  const repositoryRoot = root === undefined ? discoverRepositoryRoot() : normalizeRoot(root);
  const contractsRoot = join(repositoryRoot, "contracts");
  const realContractsRoot = realpathOrThrow(contractsRoot, "contracts");
  const manifest = readJSONObject(
    resolveContractFile(contractsRoot, realContractsRoot, "bundle.json"),
    "bundle.json"
  );
  const protocolVersion = requiredString(manifest, "protocolVersion", "bundle.json");
  const contractVersion = requiredString(manifest, "contractVersion", "bundle.json");
  const generatorVersion = requiredString(manifest, "generatorVersion", "bundle.json");
  const files = requiredStringArray(manifest, "files", "bundle.json");
  const errors = readJSONObject(
    resolveContractFile(contractsRoot, realContractsRoot, "errors.json"),
    "errors.json"
  );
  const definitions = readDefinitions(contractsRoot, realContractsRoot);
  const deviceActions: RawContractDocument[] = [];
  const hostOperations: RawContractDocument[] = [];
  const sourceFiles = new Map<object, string>();

  for (const manifestPath of files) {
    assertSafeManifestPath(manifestPath);
    const absolutePath = resolveContractFile(contractsRoot, realContractsRoot, manifestPath);
    const contract = readJSONObject(absolutePath, manifestPath);
    if (contract.kind === "deviceAction") {
      deviceActions.push(contract);
      sourceFiles.set(contract, manifestPath);
    } else if (contract.kind === "hostOperation") {
      hostOperations.push(contract);
      sourceFiles.set(contract, manifestPath);
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

/**
 * 读取并完整校验契约 bundle，供需要 typed contract 的生成器调用。
 *
 * - Parameter root: 仓库根目录或 `contracts` 目录；省略时从本模块位置发现仓库。
 * - Returns: 已通过受控 schema 与元数据校验的 typed bundle。
 * - Throws: 文件读取或契约校验失败时抛出带相对位置的错误。
 */
export function loadAndValidateContractBundle(root?: string | URL): DriverContractBundle {
  const bundle = loadContractBundle(root);
  validateContractBundle(bundle);
  return bundle;
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
  if (
    isAbsolute(path) ||
    posix.isAbsolute(path) ||
    path === "." ||
    path === ".." ||
    path.startsWith("../") ||
    path.includes("\\") ||
    posix.normalize(path) !== path
  ) {
    throw new Error(`contract manifest path must be local and relative: ${path}`);
  }
  if (!path.startsWith("device-actions/") && !path.startsWith("host-operations/")) {
    throw new Error(`contract manifest path has unsupported directory: ${path}`);
  }
}

function resolveContractFile(contractsRoot: string, realContractsRoot: string, label: string): string {
  const candidate = join(contractsRoot, label);
  let stats: ReturnType<typeof statSync>;
  try {
    stats = statSync(candidate);
  } catch {
    throw new Error(`contract file does not exist: ${label}`);
  }
  if (!stats.isFile()) throw new Error(`contract file does not exist: ${label}`);

  const realPath = realpathOrThrow(candidate, label);
  if (!isInsideContractsRoot(realContractsRoot, realPath)) {
    throw new Error(`contract file must stay inside contracts root: ${label}`);
  }
  return realPath;
}

function readDefinitions(contractsRoot: string, realContractsRoot: string): Record<string, RawContractDocument> {
  const directory = join(contractsRoot, "definitions");
  if (!existsSync(directory)) return {};
  const realDirectory = realpathOrThrow(directory, "definitions");
  if (!isInsideContractsRoot(realContractsRoot, realDirectory)) {
    throw new Error("contract file must stay inside contracts root: definitions");
  }

  let names: string[];
  try {
    names = readdirSync(directory).sort();
  } catch {
    throw new Error("failed to read contracts directory: definitions");
  }

  const definitions: Record<string, RawContractDocument> = {};
  for (const name of names) {
    if (!name.endsWith(".json")) continue;
    const label = `definitions/${name}`;
    const path = resolveContractFile(contractsRoot, realContractsRoot, label);
    definitions[label] = readJSONObject(path, label);
  }
  return definitions;
}

function readJSONObject(path: string, label: string): RawContractDocument {
  let source: string;
  try {
    source = readFileSync(path, "utf8");
  } catch {
    throw new Error(`failed to read contract JSON: ${label}`);
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(source);
  } catch {
    throw new Error(`failed to parse contract JSON: ${label}`);
  }
  if (!isRecord(parsed)) throw new Error(`contract JSON must contain an object: ${label}`);
  return parsed;
}

function realpathOrThrow(path: string, label: string): string {
  try {
    return realpathSync(path);
  } catch {
    throw new Error(`contract file does not exist: ${label}`);
  }
}

function isInsideContractsRoot(realContractsRoot: string, path: string): boolean {
  return path === realContractsRoot || path.startsWith(`${realContractsRoot}${sep}`);
}

function requiredString(object: RawContractDocument, key: string, file: string): string {
  const value = object[key];
  if (typeof value !== "string" || value.length === 0) throw new Error(`${file}.${key} must be a non-empty string`);
  return value;
}

function requiredStringArray(object: RawContractDocument, key: string, file: string): string[] {
  const value = object[key];
  if (!Array.isArray(value)) throw new Error(`${file}.${key} must be an array of strings`);
  const strings: string[] = [];
  for (const item of value) {
    if (typeof item !== "string") throw new Error(`${file}.${key} must be an array of strings`);
    strings.push(item);
  }
  return strings;
}

function isRecord(value: unknown): value is RawContractDocument {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
