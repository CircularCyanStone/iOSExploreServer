import type { CommandMetadata, ToolDefinition } from "./types.js";

export type ToolNameConflict = {
  toolName: string;
  actions: string[];
};

export type ActionToolMap = {
  tools: ToolDefinition[];
  conflicts: ToolNameConflict[];
};

export function toolNameForAction(action: string): string {
  return action.replace(/[^A-Za-z0-9_]/g, "_");
}

export function buildActionToolMap(commands: CommandMetadata[], fixedToolNames: Set<string>): ActionToolMap {
  const grouped = new Map<string, CommandMetadata[]>();
  for (const command of commands) {
    const name = toolNameForAction(command.action);
    const existing = grouped.get(name) ?? [];
    existing.push(command);
    grouped.set(name, existing);
  }

  const tools: ToolDefinition[] = [];
  const conflicts: ToolNameConflict[] = [];
  for (const [toolName, entries] of grouped) {
    if (entries.length > 1 || fixedToolNames.has(toolName)) {
      conflicts.push({ toolName, actions: entries.map(entry => entry.action) });
      continue;
    }
    const entry = entries[0];
    if (!entry) {
      continue;
    }
    tools.push({
      name: toolName,
      description: `${entry.description}\n\nOriginal iOSExplore action: ${entry.action}`,
      inputSchema: entry.inputSchema,
      action: entry.action
    });
  }

  return { tools, conflicts };
}
