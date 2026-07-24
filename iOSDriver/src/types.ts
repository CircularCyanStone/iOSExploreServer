export type JSONPrimitive = string | number | boolean | null;
export type JSONValue = JSONPrimitive | JSONObject | JSONValue[];
/** 供传输、runtime、workflow 与 adapter 共享的 JSON 对象边界。 */
export type JSONObject = { [key: string]: unknown };
