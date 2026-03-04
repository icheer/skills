---
name: daily-news
description: Create daily news briefings from the topurl.cn API. Fetch and format news, weather, history, idioms, poems, and daily quotes into a plain text summary. Use when the user asks for daily news, today's briefing, or when they want to generate a news summary. The output is plain text format, ready to copy and share.
---

# Daily News

## Overview

This skill provides tools to fetch daily news, weather, history events, idioms, poems, and daily quotes from the topurl.cn API and generate a **plain text briefing**. The briefing includes:

- Weather forecast for major cities
- Top 12 news stories intelligently selected and de-duplicated
- 3 historical events from this day
- Daily idiom (成语) with explanation
- Daily inspirational quote
- Daily progress bar for the current year

## How It Works

### Fetch News Data

Use `fetch_news.py` to retrieve **full dataset** from the API (only need to call once):

```bash
# Default: fetch full dataset with ip=202.106.0.20 (magic key)
python3 fetch_news.py

# Fetch with custom count (if needed)
python3 fetch_news.py --count 80
```

**Important**: 
- Using `--ip 202.106.0.20` is the "magic key" to get complete news and history data
- Default settings already include this IP, so no extra parameters needed
- **Category filtering is done locally** by `generate_briefing.py`, not by API
- **Only call the API once** to minimize server load

### Generate Plain Text Briefing

Use `generate_briefing.py` to convert the JSON data into formatted **plain text**:

```bash
# First fetch the data
python3 fetch_news.py > news_data.json

# Then generate plain text from the JSON
python3 generate_briefing.py news_data.json
```

**Important**: The output is **plain text** (NOT HTML or Markdown), designed for easy copying and sharing in chat apps, emails, or social media.

### Combined Workflow

For a complete workflow (recommended):

```bash
# One-time API call to fetch full dataset
python3 fetch_news.py > today.json

# Generate briefing from cached data (can run multiple times)
python3 generate_briefing.py today.json
```

You can also pipe the output:

```bash
python3 fetch_news.py | python3 generate_briefing.py
```

## API Details

### Endpoint
`https://news.topurl.cn/api`

### Parameters
- `ip`: IP address for weather location (default: **202.106.0.20** - the "magic key" for full dataset)
- `count`: Number of news items to fetch (default: **60** for full dataset)

**Note**: The API is designed to be called **once per day** with the magic IP to get complete data. All filtering and processing should be done locally.

### Response Structure

The API returns a JSON object with:

- `calendar`: Chinese lunar/civil calendar data
- `newsList`: Array of news items with title, URL, category, and importance score (0-100)
- `historyList`: Historical events from this day
- `phrase`: Daily idiom (成语) with explanation
- `sentence`: Daily inspirational quote
- `weather`: Weather information by city

### News Selection Algorithm

The `generate_briefing.py` script uses an intelligent editorial algorithm:
- **De-duplication**: Removes similar news (60% title similarity threshold)
- **Balanced sampling**: Ensures diversity across categories (时事/国内/国际/商业)
- **Score-based ranking**: Prioritizes high-importance news (score 0-100)
- **Corner case handling**: Adapts when total news count is low (weekends)

## Output Format

The script generates **plain text** in the following format:

```
慧语简报，1月29日星期四，农历腊月十一，工作愉快，平安喜乐

今天北京多云，-4 ~ 1℃，西南

1．特朗普酝酿对伊朗高层动手，伊朗警告发动史无前例报复；
2．缅北明家犯罪集团案11名罪犯被执行死刑；
3．中期选举亮红灯，特朗普就移民执法态度日趋软化；
...（共12条）

【历史上的今天】
1906年1月29日，电影在京城大受欢迎。
...（共3条）

【天天成语】
博而不精
释义：形容学识丰富，但不精深。
...

【慧语香风】
我们不但要提出任务，而且要解决完成任务的方法问题。
—— 毛泽东

【进度条】
▓░░░░░░░░░░░░░ 2026年，您已经使用了7.95%

(由 http://news.topurl.cn 采集整理)
```

**DO NOT** format the output as HTML or Markdown. The output must be plain text only.

## Examples

**Example 1: Standard Daily Workflow (Recommended)**

```bash
# Step 1: Fetch full dataset (once per day)
python3 fetch_news.py > today.json

# Step 2: Generate briefing (can run multiple times)
python3 generate_briefing.py today.json
```

**Example 2: Direct Output**

```bash
# Fetch and generate in one command
python3 fetch_news.py | python3 generate_briefing.py
```

## Resources

### scripts/
- `fetch_news.py` - Fetch full dataset from the API (call once per day with magic IP)
- `generate_briefing.py` - Generate plain text briefing from JSON data (local processing)

### references/
None

### assets/
None
