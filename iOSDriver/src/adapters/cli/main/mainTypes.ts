import type { CLIApplicationDependencies } from "../application/applicationTypes.js";

export type CLIMainDependencies = Omit<CLIApplicationDependencies, "cliEntryPath"> & {
  readonly cliEntryPath?: string;
};
