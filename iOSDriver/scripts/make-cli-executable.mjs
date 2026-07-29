// TypeScript 会保留 shebang，但不会可靠保留源文件执行位；构建末尾显式设为 0755，
// 让 package.json 的 bin 在 npm install/link 后可由 shell 直接作为 iosdriver 启动。
import { chmod } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
await chmod(resolve(scriptDirectory, "../dist/adapters/cli/main.js"), 0o755);
