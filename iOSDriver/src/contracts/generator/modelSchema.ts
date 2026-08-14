export type ContractJSONValue =
  | null
  | boolean
  | number
  | string
  | ContractJSONValue[]
  | { [key: string]: ContractJSONValue };

export type JsonSchemaType = "object" | "array" | "string" | "number" | "integer" | "boolean" | "null";

export interface JsonSchema {
  $ref?: string;
  type?: JsonSchemaType | JsonSchemaType[];
  properties?: Record<string, JsonSchema>;
  required?: string[];
  additionalProperties?: boolean | JsonSchema;
  items?: JsonSchema;
  minItems?: number;
  maxItems?: number;
  uniqueItems?: boolean;
  enum?: ContractJSONValue[];
  default?: ContractJSONValue;
  minimum?: number;
  maximum?: number;
  exclusiveMinimum?: number;
  exclusiveMaximum?: number;
  oneOf?: JsonSchema[];
  allOf?: JsonSchema[];
  not?: JsonSchema;
  description?: string;
  "x-iosExplore-constraints"?: Record<string, ContractJSONValue>;
}
