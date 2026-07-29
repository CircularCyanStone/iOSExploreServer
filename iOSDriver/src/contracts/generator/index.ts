/**
 * 合同生成器的公共导出面与命令行入口。
 *
 * `generate` 写入所有产物；`check` 只在内存中重新渲染并逐字节比较，用于 CI 检测漂移。
 * 两种模式都先加载和完整校验 bundle，不允许基于无效事实源产生部分文件。
 */
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

/** 一次预处理后渲染全部 TS/Swift/Markdown 产物，不访问目标文件系统。 */
export function renderContractArtifacts(bundle: DriverContractBundle): GeneratedArtifact[] {
  const prepared = prepareContractBundle(bundle);
  return [...emitTypeScript(prepared), ...emitSwift(prepared), emitDocs(prepared)];
}

/**
 * 生成或检查仓库全部合同产物。
 *
 * generate 为每个目标创建父目录并覆写完整内容；check 不写文件，收集全部漂移路径后
 * 一次报错，避免开发者修复一个文件后才看到下一个。
 */
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

/** 从 generator 源码/构建产物的固定层级定位仓库根，不依赖执行 cwd。 */
function discoverRepositoryRoot(): string {
  return resolve(dirname(fileURLToPath(import.meta.url)), "../../../..");
}

/** 被测试或作为库 import 时不读取 argv、不设置进程退出码。 */
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
