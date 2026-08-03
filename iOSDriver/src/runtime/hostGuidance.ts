/**
 * 将稳定错误补充为面向调用者（AI 或开发者）的下一步操作指引。
 *
 * 设计要点：指引按 `source` 和 `code` 生成，**不检查 message 文本**——App 调整文案
 * 不会改变 host 决策；只有已知的 App envelope code 才给 UI 级建议，未知 host 错误
 * 保持原样，避免误导调用者。本模块不依赖 CLI 或 MCP SDK，同一建议可被多个 adapter
 * 一致投影（MCP 的 failurePayload、CLI 的错误输出）。
 */
import type { DriverError } from "./driverErrors.js";
import type { JSONObject } from "../types.js";

/** 影响动态 action 与静态 action 指引差异的宿主调用入口。 */
export type HostGuidanceContext = "deviceAction" | "callAction" | "workflow";

/**
 * 生成 SDK 无关的失败负载：错误本体 + 保留的失败数据 + 下一步操作指引。
 *
 * @param error runtime 或 workflow 的稳定错误。
 * @param data 调用结果中优先保留的失败数据（优先于 error.data）。
 * @param context 宿主调用入口（影响 unknown_action 等指引的措辞）。
 * @returns 可直接被 MCP、CLI 或其他 adapter 投影的 JSON 对象：
 *   { …error 字段, data?, nextSteps? }。
 *   示例：transport 错误 → 含 3 条连接恢复指引的 nextSteps。
 */
export function failurePayload(
  error: DriverError,
  data: JSONObject | undefined,
  context: HostGuidanceContext
): JSONObject {
  const payloadData = data ?? error.data;
  const nextSteps = nextStepsFor(error, context);
  return {
    ...error,
    ...(payloadData === undefined ? {} : { data: payloadData }),
    ...(nextSteps === undefined ? {} : { nextSteps })
  };
}

/**
 * 按错误 source/code 生成下一步操作指引。
 *
 * 规则：transport 故障优先恢复连接（endpoint 未恢复前建议重试业务 action 没意义）；
 * workflow_timeout 提示检查 UI 进展；**只有已知的 appEnvelope code** 才给具体 UI 建议，
 * 其余返回 undefined（不臆造指引）。
 *
 * @param error 稳定错误。
 * @param context 宿主调用入口（unknown_action 区分「检查注册 action」与「检查模块」）。
 * @returns 中文指引列表；没有合适建议时 undefined。
 */
function nextStepsFor(
  error: DriverError,
  context: HostGuidanceContext
): readonly string[] | undefined {
  // transport 故障优先恢复连接；在 endpoint 未恢复前建议重试业务 action 没有意义。
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
  // 只有已知 App envelope code 才给 UI 级建议，未知 host 错误保持原样，避免误导调用者。
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
