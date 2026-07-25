import { createHostLogger } from "../../src/runtime/hostLogger.js";

/** 创建只记录结构化事件的测试 logger。 */
export function hostLogRecorder() {
  const lines: string[] = [];
  const logger = createHostLogger({
    sink: line => lines.push(line),
    now: () => new Date("2026-07-25T00:00:00.000Z")
  });
  return {
    logger,
    lines,
    entries: () => lines.map(line => JSON.parse(line) as Record<string, unknown>)
  };
}
