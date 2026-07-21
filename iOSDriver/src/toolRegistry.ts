import { IOSExploreStructuredError } from "./errors.js";
import { mapInputSchema } from "./schemaMapper.js";
import { buildActionToolMap, type ToolNameConflict } from "./toolName.js";
import type { CommandMetadata, JSONObject, StructuredError, ToolDefinition } from "./types.js";

export type IOSExploreCaller = {
  call(action: string, data?: JSONObject): Promise<JSONObject>;
};

export type RefreshResult = {
  toolCount: number;
  conflicts: ToolNameConflict[];
  error?: StructuredError;
};

export class ToolRegistry {
  private dynamicTools: ToolDefinition[] = [];
  private lastConflicts: ToolNameConflict[] = [];
  // 上一次 refresh 失败的结构化错误（成功时清空）。
  // 用途：当 dynamic call 走 lazy-refresh 路径时（server.ts:42-45），
  // refresh 又失败导致 dynamicTools 仍 [] → 不能再误报 unknown_tool，
  // 必须把这个错误透传给调用方，避免 Agent 把 "App 不可达" 误判为 "工具不存在"。
  private lastRefreshError: StructuredError | undefined;

  constructor(
    private readonly options: {
      fixedToolNames: Set<string>;
      client: IOSExploreCaller;
    }
  ) {}

  tools(): ToolDefinition[] {
    return [...this.dynamicTools];
  }

  conflicts(): ToolNameConflict[] {
    return [...this.lastConflicts];
  }

  // 返回最近一次 refresh 失败的结构化错误；refresh 成功后为 undefined。
  // server.ts 在 lazy refresh 路径里读它，决定是给 dynamic call 段塞 transport 错误
  // 还是返回 unknown_tool。
  refreshError(): StructuredError | undefined {
    return this.lastRefreshError;
  }

  findByName(name: string): ToolDefinition | undefined {
    return this.dynamicTools.find(tool => tool.name === name);
  }

  async refresh(): Promise<RefreshResult> {
    try {
      const help = await this.options.client.call("help");
      const commands = parseHelpCommands(help);
      const mapped = buildActionToolMap(commands, this.options.fixedToolNames);
      this.dynamicTools = mapped.tools.map(tool => {
        const schema = mapInputSchema(tool.inputSchema);
        let description = `${tool.description}${schema.descriptionSuffix}`;
        // ui.scrollToElement 的 App 端 inputSchema 用字段名 "value"（required）
        // 表示"匹配值: text 片段或 accessibilityIdentifier"，但字段名本身不直观，
        // Agent 容易误以为它是通用"值"字段。在描述尾部追加显式说明，不改 App 端字段名。
        if (tool.action === "ui.scrollToElement") {
          description += `\n\n⚠️ 该工具的 "value" 字段（必填）就是要滚动到的文本片段或 accessibilityIdentifier，不是通用值字段。`;
        }
        // ui.input 的 App 端 inputSchema 现在是批量字段数组；单字段也必须放在 fields[]。
        // 在描述尾部追加显式说明，避免 Agent 仍按旧单字段语义传参。
        if (tool.action === "ui.input") {
          description += `\n\n⚠️ 该工具顶层必须传 fields 数组；每个元素再包含 accessibilityIdentifier/path 二选一与必填 text。单字段输入也必须放入数组。`;
        }
        return {
          ...tool,
          inputSchema: schema.inputSchema,
          description
        };
      });
      this.lastConflicts = mapped.conflicts;
      this.lastRefreshError = undefined;
      return { toolCount: this.dynamicTools.length, conflicts: this.lastConflicts };
    } catch (error) {
      this.dynamicTools = [];
      this.lastConflicts = [];
      const structured =
        error instanceof IOSExploreStructuredError
          ? error.toJSON()
          : { source: "mcp_server" as const, code: "refresh_failed", message: error instanceof Error ? error.message : String(error) };
      this.lastRefreshError = structured;
      return { toolCount: 0, conflicts: [], error: structured };
    }
  }
}

function parseHelpCommands(help: JSONObject): CommandMetadata[] {
  const commands = help.commands;
  if (!Array.isArray(commands)) {
    throw new IOSExploreStructuredError({
      source: "mcp_server",
      code: "invalid_help_response",
      message: "help response did not contain commands array",
      action: "help"
    });
  }

  return commands.map(command => {
    if (!isObject(command)) {
      throw new Error("help command entry must be object");
    }
    const action = command.action;
    const description = command.description;
    const inputSchema = command.inputSchema;
    if (typeof action !== "string" || typeof description !== "string" || !isObject(inputSchema)) {
      throw new Error("help command entry missing action, description, or inputSchema");
    }
    return { action, description, inputSchema };
  });
}

function isObject(value: unknown): value is JSONObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
