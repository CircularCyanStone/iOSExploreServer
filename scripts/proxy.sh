#!/usr/bin/env bash
# iproxy 转发管理脚本 - 支持前台/后台运行、状态检查、停止
set -euo pipefail

PORT="${PORT:-38321}"
PIDFILE="${TMPDIR:-/tmp}/iproxy-${PORT}.pid"
LOGFILE="${TMPDIR:-/tmp}/iproxy-${PORT}.log"

show_help() {
  cat <<EOF
用法: $0 [选项]

选项:
  (无参数)          前台运行 iproxy，Ctrl-C 停止
  --daemon, -d      后台运行 iproxy，PID 写入 ${PIDFILE}
  --status, -s      检查 iproxy 运行状态
  --stop            停止后台运行的 iproxy
  --help, -h        显示此帮助

环境变量:
  PORT              转发端口（默认: 38321）

示例:
  $0                # 前台运行
  $0 --daemon       # 后台运行
  $0 --status       # 检查状态
  $0 --stop         # 停止后台进程
EOF
}

# 兜底：直接 kill 占用端口的 SPMExampl 残留进程
# 用于 simctl terminate 够不着的场景（模拟器已关闭但 Mac 进程未退出）
kill_residual_process() {
  local pids pid
  pids=$(lsof -iTCP:"${PORT}" -sTCP:LISTEN -n -P 2>/dev/null | grep "SPMExampl" | awk '{print $2}' || true)
  for pid in $pids; do
    echo "   → 终止残留进程 PID ${pid}" >&2
    kill "$pid" 2>/dev/null || true
  done
}

# 清理模拟器 SPMExample 残留：terminate booted 模拟器中的 App，必要时兜底 kill 进程
# 返回 0 = 端口已释放；1 = 仍被占用
clean_simulator_residual() {
  local booted_udids udid i
  booted_udids=$(xcrun simctl list devices 2>/dev/null | grep "(Booted)" | sed -E 's/.*\(([0-9A-Fa-f-]{36})\).*/\1/' || true)

  if [[ -n "$booted_udids" ]]; then
    while IFS= read -r udid; do
      [[ -z "$udid" ]] && continue
      echo "   → simctl terminate ${udid}" >&2
      xcrun simctl terminate "$udid" com.coo.SPMExample 2>/dev/null || true
    done <<< "$booted_udids"
  fi

  # 轮询等待端口释放（最多约 4.5s）
  for i in $(seq 1 15); do
    if ! lsof -iTCP:"${PORT}" -sTCP:LISTEN -n -P >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.3
  done

  # simctl terminate 未生效（模拟器已关但进程残留），兜底 kill 后再等
  echo "   → simctl 未释放端口，兜底 kill 残留进程" >&2
  kill_residual_process
  for i in $(seq 1 10); do
    if ! lsof -iTCP:"${PORT}" -sTCP:LISTEN -n -P >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.3
  done
  return 1
}

# 确保端口可用于启动 iproxy
# 返回 0 = 空闲可启动；非 0 = 不可启动（iproxy 已运行 / 清理失败 / 未知占用）
ensure_port_free() {
  local listeners
  listeners=$(lsof -iTCP:"${PORT}" -sTCP:LISTEN -n -P 2>/dev/null | tail -n +2 || true)

  if [[ -z "$listeners" ]]; then
    echo "✅ 端口 ${PORT} 空闲" >&2
    return 0
  fi

  if echo "$listeners" | grep -q "iproxy"; then
    echo "ℹ️  iproxy 已在运行 (端口 ${PORT})，如需重启请先执行: $0 --stop" >&2
    return 1
  fi

  if echo "$listeners" | grep -q "SPMExampl"; then
    echo "⚠️  检测到模拟器 SPMExample 残留占用 ${PORT}，自动清理..." >&2
    if clean_simulator_residual; then
      echo "✅ 残留已清理，端口已释放" >&2
      return 0
    else
      echo "❌ 自动清理后端口仍被占用" >&2
      echo "   请手动处理: xcrun simctl terminate <UDID> com.coo.SPMExample" >&2
      return 1
    fi
  fi

  echo "❌ 端口 ${PORT} 被未知进程占用:" >&2
  echo "$listeners" | awk '{print "   " $1 " (PID " $2 ")"}' >&2
  return 1
}

check_iproxy_installed() {
  if ! command -v iproxy >/dev/null 2>&1; then
    echo "❌ 未找到 iproxy，正在安装 libimobiledevice..." >&2
    brew install libimobiledevice
  fi
}

get_device_udid() {
  # 尝试获取第一个 USB 连接的设备 UDID
  local udid
  udid=$(idevice_id -l 2>/dev/null | head -1 || true)

  if [[ -z "$udid" ]]; then
    echo "⚠️  未检测到 USB 连接的设备" >&2
    echo "  → 请确保设备已连接并信任此电脑" >&2
    return 1
  fi

  echo "$udid"
}

show_status() {
  echo "📊 iproxy 状态检查 (端口 ${PORT}):"
  echo ""

  # 检查端口占用
  local listeners
  listeners=$(lsof -iTCP:"${PORT}" -sTCP:LISTEN -n -P 2>/dev/null | tail -n +2 || true)

  if [[ -z "$listeners" ]]; then
    echo "❌ 端口 ${PORT} 未被监听"
    echo ""
    echo "建议操作:"
    echo "  1. 启动 iOS App: launch_app_sim/launch_app_device"
    echo "  2. 真机需先启动 iproxy: $0 --daemon"
    return 1
  fi

  echo "✅ 端口 ${PORT} 正在监听:"
  echo "$listeners" | awk '{print "  " $1 " (PID " $2 ", User " $3 ")"}'
  echo ""

  # 判断监听进程类型
  if echo "$listeners" | grep -q "iproxy"; then
    echo "✅ iproxy 运行中 (真机模式)"

    # 检查 PID 文件
    if [[ -f "$PIDFILE" ]]; then
      local saved_pid
      saved_pid=$(cat "$PIDFILE")
      local running_pid
      running_pid=$(echo "$listeners" | grep "iproxy" | awk '{print $2}')

      if [[ "$saved_pid" == "$running_pid" ]]; then
        echo "  → PID 文件: ${PIDFILE} (PID ${saved_pid})"
      else
        echo "  ⚠️  PID 不匹配: 文件=${saved_pid}, 实际=${running_pid}"
      fi

      if [[ -f "$LOGFILE" ]]; then
        echo "  → 日志文件: ${LOGFILE}"
        echo ""
        echo "最近 5 行日志:"
        tail -5 "$LOGFILE" | sed 's/^/    /'
      fi
    else
      echo "  → 前台运行或手动启动"
    fi
  elif echo "$listeners" | grep -q "SPMExampl"; then
    echo "⚠️  模拟器 App 直接监听 (模拟器模式)"
    echo "  → 如需测试真机，先清理模拟器残留:"
    echo "     xcrun simctl list devices | grep Booted"
    echo "     xcrun simctl terminate <UDID> com.coo.SPMExample"
  else
    echo "⚠️  未知进程监听端口"
  fi

  echo ""

  # 尝试 ping 验证服务
  echo "🔍 验证服务可用性:"
  if curl -s -X POST http://localhost:"${PORT}"/ -d '{"action":"ping"}' --max-time 2 | grep -q '"code":"ok"'; then
    echo "  ✅ 服务正常响应 (ping 成功)"
  else
    echo "  ❌ 服务无响应或返回异常"
  fi

  return 0
}

stop_iproxy() {
  echo "🛑 停止 iproxy (端口 ${PORT})..."

  # 从 PID 文件读取
  if [[ -f "$PIDFILE" ]]; then
    local pid
    pid=$(cat "$PIDFILE")

    if ps -p "$pid" >/dev/null 2>&1; then
      echo "  → 终止进程 PID ${pid}"
      kill "$pid" 2>/dev/null || true
      sleep 1

      # 强制终止（如果还在运行）
      if ps -p "$pid" >/dev/null 2>&1; then
        echo "  → 强制终止 PID ${pid}"
        kill -9 "$pid" 2>/dev/null || true
      fi

      echo "  ✅ 已停止"
    else
      echo "  ⚠️  PID ${pid} 不存在（可能已停止）"
    fi

    rm -f "$PIDFILE"
    echo "  → 清理 PID 文件"
  else
    # 查找所有 iproxy 进程
    local pids
    pids=$(lsof -iTCP:"${PORT}" -sTCP:LISTEN -n -P 2>/dev/null | grep "iproxy" | awk '{print $2}' || true)

    if [[ -z "$pids" ]]; then
      echo "  ⚠️  未找到运行中的 iproxy (端口 ${PORT})"
      return 0
    fi

    echo "  → 找到 iproxy 进程: $pids"
    for pid in $pids; do
      echo "  → 终止 PID ${pid}"
      kill "$pid" 2>/dev/null || true
    done

    sleep 1
    echo "  ✅ 已停止"
  fi

  # 清理日志文件
  if [[ -f "$LOGFILE" ]]; then
    rm -f "$LOGFILE"
    echo "  → 清理日志文件"
  fi
}

start_foreground() {
  check_iproxy_installed

  if ! ensure_port_free; then
    exit 1
  fi

  local udid
  if ! udid=$(get_device_udid); then
    echo ""
    echo "将以无设备模式启动 (等待设备连接)..."
    echo "转发 Mac :${PORT} <-> 设备 :${PORT} (Ctrl-C 停止)"
    exec iproxy "${PORT}" "${PORT}"
  fi

  echo "✅ 检测到设备: ${udid}"
  echo "转发 Mac :${PORT} <-> 设备 :${PORT} (Ctrl-C 停止)"
  exec iproxy "${PORT}" "${PORT}" -u "${udid}"
}

start_daemon() {
  check_iproxy_installed

  if ! ensure_port_free; then
    exit 1
  fi

  local udid
  if ! udid=$(get_device_udid); then
    echo ""
    echo "❌ 后台模式需要连接设备，请检查 USB 连接"
    exit 1
  fi

  echo "✅ 检测到设备: ${udid}"
  echo "🚀 启动 iproxy 后台进程..."

  # 启动后台进程
  nohup iproxy "${PORT}" "${PORT}" -u "${udid}" > "$LOGFILE" 2>&1 &
  local pid=$!

  # 保存 PID
  echo "$pid" > "$PIDFILE"

  # 等待启动
  sleep 1

  # 验证进程仍在运行
  if ! ps -p "$pid" >/dev/null 2>&1; then
    echo "❌ iproxy 启动失败"
    echo ""
    echo "日志内容:"
    cat "$LOGFILE" | sed 's/^/  /'
    rm -f "$PIDFILE"
    exit 1
  fi

  echo "✅ iproxy 已启动 (PID ${pid})"
  echo "  → PID 文件: ${PIDFILE}"
  echo "  → 日志文件: ${LOGFILE}"
  echo ""
  echo "验证连接:"
  echo "  curl -X POST http://localhost:${PORT}/ -d '{\"action\":\"ping\"}'"
  echo ""
  echo "查看状态: $0 --status"
  echo "停止服务: $0 --stop"
}

# 主逻辑
case "${1:-}" in
  --daemon|-d)
    start_daemon
    ;;
  --status|-s)
    show_status
    ;;
  --stop)
    stop_iproxy
    ;;
  --help|-h)
    show_help
    ;;
  "")
    start_foreground
    ;;
  *)
    echo "❌ 未知选项: $1" >&2
    echo "" >&2
    show_help >&2
    exit 1
    ;;
esac
