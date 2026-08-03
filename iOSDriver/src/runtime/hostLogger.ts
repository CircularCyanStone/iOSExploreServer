/**
 * Host 侧结构化日志及敏感字段过滤。
 *
 * 通道纪律：CLI 与 MCP 都把日志固定写到 stderr——MCP 的 stdout 被协议帧独占，
 * 任何普通日志混入都会破坏 JSON-RPC 帧解析。
 *
 * 安全设计：
 * 1. logger 接口只接受**标量**字段（禁止传对象/payload）；
 * 2. 默认实现按字段名丢弃 payload/token/响应正文等高风险内容（大小写/连字符/下划线
 *    变体也会被归一化后识别，防止绕过）；
 * 3. sink 故障（写 stderr 失败）会被静默吞掉——日志系统永远不得改变自动化调用结果。
 */
/** Host 日志等级：debug=诊断、info=正常生命周期、warn=可恢复失败、error=未分类异常。 */
export type HostLogLevel = "debug" | "info" | "warn" | "error";

/** Host 日志字段只允许标量，从类型上阻止调用方误传命令 payload 或 artifact。 */
export type HostLogFields = Readonly<Record<string, string | number | boolean | null | undefined>>;

/**
 * 可注入的 Host 日志接口；runtime、workflow 和 adapter 共用这一边界（测试可注入 noop）。
 */
export interface HostLogger {
  /**
   * 写入一条结构化事件（最终序列化为单行 JSON + 换行）。
   *
   * @param level 日志等级。
   * @param event 稳定事件名（如 "runtime.invoke.start"），日志消费方据此筛选。
   * @param fields 不含 payload、用户输入和错误全文的标量摘要。
   *   示例：emit("info", "cli.command.start", { command: "call" })
   *     → {"timestamp":…,"level":"info","event":"cli.command.start","command":"call"}
   */
  emit(level: HostLogLevel, event: string, fields?: HostLogFields): void;
}

/** 单行日志 sink（写入点）；生产环境默认实现固定写 stderr。 */
export type HostLogSink = (line: string) => void;

/** HostLogger 的可注入构造参数。 */
export interface HostLoggerOptions {
  /** 单行 JSON sink；默认 `process.stderr.write`（绝不写 stdout）。 */
  readonly sink?: HostLogSink;
  /** 生成 ISO 时间戳的时钟；测试可替换为固定时间。 */
  readonly now?: () => Date;
}

/** 命中即丢弃的敏感字段名单（大小写/分隔符不敏感，见 normalizeFieldName）。 */
const BLOCKED_FIELD_NAMES = new Set([
  "args", "authtoken", "base64", "baseurl", "bodysnippet", "data", "image",
  "event", "level", "message", "payload", "request", "response", "timestamp", "token", "userinput"
]);

/**
 * 创建结构化 Host logger（默认实现）。
 *
 * 安全过滤三步：字段名归一化后对照黑名单丢弃（防绕过）；字符串截断到 256 字符
 * （限制日志行大小）；非有限数值与 undefined 不进入 JSON。sink 抛错被隔离——
 * 日志系统不能改变 action/workflow/MCP/CLI 的业务行为。
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

/** 生产默认 logger：唯一默认 sink 是 stderr。 */
export const defaultHostLogger: HostLogger = createHostLogger();

/** 无输出 logger：低层组件默认使用它，由 CLI/MCP 生产入口显式注入 stderr logger。 */
export const noopHostLogger: HostLogger = Object.freeze({ emit() {} });

/**
 * 归一化字段名：去掉所有非字母数字字符并转小写。
 * 使 "baseURL"、"base-url"、"base_url" 命中同一个黑名单条目。
 *
 * @param name 原始字段名。
 * @returns 归一化后的键名。
 */
function normalizeFieldName(name: string): string {
  return name.replace(/[^a-z0-9]/gi, "").toLowerCase();
}
