/** JSON 能直接编码的标量；不包含 `undefined`、`bigint`、函数或类实例。 */
export type JSONPrimitive = string | number | boolean | null;

/** iOSDriver 各层允许交换的递归 JSON 值。 */
export type JSONValue = JSONPrimitive | JSONObject | JSONValue[];

/**
 * 供 transport、runtime、workflow 与 adapter 共享的 JSON 对象边界。
 *
 * 属性值使用 `unknown` 是有意为之：来自 App、配置文件或 MCP 的数据必须先在
 * 对应所有者处校验，底层公共类型不提前声称任意外部数据都已满足 `JSONValue`。
 */
export type JSONObject = { [key: string]: unknown };
