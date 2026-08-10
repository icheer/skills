#!/usr/bin/env bash
# 实用工具: 网页完整归档

URL="${1}"
OUTPUT_DIR="${2:-./archive_$(date +%Y%m%d_%H%M%S)}"

if [ -z "$URL" ]; then
  echo "用法: $0 <URL> [输出目录]"
  echo ""
  echo "示例:"
  echo "  $0 https://example.com"
  echo "  $0 https://example.com ./my-archive"
  exit 1
fi

echo "=== 网页归档工具 ==="
echo ""
echo "目标 URL: $URL"
echo "输出目录: $OUTPUT_DIR"
echo ""

# 创建输出目录
mkdir -p "$OUTPUT_DIR"

# 1. 保存原始 HTML
echo "[1/7] 保存原始 HTML..."
obscura fetch "$URL" --dump original --quiet > "$OUTPUT_DIR/original.html"
echo "✓ original.html"

# 2. 保存渲染后的 HTML
echo "[2/7] 保存渲染后的 HTML..."
obscura fetch "$URL" --dump html --quiet > "$OUTPUT_DIR/rendered.html"
echo "✓ rendered.html"

# 3. 保存纯文本
echo "[3/7] 保存纯文本..."
obscura fetch "$URL" --dump text --quiet > "$OUTPUT_DIR/page.txt"
echo "✓ page.txt"

# 4. 保存 Markdown
echo "[4/7] 保存 Markdown..."
obscura fetch "$URL" --dump markdown --quiet > "$OUTPUT_DIR/page.md"
echo "✓ page.md"

# 5. 保存截图
echo "[5/7] 保存截图..."
obscura fetch "$URL" --wait-until networkidle0 --screenshot "$OUTPUT_DIR/screenshot.png" --quiet 2>/dev/null || echo "⚠ 截图失败 (可能需要渲染功能)"
if [ -f "$OUTPUT_DIR/screenshot.png" ]; then
  echo "✓ screenshot.png"
fi

# 6. 保存链接
echo "[6/7] 保存所有链接..."
obscura fetch "$URL" --dump links --quiet > "$OUTPUT_DIR/links.txt"
echo "✓ links.txt ($(wc -l < "$OUTPUT_DIR/links.txt") 个链接)"

# 7. 保存资源列表
echo "[7/7] 保存资源列表..."
obscura fetch "$URL" --dump assets --quiet > "$OUTPUT_DIR/assets.ndjson"
echo "✓ assets.ndjson ($(wc -l < "$OUTPUT_DIR/assets.ndjson") 个资源)"

# 8. 保存元数据
echo ""
echo "生成元数据..."
obscura fetch "$URL" --eval "({
  url: location.href,
  title: document.title,
  timestamp: new Date().toISOString(),
  charset: document.characterSet,
  linkCount: document.querySelectorAll('a').length,
  imageCount: document.querySelectorAll('img').length,
  scriptCount: document.querySelectorAll('script').length
})" --quiet > "$OUTPUT_DIR/metadata.json"
echo "✓ metadata.json"

# 生成索引文件
cat > "$OUTPUT_DIR/index.txt" << EOF
网页归档 - $(date)
========================================

URL: $URL
归档时间: $(date +"%Y-%m-%d %H:%M:%S")

文件列表:
$(ls -lh "$OUTPUT_DIR" | tail -n +2)

元数据:
$(cat "$OUTPUT_DIR/metadata.json" | jq '.')
EOF

echo ""
echo "✅ 归档完成!"
echo ""
echo "文件列表:"
ls -lh "$OUTPUT_DIR"
echo ""
echo "查看索引: cat $OUTPUT_DIR/index.txt"
