import type { DeviceActionContract, ErrorContract, HostOperationSpec } from "./modelContracts.js";
import type { JsonSchema } from "./modelSchema.js";

export interface RawDriverContractBundle {
  protocolVersion: string;
  contractVersion: string;
  generatorVersion: string;
  files: string[];
  deviceActions: object[];
  hostOperations: object[];
  errors: object;
  definitions: Record<string, object>;
  sourceFiles: ReadonlyMap<object, string>;
}

export interface DriverContractBundle {
  protocolVersion: string;
  contractVersion: string;
  generatorVersion: string;
  files: string[];
  deviceActions: DeviceActionContract[];
  hostOperations: HostOperationSpec[];
  errors: Record<string, ErrorContract>;
  definitions: Record<string, JsonSchema>;
  sourceFiles: ReadonlyMap<object, string>;
}
