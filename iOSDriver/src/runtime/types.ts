import type { JSONObject } from "../types.js";
import type { DriverError } from "./driverErrors.js";

/** Runtime 产出的二进制或结构化附件，不依赖任何上层 adapter SDK。 */
export interface Artifact {
  readonly kind: "image" | "text" | "json";
  readonly mimeType: string;
  readonly data: Uint8Array;
  readonly metadata: JSONObject;
}

/** action 成功时的稳定 runtime 返回值。 */
export interface InvocationSuccess {
  readonly ok: true;
  readonly data: JSONObject;
  readonly artifacts: readonly Artifact[];
  readonly elapsedMs: number;
  readonly attempts: number;
}

/** action 预期失败时的稳定 runtime 返回值。 */
export interface InvocationFailure {
  readonly ok: false;
  readonly error: DriverError;
  readonly data?: JSONObject;
  readonly artifacts?: readonly Artifact[];
  readonly elapsedMs: number;
  readonly attempts: number;
}

/** DriverRuntime 的统一结果；业务失败通过值返回而不是抛异常。 */
export type InvocationResult = InvocationSuccess | InvocationFailure;
