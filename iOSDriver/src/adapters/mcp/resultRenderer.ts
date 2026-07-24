import type { CallToolResult } from "@modelcontextprotocol/sdk/types.js";
import type { DriverError } from "../../runtime/driverErrors.js";
import type { InvocationResult } from "../../runtime/types.js";
import type { JSONObject } from "../../types.js";

/** 影响 App envelope 失败是否升级为 MCP tool error 的调用入口。 */
export type ResultRenderContext = "deviceAction" | "callAction" | "workflow";

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
  if (result.ok) {
    return {
      content: [
        ...result.artifacts
          .filter(artifact => artifact.kind === "image")
          .map(artifact => ({
            type: "image" as const,
            data: Buffer.from(artifact.data).toString("base64"),
            mimeType: artifact.mimeType
          })),
        { type: "text", text: JSON.stringify(result.data) }
      ],
      isError: false
    };
  }

  const data = result.data ?? result.error.data;
  const nextSteps = nextStepsFor(result.error, context);
  const payload: JSONObject = {
    ...result.error,
    ...(data === undefined ? {} : { data }),
    ...(nextSteps === undefined ? {} : { nextSteps })
  };
  return {
    content: [{ type: "text", text: JSON.stringify(payload) }],
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

function nextStepsFor(error: DriverError, context: ResultRenderContext): readonly string[] | undefined {
  if (error.source === "transport") {
    return [
      "确认目标 App 正在运行并已启动 iOSExplore HTTP server。",
      "确认当前 baseURL 可达；真机场景同时检查 USB 端口转发。",
      "连接恢复后重新执行 health_check，再重试原工具。"
    ];
  }
  if (error.source === "workflow" && error.code === "workflow_timeout") {
    return [
      "重新检查当前 UI，确认 workflow 超时时页面停留在哪个阶段。",
      "仅在 UI 仍持续进展时扩大业务 timeout，再重试 workflow。"
    ];
  }
  if (error.source !== "appEnvelope") return undefined;
  switch (error.code) {
    case "invalid_data":
      return ["对照当前工具 inputSchema 修正字段、必填项、互斥项和取值范围。"];
    case "unknown_action":
      return context === "callAction"
        ? ["运行 check_capabilities 确认 App 当前注册的 action。"]
        : ["运行 check_capabilities，并确认宿主已注册对应 UIKit 或 Diagnostics 模块。"];
    case "stale_locator":
      return ["重新调用 ui_inspect 获取 viewSnapshotID，并从最新快照重新选择目标。"];
    case "target_not_found":
      return ["重新调用 ui_inspect；若目标在屏幕外，先滚动再获取新快照。"];
    case "not_actionable":
      return ["从最新 ui_inspect 中选择 availableActions 匹配当前操作的节点。"];
    case "unsupported_target":
      return ["重新检查目标类型，并改用与 availableActions 对应的专用工具。"];
    case "wait_timeout":
      return ["重新检查当前 UI；仅在界面仍持续进展时扩大业务 timeout。"];
    case "response_too_large":
      return ["降低 inspect 深度或目标数量，或缩小截图尺寸后重试。"];
    case "stale_cursor":
      return ["重新调用 app_logs_mark，并使用新 cursor 增量读取日志。"];
    case "alert_unavailable":
      return ["先确认当前 alert 已出现，再调用 ui_alert_respond。"];
    default:
      return undefined;
  }
}
