#!/usr/bin/env bash
# 示例 3: 页面截图

echo "=== 截图示例 ==="
echo ""

OUTPUT_DIR="./screenshots"
mkdir -p "$OUTPUT_DIR"

# 1. 基础截图
echo "1. 基础截图:"
obscura fetch https://example.com \
  --screenshot "$OUTPUT_DIR/example.png" \
  --quiet
echo "✓ 已保存: $OUTPUT_DIR/example.png"
echo ""

# 2. 等待加载完成后截图
echo "2. 等待网络空闲后截图:"
obscura fetch https://news.ycombinator.com \
  --wait-until networkidle0 \
  --screenshot "$OUTPUT_DIR/hn.png" \
  --quiet
echo "✓ 已保存: $OUTPUT_DIR/hn.png"
echo ""

# 3. 延迟后截图 (等待动画/JS)
echo "3. 延迟 2 秒后截图:"
obscura fetch https://example.com \
  --wait 2 \
  --screenshot "$OUTPUT_DIR/delayed.png" \
  --quiet
echo "✓ 已保存: $OUTPUT_DIR/delayed.png"
echo ""

# 4. 滚动后截图
echo "4. 滚动到底部后截图:"
obscura fetch https://example.com \
  --eval "window.scrollTo(0, document.body.scrollHeight)" \
  --screenshot "$OUTPUT_DIR/scrolled.png" \
  --quiet
echo "✓ 已保存: $OUTPUT_DIR/scrolled.png"
echo ""

echo "✅ 所有截图已保存到 $OUTPUT_DIR/"
ls -lh "$OUTPUT_DIR"
