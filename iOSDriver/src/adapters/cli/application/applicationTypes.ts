import type { MCPClientSetupInput, MCPClientSetupResult } from "../../../registration/mcpClientSetup.js";
import type { HostLogger } from "../../../runtime/hostLogger.js";
import type { CLIOutput } from "../output.js";

export interface CLIApplicationDependencies {
  readonly cliEntryPath: string;
  readonly output?: CLIOutput;
  readonly env?: NodeJS.ProcessEnv;
  readonly nodeVersion?: string;
  readonly logger?: HostLogger;
  readonly cwd?: string;
  readonly homeDir?: string;
  readonly nodePath?: string;
  readonly setupMCPClient?: (input: MCPClientSetupInput) => Promise<MCPClientSetupResult>;
}
