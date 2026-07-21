#!/usr/bin/env bash
# iproxy 管理脚本 - ios-automation skill 配套工具
# 功能：安装、启动、停止、诊断 iproxy

set -euo pipefail

PORT="${PORT:-38321}"
REMOTE_PORT="${REMOTE_PORT:-$PORT}"
DEVICE_UDID="${DEVICE_UDID:-${UDID:-}}"
APP_BUNDLE_ID="${APP_BUNDLE_ID:-${IOS_APP_BUNDLE_ID:-}}"
SIMULATOR_PROCESS_NAME="${SIMULATOR_PROCESS_NAME:-}"
PIDFILE="${TMPDIR:-/tmp}/iproxy-${PORT}.pid"
LOGFILE="${TMPDIR:-/tmp}/iproxy-${PORT}.log"
LAUNCHD_LABEL="${LAUNCHD_LABEL:-com.codex.iproxy.${PORT}}"
LAUNCHD_PLIST="${LAUNCHD_PLIST:-$HOME/Library/LaunchAgents/${LAUNCHD_LABEL}.plist}"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info() { echo -e "${BLUE}ℹ️  $*${NC}" >&2; }
success() { echo -e "${GREEN}✅ $*${NC}" >&2; }
warning() { echo -e "${YELLOW}⚠️  $*${NC}" >&2; }
error() { echo -e "${RED}❌ $*${NC}" >&2; }

show_help() {
  cat <<EOF
iproxy 管理脚本 - ios-automation skill

用法: $0 <命令> [选项]

命令:
  install           安装 iproxy（通过 Homebrew）
  start             启动 iproxy（launchd 托管，KeepAlive）
  stop              停止 iproxy 并卸载 LaunchAgent
  restart           重启 launchd 托管的 iproxy
  status            检查状态并诊断问题
  clean             清理端口占用（模拟器残留）
  check             快速检查连接（ping App）

环境变量:
  PORT                    Mac 本地监听端口（默认: 38321）
  REMOTE_PORT             iOS 设备端口（默认: 与 PORT 相同）
  DEVICE_UDID             指定 USB 设备 UDID（默认: 自动取第一个 idevice_id -l）
  APP_BUNDLE_ID           可选。清理模拟器残留时要 terminate 的 App bundle id
  SIMULATOR_PROCESS_NAME  可选。端口被模拟器 App 进程占用时用于匹配并终止进程
  LAUNCHD_LABEL           可选。LaunchAgent label（默认: com.codex.iproxy.<PORT>）
  LAUNCHD_PLIST           可选。LaunchAgent plist 路径

示例:
  $0 install        # 安装 iproxy
  $0 start          # 启动 launchd 托管的 iproxy
  APP_BUNDLE_ID=your.bundle.id $0 clean
  $0 status         # 检查状态
  $0 clean          # 清理残留
EOF
}

# 检查 Homebrew 是否安装
check_homebrew() {
  if ! command -v brew >/dev/null 2>&1; then
    error "未找到 Homebrew"
    echo ""
    echo "请先安装 Homebrew:"
    echo '  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
    return 1
  fi
  return 0
}

# 检查 iproxy 是否已安装
check_iproxy_installed() {
  if command -v iproxy >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

# 安装 iproxy
install_iproxy() {
  info "检查 iproxy 安装状态..."

  if check_iproxy_installed; then
    local version
    version=$(iproxy --version 2>&1 | head -1 || echo "unknown")
    success "iproxy 已安装: $version"
    return 0
  fi

  if ! check_homebrew; then
    return 1
  fi

  info "安装 libimobiledevice (包含 iproxy)..."
  brew install libimobiledevice

  if check_iproxy_installed; then
    success "iproxy 安装成功"
    iproxy --version
  else
    error "iproxy 安装失败"
    return 1
  fi
}

# 获取 USB 连接的设备 UDID
get_device_udid() {
  if [[ -n "$DEVICE_UDID" ]]; then
    echo "$DEVICE_UDID"
    return 0
  fi

  if ! command -v idevice_id >/dev/null 2>&1; then
    error "未找到 idevice_id 命令"
    info "正在安装 libimobiledevice..."
    install_iproxy || return 1
  fi

  local udid
  udid=$(idevice_id -l 2>/dev/null | head -1 || true)

  if [[ -z "$udid" ]]; then
    error "未检测到 USB 连接的设备"
    echo ""
    echo "请检查："
    echo "  1. 设备已通过 USB 连接到 Mac"
    echo "  2. 设备已解锁并信任此电脑"
    echo "  3. 设备屏幕亮起"
    return 1
  fi

  echo "$udid"
}

xml_escape() {
  sed \
    -e 's/&/\&amp;/g' \
    -e 's/</\&lt;/g' \
    -e 's/>/\&gt;/g' \
    -e 's/"/\&quot;/g' \
    -e "s/'/\&apos;/g"
}

launchd_domain() {
  echo "gui/$(id -u)"
}

launchd_service_target() {
  echo "$(launchd_domain)/${LAUNCHD_LABEL}"
}

is_launchd_loaded() {
  launchctl print "$(launchd_service_target)" >/dev/null 2>&1
}

is_iproxy_listening() {
  lsof -iTCP:"${PORT}" -sTCP:LISTEN -n -P 2>/dev/null | tail -n +2 | grep -q "iproxy"
}

write_launchd_plist() {
  local iproxy_bin udid escaped_label escaped_iproxy escaped_port escaped_remote escaped_udid escaped_log
  iproxy_bin=$(command -v iproxy)
  udid="$1"

  mkdir -p "$(dirname "$LAUNCHD_PLIST")"

  escaped_label=$(printf '%s' "$LAUNCHD_LABEL" | xml_escape)
  escaped_iproxy=$(printf '%s' "$iproxy_bin" | xml_escape)
  escaped_port=$(printf '%s' "$PORT" | xml_escape)
  escaped_remote=$(printf '%s' "$REMOTE_PORT" | xml_escape)
  escaped_udid=$(printf '%s' "$udid" | xml_escape)
  escaped_log=$(printf '%s' "$LOGFILE" | xml_escape)

  cat > "$LAUNCHD_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${escaped_label}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${escaped_iproxy}</string>
    <string>${escaped_port}</string>
    <string>${escaped_remote}</string>
    <string>-u</string>
    <string>${escaped_udid}</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>${escaped_log}</string>
  <key>StandardErrorPath</key>
  <string>${escaped_log}</string>
  <key>ProcessType</key>
  <string>Background</string>
</dict>
</plist>
EOF
}

unload_launchd_job() {
  if is_launchd_loaded; then
    launchctl bootout "$(launchd_domain)" "$LAUNCHD_PLIST" >/dev/null 2>&1 \
      || launchctl bootout "$(launchd_service_target)" >/dev/null 2>&1 \
      || true
  fi
}

# 清理模拟器残留进程
clean_simulator_residual() {
  info "清理模拟器 App 残留..."

  # 1. 如果调用方提供了 bundle id，优先用 simctl 正常终止 App。
  if [[ -n "$APP_BUNDLE_ID" ]]; then
    local booted_udids
    booted_udids=$(xcrun simctl list devices 2>/dev/null | grep "(Booted)" | sed -E 's/.*\(([0-9A-Fa-f-]{36})\).*/\1/' || true)

    if [[ -n "$booted_udids" ]]; then
      while IFS= read -r udid; do
        [[ -z "$udid" ]] && continue
        info "终止模拟器 ${udid} 中的 App (${APP_BUNDLE_ID})..."
        xcrun simctl terminate "$udid" "$APP_BUNDLE_ID" 2>/dev/null || true
      done <<< "$booted_udids"
    fi
  else
    warning "未设置 APP_BUNDLE_ID，跳过 simctl terminate"
  fi

  # 2. 等待端口释放
  local i
  for i in $(seq 1 15); do
    if ! lsof -iTCP:"${PORT}" -sTCP:LISTEN -n -P >/dev/null 2>&1; then
      success "端口已释放"
      return 0
    fi
    sleep 0.3
  done

  # 3. simctl 未生效，兜底 kill 残留进程
  if [[ -z "$SIMULATOR_PROCESS_NAME" ]]; then
    error "端口仍被占用，且未设置 SIMULATOR_PROCESS_NAME，拒绝按未知进程名强杀"
    echo ""
    echo "请设置 APP_BUNDLE_ID 后重试 clean，或设置 SIMULATOR_PROCESS_NAME 指定可终止的模拟器 App 进程名"
    lsof -iTCP:"${PORT}" -sTCP:LISTEN -n -P 2>/dev/null || true
    return 1
  fi

  warning "simctl 未释放端口，尝试强制终止匹配进程 (${SIMULATOR_PROCESS_NAME})..."
  local pids
  pids=$(lsof -iTCP:"${PORT}" -sTCP:LISTEN -n -P 2>/dev/null | awk -v name="$SIMULATOR_PROCESS_NAME" 'NR > 1 && index($1, name) {print $2}' || true)

  if [[ -n "$pids" ]]; then
    for pid in $pids; do
      info "强制终止进程 PID ${pid}"
      kill "$pid" 2>/dev/null || true
    done

    sleep 1

    if ! lsof -iTCP:"${PORT}" -sTCP:LISTEN -n -P >/dev/null 2>&1; then
      success "端口已释放"
      return 0
    fi
  fi

  error "清理失败，端口仍被占用"
  return 1
}

# 确保端口可用
ensure_port_free() {
  local listeners
  listeners=$(lsof -iTCP:"${PORT}" -sTCP:LISTEN -n -P 2>/dev/null | tail -n +2 || true)

  if [[ -z "$listeners" ]]; then
    success "端口 ${PORT} 空闲"
    return 0
  fi

  # 检查是否是 iproxy 占用
  if echo "$listeners" | grep -q "iproxy"; then
    warning "iproxy 已在运行"
    echo ""
    echo "如需重启，请先执行: $0 stop"
    return 1
  fi

  # 已提供 App 信息时，可尝试清理模拟器 App 残留；否则不猜测具体项目。
  if [[ -n "$APP_BUNDLE_ID$SIMULATOR_PROCESS_NAME" ]]; then
    warning "端口被非 iproxy 进程占用，尝试按提供的 App 信息清理..."
    if clean_simulator_residual; then
      return 0
    else
      return 1
    fi
  fi

  # 未知进程占用
  error "端口 ${PORT} 被非 iproxy 进程占用:"
  echo "$listeners" | awk '{print "  " $1 " (PID " $2 ")"}'
  echo ""
  echo "请手动处理后重试，或设置 APP_BUNDLE_ID / SIMULATOR_PROCESS_NAME 后执行: $0 clean"
  return 1
}

# 启动 iproxy
start_iproxy() {
  info "启动 iproxy (本地端口 ${PORT} -> 设备端口 ${REMOTE_PORT})..."

  # 检查 iproxy 是否已安装
  if ! check_iproxy_installed; then
    warning "未找到 iproxy，正在安装..."
    install_iproxy || return 1
  fi

  # 确保端口可用
  if ! ensure_port_free; then
    return 1
  fi

  # 获取设备 UDID
  local udid
  if ! udid=$(get_device_udid); then
    return 1
  fi

  success "检测到设备: ${udid}"

  info "写入 LaunchAgent: ${LAUNCHD_PLIST}"
  write_launchd_plist "$udid"

  info "启动 launchd 服务: ${LAUNCHD_LABEL}"
  unload_launchd_job
  launchctl bootstrap "$(launchd_domain)" "$LAUNCHD_PLIST"
  launchctl kickstart -k "$(launchd_service_target)" >/dev/null 2>&1 || true

  sleep 1

  if ! is_launchd_loaded; then
    error "iproxy 启动失败"
    echo ""
    echo "日志内容:"
    [[ -f "$LOGFILE" ]] && cat "$LOGFILE" | sed 's/^/  /'
    return 1
  fi

  if ! is_iproxy_listening; then
    error "launchd 已加载，但 iproxy 尚未监听端口 ${PORT}"
    echo ""
    echo "请检查 USB 连接、设备信任状态和日志:"
    echo "  ${LOGFILE}"
    [[ -f "$LOGFILE" ]] && tail -20 "$LOGFILE" | sed 's/^/  /'
    return 1
  fi

  success "iproxy 已交给 launchd 托管"
  echo ""
  echo "  LaunchAgent: ${LAUNCHD_PLIST}"
  echo "  Label: ${LAUNCHD_LABEL}"
  echo "  日志文件: ${LOGFILE}"
  echo ""
  info "验证连接: $0 check"
}

# 停止 iproxy
stop_iproxy() {
  info "停止 iproxy (端口 ${PORT})..."

  if is_launchd_loaded; then
    info "卸载 LaunchAgent: ${LAUNCHD_LABEL}"
    unload_launchd_job
  fi

  if [[ -f "$LAUNCHD_PLIST" ]]; then
    rm -f "$LAUNCHD_PLIST"
  fi

  # 从 PID 文件读取
  if [[ -f "$PIDFILE" ]]; then
    local pid
    pid=$(cat "$PIDFILE")

    if ps -p "$pid" >/dev/null 2>&1; then
      info "终止进程 PID ${pid}"
      kill "$pid" 2>/dev/null || true
      sleep 1

      # 强制终止（如果还在运行）
      if ps -p "$pid" >/dev/null 2>&1; then
        warning "强制终止 PID ${pid}"
        kill -9 "$pid" 2>/dev/null || true
      fi

      success "已停止"
    else
      warning "PID ${pid} 不存在（可能已停止）"
    fi

    rm -f "$PIDFILE"
  else
    # 查找所有 iproxy 进程
    local pids
    pids=$(lsof -iTCP:"${PORT}" -sTCP:LISTEN -n -P 2>/dev/null | grep "iproxy" | awk '{print $2}' || true)

    if [[ -z "$pids" ]]; then
      warning "未找到运行中的 iproxy (端口 ${PORT})"
      return 0
    fi

    info "找到 iproxy 进程: $pids"
    for pid in $pids; do
      info "终止 PID ${pid}"
      kill "$pid" 2>/dev/null || true
    done

    sleep 1
    success "已停止"
  fi

  # 清理日志文件
  if [[ -f "$LOGFILE" ]]; then
    rm -f "$LOGFILE"
  fi
}

# 检查状态
show_status() {
  echo "📊 iproxy 状态检查 (本地端口 ${PORT}, 设备端口 ${REMOTE_PORT})"
  echo ""

  # 检查 iproxy 是否已安装
  if ! check_iproxy_installed; then
    error "iproxy 未安装"
    echo ""
    echo "安装命令: $0 install"
    return 1
  fi

  local version
  version=$(iproxy --version 2>&1 | head -1 || echo "unknown")
  info "iproxy 版本: $version"
  echo ""

  # 检查端口占用
  local listeners
  listeners=$(lsof -iTCP:"${PORT}" -sTCP:LISTEN -n -P 2>/dev/null | tail -n +2 || true)

  if [[ -z "$listeners" ]]; then
    error "端口 ${PORT} 未被监听"
    if is_launchd_loaded; then
      warning "LaunchAgent 已加载但当前未监听；可能是设备断开、未信任，或 iproxy 正在被 launchd 重试"
      info "LaunchAgent: ${LAUNCHD_PLIST}"
      if [[ -f "$LOGFILE" ]]; then
        echo ""
        echo "最近 10 行日志:"
        tail -10 "$LOGFILE" | sed 's/^/    /'
      fi
    fi
    echo ""
    echo "可能原因："
    echo "  1. iOS App 未启动"
    echo "  2. 真机需要先启动 iproxy: $0 start"
    echo "  3. App 中的 server.start() 未调用"
    return 1
  fi

  success "端口 ${PORT} 正在监听:"
  echo "$listeners" | awk '{print "  " $1 " (PID " $2 ", User " $3 ")"}'
  echo ""

  # 判断监听进程类型
  if echo "$listeners" | grep -q "iproxy"; then
    success "iproxy 运行中 (真机模式)"

    if is_launchd_loaded; then
      success "launchd 正在托管: ${LAUNCHD_LABEL}"
      info "LaunchAgent: ${LAUNCHD_PLIST}"
    else
      warning "检测到 iproxy 监听，但未发现当前 label 的 launchd 托管；可能是手动启动或旧脚本启动"
    fi

    # 检查 PID 文件
    if [[ -f "$PIDFILE" ]]; then
      local saved_pid
      saved_pid=$(cat "$PIDFILE")
      info "PID 文件: ${PIDFILE} (PID ${saved_pid})"

      if [[ -f "$LOGFILE" ]]; then
        echo ""
        echo "最近 5 行日志:"
        tail -5 "$LOGFILE" | sed 's/^/    /'
      fi
    fi
  else
    warning "非 iproxy 进程监听端口；这通常表示模拟器 App 直接监听或其他本地进程占用"
    warning "如需测试真机，需先清理或停止该进程。可设置 APP_BUNDLE_ID 后执行: $0 clean"
  fi

  echo ""

  # 检查设备连接
  info "检查 USB 设备连接..."
  local udid
  udid=$(idevice_id -l 2>/dev/null | head -1 || true)

  if [[ -n "$udid" ]]; then
    success "检测到设备: ${udid}"
  else
    warning "未检测到 USB 设备"
  fi

  echo ""

  # 尝试 ping 验证服务
  info "验证服务可用性..."
  if curl -s -X POST http://localhost:"${PORT}"/ -d '{"action":"ping"}' --max-time 2 2>/dev/null | grep -q '"code":"ok"'; then
    success "服务正常响应 (ping 成功)"
  else
    error "服务无响应或返回异常"
    echo ""
    echo "排查步骤："
    echo "  1. 检查 App 是否已启动"
    echo "  2. 检查 App 中的 server.start() 是否已调用"
    echo "  3. 查看日志: $0 status"
  fi
}

# 快速检查连接
quick_check() {
  info "快速检查连接..."

  if curl -s -X POST http://localhost:"${PORT}"/ -d '{"action":"ping"}' --max-time 2 2>/dev/null | grep -q '"code":"ok"'; then
    success "连接正常"
    return 0
  else
    error "连接失败"
    echo ""
    echo "详细诊断: $0 status"
    return 1
  fi
}

# 重启 iproxy
restart_iproxy() {
  info "重启 iproxy..."
  stop_iproxy
  sleep 1
  start_iproxy
}

# 主逻辑
case "${1:-}" in
  install)
    install_iproxy
    ;;
  start)
    start_iproxy
    ;;
  stop)
    stop_iproxy
    ;;
  restart)
    restart_iproxy
    ;;
  status)
    show_status
    ;;
  clean)
    clean_simulator_residual
    ;;
  check)
    quick_check
    ;;
  --help|-h|help)
    show_help
    ;;
  "")
    error "缺少命令"
    echo ""
    show_help
    exit 1
    ;;
  *)
    error "未知命令: $1"
    echo ""
    show_help
    exit 1
    ;;
esac
