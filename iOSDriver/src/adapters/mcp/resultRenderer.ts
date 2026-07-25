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
 * @param result SDK 无关的统一调用结果。
 * @param context 当前工具入口，用于保留 call_action 的 unknown_action 探索语义。
 * @returns MCP tool result；image artifact 使用 image content，JSON 元数据使用 text content。
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
 * 把 capability 等普通 host data 渲染为非错误 JSON text。
 *
 * @param data 要返回给 MCP client 的 JSON 对象。
 * @returns 非 tool error 的 MCP 结果。
 */
export function renderJSONData(data: JSONObject): CallToolResult {
  return { content: [{ type: "text", text: JSON.stringify(data) }], isError: false };
}

/**
 * 创建 adapter 自身的稳定错误结果。
 *
 * @param code 稳定错误码。
 * @param message 不包含用户输入的固定错误说明。
 * @returns 标记为 tool error 的 MCP 结果。
 */
export function renderAdapterError(code: string, message: string): CallToolResult {
  return {
    content: [{ type: "text", text: JSON.stringify({ source: "mcp_server", code, message }) }],
    isError: true
  };
}

function isToolError(error: DriverError, context: ResultRenderContext): boolean {
  if (error.source !== "appEnvelope") return true;
  if (context === "callAction" && error.code === "unknown_action") return false;
  return error.code === "invalid_data"
    || error.code === "stale_locator"
    || error.code === "unknown_action";
}
