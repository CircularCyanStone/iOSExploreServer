#!/usr/bin/env python3
"""从 mcp-inspector.mjs 输出里提取每个 JSON-RPC 响应块（含 tools/call），打印出来。

tools/call 特殊处理：把 result.content[0].text 里的 stringified 业务 JSON 反序列化为对象再打印。
其它方法直接打印 result/error。

支持 --keys key1,key2,... 只保留 tools/call 业务 JSON 顶层的指定 key（便于裁剪大响应）。
"""
import json
import re
import sys


def split_blocks(raw: str):
    """按 '=== <header> (id=N) ===' 分块。"""
    pattern = re.compile(r"^=== (.+?) \(id=(\d+)\) ===$", re.MULTILINE)
    matches = list(pattern.finditer(raw))
    for i, m in enumerate(matches):
        start = m.end()
        if start < len(raw) and raw[start] == "\n":
            start += 1
        end = matches[i + 1].start() if i + 1 < len(matches) else len(raw)
        # 末尾的 '\n=== done ===\n' 不属于最后一个 tools/call 块
        done_marker = raw.find("=== done ===", start)
        if done_marker != -1 and (i + 1 >= len(matches)):
            end = done_marker
        body = raw[start:end].strip()
        yield m.group(1), m.group(2), body


def main():
    keys_to_keep = None
    args = sys.argv[1:]
    if args and args[0] == "--keys":
        keys_to_keep = [k.strip() for k in args[1].split(",") if k.strip()]
        args = args[2:]

    raw = sys.stdin.read()
    for header, mid, body in split_blocks(raw):
        print(f"\n=========== {header} (id={mid}) ===========")
        if not body:
            print("[empty]")
            continue
        try:
            msg = json.loads(body)
        except Exception as e:
            print(f"[parse error: {e}]")
            print(body[:500])
            continue
        result = msg.get("result") or msg.get("error")
        if result is None:
            print("[no result/error]")
            continue
        if "result" in msg:
            content = result.get("content") if isinstance(result, dict) else None
            if (isinstance(content, list) and content
                    and isinstance(content[0], dict) and "text" in content[0]):
                text = content[0]["text"]
                try:
                    inner = json.loads(text)
                    if keys_to_keep:
                        pruned = {k: inner.get(k) for k in keys_to_keep if k in inner}
                        pruned["__isError"] = result.get("isError")
                        print(json.dumps(pruned, indent=2, ensure_ascii=False))
                    else:
                        inner_with_flag = dict(inner)
                        inner_with_flag["__isError"] = result.get("isError")
                        print(json.dumps(inner_with_flag, indent=2, ensure_ascii=False))
                except Exception as e:
                    print(f"[content text parse error: {e}]")
                    print(text[:3000])
                continue
        print(json.dumps(result, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
