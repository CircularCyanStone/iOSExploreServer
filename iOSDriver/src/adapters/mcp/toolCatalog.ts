/**
 * MCP `tools/list` 的离线工具目录。
 *
 * 工具名来自显式兼容映射（toolMappings.ts），description/inputSchema 来自 generated
 * contracts。构造过程**不调用 App help**——客户端即使在设备离线时也能发现完整、
 * 稳定的工具集合（工具「被发现」与「被调用」解耦：调用时才发 HTTP）。
 *
 * 构建顺序：TOOL_MAPPINGS → 按 kind 查合同（deviceAction 查 DEVICE_ACTION_CONTRACTS，
 * hostOperation 查 HOST_OPERATION_SPECS）→ 组装 {name, description, inputSchema}。
 */
import { DEVICE_ACTION_CONTRACTS } from "../../generated/deviceActionContracts.js";
import { HOST_OPERATION_SPECS } from "../../generated/hostOperationSpecs.js";
import type { JSONObject } from "../../types.js";
import { TOOL_MAPPINGS, type ToolMapping } from "./toolMappings.js";

/**
 * `tools/list` 暴露的 SDK 无关工具定义（可直接转成 MCP Tool 对象）。
 */
export interface CatalogTool {
  /** 工具名；来自显式兼容映射，不随 App help 或 action 注册状态变化。 */
  readonly name: string;
  /** 工具说明；直接读取 generated contract（adapter 不维护第二份说明）。 */
  readonly description: string;
  /** 入参 JSON Schema；直接读取 generated contract，供 SDK 原样发布到 tools/list。 */
  readonly inputSchema: JSONObject;
}

/**
 * 工具目录项 = 目录展示信息 + 执行路由（mapping 告诉 server 怎么执行这个工具）。
 * 不含 transport 或 SDK 类型，保持 SDK 无关。
 */
export interface ToolCatalogEntry extends CatalogTool {
  /** 当前工具对应的合同标识（deviceAction action 名 / hostOperation 名）。 */
  readonly mapping: ToolMapping;
}

/** action 名 → device action 合同的索引（构建时生成）。 */
const DEVICE_CONTRACTS: ReadonlyMap<string, typeof DEVICE_ACTION_CONTRACTS[number]> = new Map(
  DEVICE_ACTION_CONTRACTS.map(contract => [contract.action, contract] as const)
);
/** operation 名 → host operation 合同的索引（构建时生成）。 */
const HOST_SPECS: ReadonlyMap<string, typeof HOST_OPERATION_SPECS[number]> = new Map(
  HOST_OPERATION_SPECS.map(spec => [spec.operation, spec] as const)
);

/**
 * 仅由 generated contracts 和显式映射构造固定工具目录。
 *
 * 两个 fail-fast：映射重名、映射指向的合同缺失，都在**启动阶段**直接抛错——
 * 这些是构建期编程错误，不能静默少工具。
 *
 * @returns 28 个稳定目录项（冻结数组）。
 * @throws {Error} 重名映射或缺失合同时抛出。
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

/** 进程内固定工具目录（模块加载时构建一次）；创建过程不会访问 App 或网络。 */
export const TOOL_CATALOG: readonly ToolCatalogEntry[] = createToolCatalog();
