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

/** 将失败结果写到 stderr，并返回可机器读取的稳定错误对象。 */
export function printInvocationFailure(output: CLIOutput, result: Extract<InvocationResult, { readonly ok: false }>): void {
  printJSON({ ...output, stdout: output.stderr }, {
    source: result.error.source,
    code: result.error.code,
    message: result.error.message,
    ...(result.error.action === undefined ? {} : { action: result.error.action }),
    ...(result.error.data === undefined ? {} : { data: result.error.data })
  });
}

async function writeArtifact(path: string, data: Uint8Array): Promise<void> {
  await writeFile(path, data);
}
