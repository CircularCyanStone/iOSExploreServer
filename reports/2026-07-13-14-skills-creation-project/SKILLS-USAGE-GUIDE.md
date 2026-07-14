# iOS Automation Skills 使用指南

## 概述

本文档展示如何使用已创建的 10 个 iOS 自动化 Skills，包括：
1. **自然语言案例** - 直接与 Claude 对话使用
2. **结构化信息案例** - 用于测试平台集成

---

## 使用方式 1: 自然语言交互

### 案例 1: 登录表单测试

**用户输入（自然语言）**：
```
我需要测试 iOS App 的登录功能：
1. 在用户名输入框输入 "test@example.com"
2. 在密码输入框输入 "Password123"
3. 点击登录按钮
4. 验证是否成功跳转到首页

App 已经在模拟器运行，iOSExploreServer 在 localhost:38321
```

**Skills 自动触发**：
- `ios-form-filling` - 处理表单输入
- `ios-navigation` - 处理页面跳转验证

**Claude 执行流程**：
```bash
# Step 1: 检查当前页面
curl -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}'

# Step 2: 填写用户名
curl -X POST http://localhost:38321/ -d '{
  "action": "ui.input",
  "data": {
    "accessibilityIdentifier": "username_field",
    "text": "test@example.com",
    "mode": "replace"
  }
}'

# Step 3: 填写密码
curl -X POST http://localhost:38321/ -d '{
  "action": "ui.input",
  "data": {
    "accessibilityIdentifier": "password_field",
    "text": "Password123",
    "mode": "replace"
  }
}'

# Step 4: 关闭键盘
curl -X POST http://localhost:38321/ -d '{"action":"ui.keyboard.dismiss"}'

# Step 5: 点击登录按钮
curl -X POST http://localhost:38321/ -d '{
  "action": "ui.tap",
  "data": {
    "accessibilityIdentifier": "login_button"
  }
}'

# Step 6: 等待跳转并验证
sleep 2
curl -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}' | jq '.data.navigationBar.title'
```

**预期输出**：
```
✅ 登录测试完成
- 用户名已填写
- 密码已填写
- 登录按钮已点击
- 当前页面：首页（验证通过）
```

---

### 案例 2: 列表滚动和点击

**用户输入**：
```
在 iOS App 的设置列表中：
1. 滚动到 "隐私设置" 选项
2. 点击进入
3. 截图保存为 privacy-settings.png
```

**Skills 触发**：
- `ios-list-interaction` - 列表滚动
- `ios-navigation` - 点击导航
- `ios-screenshot` - 截图保存

**执行结果**：
```
✅ 操作完成
- 已滚动到 "隐私设置"
- 已点击进入隐私设置页面
- 截图已保存：privacy-settings.png
```

---

### 案例 3: Alert 处理

**用户输入**：
```
测试删除功能的 iOS App Alert：
1. 点击删除按钮
2. 等待确认弹窗出现
3. 点击 "确认删除"
4. 验证数据已删除
```

**Skills 触发**：
- `ios-alert-handling` - Alert 响应

**执行流程**：
```bash
# 触发删除
curl -X POST http://localhost:38321/ -d '{
  "action": "ui.tap",
  "data": {"accessibilityIdentifier": "delete_button"}
}'

# 等待 Alert
sleep 0.5

# 检查 Alert
curl -X POST http://localhost:38321/ -d '{"action":"ui.inspect"}' | jq '.data.alert'

# 点击确认
curl -X POST http://localhost:38321/ -d '{
  "action": "ui.alert.respond",
  "data": {"buttonTitle": "确认删除"}
}'
```

---

## 使用方式 2: 结构化测试信息

### 测试用例格式（JSON Schema）

```json
{
  "testSuite": "iOS App E2E Tests",
  "environment": {
    "platform": "iOS",
    "device": "iPhone 17 Simulator",
    "appBundleId": "com.example.app",
    "serverUrl": "http://localhost:38321"
  },
  "testCases": [
    {
      "id": "TC001",
      "name": "User Login",
      "priority": "P0",
      "tags": ["auth", "smoke"],
      "steps": [
        {
          "action": "fillForm",
          "description": "Fill login form",
          "fields": [
            {
              "identifier": "username_field",
              "value": "test@example.com",
              "type": "text"
            },
            {
              "identifier": "password_field",
              "value": "Password123",
              "type": "secure"
            }
          ]
        },
        {
          "action": "tap",
          "description": "Tap login button",
          "target": {
            "identifier": "login_button",
            "type": "button"
          }
        },
        {
          "action": "verify",
          "description": "Verify successful navigation",
          "assertions": [
            {
              "type": "navigationTitle",
              "expected": "Home",
              "timeout": 5000
            }
          ]
        }
      ]
    }
  ]
}
```

---

### 案例 1: 登录流程测试（结构化）

```json
{
  "testCase": {
    "id": "LOGIN_001",
    "name": "Valid User Login",
    "description": "Test successful login with valid credentials",
    "preconditions": [
      "App is installed and launched",
      "User is on login screen",
      "Test account exists: test@example.com"
    ],
    "steps": [
      {
        "stepId": 1,
        "skill": "ios-form-filling",
        "action": "fillTextField",
        "params": {
          "identifier": "username_field",
          "text": "test@example.com",
          "mode": "replace"
        },
        "expected": "Username field contains test@example.com"
      },
      {
        "stepId": 2,
        "skill": "ios-form-filling",
        "action": "fillTextField",
        "params": {
          "identifier": "password_field",
          "text": "Password123",
          "mode": "replace"
        },
        "expected": "Password field is filled (masked)"
      },
      {
        "stepId": 3,
        "skill": "ios-form-filling",
        "action": "dismissKeyboard",
        "params": {},
        "expected": "Keyboard is hidden"
      },
      {
        "stepId": 4,
        "skill": "ios-navigation",
        "action": "tapButton",
        "params": {
          "identifier": "login_button"
        },
        "expected": "Login button is tapped"
      },
      {
        "stepId": 5,
        "skill": "ios-navigation",
        "action": "verifyNavigation",
        "params": {
          "expectedTitle": "Home",
          "timeout": 5000
        },
        "expected": "Navigation bar shows 'Home'"
      }
    ],
    "postconditions": [
      "User is logged in",
      "Home screen is displayed"
    ],
    "cleanup": [
      {
        "action": "logout",
        "description": "Log out test user"
      }
    ]
  }
}
```

---

### 案例 2: 删除确认流程（结构化）

```json
{
  "testCase": {
    "id": "DELETE_001",
    "name": "Delete Item with Confirmation",
    "description": "Test delete item with alert confirmation",
    "steps": [
      {
        "stepId": 1,
        "skill": "ios-list-interaction",
        "action": "swipeCell",
        "params": {
          "cellIdentifier": "item_cell_0",
          "direction": "left"
        },
        "expected": "Delete button revealed"
      },
      {
        "stepId": 2,
        "skill": "ios-navigation",
        "action": "tap",
        "params": {
          "text": "Delete"
        },
        "expected": "Delete action triggered"
      },
      {
        "stepId": 3,
        "skill": "ios-alert-handling",
        "action": "waitForAlert",
        "params": {
          "timeout": 2000
        },
        "expected": "Confirmation alert appears"
      },
      {
        "stepId": 4,
        "skill": "ios-alert-handling",
        "action": "respondToAlert",
        "params": {
          "buttonTitle": "确认删除"
        },
        "expected": "Alert is dismissed"
      },
      {
        "stepId": 5,
        "skill": "ios-list-interaction",
        "action": "verifyItemGone",
        "params": {
          "cellIdentifier": "item_cell_0"
        },
        "expected": "Item is removed from list"
      }
    ]
  }
}
```

---

### 案例 3: 多页表单测试（结构化）

```json
{
  "testCase": {
    "id": "FORM_001",
    "name": "Multi-Page Registration",
    "description": "Complete registration across 3 pages",
    "steps": [
      {
        "stepId": 1,
        "page": "Page 1: Basic Info",
        "skill": "ios-form-filling",
        "actions": [
          {
            "action": "fillTextField",
            "params": {
              "identifier": "first_name",
              "text": "John"
            }
          },
          {
            "action": "fillTextField",
            "params": {
              "identifier": "last_name",
              "text": "Doe"
            }
          }
        ]
      },
      {
        "stepId": 2,
        "skill": "ios-navigation",
        "action": "tapButton",
        "params": {
          "text": "Next"
        },
        "expected": "Navigate to Page 2"
      },
      {
        "stepId": 3,
        "page": "Page 2: Contact",
        "skill": "ios-form-filling",
        "actions": [
          {
            "action": "fillTextField",
            "params": {
              "identifier": "email",
              "text": "john.doe@example.com"
            }
          },
          {
            "action": "fillTextField",
            "params": {
              "identifier": "phone",
              "text": "+1234567890"
            }
          }
        ]
      },
      {
        "stepId": 4,
        "skill": "ios-navigation",
        "action": "tapButton",
        "params": {
          "text": "Next"
        }
      },
      {
        "stepId": 5,
        "page": "Page 3: Confirmation",
        "skill": "ios-screenshot",
        "action": "capture",
        "params": {
          "filename": "registration-confirmation.png",
          "description": "Confirmation page before submit"
        }
      },
      {
        "stepId": 6,
        "skill": "ios-navigation",
        "action": "tapButton",
        "params": {
          "text": "Submit"
        }
      }
    ]
  }
}
```

---

## 测试平台集成

### 集成方式 1: REST API 接口

```python
# 测试平台调用示例
import requests

def execute_ios_test(test_case_json):
    """
    执行 iOS 自动化测试
    
    Args:
        test_case_json: 结构化测试用例（JSON 格式）
    
    Returns:
        测试结果（包含每步执行状态和截图）
    """
    # 调用 Claude Code API（假设）
    response = requests.post(
        "http://claude-api/execute-ios-test",
        json={
            "test_case": test_case_json,
            "skills": [
                "ios-form-filling",
                "ios-navigation",
                "ios-alert-handling",
                "ios-list-interaction",
                "ios-screenshot"
            ],
            "server_url": "http://localhost:38321"
        }
    )
    
    return response.json()

# 使用示例
test_case = {
    "id": "LOGIN_001",
    "steps": [...] # 结构化步骤
}

result = execute_ios_test(test_case)
print(f"Test Status: {result['status']}")
print(f"Duration: {result['duration_ms']}ms")
```

---

### 集成方式 2: 测试文件生成

```python
# 从结构化信息生成 pytest 测试
def generate_pytest_from_json(test_case):
    """
    从结构化测试用例生成 pytest 代码
    """
    test_code = f"""
import pytest
from ios_automation import IOSTestClient

def test_{test_case['id'].lower()}():
    '''
    {test_case['name']}
    {test_case['description']}
    '''
    client = IOSTestClient('http://localhost:38321')
    
"""
    
    for step in test_case['steps']:
        skill = step['skill']
        action = step['action']
        params = step['params']
        
        if skill == 'ios-form-filling':
            if action == 'fillTextField':
                test_code += f"""
    # Step {step['stepId']}: Fill {params['identifier']}
    client.fill_text_field(
        identifier='{params['identifier']}',
        text='{params['text']}',
        mode='{params.get('mode', 'replace')}'
    )
"""
        elif skill == 'ios-navigation':
            if action == 'tapButton':
                test_code += f"""
    # Step {step['stepId']}: Tap button
    client.tap_button(identifier='{params['identifier']}')
"""
        # ... 其他 skill 和 action
    
    test_code += """
    # Verification
    assert client.verify_success(), "Test failed"
"""
    
    return test_code
```

---

### 集成方式 3: CI/CD Pipeline

```yaml
# .github/workflows/ios-e2e-test.yml
name: iOS E2E Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: macos-latest
    
    steps:
      - name: Checkout code
        uses: actions/checkout@v2
      
      - name: Setup iOS Simulator
        run: |
          xcrun simctl boot "iPhone 17"
      
      - name: Start iOSExploreServer
        run: |
          cd SPMExample
          swift run &
          sleep 5
      
      - name: Run E2E Tests with Claude Skills
        run: |
          # 使用 Claude Code CLI 执行测试
          claude-code execute-test \
            --test-suite tests/e2e/ios-tests.json \
            --skills-path .claude/skills \
            --server-url http://localhost:38321 \
            --output test-results/
      
      - name: Upload Results
        uses: actions/upload-artifact@v2
        with:
          name: test-results
          path: test-results/
```

---

## Skills 命令映射表

| Skill | 常用操作 | 对应 MCP 命令 |
|-------|---------|--------------|
| ios-form-filling | fillTextField | ui.input |
| ios-form-filling | toggleSwitch | ui.control.sendAction |
| ios-form-filling | dismissKeyboard | ui.keyboard.dismiss |
| ios-navigation | tapButton | ui.tap |
| ios-navigation | navigateBack | ui.navigation.back |
| ios-alert-handling | respondToAlert | ui.alert.respond |
| ios-list-interaction | scrollToItem | ui.scroll |
| ios-list-interaction | swipeCell | ui.swipe |
| ios-screenshot | capture | ui.screenshot |

---

## 完整示例：端到端购物流程

### 自然语言版本

```
测试 iOS App 的完整购物流程：

1. 在搜索框输入 "iPhone 手机壳"
2. 点击第一个搜索结果
3. 滑动查看商品详情
4. 点击 "加入购物车" 按钮
5. 如果弹出尺寸选择，选择 "通用"
6. 点击 "确认"
7. 截图保存购物车页面
8. 点击 "去结算"
9. 验证是否到达结算页面

App 在模拟器运行，端口 38321
```

### 结构化版本

```json
{
  "testCase": {
    "id": "SHOPPING_E2E_001",
    "name": "Complete Shopping Flow",
    "steps": [
      {
        "stepId": 1,
        "skill": "ios-form-filling",
        "action": "fillSearchField",
        "params": {
          "identifier": "search_field",
          "text": "iPhone 手机壳"
        }
      },
      {
        "stepId": 2,
        "skill": "ios-list-interaction",
        "action": "tapFirstItem",
        "params": {
          "listIdentifier": "search_results"
        }
      },
      {
        "stepId": 3,
        "skill": "ios-gestures",
        "action": "swipe",
        "params": {
          "direction": "up",
          "distance": 0.5
        }
      },
      {
        "stepId": 4,
        "skill": "ios-navigation",
        "action": "tap",
        "params": {
          "text": "加入购物车"
        }
      },
      {
        "stepId": 5,
        "skill": "ios-alert-handling",
        "action": "respondIfPresent",
        "params": {
          "buttonText": "通用",
          "timeout": 2000
        }
      },
      {
        "stepId": 6,
        "skill": "ios-alert-handling",
        "action": "respond",
        "params": {
          "buttonText": "确认"
        }
      },
      {
        "stepId": 7,
        "skill": "ios-screenshot",
        "action": "capture",
        "params": {
          "filename": "shopping-cart-{timestamp}.png"
        }
      },
      {
        "stepId": 8,
        "skill": "ios-navigation",
        "action": "tap",
        "params": {
          "text": "去结算"
        }
      },
      {
        "stepId": 9,
        "skill": "ios-navigation",
        "action": "verify",
        "params": {
          "title": "结算",
          "timeout": 5000
        }
      }
    ],
    "assertions": [
      {
        "type": "screenshot_exists",
        "file": "shopping-cart-*.png"
      },
      {
        "type": "navigation_title",
        "value": "结算"
      }
    ]
  }
}
```

---

## 总结

### 自然语言方式
- ✅ 简单直观，适合手动测试
- ✅ 快速验证功能
- ✅ 无需学习复杂格式

### 结构化方式
- ✅ 可重复执行
- ✅ 易于集成测试平台
- ✅ 支持批量测试
- ✅ 结果标准化

两种方式可以互补使用，根据场景选择最合适的方式。
