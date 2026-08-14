import type { CapabilityProbe } from "../../../runtime/capabilityProbe.js";
import type { DriverRuntime } from "../../../runtime/driverRuntime.js";
import type { HostLogger } from "../../../runtime/hostLogger.js";
import type { WorkflowRunner } from "../../../workflows/workflowRunner.js";
import type { CLIConfig, ConfigFileSystem } from "../config/configTypes.js";
import type { ArtifactWriter, CLIOutput } from "../output.js";

export type CLICommandName = "init" | "doctor" | "call" | "mcp";

export interface CallCommandOptions {
  readonly action: string;
  readonly data?: string;
  readonly output?: string;
}

export interface CLICommandContext {
  readonly config: CLIConfig;
  readonly output: CLIOutput;
  readonly runtime: Pick<DriverRuntime, "invoke">;
  readonly capabilityProbe: Pick<CapabilityProbe, "doctor" | "invocationPolicy">;
  readonly workflowRunner: Pick<WorkflowRunner, "run">;
  readonly startMCP?: () => Promise<void>;
  readonly readFile?: (path: string) => Promise<string>;
  readonly writeArtifact?: ArtifactWriter;
  readonly fileSystem?: ConfigFileSystem;
  readonly env?: NodeJS.ProcessEnv;
  readonly human?: boolean;
  readonly nodeVersion?: string;
  readonly signal?: AbortSignal;
  readonly logger?: HostLogger;
}

export const EXIT_CODES = Object.freeze({
  success: 0,
  appFailure: 1,
  configError: 2,
  transportFailure: 3
});
