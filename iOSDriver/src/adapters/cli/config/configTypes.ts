/** CLI 配置层的公共类型与错误边界。 */

export interface CLIConfigOverrides {
  readonly baseURL?: string;
  readonly requestTimeoutMs?: number;
  readonly configPath?: string;
}

export interface CLIConfig {
  readonly baseURL: string;
  readonly requestTimeoutMs: number;
  readonly authToken?: string;
  readonly configPath: string;
  readonly fileValues: Readonly<Record<string, unknown>>;
}

export class CLIConfigError extends Error {
  readonly code = "invalid_config";

  constructor(message: string) {
    super(message);
    this.name = "CLIConfigError";
  }
}

export interface ConfigFileSystem {
  readonly readFile: (path: string) => Promise<string>;
  readonly mkdir: (path: string) => Promise<void>;
  readonly writeFile: (path: string, data: string) => Promise<void>;
  readonly rename: (from: string, to: string) => Promise<void>;
}
