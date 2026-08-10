#!/usr/bin/env bash
# 实用工具: 隐身爬虫

URL="${1}"
PROXY="${2:-${SOCKS5_PROXY}}"  # 从参数或环境变量获取
OUTPUT_DIR="./stealth-crawl_$(date +%Y%m%d_%H%M%S)"
SESSION_DIR="$OUTPUT_DIR/session"

if [ -z "$URL" ]; then
  echo "用法: $0 <URL> [代理地址]"
  echo ""
  echo "示例:"
  echo "  $0 https://example.com"
  echo "  $0 https://example.com socks5://user:pass@proxy.example.com:1080"
  echo ""
  echo "或设置环境变量:"
  echo "  export SOCKS5_PROXY=socks5://user:pass@proxy.example.com:1080"
  echo "  $0 https://example.com"
  exit 1
fi

mkdir -p "$OUTPUT_DIR" "$SESSION_DIR"

echo "=== 隐身爬虫工具 ==="
echo ""
echo "目标: $URL"
echo "代理: ${PROXY:-未使用}"
echo "输出: $OUTPUT_DIR"
echo ""

# 构建基础命令
BASE_CMD="obscura --stealth --storage-dir $SESSION_DIR"
if [ -n "$PROXY" ]; then
  BASE_CMD="$BASE_CMD --proxy $PROXY"
fi

# 自定义 User-Agent (模拟真实浏览器)
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
BASE_CMD="$BASE_CMD --user-agent '$UA'"

# 1. 初始访问
echo "[1/5] 初始访问 (建立会话)..."
eval "$BASE_CMD fetch '$URL' --wait 3 --dump text --quiet" > "$OUTPUT_DIR/page.txt"
echo "✓ 会话已建立"
sleep $(( RANDOM % 3 + 2 ))  # 随机延迟 2-5 秒
echo ""

# 2. 获取页面元数据
echo "[2/5] 提取页面元数据..."
eval "$BASE_CMD fetch '$URL' --eval \"({
  url: location.href,
  title: document.title,
  userAgent: navigator.userAgent,
  webdriver: navigator.webdriver,
  languages: navigator.languages,
  platform: navigator.platform,
  linkCount: document.querySelectorAll('a').length
})\" --quiet" > "$OUTPUT_DIR/metadata.json"
echo "✓ 元数据已保存"
sleep $(( RANDOM % 3 + 2 ))
echo ""

# 3. 保存 HTML
echo "[3/5] 保存 HTML..."
eval "$BASE_CMD fetch '$URL' --dump html --quiet" > "$OUTPUT_DIR/page.html"
echo "✓ HTML 已保存"
sleep $(( RANDOM % 3 + 2 ))
echo ""

# 4. 截图
echo "[4/5] 保存截图..."
eval "$BASE_CMD fetch '$URL' --wait-until networkidle0 --screenshot '$OUTPUT_DIR/screenshot.png' --quiet" 2>/dev/null || echo "⚠ 截图失败"
if [ -f "$OUTPUT_DIR/screenshot.png" ]; then
  echo "✓ 截图已保存"
fi
sleep $(( RANDOM % 3 + 2 ))
echo ""

# 5. 导出 cookies
echo "[5/5] 导出 cookies..."
eval "$BASE_CMD fetch '$URL' --dump cookies --quiet" > "$OUTPUT_DIR/cookies.json"
COOKIE_COUNT=$(jq 'length' "$OUTPUT_DIR/cookies.json")
echo "✓ 已导出 $COOKIE_COUNT 个 cookies"
echo ""

# 生成报告
{
  echo "# 隐身爬虫报告"
  echo ""
  echo "目标 URL: $URL"
  echo "爬取时间: $(date)"
  echo "使用代理: ${PROXY:-否}"
  echo ""
  echo "## 浏览器指纹"
  echo ""
  echo '```json'
  cat "$OUTPUT_DIR/metadata.json" | jq '.'
  echo '```'
  echo ""
  echo "## Cookies"
  echo ""
  echo "- 总数: $COOKIE_COUNT"
  echo ""
  if [ $COOKIE_COUNT -gt 0 ]; then
    echo "Cookie 列表:"
    jq -r '.[] | "- \(.name): \(.domain)"' "$OUTPUT_DIR/cookies.json"
  fi
  echo ""
  echo "## 文件"
  echo ""
  ls -lh "$OUTPUT_DIR" | tail -n +2 | awk '{print "- " $9 " (" $5 ")"}'
} > "$OUTPUT_DIR/report.md"

echo "✅ 爬取完成!"
echo ""
echo "文件列表:"
ls -lh "$OUTPUT_DIR"
echo ""
echo "查看报告: cat $OUTPUT_DIR/report.md"
