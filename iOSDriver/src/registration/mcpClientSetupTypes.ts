export type MCPClientName = "codex" | "claude" | "trae";
export type MCPRegistrationScope = "local" | "user" | "project";

export interface MCPLaunchCommand {
  readonly command: string;
  readonly args: readonly string[];
}

export interface MCPClientSetupInput {
  readonly client: MCPClientName;
  readonly scope?: MCPRegistrationScope;
  readonly dryRun?: boolean;
  readonly force?: boolean;
  readonly cwd: string;
  readonly homeDir: string;
  readonly env: NodeJS.ProcessEnv;
  readonly launch: MCPLaunchCommand;
}

export interface MCPClientSetupResult {
  readonly client: MCPClientName;
  readonly scope: MCPRegistrationScope;
  readonly status: "created" | "updated" | "unchanged" | "planned";
  readonly operation: "create" | "update" | "none";
  readonly registrationName: "iOSDriver";
  readonly manager: "claude-cli" | "codex-cli" | "json-file";
  readonly configPath?: string;
  readonly launch: MCPLaunchCommand;
}

export interface MCPSetupFileSystem {
  readonly readFile: (path: string) => Promise<string>;
  readonly mkdir: (path: string) => Promise<void>;
  readonly writeFile: (path: string, data: string) => Promise<void>;
  readonly rename: (from: string, to: string) => Promise<void>;
}

export interface MCPSetupCommandResult {
  readonly exitCode: number;
  readonly stdout: string;
  readonly stderr: string;
}

export type MCPSetupCommandRunner = (
  command: string,
  args: readonly string[],
  options: { readonly cwd: string; readonly env: NodeJS.ProcessEnv }
) => Promise<MCPSetupCommandResult>;

export interface MCPClientSetupDependencies {
  /** 省略时使用真实 fs；仅 TRAE JSON 路径使用。 */
  readonly fileSystem?: MCPSetupFileSystem;
  /** 省略时使用真实 spawn；Codex 和 Claude CLI 路径使用。 */
  readonly runCommand?: MCPSetupCommandRunner;
}

export class MCPClientSetupError extends Error {
  readonly code = "mcp_setup_failed";

  constructor(message: string) {
    super(message);
    this.name = "MCPClientSetupError";
  }
}
