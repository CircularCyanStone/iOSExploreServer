/**
 * Host 侧结构化日志及敏感字段过滤。
 *
 * CLI 与 MCP 都把日志固定写到 stderr，MCP stdout 因而只包含协议帧。logger 接口只接受
 * 标量，默认实现还会按字段名丢弃 payload/token/响应正文等高风险内容；sink 故障永远
 * 不得改变自动化调用结果。
 */
/** Host 日志等级；用于区分正常生命周期、可恢复失败和未分类异常。 */
export type HostLogLevel = "debug" | "info" | "warn" | "error";

/** Host 日志字段只允许标量，避免调用方误传命令 payload 或 artifact。 */
export type HostLogFields = Readonly<Record<string, string | number | boolean | null | undefined>>;

/** 可注入的 Host 日志接口；runtime、workflow 和 adapter 共用这一边界。 */
export interface HostLogger {
  /**
   * 写入一条结构化事件。
   *
   * @param level 日志等级。
   * @param event 稳定事件名。
   * @param fields 不含 payload、用户输入和错误全文的标量摘要。
   */
  emit(level: HostLogLevel, event: string, fields?: HostLogFields): void;
}

/** 单行日志 sink；生产环境默认实现固定写入 stderr。 */
export type HostLogSink = (line: string) => void;

/** HostLogger 的可注入构造参数。 */
export interface HostLoggerOptions {
  /** 单行 JSON sink；默认调用 `process.stderr.write`，不会写 stdout。 */
  readonly sink?: HostLogSink;
  /** 生成 ISO 时间戳的时钟，测试可替换。 */
  readonly now?: () => Date;
}

const BLOCKED_FIELD_NAMES = new Set([
  "args", "authtoken", "base64", "baseurl", "bodysnippet", "data", "image",
  "event", "level", "message", "payload", "request", "response", "timestamp", "token", "userinput"
]);

/**
 * 创建结构化 Host logger。
 *
 * sink 失败会被隔离，日志系统不能改变 action、workflow、MCP 或 CLI 的业务行为。
 *
 * @param options 可注入 sink 与时钟；省略 sink 时固定写 stderr。
 * @returns 可跨 host 各层共享的 logger。
 */
export function createHostLogger(options: HostLoggerOptions = {}): HostLogger {
  const sink = options.sink ?? (line => { process.stderr.write(line); });
  const now = options.now ?? (() => new Date());
  return {
    emit(level, event, fields = {}) {
      const safeFields: Record<string, string | number | boolean | null> = {};
      for (const [key, value] of Object.entries(fields)) {
        // 归一化字段名后过滤，避免用大小写、连字符或下划线绕过敏感字段名单。
        if (BLOCKED_FIELD_NAMES.has(normalizeFieldName(key))) continue;
        // 字符串截断限制日志行大小；非有限数值和 undefined 不进入 JSON。
        if (typeof value === "string") safeFields[key] = value.slice(0, 256);
        else if (typeof value === "number" && Number.isFinite(value)) safeFields[key] = value;
        else if (value === null || typeof value === "boolean") safeFields[key] = value;
      }
      try {
        sink(`${JSON.stringify({ timestamp: now().toISOString(), level, event, ...safeFields })}\n`);
      } catch {
        // 日志 sink 失效不能影响命令链。
      }
    }
  };
}

/** 生产默认 logger；唯一默认 sink 是 stderr。 */
export const defaultHostLogger: HostLogger = createHostLogger();

/** 无输出 logger；低层组件默认使用它，由 CLI/MCP 生产入口显式注入 stderr logger。 */
export const noopHostLogger: HostLogger = Object.freeze({ emit() {} });

function normalizeFieldName(name: string): string {
  return name.replace(/[^a-z0-9]/gi, "").toLowerCase();
}
