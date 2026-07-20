#!/usr/bin/env bash
# iproxy 管理脚本 - ios-automation skill 专用
# 功能：安装、启动、停止、诊断 iproxy

set -euo pipefail

PORT="${PORT:-38321}"
PIDFILE="${TMPDIR:-/tmp}/iproxy-${PORT}.pid"
LOGFILE="${TMPDIR:-/tmp}/iproxy-${PORT}.log"

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
  start             启动 iproxy（后台运行）
  stop              停止 iproxy
  restart           重启 iproxy
  status            检查状态并诊断问题
  clean             清理端口占用（模拟器残留）
  check             快速检查连接（ping App）

环境变量:
  PORT              转发端口（默认: 38321）

示例:
  $0 install        # 安装 iproxy
  $0 start          # 启动 iproxy
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

# 清理模拟器残留进程
clean_simulator_residual() {
  info "清理模拟器 App 残留..."

  # 1. 尝试 simctl terminate 所有 booted 模拟器中的 App
  local booted_udids
  booted_udids=$(xcrun simctl list devices 2>/dev/null | grep "(Booted)" | sed -E 's/.*\(([0-9A-Fa-f-]{36})\).*/\1/' || true)

  if [[ -n "$booted_udids" ]]; then
    while IFS= read -r udid; do
      [[ -z "$udid" ]] && continue
      info "终止模拟器 ${udid} 中的 App..."
      xcrun simctl terminate "$udid" com.coo.SPMExample 2>/dev/null || true
    done <<< "$booted_udids"
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
  warning "simctl 未释放端口，尝试强制终止进程..."
  local pids
  pids=$(lsof -iTCP:"${PORT}" -sTCP:LISTEN -n -P 2>/dev/null | grep "SPMExampl" | awk '{print $2}' || true)

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

  # 检查是否是模拟器 App 占用
  if echo "$listeners" | grep -q "SPMExampl"; then
    warning "端口被模拟器 App 占用，自动清理..."
    if clean_simulator_residual; then
      return 0
    else
      return 1
    fi
  fi

  # 未知进程占用
  error "端口 ${PORT} 被未知进程占用:"
  echo "$listeners" | awk '{print "  " $1 " (PID " $2 ")"}'
  echo ""
  echo "请手动处理后重试"
  return 1
}

# 启动 iproxy
start_iproxy() {
  info "启动 iproxy (端口 ${PORT})..."

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

  # 启动后台进程
  info "启动 iproxy 后台进程..."
  nohup iproxy "${PORT}" "${PORT}" -u "${udid}" > "$LOGFILE" 2>&1 &
  local pid=$!

  # 保存 PID
  echo "$pid" > "$PIDFILE"

  # 等待启动
  sleep 1

  # 验证进程仍在运行
  if ! ps -p "$pid" >/dev/null 2>&1; then
    error "iproxy 启动失败"
    echo ""
    echo "日志内容:"
    cat "$LOGFILE" | sed 's/^/  /'
    rm -f "$PIDFILE"
    return 1
  fi

  success "iproxy 已启动 (PID ${pid})"
  echo ""
  echo "  PID 文件: ${PIDFILE}"
  echo "  日志文件: ${LOGFILE}"
  echo ""
  info "验证连接: $0 check"
}

# 停止 iproxy
stop_iproxy() {
  info "停止 iproxy (端口 ${PORT})..."

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
  echo "📊 iproxy 状态检查 (端口 ${PORT})"
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
  elif echo "$listeners" | grep -q "SPMExampl"; then
    success "模拟器 App 直接监听 (模拟器模式)"
    warning "如需测试真机，需先清理模拟器残留: $0 clean"
  else
    warning "未知进程监听端口"
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
