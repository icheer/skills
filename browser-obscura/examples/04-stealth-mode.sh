#!/usr/bin/env bash
# 示例 4: 隐身模式

echo "=== 隐身模式示例 ==="
echo ""

# 1. 基础隐身模式
echo "1. 启用隐身模式:"
obscura --stealth fetch https://example.com \
  --eval "({
    userAgent: navigator.userAgent,
    webdriver: navigator.webdriver,
    languages: navigator.languages,
    platform: navigator.platform
  })" \
  --quiet
echo ""

# 2. 隐身模式 + 自定义 User-Agent
echo "2. 隐身模式 + 自定义 UA:"
obscura --stealth \
  --user-agent "Mozilla/5.0 (iPhone; CPU iPhone OS 14_0 like Mac OS X) AppleWebKit/537.36" \
  fetch https://example.com \
  --eval "navigator.userAgent" \
  --quiet
echo ""

# 3. 隐身模式 + 代理 (如果配置了代理)
if [ -n "$HTTP_PROXY" ]; then
  echo "3. 隐身模式 + 代理:"
  obscura --stealth --proxy "$HTTP_PROXY" \
    fetch https://api.ipify.org?format=json \
    --dump text \
    --quiet
  echo ""
else
  echo "3. 隐身模式 + 代理: (跳过 - 未配置代理)"
  echo "   提示: 设置 HTTP_PROXY 环境变量来测试"
  echo ""
fi

# 4. 隐身模式 + 持久化会话
echo "4. 隐身模式 + 持久化会话:"
SESSION_DIR="/tmp/obscura-stealth-session"
obscura --stealth --storage-dir "$SESSION_DIR" \
  fetch https://example.com \
  --dump cookies \
  --quiet | jq 'length'
echo "  ↑ 保存的 cookie 数量"
rm -rf "$SESSION_DIR"
echo ""

echo "✅ 隐身模式示例完成"
