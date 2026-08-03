/** 合同文件允许出现的 JSON 值；生成器拒绝 `undefined`、非有限数和运行时对象。 */
export type ContractJSONValue =
  | null
  | boolean
  | number
  | string
  | ContractJSONValue[]
  | { [key: string]: ContractJSONValue };

/** Swift 与 TypeScript 生成器共同支持的 JSON Schema 类型子集。 */
export type JsonSchemaType = "object" | "array" | "string" | "number" | "integer" | "boolean" | "null";

/**
 * 两端生成器共同实现的受控 JSON Schema 方言。
 *
 * 这里不是通用 JSON Schema 类型。新增 keyword 必须同时更新 bundle validator、host 输入
 * validator 与 Swift emitter；否则合同可能在文档中成立、运行时却无法执行。
 */
export interface JsonSchema {
  /** 仅允许指向 `contracts/definitions/*.json` 的本地文件引用。 */
  $ref?: string;
  /** 多类型主要用于表达 nullable，例如 `["string", "null"]`。 */
  type?: JsonSchemaType | JsonSchemaType[];
  /** 插入顺序属于 Swift `propertyOrder` 元数据，canonical hash 会保留该顺序。 */
  properties?: Record<string, JsonSchema>;
  /** 每个名字必须同时存在于 `properties`。 */
  required?: string[];
  /** 可控制未知字段或为未知字段提供统一 schema。 */
  additionalProperties?: boolean | JsonSchema;
  /** 数组元素合同；数组约束出现时 schema type 必须包含 array。 */
  items?: JsonSchema;
  /** 数组最少元素数；出现时 schema type 必须包含 array。 */
  minItems?: number;
  /** 数组最多元素数；出现时 schema type 必须包含 array。 */
  maxItems?: number;
  /** host validator 使用结构化 JSON 相等判断唯一性。 */
  uniqueItems?: boolean;
  /** 非空且每个值必须与声明 type 相容。 */
  enum?: ContractJSONValue[];
  /** 生成器只记录默认值，不在 host validator 中自动补值。 */
  default?: ContractJSONValue;
  /** 数值下限（含）；出现时 schema type 必须为 number/integer。 */
  minimum?: number;
  /** 数值上限（含）；出现时 schema type 必须为 number/integer。 */
  maximum?: number;
  /** 数值下限（不含）。 */
  exclusiveMinimum?: number;
  /** 数值上限（不含）。 */
  exclusiveMaximum?: number;
  /** 仅 host schema runtime 支持；device action Swift emitter 会显式拒绝复合 schema。 */
  oneOf?: JsonSchema[];
  allOf?: JsonSchema[];
  not?: JsonSchema;
  /** 同时进入生成文档和 MCP tools/list schema。 */
  description?: string;
  /** 项目扩展：跨字段 exactlyOneOf/mutuallyExclusive 以及说明性 note。 */
  "x-iosExplore-constraints"?: Record<string, ContractJSONValue>;
}

/** App action 的注册所有者；host 据此判断 UIKit/Diagnostics 模块是否完整注册。 */
export type ContractProvider = "core" | "uikit" | "diagnostics" | "extension";

/** action 的发布稳定度，进入生成元数据但不改变 wire 路由。 */
export type ContractStability = "public" | "experimental" | "internal";

/** adapter 选择结果投影方式所需的最小声明。 */
export interface ResultSpec {
  /** `image` 会触发 artifact 处理；json/text 不携带隐式二进制。 */
  kind: "json" | "image" | "text";
}

/** device action 的重放安全级别；只有前两类允许在有限传输阶段自动重试。 */
export type ContractIdempotency = "readOnly" | "idempotent" | "sideEffecting";

/** host runtime 的请求超时策略；wait 类会把业务 timeout 纳入 transport 预算。 */
export type ContractTimeoutClass = "standard" | "wait" | "screenshot";

/** 单个 App action 的 canonical wire 合同。 */
export interface DeviceActionContract {
  /** 与 host operation 区分的文件判别字段。 */
  kind: "deviceAction";
  /** 固定 `POST /` 请求体中的路由键，全 bundle 唯一。 */
  action: string;
  /** 面向工具调用者的用途说明，由 MCP 和生成文档直接消费。 */
  description: string;
  /** 用于生成 Swift provider 文件和能力注册报告。 */
  provider: ContractProvider;
  stability: ContractStability;
  /** App typed input factory 和 MCP schema 的共同事实源。 */
  inputSchema: JsonSchema;
  result: ResultSpec;
  /** 每个 code 必须在全局 `errors.json` 中声明。 */
  errors: string[];
  /** 决定 connect/reset 失败时能否自动重放。 */
  idempotency: ContractIdempotency;
  /** 决定 runtime 如何从业务等待预算推导 transport timeout。 */
  timeoutClass: ContractTimeoutClass;
}

/** 只在 Mac 侧执行的 operation/workflow 合同，不会注册为 App action。 */
export interface HostOperationSpec {
  /** 与 device action 区分的文件判别字段。 */
  kind: "hostOperation";
  /** Mac 侧路由名，全 bundle 唯一且不发送给 App。 */
  operation: string;
  /** 直接进入 MCP 工具目录的用途说明。 */
  description: string;
  /** 在 host 执行前由 TypeScript validator 校验。 */
  inputSchema: JsonSchema;
  /** workflow 结果交给 adapter 的投影类型。 */
  result: ResultSpec;
  /** 每个 code 必须复用全局错误索引。 */
  errors: string[];
}

/** 跨 action 共享错误码的机器语义；workflow 会读取 terminal/source 决定是否继续。 */
export interface ErrorContract {
  /** 决定错误由 App envelope 还是某个 host 层产生。 */
  source: "appEnvelope" | "transport" | "http" | "protocol" | "contract" | "config" | "workflow" | "artifact";
  /** 面向显式调用方的重试建议，不等同于 runtime 一定自动重试。 */
  retryable: boolean;
  /** workflow 判断错误能否作为中间过程状态继续观察。 */
  terminal: boolean;
}

/** 未经完整契约校验的 JSON 对象。 */
export type RawContractDocument = Record<string, unknown>;

/**
 * 加载器读取、等待完整校验的原始 bundle。
 * 字段只证明 JSON 外形足以聚合，不代表 action/schema/error 已满足合同约束。
 */
export interface RawDriverContractBundle {
  protocolVersion: string;
  contractVersion: string;
  generatorVersion: string;
  /** manifest 顺序，用于确认每个源文件恰好加载一次。 */
  files: string[];
  deviceActions: object[];
  hostOperations: object[];
  errors: object;
  definitions: Record<string, object>;
  /** 以对象身份关联到相对源文件，错误报告不泄露本机绝对路径。 */
  sourceFiles: ReadonlyMap<object, string>;
}

/** 已通过完整合同校验，可安全交给所有 emitter 的 typed bundle。 */
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
