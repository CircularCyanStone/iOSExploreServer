// 构建前删除完整 dist，防止 TypeScript 已删除/移动的旧模块继续残留在发布包中。
// 路径相对脚本自身解析，因此从仓库外工作目录触发 npm build 也只会清理 iOSDriver/dist。
import { rm } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
await rm(resolve(scriptDirectory, "../dist"), { recursive: true, force: true });
