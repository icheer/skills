#!/usr/bin/env bash
# 示例 5: 网页监控

echo "=== 网页监控示例 ==="
echo ""

MONITOR_URL="${1:-https://example.com}"
OUTPUT_DIR="./monitoring"
INTERVAL=10  # 秒
MAX_SNAPSHOTS=3

mkdir -p "$OUTPUT_DIR"

echo "监控目标: $MONITOR_URL"
echo "快照间隔: ${INTERVAL}秒"
echo "快照次数: $MAX_SNAPSHOTS"
echo ""

for i in $(seq 1 $MAX_SNAPSHOTS); do
  TIMESTAMP=$(date +%Y%m%d_%H%M%S)
  echo "[$i/$MAX_SNAPSHOTS] 创建快照: $TIMESTAMP"

  # 1. 保存 HTML
  obscura fetch "$MONITOR_URL" \
    --dump html \
    --quiet > "$OUTPUT_DIR/snapshot_${TIMESTAMP}.html"

  # 2. 保存截图
  obscura fetch "$MONITOR_URL" \
    --screenshot "$OUTPUT_DIR/snapshot_${TIMESTAMP}.png" \
    --quiet

  # 3. 提取关键指标
  obscura fetch "$MONITOR_URL" \
    --eval "({
      timestamp: new Date().toISOString(),
      title: document.title,
      bodyLength: document.body.textContent.length,
      linkCount: document.querySelectorAll('a').length,
      imageCount: document.querySelectorAll('img').length
    })" \
    --quiet > "$OUTPUT_DIR/metrics_${TIMESTAMP}.json"

  echo "  ✓ HTML, 截图, 指标已保存"

  # 等待下一个快照 (最后一次不等待)
  if [ $i -lt $MAX_SNAPSHOTS ]; then
    echo "  等待 ${INTERVAL} 秒..."
    sleep $INTERVAL
  fi
  echo ""
done

echo "✅ 监控完成，共 $MAX_SNAPSHOTS 个快照"
echo ""
echo "快照文件:"
ls -lh "$OUTPUT_DIR"
echo ""
echo "对比变化:"
if [ $MAX_SNAPSHOTS -ge 2 ]; then
  FIRST=$(ls "$OUTPUT_DIR"/snapshot_*.html | head -1)
  LAST=$(ls "$OUTPUT_DIR"/snapshot_*.html | tail -1)
  echo "HTML 大小变化:"
  echo "  第一个: $(wc -c < "$FIRST") 字节"
  echo "  最后一个: $(wc -c < "$LAST") 字节"
fi
