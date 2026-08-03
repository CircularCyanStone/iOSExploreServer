/**
 * 把 SDK 无关的 runtime 结果投影为 MCP content（`CallToolResult`）。
 *
 * 投影规则：
 * - image artifact → MCP `image` content（base64 编码，客户端可直接展示图片）；
 * - 业务数据 → MCP `text` content（JSON 字符串）；
 * - App envelope 失败是否标记 `isError` 取决于调用入口：动态 `call_action` 的
 *   unknown_action 是可探索结果（AI 可以换 action 再试），而固定工具的同一错误表示
 *   客户端调用了当前 App 未注册的能力——两种语义不同，isError 随之不同。
 */
import type { CallToolResult } from "@modelcontextprotocol/sdk/types.js";
import type { DriverError } from "../../runtime/driverErrors.js";
import { failurePayload, type HostGuidanceContext } from "../../runtime/hostGuidance.js";
import type { InvocationResult } from "../../runtime/types.js";
import type { JSONObject } from "../../types.js";

/** 影响 App envelope 失败是否升级为 MCP tool error 的调用入口。 */
export type ResultRenderContext = HostGuidanceContext;

/**
 * 把 runtime/workflow 结果渲染为 MCP content。
 *
 * @param result SDK 无关的统一调用结果（成功或失败）。
 * @param context 当前工具入口（"deviceAction"/"callAction"/"workflow"），
 *   用于保留 call_action 的 unknown_action 探索语义。
 * @returns MCP tool result：image artifact 使用 image content，JSON 元数据使用
 *   text content，失败按语义设置 isError。
 */
export function renderInvocationResult(
  result: InvocationResult,
  context: ResultRenderContext = "deviceAction"
): CallToolResult {
  const imageContent = (result.ok ? result.artifacts : result.artifacts ?? [])
    .filter(artifact => artifact.kind === "image")
    .map(artifact => ({
      type: "image" as const,
      data: Buffer.from(artifact.data).toString("base64"),
      mimeType: artifact.mimeType
    }));

  if (result.ok) {
    return {
      content: [
        ...imageContent,
        { type: "text", text: JSON.stringify(result.data) }
      ],
      isError: false
    };
  }

  return {
    content: [
      ...imageContent,
      { type: "text", text: JSON.stringify(failurePayload(result.error, result.data, context)) }
    ],
    isError: isToolError(result.error, context)
  };
}

/**
 * 把 capability 等普通 host data 渲染为非错误 JSON text（health/capabilities 工具用）。
 *
 * @param data 要返回给 MCP client 的 JSON 对象。
 * @returns 非 tool error 的 MCP 结果。
 */
export function renderJSONData(data: JSONObject): CallToolResult {
  return { content: [{ type: "text", text: JSON.stringify(data) }], isError: false };
}

/**
 * 创建 adapter 自身的稳定错误结果（未知工具、输入非法、意外异常等）。
 *
 * @param code 稳定错误码（如 "unknown_tool"）。
 * @param message 固定错误说明（**不含用户输入**，防泄漏）。
 * @returns 标记为 tool error 的 MCP 结果。
 */
export function renderAdapterError(code: string, message: string): CallToolResult {
  return {
    content: [{ type: "text", text: JSON.stringify({ source: "mcp_server", code, message }) }],
    isError: true
  };
}

/**
 * 区分「工具执行失败」与「工具返回了可供模型继续判断的业务状态」。
 *
 * 规则：transport/protocol/workflow 等 host 失败一律为 tool error（基础设施问题）；
 * App 的普通业务失败默认**作为数据返回**（让 AI 继续判断），仅参数、定位器和能力
 * 注册这类「需要调用方改正」的错误升级为 error——且 `call_action` 的 unknown_action
 * 例外地不标记（它是可探索结果，AI 可以换一个 action 再试）。
 *
 * @param error 稳定错误。
 * @param context 调用入口。
 * @returns true=标记为 MCP tool error。
 */
function isToolError(error: DriverError, context: ResultRenderContext): boolean {
  if (error.source !== "appEnvelope") return true;
  if (context === "callAction" && error.code === "unknown_action") return false;
  return error.code === "invalid_data"
    || error.code === "stale_locator"
    || error.code === "unknown_action";
}
