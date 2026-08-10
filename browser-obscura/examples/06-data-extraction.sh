#!/usr/bin/env bash
# 示例 6: 数据提取管道

echo "=== 数据提取管道示例 ==="
echo ""

OUTPUT_DIR="./extracted-data"
mkdir -p "$OUTPUT_DIR"

# 目标: 从 Hacker News 提取头条新闻

# 第 1 步: 获取首页所有文章链接
echo "步骤 1: 获取文章列表"
obscura fetch https://news.ycombinator.com \
  --eval "
    Array.from(document.querySelectorAll('.athing'))
      .slice(0, 5)
      .map(row => {
        const titleLink = row.querySelector('.titleline > a');
        const id = row.id;
        return {
          id: id,
          title: titleLink ? titleLink.textContent : '',
          url: titleLink ? titleLink.href : '',
          commentUrl: 'https://news.ycombinator.com/item?id=' + id
        };
      })
  " \
  --quiet > "$OUTPUT_DIR/articles.json"

echo "✓ 已保存文章列表到 articles.json"
echo ""

# 第 2 步: 显示提取的数据
echo "步骤 2: 文章摘要"
jq -r '.[] | "- \(.title)\n  \(.url)"' "$OUTPUT_DIR/articles.json"
echo ""

# 第 3 步: 提取评论页面的链接
echo "步骤 3: 提取评论页面 URL"
jq -r '.[].commentUrl' "$OUTPUT_DIR/articles.json" > "$OUTPUT_DIR/comment_urls.txt"
echo "✓ 已保存 $(wc -l < "$OUTPUT_DIR/comment_urls.txt") 个评论页面 URL"
echo ""

# 第 4 步: 批量获取评论数
echo "步骤 4: 批量获取评论统计"
cat "$OUTPUT_DIR/comment_urls.txt" | obscura scrape - \
  --concurrency 5 \
  --eval "({
    url: location.href,
    commentCount: document.querySelectorAll('.commtext').length,
    title: document.querySelector('.athing .titleline')?.textContent || 'N/A'
  })" \
  --format json \
  --quiet > "$OUTPUT_DIR/comment_stats.json"

echo "✓ 已保存评论统计"
echo ""

# 第 5 步: 生成报告
echo "步骤 5: 生成汇总报告"
{
  echo "# Hacker News 数据提取报告"
  echo ""
  echo "提取时间: $(date)"
  echo ""
  echo "## 文章列表"
  echo ""
  jq -r '.[] | "### \(.title)\n- URL: \(.url)\n- HN讨论: \(.commentUrl)\n"' "$OUTPUT_DIR/articles.json"
  echo ""
  echo "## 评论统计"
  echo ""
  jq -r '.[] | "- \(.title): \(.commentCount) 条评论"' "$OUTPUT_DIR/comment_stats.json"
} > "$OUTPUT_DIR/report.md"

echo "✓ 已生成报告: report.md"
echo ""

echo "✅ 数据提取完成"
echo ""
echo "输出文件:"
ls -lh "$OUTPUT_DIR"
echo ""
echo "查看报告:"
echo "  cat $OUTPUT_DIR/report.md"
