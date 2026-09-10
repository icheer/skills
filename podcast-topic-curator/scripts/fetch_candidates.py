#!/usr/bin/env python3
"""Fetch and compress geek.news candidates for podcast topic curation.

Stdout: one compact JSON document.
Stderr: human-readable diagnostics.
No files are created.
"""

from __future__ import annotations

import argparse
import difflib
import json
import re
import sys
import urllib.error
import urllib.request
from collections import Counter

API_URL = "https://geek.keyi.ma/api/news"

# Broad enough to preserve cross-domain material, but narrow enough to avoid
# placing all 300 records in the model context.
KEYWORDS = {
    "AI", "人工智能", "模型", "Agent", "智能体", "软件工程", "编程",
    "开源", "网络安全", "安全", "隐私", "监控", "数据", "芯片", "GPU",
    "云", "基础设施", "自动驾驶", "就业", "教育", "知识", "版权", "许可证",
    "互联网", "浏览器", "WebAssembly", "数学", "科学", "社会", "哲学",
    "垄断", "资本", "能源", "广告", "阅读", "偏见", "责任", "研究",
}


def fetch() -> dict:
    req = urllib.request.Request(
        API_URL,
        headers={
            "User-Agent": "Mozilla/5.0 (compatible; PodcastTopicCurator/1.0)",
            "Accept": "application/json",
        },
    )
    with urllib.request.urlopen(req, timeout=30) as response:
        payload = response.read().decode("utf-8")
    data = json.loads(payload)
    if not isinstance(data, dict) or data.get("success") is not True:
        raise ValueError("API 返回 success 不为 true")
    if not isinstance(data.get("data"), list):
        raise ValueError("API 返回缺少 data 数组")
    return data


def normalized(text: str) -> str:
    return re.sub(r"[^\w\u4e00-\u9fff]+", "", text.lower())


def similarity(a: str, b: str) -> float:
    return difflib.SequenceMatcher(None, normalized(a), normalized(b)).ratio()


def score(item: dict) -> float:
    title = str(item.get("ai_title", ""))
    abstract = str(item.get("ai_abstract", ""))
    points = str(item.get("ai_points", ""))
    tags = " ".join(map(str, item.get("ai_tags", []) or []))
    text = " ".join((title, abstract, points, tags))
    hits = sum(1 for word in KEYWORDS if word.lower() in text.lower())
    tags_lower = tags.lower()
    hacker = 2.0 if "hackernews" in tags_lower else 0.0
    controversy = sum(1 for word in ("争议", "批评", "警告", "隐私", "垄断", "辞职", "责任", "风险", "抢先", "监控") if word in text)
    try:
        importance = float(item.get("ai_score") or 0)
    except (TypeError, ValueError):
        importance = 0.0
    return importance * 4 + hits * 0.45 + controversy * 0.55 + hacker


def compact(item: dict) -> dict:
    fields = ("id", "url", "ai_title", "ai_abstract", "ai_points", "ai_tags", "ai_sector", "ai_score", "created_at")
    return {key: item.get(key) for key in fields}


def select(items: list[dict], limit: int) -> list[dict]:
    ranked = sorted(items, key=score, reverse=True)
    selected: list[dict] = []
    for item in ranked:
        title = str(item.get("ai_title", "")).strip()
        if not title:
            continue
        # Keep different angles on a story only when titles are not near copies.
        if any(similarity(title, str(old.get("ai_title", ""))) >= 0.78 for old in selected):
            continue
        selected.append(item)
        if len(selected) >= limit:
            break
    return selected


def main() -> int:
    parser = argparse.ArgumentParser(description="Fetch compact podcast-topic candidates")
    parser.add_argument("--limit", type=int, default=80)
    args = parser.parse_args()
    if args.limit < 10 or args.limit > 200:
        parser.error("--limit must be between 10 and 200")
    try:
        payload = fetch()
        items = payload["data"]
        tags = Counter(tag for item in items for tag in (item.get("ai_tags") or []))
        selected = select(items, args.limit)
        result = {
            "success": True,
            "source": API_URL,
            "total": len(items),
            "hackernews_count": sum("hackernews" in " ".join(map(str, item.get("ai_tags", []) or [])).lower() for item in items),
            "top_tags": [{"tag": tag, "count": count} for tag, count in tags.most_common(20)],
            "candidate_count": len(selected),
            "items": [compact(item) for item in selected],
        }
        print(json.dumps(result, ensure_ascii=False, separators=(",", ":")))
        print(f"fetched={len(items)} candidates={len(selected)}", file=sys.stderr)
        return 0
    except urllib.error.HTTPError as exc:
        print(f"HTTP error {exc.code}: {exc.reason}", file=sys.stderr)
    except urllib.error.URLError as exc:
        print(f"URL error: {exc.reason}", file=sys.stderr)
    except (TimeoutError, json.JSONDecodeError, ValueError) as exc:
        print(f"data error: {exc}", file=sys.stderr)
    except Exception as exc:  # Keep stdout clean and make failures actionable.
        print(f"unexpected error: {exc}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
