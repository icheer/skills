#!/usr/bin/env bash
# 实用工具: API 端点发现

URL="${1}"

if [ -z "$URL" ]; then
  echo "用法: $0 <URL>"
  echo ""
  echo "示例:"
  echo "  $0 https://example.com"
  exit 1
fi

echo "=== API 端点发现工具 ==="
echo ""
echo "目标: $URL"
echo ""

OUTPUT_DIR="./api-discovery_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUTPUT_DIR"

# 1. 提取页面中的所有资源
echo "[1/3] 提取所有外部资源..."
obscura fetch "$URL" --dump assets --quiet > "$OUTPUT_DIR/all_assets.ndjson"
TOTAL_ASSETS=$(wc -l < "$OUTPUT_DIR/all_assets.ndjson")
echo "✓ 找到 $TOTAL_ASSETS 个资源"
echo ""

# 2. 过滤可能的 API 端点
echo "[2/3] 过滤 API 端点..."
jq -r 'select(.url | test("api|graphql|rest|v[0-9]|/data/|/service/"; "i")) | .url' \
  "$OUTPUT_DIR/all_assets.ndjson" | sort -u > "$OUTPUT_DIR/api_candidates.txt"
API_COUNT=$(wc -l < "$OUTPUT_DIR/api_candidates.txt")
echo "✓ 找到 $API_COUNT 个可能的 API 端点"
echo ""

# 3. 分析 API 端点
echo "[3/3] 分析 API 端点..."
{
  echo "# API 端点发现报告"
  echo ""
  echo "目标 URL: $URL"
  echo "扫描时间: $(date)"
  echo ""
  echo "## 发现的 API 端点 ($API_COUNT 个)"
  echo ""

  if [ $API_COUNT -gt 0 ]; then
    cat "$OUTPUT_DIR/api_candidates.txt" | while read -r api_url; do
      echo "- \`$api_url\`"
    done
  else
    echo "未发现明显的 API 端点"
  fi

  echo ""
  echo "## 所有资源统计"
  echo ""
  echo "- 总资源数: $TOTAL_ASSETS"
  echo "- API 候选: $API_COUNT"
  echo ""
  echo "## 资源类型分布"
  echo ""
  jq -r '.url' "$OUTPUT_DIR/all_assets.ndjson" | sed 's/.*\.//' | sort | uniq -c | sort -rn | head -10 | while read count ext; do
    echo "- .$ext: $count"
  done

} > "$OUTPUT_DIR/report.md"

echo "✓ 分析完成"
echo ""

# 显示结果
echo "✅ 发现 $API_COUNT 个可能的 API 端点"
echo ""
if [ $API_COUNT -gt 0 ]; then
  echo "API 端点列表:"
  cat "$OUTPUT_DIR/api_candidates.txt"
  echo ""
fi

echo "完整报告已保存到: $OUTPUT_DIR/report.md"
echo ""
echo "查看报告:"
echo "  cat $OUTPUT_DIR/report.md"
