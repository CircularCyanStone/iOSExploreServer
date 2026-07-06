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
        return {
          ...tool,
          inputSchema: schema.inputSchema,
          description: `${tool.description}${schema.descriptionSuffix}`
        };
      });
      this.lastConflicts = mapped.conflicts;
      return { toolCount: this.dynamicTools.length, conflicts: this.lastConflicts };
    } catch (error) {
      this.dynamicTools = [];
      this.lastConflicts = [];
      const structured =
        error instanceof IOSExploreStructuredError
          ? error.toJSON()
          : { source: "mcp_server" as const, code: "refresh_failed", message: error instanceof Error ? error.message : String(error) };
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
