#!/usr/bin/env bash
# 实用工具: 新闻监控

URLS_FILE="${1:-./news-urls.txt}"
INTERVAL="${2:-600}"  # 默认 10 分钟
OUTPUT_DIR="./news-monitoring"

if [ ! -f "$URLS_FILE" ]; then
  echo "错误: 找不到 URL 文件: $URLS_FILE"
  echo ""
  echo "用法: $0 [URL文件] [间隔秒数]"
  echo ""
  echo "请创建一个包含 URL 的文件，每行一个 URL"
  echo ""
  echo "示例:"
  echo "  cat > news-urls.txt << EOF"
  echo "https://news.ycombinator.com"
  echo "https://reddit.com/r/programming"
  echo "https://dev.to"
  echo "EOF"
  echo ""
  echo "  $0 news-urls.txt 300"
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

echo "=== 新闻监控工具 ==="
echo ""
echo "监控来源: $(wc -l < "$URLS_FILE") 个网站"
echo "检查间隔: ${INTERVAL} 秒 ($(($INTERVAL / 60)) 分钟)"
echo "输出目录: $OUTPUT_DIR"
echo ""
echo "按 Ctrl+C 停止监控"
echo ""

ITERATION=0

while true; do
  ITERATION=$((ITERATION + 1))
  TIMESTAMP=$(date +%Y%m%d_%H%M%S)

  echo "[$(date)] 开始第 $ITERATION 次扫描..."

  # 批量抓取所有新闻源
  cat "$URLS_FILE" | obscura scrape - \
    --concurrency 5 \
    --timeout 30 \
    --eval "({
      url: location.href,
      title: document.title,
      timestamp: '${TIMESTAMP}',
      headlines: Array.from(document.querySelectorAll('h1, h2, h3, .title, .titleline > a'))
        .slice(0, 10)
        .map(h => h.textContent.trim())
        .filter(t => t.length > 0)
    })" \
    --format json \
    --quiet > "$OUTPUT_DIR/snapshot_${TIMESTAMP}.json"

  # 检查是否成功
  if [ $? -eq 0 ]; then
    HEADLINE_COUNT=$(jq '[.[].headlines | length] | add' "$OUTPUT_DIR/snapshot_${TIMESTAMP}.json")
    echo "✓ 已保存快照 (共 $HEADLINE_COUNT 条标题)"

    # 提取新标题 (与上一次对比)
    if [ $ITERATION -gt 1 ]; then
      PREV_FILE=$(ls -t "$OUTPUT_DIR"/snapshot_*.json | sed -n 2p)
      if [ -n "$PREV_FILE" ]; then
        echo "  检查新标题..."
        # 这里可以添加更复杂的对比逻辑
      fi
    fi
  else
    echo "✗ 扫描失败"
  fi

  echo "  等待 ${INTERVAL} 秒后进行下一次扫描..."
  echo ""

  sleep "$INTERVAL"
done
