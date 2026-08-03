/**
 * JSON 能直接编码的标量类型：字符串、数字、布尔、null。
 * 不包含 `undefined`、`bigint`、函数或类实例（这些无法被 JSON.stringify 编码）。
 */
export type JSONPrimitive = string | number | boolean | null;

/**
 * 递归 JSON 值：标量、JSON 对象或 JSON 值数组。
 * 用于描述「一定能被 JSON 序列化」的值。
 */
export type JSONValue = JSONPrimitive | JSONObject | JSONValue[];

/**
 * 供 transport、runtime、workflow 与 adapter 共享的 JSON 对象边界。
 *
 * 属性值使用 `unknown` 是有意为之：来自 App、配置文件或 MCP 的数据必须先在
 * 对应所有者处校验，底层公共类型不提前声称任意外部数据都已满足 `JSONValue`。
 */
export type JSONObject = { [key: string]: unknown };
