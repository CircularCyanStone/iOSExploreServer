/**
 * CLI 结果的终端投影：把 runtime 的结果渲染成终端输出。
 *
 * 通道纪律（本文件的核心约束）：
 * - 成功业务结果 → stdout（脚本可以安全地把它交给 JSON parser）；
 * - 失败结果与结构化 Host 日志 → stderr；
 * - MCP 模式完全绕过本模块的进程输出（MCP 的 stdout 被协议帧独占，
 *   由 `resultRenderer.ts` 负责投影）。
 *
 * 所有打印函数都接收注入的 `CLIOutput`，测试可收集到数组断言，不污染真实终端。
 */
import { writeFile } from "node:fs/promises";
import type { InvocationResult } from "../../runtime/types.js";
import type { DriverError } from "../../runtime/driverErrors.js";
import type { JSONObject } from "../../types.js";

/**
 * 可注入的输出流（依赖注入插头）：stdout/stderr 两个写入函数。
 * 测试注入「往数组里 push」的实现即可断言输出内容，不污染真实终端。
 */
export interface CLIOutput {
  /** 写入 stdout（业务结果通道）。 */
  readonly stdout: (text: string) => void;
  /** 写入 stderr（错误与日志通道）。 */
  readonly stderr: (text: string) => void;
}

/**
 * image artifact（截图等二进制附件）的落盘边界；测试注入 fake 可验证内容而不写磁盘。
 */
export type ArtifactWriter = (path: string, data: Uint8Array) => Promise<void>;

/**
 * 进程默认输出实现：直接写 `process.stdout/stderr`。
 * MCP 模式不调用这些方法（由 resultRenderer 输出），避免污染 stdout 协议帧。
 */
export const processOutput: CLIOutput = {
  stdout: text => process.stdout.write(text),
  stderr: text => process.stderr.write(text)
};

/**
 * 把任意值以 2 空格缩进的 JSON 格式写入 stdout。
 *
 * @param output 输出流。
 * @param value 要序列化的值（对象/数组等）。
 *   示例：printJSON(out, {code:"ok"}) → stdout 输出 `{\n  "code": "ok"\n}`。
 */
export function printJSON(output: CLIOutput, value: unknown): void {
  output.stdout(`${JSON.stringify(value, null, 2)}\n`);
}

/**
 * 输出一行人类可读文本到 stdout（用于 --human 模式）。
 *
 * @param output 输出流。
 * @param text 文本行，自动补换行。
 */
export function printHuman(output: CLIOutput, text: string): void {
  output.stdout(`${text}\n`);
}

/**
 * 输出错误摘要到 stderr。
 *
 * 只输出 message（不输出完整 payload），避免把用户 data 写进终端/日志；
 * `DriverError` 对象则输出 "code: message" 便于机器识别。
 *
 * @param output 输出流。
 * @param error 错误对象或字符串。
 *   示例：printError(out, new CLIConfigError("x")) → stderr 输出 "x"。
 */
export function printError(output: CLIOutput, error: DriverError | Error | string): void {
  const message = error instanceof Error ? error.message : typeof error === "string" ? error : `${error.code}: ${error.message}`;
  output.stderr(`${message}\n`);
}

/**
 * 调用成功时的 CLI 投影：可选把截图 artifact 落盘，并把结果 JSON 输出到 stdout。
 *
 * 规则：只有用户显式传了 `--output` 且有 image artifact 时才写文件——
 * 绝不隐式落盘（MCP 模式用 image content 投影附件，不走这里）。
 * 写文件后，stdout 的 JSON 里会附带 artifact 元信息（kind/mimeType/bytes/path），
 * 不写文件则元信息不带 path。
 *
 * @param output 输出流。
 * @param result 成功结果（ok: true）。
 * @param artifactOutput `--output` 指定的落盘路径；未传则只输出 JSON。
 * @param write 落盘实现，默认真实 fs。
 *   示例：result 带截图 + artifactOutput="s.png" → 写 s.png，
 *     stdout 输出含 artifact 元信息的 JSON。
 */
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
 * 把失败结果写到 stderr，保留可机器读取的稳定字段（source/code/message 等）。
 *
 * 为什么手动展开字段而不是直接打印 `DriverError`：省略不存在的可选键（输出更干净），
 * 并且 `data` 字段取 runtime 已清理的版本——防止失败 envelope 里的非法/超限 artifact
 * 绕过 decoder 原样泄漏到输出。
 *
 * @param output 输出流（stdout 被临时替换为 stderr，复用 printJSON 的格式）。
 * @param result 失败结果（ok: false）。
 *   示例：transport 错误 → stderr 输出含 source/code/message/baseURL/transportPhase 的 JSON。
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

/**
 * 默认 artifact 落盘实现：直接写文件（`--output` 路径）。
 *
 * @param path 目标路径。
 * @param data 二进制内容。
 */
async function writeArtifact(path: string, data: Uint8Array): Promise<void> {
  await writeFile(path, data);
}
