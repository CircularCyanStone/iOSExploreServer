/**
 * MCP `tools/list` 的离线目录。
 *
 * 工具名来自显式兼容映射，description/inputSchema 来自 generated contracts。构造过程不
 * 调用 App help，保证客户端即使在设备离线时也能发现完整、稳定的工具集合。
 */
import { DEVICE_ACTION_CONTRACTS } from "../../generated/deviceActionContracts.js";
import { HOST_OPERATION_SPECS } from "../../generated/hostOperationSpecs.js";
import type { JSONObject } from "../../types.js";
import { TOOL_MAPPINGS, type ToolMapping } from "./toolMappings.js";

/** tools/list 暴露的 SDK 无关工具定义。 */
export interface CatalogTool {
  /** 来自显式兼容映射，不随 App help 或 action 注册状态变化。 */
  readonly name: string;
  /** 直接读取 generated contract，避免 adapter 维护第二份说明。 */
  readonly description: string;
  /** 直接读取 generated contract，供 SDK 原样发布到 tools/list。 */
  readonly inputSchema: JSONObject;
}

/** 工具目录项；额外保留执行路由，但不包含 transport 或 SDK 类型。 */
export interface ToolCatalogEntry extends CatalogTool {
  /** 当前工具对应的 generated contract 标识。 */
  readonly mapping: ToolMapping;
}

const DEVICE_CONTRACTS: ReadonlyMap<string, typeof DEVICE_ACTION_CONTRACTS[number]> = new Map(
  DEVICE_ACTION_CONTRACTS.map(contract => [contract.action, contract] as const)
);
const HOST_SPECS: ReadonlyMap<string, typeof HOST_OPERATION_SPECS[number]> = new Map(
  HOST_OPERATION_SPECS.map(spec => [spec.operation, spec] as const)
);

/**
 * 仅由 generated contracts 和显式映射构造固定工具目录。
 *
 * @returns 28 个稳定目录项；合同缺失或名称重复时在启动阶段直接失败。
 */
export function createToolCatalog(): readonly ToolCatalogEntry[] {
  const names = new Set<string>();
  return Object.freeze(TOOL_MAPPINGS.map(mapping => {
    // 重名和缺合同属于构建时编程错误，必须在 MCP server 启动时暴露，不能静默少工具。
    if (names.has(mapping.toolName)) throw new Error(`Duplicate MCP tool mapping: ${mapping.toolName}`);
    names.add(mapping.toolName);

    const contract = mapping.kind === "deviceAction"
      ? DEVICE_CONTRACTS.get(mapping.action)
      : HOST_SPECS.get(mapping.operation);
    if (contract === undefined) {
      const identifier = mapping.kind === "deviceAction" ? mapping.action : mapping.operation;
      throw new Error(`Missing generated contract for MCP tool mapping: ${identifier}`);
    }
    return Object.freeze({
      name: mapping.toolName,
      description: contract.description,
      inputSchema: contract.inputSchema as unknown as JSONObject,
      mapping
    });
  }));
}

/** 进程内固定工具目录；创建过程不会访问 App 或网络。 */
export const TOOL_CATALOG: readonly ToolCatalogEntry[] = createToolCatalog();
