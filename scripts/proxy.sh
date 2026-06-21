#!/usr/bin/env bash
# 一键起 iproxy 转发到 iOSExploreServer（前台运行，Ctrl-C 停止）。
set -euo pipefail

PORT="${PORT:-38321}"

if ! command -v iproxy >/dev/null 2>&1; then
  echo "未找到 iproxy，正在安装 libimobiledevice..." >&2
  brew install libimobiledevice
fi

echo "转发 Mac :${PORT} <-> 设备 :${PORT}（Ctrl-C 停止）"
exec iproxy "${PORT}" "${PORT}"
