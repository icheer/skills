#!/usr/bin/env bash
# 示例 2: 批量抓取

echo "=== 批量抓取示例 ==="
echo ""

# 准备测试 URL
URLS=(
  "https://example.com"
  "https://www.ietf.org"
  "https://www.w3.org"
)

# 1. 批量获取标题
echo "1. 批量获取页面标题:"
obscura scrape "${URLS[@]}" \
  --eval "document.title" \
  --concurrency 3 \
  --format json \
  --quiet
echo ""

# 2. 批量提取元数据
echo "2. 批量提取元数据:"
obscura scrape "${URLS[@]}" \
  --eval "({
    title: document.title,
    url: location.href,
    linkCount: document.querySelectorAll('a').length,
    hasH1: !!document.querySelector('h1')
  })" \
  --concurrency 3 \
  --format json \
  --quiet
echo ""

# 3. 从文件读取 URL
echo "3. 从文件读取 URL:"
printf "%s\n" "${URLS[@]}" > /tmp/urls.txt
cat /tmp/urls.txt | obscura scrape - \
  --eval "({ url: location.href, title: document.title })" \
  --concurrency 3 \
  --format json \
  --quiet
rm /tmp/urls.txt
echo ""

echo "✅ 批量抓取示例完成"
