#!/usr/bin/env python3
"""Generate plain text briefing from geek news data."""

import json
import sys
import difflib
from datetime import datetime


def is_similar(title1, title2, threshold=0.6):
    """Check if two titles are similar (for de-duplication)."""
    return difflib.SequenceMatcher(None, title1, title2).ratio() > threshold


def deduplicate_and_sort(news_list, top_n=50):
    """
    Sort by ai_score, take top N, and remove similar titles.

    Args:
        news_list: List of news items
        top_n: Number of items to keep after sorting (default: 50)

    Returns:
        List of deduplicated and sorted news items
    """
    if not news_list:
        return []

    # Sort by ai_score descending (0-1, higher is more important)
    sorted_news = sorted(
        news_list,
        key=lambda x: x.get('ai_score') or 0,
        reverse=True
    )

    # Take top N
    top_news = sorted_news[:top_n]

    # De-duplicate by similar titles
    result = []
    seen_titles = []

    for news in top_news:
        title = news.get('ai_title', '').strip()
        if not title:
            continue

        # Check similarity with already selected titles
        is_duplicate = False
        for seen in seen_titles:
            if is_similar(title, seen):
                is_duplicate = True
                break

        if not is_duplicate:
            result.append(news)
            seen_titles.append(title)

    return result


def truncate(text, max_length=150):
    """Truncate text to max_length, add ellipsis if needed."""
    if not text:
        return ''
    text = text.strip()
    if len(text) <= max_length:
        return text
    return text[:max_length].rstrip() + '...'


def generate_text(data, count=12):
    """
    Generate plain text briefing from JSON data.

    Args:
        data: Parsed JSON data from API
        count: Number of news items to include (default: 12)

    Returns:
        Plain text string
    """
    if not data:
        return "无法获取数据"

    if data.get('error'):
        return f"获取数据失败: {data.get('error')}"

    if not data.get('success'):
        return "API 返回错误"

    news_list = data.get('data', [])
    if not news_list:
        return "暂无资讯数据"

    # De-duplicate and sort, keep top 50
    processed = deduplicate_and_sort(news_list, top_n=50)

    # Take requested count
    selected = processed[:count]

    # Generate output
    now = datetime.now()
    date_str = now.strftime('%Y年%-m月%-d日')

    lines = []
    lines.append(f"极客日报 · {date_str}")
    lines.append("")

    for i, news in enumerate(selected, 1):
        title = news.get('ai_title', '').strip()
        tags = news.get('ai_tags', [])
        abstract = truncate(news.get('ai_abstract', ''), 120)
        url = news.get('url', '')

        lines.append(f"{i}. {title}")

        # Tags - keep original format (with # prefix)
        if tags:
            tag_str = ' '.join(tags)
            lines.append(f"   {tag_str}")

        if abstract:
            lines.append(f"   {abstract}")

        if url:
            lines.append(f"   {url}")

        lines.append("")

    lines.append(f"（由 https://geek.keyi.ma 采集整理）")

    return '\n'.join(lines)


def main():
    try:
        # Read from stdin or file argument
        if len(sys.argv) < 2:
            data = json.load(sys.stdin)
        else:
            with open(sys.argv[1], 'r', encoding='utf-8') as f:
                data = json.load(f)

        # Check for count argument
        count = 12
        if len(sys.argv) >= 3:
            try:
                count = int(sys.argv[2])
            except ValueError:
                pass

        print(generate_text(data, count))
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)


if __name__ == "__main__":
    main()
