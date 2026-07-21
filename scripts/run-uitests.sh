#!/bin/bash
#
# run-uitests.sh
# 运行 SPMExample 的 XCUITest 测试
#
# 使用示例：
#   ./scripts/run-uitests.sh                                    # 列出可用设备
#   ./scripts/run-uitests.sh --simulator "iPhone 17"            # 模拟器测试
#   ./scripts/run-uitests.sh --device-id <UDID>                 # 真机测试
#   ./scripts/run-uitests.sh --sim-id <SIM-UUID>                # 指定模拟器 UUID
#   ./scripts/run-uitests.sh --test-class LoginFlowTests        # 只运行特定测试类
#   ./scripts/run-uitests.sh --test testSuccessfulLogin         # 只运行特定测试方法
#

set -euo pipefail

# 颜色输出
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# 项目路径
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly EXAMPLE_DIR="$PROJECT_ROOT/Examples/SPMExample"
readonly PROJECT_PATH="$EXAMPLE_DIR/SPMExample.xcodeproj"
readonly SCHEME="SPMExample"

# 默认参数
DESTINATION=""
TEST_FILTER=""
VERBOSE=false
RESULT_BUNDLE_PATH=""

# 打印使用说明
usage() {
    cat << EOF
使用说明: $0 [选项]

选项:
    --simulator <name>          在指定名称的模拟器上运行（例如: "iPhone 17"）
    --sim-id <uuid>             在指定 UUID 的模拟器上运行
    --device-id <udid>          在指定 UDID 的真机上运行
    --test-class <class>        只运行指定的测试类（例如: LoginFlowTests）
    --test <method>             只运行指定的测试方法（例如: testSuccessfulLogin）
    --verbose                   显示详细输出
    --result-bundle <path>      指定测试结果 bundle 路径
    --help                      显示此帮助信息

示例:
    # 列出可用设备
    $0

    # 在 iPhone 17 模拟器上运行所有测试
    $0 --simulator "iPhone 17"

    # 在真机上运行测试
    $0 --device-id 00008030-XXXXXXXXXXXX

    # 只运行登录测试
    $0 --simulator "iPhone 17" --test-class LoginFlowTests

    # 只运行成功登录测试
    $0 --simulator "iPhone 17" --test testSuccessfulLogin

EOF
    exit 0
}

# 打印带颜色的信息
info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
    exit 1
}

# 列出可用设备
list_devices() {
    info "可用的模拟器："
    xcrun simctl list devices available | grep -E "iPhone|iPad" | grep -v "unavailable" || true
    echo ""

    info "可用的真机："
    xcrun xctrace list devices 2>&1 | grep -E "^[A-Za-z].*\([0-9A-F]{8}-" || true
    echo ""
}

# 解析命令行参数
parse_args() {
    if [[ $# -eq 0 ]]; then
        list_devices
        exit 0
    fi

    while [[ $# -gt 0 ]]; do
        case $1 in
            --simulator)
                DESTINATION="platform=iOS Simulator,name=$2"
                shift 2
                ;;
            --sim-id)
                DESTINATION="platform=iOS Simulator,id=$2"
                shift 2
                ;;
            --device-id)
                DESTINATION="platform=iOS,id=$2"
                shift 2
                ;;
            --test-class)
                TEST_FILTER="-only-testing:SPMExampleUITests/$2"
                shift 2
                ;;
            --test)
                TEST_FILTER="-only-testing:SPMExampleUITests/$2"
                shift 2
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --result-bundle)
                RESULT_BUNDLE_PATH="$2"
                shift 2
                ;;
            --help)
                usage
                ;;
            *)
                error "未知选项: $1\n使用 --help 查看帮助"
                ;;
        esac
    done

    if [[ -z "$DESTINATION" ]]; then
        error "必须指定运行设备（--simulator 或 --device-id 或 --sim-id）"
    fi
}

# 检查项目是否存在
check_project() {
    if [[ ! -d "$PROJECT_PATH" ]]; then
        error "项目不存在: $PROJECT_PATH"
    fi

    if [[ ! -d "$EXAMPLE_DIR/SPMExampleUITests" ]]; then
        error "UITests 目录不存在: $EXAMPLE_DIR/SPMExampleUITests\n需要在 Xcode 中手动创建 UI Test target"
    fi
}

# 运行测试
run_tests() {
    info "运行 XCUITest 测试..."
    echo ""
    info "项目: $PROJECT_PATH"
    info "Scheme: $SCHEME"
    info "目标设备: $DESTINATION"
    [[ -n "$TEST_FILTER" ]] && info "测试过滤: $TEST_FILTER"
    echo ""

    # 构建测试命令
    local xcodebuild_cmd=(
        xcodebuild test
        -project "$PROJECT_PATH"
        -scheme "$SCHEME"
        -destination "$DESTINATION"
    )

    # 添加测试过滤
    if [[ -n "$TEST_FILTER" ]]; then
        xcodebuild_cmd+=("$TEST_FILTER")
    fi

    # 添加 result bundle
    if [[ -n "$RESULT_BUNDLE_PATH" ]]; then
        xcodebuild_cmd+=(-resultBundlePath "$RESULT_BUNDLE_PATH")
    else
        # 默认保存到临时目录
        local timestamp=$(date +%Y%m%d_%H%M%S)
        RESULT_BUNDLE_PATH="/tmp/SPMExample_UITest_${timestamp}.xcresult"
        xcodebuild_cmd+=(-resultBundlePath "$RESULT_BUNDLE_PATH")
    fi

    # 执行测试
    local start_time=$(date +%s)

    if [[ "$VERBOSE" == true ]]; then
        "${xcodebuild_cmd[@]}"
    else
        # 过滤输出，只显示重要信息
        "${xcodebuild_cmd[@]}" 2>&1 | grep -E "Test Suite|Test Case|passed|failed|error|warning|Testing started|Testing finished" || {
            local exit_code=$?
            if [[ $exit_code -ne 0 && $exit_code -ne 1 ]]; then
                error "xcodebuild 执行失败"
            fi
        }
    fi

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    echo ""
    success "测试完成！耗时: ${duration}s"
    info "测试结果保存在: $RESULT_BUNDLE_PATH"
    echo ""
}

# 检查真机连接和 iproxy
check_device_setup() {
    if [[ "$DESTINATION" =~ "platform=iOS,id=" ]]; then
        local device_id=$(echo "$DESTINATION" | sed -E 's/.*id=([A-F0-9-]+).*/\1/')

        info "检查真机连接状态..."

        # 检查设备是否连接
        if ! xcrun xctrace list devices 2>&1 | grep -q "$device_id"; then
            error "设备未连接或不可用: $device_id"
        fi

        success "真机已连接: $device_id"

        # 提示 iproxy 配置
        echo ""
        warning "真机测试注意事项："
        echo "  1. 确保设备已信任此电脑"
        echo "  2. 确保设备开发者模式已启用"
        echo "  3. 如需与 iOSExploreServer 通信，运行："
        echo "     iproxy 38321 38321"
        echo ""
    fi
}

# 主函数
main() {
    parse_args "$@"
    check_project
    check_device_setup
    run_tests
}

main "$@"
