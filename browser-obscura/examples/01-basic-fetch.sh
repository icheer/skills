#!/usr/bin/env bash
# 示例 1: 基础网页内容获取

echo "=== 基础 Fetch 示例 ==="
echo ""

# 1. 获取纯文本内容
echo "1. 获取纯文本:"
obscura fetch https://example.com --dump text --quiet
echo ""

# 2. 获取页面标题
echo "2. 获取页面标题:"
obscura fetch https://example.com --eval "document.title" --quiet
echo ""

# 3. 获取所有链接
echo "3. 获取所有链接 (前 5 个):"
obscura fetch https://example.com --dump links --quiet | head -5
echo ""

# 4. 转换为 Markdown
echo "4. 转换为 Markdown (保存到文件):"
obscura fetch https://example.com --dump markdown -o example.md --quiet
echo "✓ 已保存到 example.md"
echo ""

# 5. 提取结构化数据
echo "5. 提取结构化数据:"
obscura fetch https://news.ycombinator.com --eval "
Array.from(document.querySelectorAll('.titleline > a'))
  .slice(0, 5)
  .map(a => ({ title: a.textContent.trim(), url: a.href }))
" --quiet
echo ""

echo "✅ 基础示例完成"
