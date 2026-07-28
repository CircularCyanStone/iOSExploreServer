import { CONTRACT_ERROR_INDEX } from "../generated/contractBundle.js";
import type { DriverError } from "../runtime/driverErrors.js";

interface ContractErrorMetadata {
  readonly source: string;
  readonly terminal: boolean;
}

const WAIT_CONTINUE_CODES = new Set(["wait_timeout"]);

/**
 * Decide whether a failed wait step is still a useful process signal.
 *
 * Only `wait_timeout` is intentionally non-terminal for inspect-following
 * workflows. Other non-terminal metadata such as transport retries is not a UI
 * observation signal and should short-circuit the workflow.
 */
export function shouldContinueAfterWaitFailure(error: DriverError): boolean {
  if (!WAIT_CONTINUE_CODES.has(error.code)) return false;
  const metadata = (CONTRACT_ERROR_INDEX as Record<string, ContractErrorMetadata | undefined>)[error.code];
  return metadata?.source === "appEnvelope" && metadata.terminal === false;
}
