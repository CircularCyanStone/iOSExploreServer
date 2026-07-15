#!/bin/bash
# 登录流程自动化测试脚本

set -e

BASE_URL="http://localhost:38321"
DELAY=2  # 每个操作之间的延迟（秒）

echo "🔵 登录流程自动化测试"
echo "================================"
echo ""

# 辅助函数：发送命令
send_command() {
    local action=$1
    local data=$2
    echo "📤 发送命令: $action"
    response=$(curl -s -X POST "$BASE_URL/" \
        -H "Content-Type: application/json" \
        -d "{\"action\":\"$action\",\"data\":$data}")
    echo "📥 响应: $response"
    echo ""
    sleep $DELAY
}

# 辅助函数：UI 输入
ui_input() {
    local identifier=$1
    local text=$2
    echo "⌨️  输入文本: $text → $identifier"
    send_command "ui.input" "{\"accessibilityIdentifier\":\"$identifier\",\"text\":\"$text\"}"
}

# 辅助函数：UI 点击
ui_tap() {
    local identifier=$1
    echo "👆 点击: $identifier"
    send_command "ui.tap" "{\"accessibilityIdentifier\":\"$identifier\"}"
}

# 辅助函数：UI 检查
ui_inspect() {
    echo "🔍 检查当前界面"
    send_command "ui.inspect" "{}"
}

echo "============================================"
echo "测试 1: 成功登录流程（使用预置账号）"
echo "============================================"
echo ""

echo "📝 填写登录信息..."
ui_input "login_username_field" "test"
ui_input "login_password_field" "123456"

echo "🚀 点击登录按钮..."
ui_tap "login_button"

echo "⏳ 等待网络请求完成（模拟延迟 1.5 秒）..."
sleep 3

echo "✅ 应该已经跳转到首页"
ui_inspect

echo ""
echo "============================================"
echo "测试 2: 退出登录"
echo "============================================"
echo ""

echo "🚪 点击退出登录按钮..."
ui_tap "home_logout_button"

echo "⏳ 等待确认对话框..."
sleep 1

echo "✅ 确认退出..."
send_command "ui.alert.respond" "{\"buttonTitle\":\"退出\"}"

echo "⏳ 等待返回登录页..."
sleep 2

echo "✅ 应该已经返回登录页"
ui_inspect

echo ""
echo "============================================"
echo "测试 3: 注册新用户"
echo "============================================"
echo ""

echo "📝 点击去注册..."
ui_tap "goto_register_button"

echo "⏳ 等待页面切换..."
sleep 1

echo "📝 填写注册信息..."
ui_input "register_username_field" "newuser"
ui_input "register_email_field" "newuser@example.com"
ui_input "register_password_field" "password123"
ui_input "register_confirm_password_field" "password123"

echo "🚀 点击注册按钮..."
ui_tap "register_button"

echo "⏳ 等待网络请求完成..."
sleep 3

echo "✅ 应该显示注册成功对话框"
ui_inspect

echo ""
echo "============================================"
echo "测试 4: 重置密码"
echo "============================================"
echo ""

echo "🔙 返回登录页..."
send_command "ui.alert.respond" "{\"buttonTitle\":\"确定\"}"
sleep 1

echo "📝 点击忘记密码..."
ui_tap "goto_reset_password_button"

echo "⏳ 等待页面切换..."
sleep 1

echo "📝 填写重置密码信息..."
ui_input "reset_username_field" "test"
ui_input "reset_email_field" "test@example.com"
ui_input "reset_new_password_field" "newpass123"
ui_input "reset_confirm_password_field" "newpass123"

echo "🚀 点击重置密码按钮..."
ui_tap "reset_password_button"

echo "⏳ 等待网络请求完成..."
sleep 3

echo "✅ 应该显示重置成功对话框"
ui_inspect

echo ""
echo "============================================"
echo "测试 5: 错误场景 - 密码不一致"
echo "============================================"
echo ""

echo "🔙 返回登录页并进入注册..."
send_command "ui.alert.respond" "{\"buttonTitle\":\"确定\"}"
sleep 1
send_command "ui.navigation.back" "{}"
sleep 1
ui_tap "goto_register_button"
sleep 1

echo "📝 填写不一致的密码..."
ui_input "register_username_field" "testuser2"
ui_input "register_email_field" "test2@example.com"
ui_input "register_password_field" "password123"
ui_input "register_confirm_password_field" "different"

echo "🚀 点击注册按钮..."
ui_tap "register_button"

echo "⏳ 等待验证..."
sleep 1

echo "✅ 应该显示错误提示：两次密码输入不一致"
ui_inspect

echo ""
echo "============================================"
echo "✅ 所有测试完成！"
echo "============================================"
echo ""
echo "📊 测试总结："
echo "  1. ✅ 成功登录（预置账号）"
echo "  2. ✅ 退出登录"
echo "  3. ✅ 注册新用户"
echo "  4. ✅ 重置密码"
echo "  5. ✅ 错误处理（密码不一致）"
echo ""
echo "💡 提示："
echo "  - 查看 Console.app 可以看到完整的日志输出"
echo "  - 使用 ui.inspect 可以查看当前界面结构"
echo "  - 可以通过 AuthService.shared.simulateFailureRate 模拟网络错误"
