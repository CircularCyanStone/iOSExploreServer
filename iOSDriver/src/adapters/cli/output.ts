/**
 * CLI 结果的终端投影。
 *
 * 成功业务结果只写 stdout，失败对象只写 stderr，结构化 Host 日志也使用 stderr。
 * 因此脚本可以安全地把 stdout 交给 JSON parser；MCP 模式完全绕过本模块的进程输出。
 */
import { writeFile } from "node:fs/promises";
import type { InvocationResult } from "../../runtime/types.js";
import type { DriverError } from "../../runtime/driverErrors.js";
import type { JSONObject } from "../../types.js";

/** CLI 的可注入输出流，保证业务输出和诊断日志不混用。 */
export interface CLIOutput {
  readonly stdout: (text: string) => void;
  readonly stderr: (text: string) => void;
}

/** image artifact 的可注入文件写入边界。 */
export type ArtifactWriter = (path: string, data: Uint8Array) => Promise<void>;

/** 进程默认输出；MCP 模式不调用这些方法，避免污染 stdout 帧。 */
export const processOutput: CLIOutput = {
  stdout: text => process.stdout.write(text),
  stderr: text => process.stderr.write(text)
};

/** 输出 JSON 数据到 stdout。 */
export function printJSON(output: CLIOutput, value: unknown): void {
  output.stdout(`${JSON.stringify(value, null, 2)}\n`);
}

/** 输出一行人类可读文本到 stdout。 */
export function printHuman(output: CLIOutput, text: string): void {
  output.stdout(`${text}\n`);
}

/** 输出错误摘要到 stderr，不把完整用户 payload 写入日志。 */
export function printError(output: CLIOutput, error: DriverError | Error | string): void {
  const message = error instanceof Error ? error.message : typeof error === "string" ? error : `${error.code}: ${error.message}`;
  output.stderr(`${message}\n`);
}

/** 调用成功时的 CLI 投影；截图 artifact 只在显式 output 时写文件。 */
export async function printInvocationSuccess(
  output: CLIOutput,
  result: Extract<InvocationResult, { readonly ok: true }>,
  artifactOutput?: string,
  write: ArtifactWriter = writeArtifact
): Promise<void> {
  const image = result.artifacts.find(artifact => artifact.kind === "image");
  // 不提供 --output 时绝不隐式落盘；MCP adapter 会用自己的 image content 投影附件。
  if (artifactOutput !== undefined && image !== undefined) {
    await write(artifactOutput, image.data);
  }
  const metadata: JSONObject = {
    ...result.data,
    ...(image === undefined ? {} : {
      artifact: {
        kind: image.kind,
        mimeType: image.mimeType,
        bytes: image.data.byteLength,
        path: artifactOutput
      }
    })
  };
  printJSON(output, metadata);
}

/**
 * 将失败结果写到 stderr，并保留可机器读取的稳定字段。
 *
 * 这里不直接打印 `DriverError`，是为了省略不存在的可选键，并优先使用 runtime 已清理
 * 的 data，防止失败 envelope 中的非法或超限 artifact 原文绕过 decoder。
 */
export function printInvocationFailure(output: CLIOutput, result: Extract<InvocationResult, { readonly ok: false }>): void {
  const error = result.error;
  printJSON({ ...output, stdout: output.stderr }, {
    source: error.source,
    code: error.code,
    message: error.message,
    ...(error.action === undefined ? {} : { action: error.action }),
    ...(error.baseURL === undefined ? {} : { baseURL: error.baseURL }),
    ...(error.status === undefined ? {} : { status: error.status }),
    ...(error.timeoutMs === undefined ? {} : { timeoutMs: error.timeoutMs }),
    ...(error.bodySnippet === undefined ? {} : { bodySnippet: error.bodySnippet }),
    ...(error.data === undefined ? {} : { data: error.data }),
    ...(error.transportPhase === undefined ? {} : { transportPhase: error.transportPhase }),
    ...(error.protocolIssue === undefined ? {} : { protocolIssue: error.protocolIssue })
  });
}

async function writeArtifact(path: string, data: Uint8Array): Promise<void> {
  await writeFile(path, data);
}
