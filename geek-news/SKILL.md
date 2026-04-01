---
name: geek-news
description: Fetch and summarize Hacker News based geek news from geek.keyi.ma API. Use when the user asks for "极客日报", "geek news", "科技简报", "HN news summary", or wants to get a daily digest of hard-core tech news. This skill fetches AI-curated tech news and generates plain text briefings.
---

# Geek News (极客日报)

## Overview

This skill fetches curated tech news from geek.keyi.ma and generates plain text briefings. The data comes from Hacker News with AI-generated titles, abstracts, and tags.

## Usage

### Standard Workflow

```bash
# Fetch and generate default 12 items
python3 fetch_news.py | python3 generate_briefing.py

# Fetch to file first (recommended for caching)
python3 fetch_news.py > today.json

# Generate with custom count
python3 generate_briefing.py today.json 20
```

### Output Format

The briefing is **plain text only** — no Markdown, no HTML:

```
极客日报 · 2026年3月31日

1. 紧急：Axios库在NPM遭劫持，恶意版本植入跨平台木马
   HackerNews 网络安全 软件工程与开发
   流行HTTP库axios的维护者账号遭入侵，攻击者发布了包含恶意依赖的1.14.1和0.30.4版本...
   https://...

2. Google 披露量子计算安全风险，推动加密货币向 PQC 迁移
   ...
```

**DO NOT** format the output as HTML or Markdown. The output must be plain text only.
**DO NOT** add extra introductions or conclusions, **DO NOT** add unnecessary dividers or markdown formatting.
Just output the briefing content directly.

## API Details

- **Endpoint**: `https://geek.keyi.ma/api/news`
- **Method**: GET (no parameters)
- **Response**: `{"success": true, "data": [...]}`

### Data Fields

| Field | Description |
|-------|-------------|
| `ai_title` | AI-generated title |
| `ai_tags` | Array of tags (e.g., ["#HackerNews", "#网络安全"]) |
| `ai_abstract` | AI-generated summary |
| `ai_score` | Importance score (0-1, higher = more important) |
| `url` | Original article link |
| `created_at` | Publication timestamp |

## Processing Logic

1. **Sort**: By `ai_score` descending (most important first)
2. **Limit**: Top 50 items after sorting
3. **De-duplicate**: Remove items with similar titles (>60% similarity)
4. **Output**: Take requested count (default 12) from deduplicated list

## Customization

### Change Output Count

```bash
# Generate 20 items
python3 generate_briefing.py today.json 20
```

## Resources

### scripts/
- `fetch_news.py` - Fetch data from API
- `generate_briefing.py` - Generate plain text briefing

### references/
None

### assets/
None
