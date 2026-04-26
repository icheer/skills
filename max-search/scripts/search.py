#!/usr/bin/env python3
"""
max-search: Parallel Tavily Search & Result Synthesis
=====================================================
Subcommands:
    search  — Execute parallel Tavily searches and output a synthesis prompt
    config  — Manage Tavily API key (save / view status)

Usage:
    python search.py search --question "用户问题" --search-json '{"search_queries":[...],"num_results":N}'
    python search.py config --set-api-key YOUR_KEY
    python search.py config

Requires:
    - Tavily API key (via env TAVILY_API_KEY or ~/.tavily_api_key)
    - Optional: pip install aiohttp  (falls back to sync urllib if unavailable)
"""

import argparse
import json
import os
import random
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

# ---------------------------------------------------------------------------
# Async / Sync adapter: prefer aiohttp, fall back to urllib + ThreadPool
# ---------------------------------------------------------------------------
try:
    import asyncio
    import aiohttp

    HAS_AIOHTTP = True
except ImportError:
    HAS_AIOHTTP = False
    import urllib.request
    import urllib.error
    from concurrent.futures import ThreadPoolExecutor, as_completed

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
TAVILY_URL = "https://api.tavily.com/search"
TAVILY_KEY_FILE = Path.home() / ".tavily_api_key"
DOTENV_FILE = Path.home() / ".env"

EXCLUDE_DOMAINS = [
    # 中文 — 强烈偏见 / 伪科学
    "ntdtv.com", "ntd.tv", "aboluowang.com", "epochtimes.com", "epochtimes.jp",
    "dafahao.com", "minghui.org", "secretchina.com", "kanzhongguo.com",
    "soundofhope.org", "rfa.org", "bannedbook.org", "boxun.com", "peacehall.com",
    "creaders.net", "backchina.com", "guancha.cn", "wenxuecity.com",
    "awaker.cn", "tuidang.org",
    # 英文 — 极右翼 / 阴谋论
    "breitbart.com", "infowars.com", "naturalnews.com", "globalresearch.ca",
    "zerohedge.com", "thegatewaypundit.com", "newsmax.com", "oann.com",
    "dailywire.com", "theblaze.com", "redstate.com", "thenationalpulse.com",
    "thefederalist.com",
    # 英文 — 极左翼
    "dailykos.com", "alternet.org", "commondreams.org", "thecanary.co",
    "occupydemocrats.com", "truthout.org",
    # 小报 / 低质量
    "dailymail.co.uk", "thesun.co.uk", "nypost.com", "express.co.uk",
    "mirror.co.uk", "dailystar.co.uk",
    # 讽刺 / 虚假
    "theonion.com", "clickhole.com", "babylonbee.com", "newspunch.com",
    "beforeitsnews.com",
    # 俄罗斯国家媒体
    "rt.com", "sputniknews.com", "tass.com",
    # 其他
    "wikileaks.org", "mediabiasfactcheck.com", "allsides.com",
]


# ---------------------------------------------------------------------------
# API Key management
# ---------------------------------------------------------------------------
def _split_keys(raw: str) -> list:
    """Split a raw string by comma or newline, strip whitespace, drop empties."""
    return [k.strip() for k in re.split(r"[,\n]", raw) if k.strip()]


def load_api_keys() -> list:
    """Load all Tavily API keys.

    Priority:
      1. TAVILY_API_KEY environment variable
      2. ~/.env  (standard KEY=VALUE, e.g. TAVILY_API_KEY=key1,key2)
      3. ~/.tavily_api_key  (legacy single-key file)

    Values may be comma- or newline-separated; all non-empty entries are returned.
    """
    # 1. Environment variable
    env_val = os.environ.get("TAVILY_API_KEY", "").strip()
    if env_val:
        keys = _split_keys(env_val)
        if keys:
            return keys

    # 2. ~/.env  (parse the first TAVILY_API_KEY= line found)
    if DOTENV_FILE.exists():
        for line in DOTENV_FILE.read_text(encoding="utf-8").splitlines():
            stripped = line.strip()
            if stripped.startswith("TAVILY_API_KEY="):
                val = stripped[len("TAVILY_API_KEY="):]
                keys = _split_keys(val)
                if keys:
                    return keys

    # 3. ~/.tavily_api_key  (legacy)
    if TAVILY_KEY_FILE.exists():
        raw = TAVILY_KEY_FILE.read_text(encoding="utf-8").strip()
        if raw:
            keys = _split_keys(raw)
            if keys:
                return keys

    return []


def load_api_key() -> Optional[str]:
    """Return a randomly selected API key from all available keys."""
    keys = load_api_keys()
    if not keys:
        return None
    return random.choice(keys)


def save_api_key(key: str) -> None:
    """Save Tavily API key to ~/.tavily_api_key with restricted permissions."""
    cleaned = key.strip()
    TAVILY_KEY_FILE.write_text(cleaned, encoding="utf-8")
    os.chmod(str(TAVILY_KEY_FILE), 0o600)


def mask_key(key: str) -> str:
    """Return a masked version of the key for display, e.g. tvly****abcd."""
    if len(key) <= 8:
        return "****"
    return "{}****{}".format(key[:4], key[-4:])


# ---------------------------------------------------------------------------
# Tavily search — async version
# ---------------------------------------------------------------------------
async def _search_async(
    session: "aiohttp.ClientSession",
    query: str,
    num_results: int,
    api_key: str,
) -> Optional[dict]:
    """Send a single Tavily search request."""
    payload = {
        "query": query,
        "max_results": num_results,
        "include_answer": "basic",
        "auto_parameters": True,
        "exclude_domains": EXCLUDE_DOMAINS,
    }
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {api_key}",
    }
    try:
        async with session.post(
            TAVILY_URL,
            json=payload,
            headers=headers,
            timeout=aiohttp.ClientTimeout(total=30),
        ) as resp:
            if resp.status != 200:
                body = await resp.text()
                print(
                    f'[WARN] Tavily returned HTTP {resp.status} for "{query}": {body}',
                    file=sys.stderr,
                )
                return None
            data = await resp.json()
            data["_query"] = query
            return data
    except asyncio.TimeoutError:
        print(f'[WARN] Timeout for query "{query}"', file=sys.stderr)
        return None
    except Exception as exc:
        print(f'[ERROR] Exception for query "{query}": {exc}', file=sys.stderr)
        return None


async def run_searches_async(
    queries: list, num_results: int, api_key: str
) -> list:
    """Run all searches concurrently."""
    async with aiohttp.ClientSession() as session:
        tasks = [
            _search_async(session, q, num_results, api_key) for q in queries
        ]
        return await asyncio.gather(*tasks)


# ---------------------------------------------------------------------------
# Tavily search — sync fallback
# ---------------------------------------------------------------------------
def _search_sync(
    query: str, num_results: int, api_key: str
) -> Optional[dict]:
    """Fallback: blocking search via urllib."""
    payload = json.dumps(
        {
            "query": query,
            "max_results": num_results,
            "include_answer": "basic",
            "auto_parameters": True,
            "exclude_domains": EXCLUDE_DOMAINS,
        }
    ).encode("utf-8")
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {api_key}",
    }
    req = urllib.request.Request(
        TAVILY_URL, data=payload, headers=headers, method="POST"
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            data["_query"] = query
            return data
    except urllib.error.HTTPError as exc:
        print(
            f'[WARN] Tavily returned HTTP {exc.code} for "{query}"',
            file=sys.stderr,
        )
        return None
    except Exception as exc:
        print(
            f'[ERROR] Exception for query "{query}": {exc}', file=sys.stderr
        )
        return None


def run_searches_sync(
    queries: list, num_results: int, api_key: str
) -> list:
    """Run all searches in a thread pool (fallback)."""
    results = [None] * len(queries)
    with ThreadPoolExecutor(max_workers=min(len(queries), 8)) as pool:
        future_map = {
            pool.submit(_search_sync, q, num_results, api_key): idx
            for idx, q in enumerate(queries)
        }
        for fut in as_completed(future_map):
            results[future_map[fut]] = fut.result()
    return results


# ---------------------------------------------------------------------------
# Result formatting — build the synthesis prompt
# ---------------------------------------------------------------------------
def format_search_context(results: list, queries: list) -> str:
    """Format raw Tavily results into a readable Search_Context block."""
    sections = []
    for idx, res in enumerate(results):
        query_label = queries[idx] if idx < len(queries) else f"Query {idx + 1}"
        if res is None:
            sections.append(
                f'### Query: "{query_label}"\n> ⚠️ Search failed or timed out.\n'
            )
            continue

        answer = res.get("answer", "")
        items = res.get("results", [])
        lines = [f'### Query: "{query_label}"']
        if answer:
            lines.append(f"**Tavily AI Answer**: {answer}\n")
        if not items:
            lines.append("> No results returned.\n")
        for i, item in enumerate(items, 1):
            title = item.get("title", "Untitled")
            url = item.get("url", "")
            content = item.get("content", "").strip()
            score = item.get("score", 0)
            lines.append(f"**[{i}] {title}**  (score: {score:.2f})")
            lines.append(f"URL: {url}")
            lines.append(f"{content}\n")
        sections.append("\n".join(lines))
    return "\n---\n".join(sections)


def compute_stats(results: list) -> tuple:
    """Return (total_queries_ok, total_items, high_relevance_items)."""
    queries_ok = sum(1 for r in results if r is not None)
    total = 0
    high = 0
    for r in results:
        if r is None:
            continue
        for item in r.get("results", []):
            total += 1
            if item.get("score", 0) >= 0.8:
                high += 1
    return queries_ok, total, high


def build_synthesis_prompt(
    user_question: str, results: list, queries: list
) -> str:
    """Assemble the final prompt that the LLM will use to answer the user."""
    now_str = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
    search_context = format_search_context(results, queries)
    queries_ok, total_items, high_items = compute_stats(results)
    num_queries = len(queries)

    prompt = f"""# Role: Expert Research Analyst & Information Synthesizer

## 核心任务
基于下方提供的 **实时搜索结果**（Tavily Search Results），回答用户的原始问题。
像撰写深度调查报告一样，将碎片化的信息拼凑成完整的逻辑链条。

## 输入数据
1. **用户问题**: 见下文 `<User_Question>`
2. **当前时间**: {now_str}（请据此推断"最近"、"今年"等时间词的具体含义）
3. **搜索语料**: 见下文 `<Search_Context>`

## 严格执行原则 (Critical Rules)

### 1. 事实基准 (Grounding)
- **优先权**：搜索语料的权重 **高于** 你的内部训练知识。如果搜索结果与你的记忆冲突（特别是时效性信息），**必须**以搜索结果为准。
- **诚实性**：如果搜索结果中没有包含回答问题所需的关键信息，请明确指出"搜索结果未提及此事"，严禁编造数据。

### 2. "最大化"信息的处理
- 你收到的搜索结果可能覆盖了问题的不同维度（定义、新闻、正反观点等）。
- **不要** 简单罗列结果。
- **要** 进行 **交叉验证** 和 **综合叙述**。例如：将 Source A 的数据与 Source B 的观点结合起来分析。

### 3. 格式要求
- 使用 Markdown 格式。
- 如果信息量大，**必须**使用层级标题、着重号（Bold）和列表。
- 如果涉及对比（如 A vs B），尽量使用 Markdown 表格。

## 回答结构框架

### 0. 搜索语料概况 (Search Overview)
在正式回答前，先输出以下统计（数据已预计算，直接使用）：

> 📊 **搜索概况**：执行了 {num_queries} 次查询（{queries_ok} 次成功），获取 {total_items} 条结果，其中 {high_items} 条高度相关（相关度 ≥ 0.8）

### 1. 直接解答 (The Bottom Line)
用一句话总结核心答案（TL;DR）。

### 2. 关键发现 (Key Findings)
分点详述，整合不同维度的信息。

### 3. 深度解析 (Deep Dive)（视情况而定）
解释背后的原因、背景或具体数据支撑。

### 4. 来源列表 (References)
列出你实际引用的参考链接（必须是包含真实 URL、可通过点击跳转的 Markdown 超链接）。
示例格式：1. [DeepSeek - Wikipedia](https://en.wikipedia.org/wiki/DeepSeek)

---

## 用户问题 (User Question)
<User_Question>
{user_question}
</User_Question>

## 搜索语料 (Search Context)
<Search_Context>
{search_context}
</Search_Context>"""

    return prompt


# ---------------------------------------------------------------------------
# Subcommand: config
# ---------------------------------------------------------------------------
def cmd_config(args: argparse.Namespace) -> int:
    """Handle the 'config' subcommand."""
    if args.set_api_key:
        save_api_key(args.set_api_key)
        print("✅ API key saved to {}".format(TAVILY_KEY_FILE))
        return 0

    keys = load_api_keys()
    if keys:
        # Determine source
        if os.environ.get("TAVILY_API_KEY", "").strip():
            source = "environment variable (TAVILY_API_KEY)"
        elif DOTENV_FILE.exists():
            # Check if .env actually provided the keys
            for line in DOTENV_FILE.read_text(encoding="utf-8").splitlines():
                if line.strip().startswith("TAVILY_API_KEY="):
                    source = "~/.env"
                    break
            else:
                source = "file ({})".format(TAVILY_KEY_FILE)
        else:
            source = "file ({})".format(TAVILY_KEY_FILE)

        print("TAVILY_API_KEY is configured: {} key(s) found".format(len(keys)))
        print("  Source: {}".format(source))
        for i, k in enumerate(keys, 1):
            print("  [{}] {}".format(i, mask_key(k)))
    else:
        print(
            "TAVILY_API_KEY is not configured.\n"
            "\n"
            "To configure your Tavily API key:\n"
            "  1. Get your API key from https://app.tavily.com/home\n"
            "  2. Choose one of the following options:\n"
            "\n"
            "  Option A — Save to ~/.tavily_api_key (single key):\n"
            "     python scripts/search.py config --set-api-key YOUR_KEY\n"
            "\n"
            "  Option B — Add to ~/.env (supports multiple keys):\n"
            "     TAVILY_API_KEY=key1,key2,key3\n"
            "     (comma- or newline-separated; one key is chosen randomly per search)\n"
            "\n"
            "  Option C — Set environment variable:\n"
            "     export TAVILY_API_KEY=\"key1,key2\""
        )
    return 0


# ---------------------------------------------------------------------------
# Subcommand: search
# ---------------------------------------------------------------------------
def cmd_search(args: argparse.Namespace) -> int:
    """Handle the 'search' subcommand."""
    # --- Parse search config ---
    try:
        search_config = json.loads(args.search_json)
    except json.JSONDecodeError as exc:
        print(
            f"[FATAL] Invalid JSON in --search-json: {exc}", file=sys.stderr
        )
        return 1

    queries = search_config.get("search_queries", [])
    num_results = search_config.get("num_results", 5)

    # --- No-search shortcut ---
    if not queries:
        print(
            "[INFO] search_queries is empty — no web search needed.",
            file=sys.stderr,
        )
        print(
            "No web search was performed (the query was classified as not "
            "requiring external information). Please answer the following "
            "question directly using your own knowledge:\n\n{}".format(
                args.question
            )
        )
        return 0

    # --- API key ---
    api_key = load_api_key()
    if not api_key:
        print(
            "[FATAL] Tavily API key is not configured.\n"
            "\n"
            "Option A — Save permanently (recommended):\n"
            "  python scripts/search.py config --set-api-key YOUR_KEY\n"
            "\n"
            "Option B — Set environment variable:\n"
            "  export TAVILY_API_KEY=\"YOUR_KEY\"\n"
            "\n"
            "Get your key at: https://app.tavily.com/home",
            file=sys.stderr,
        )
        return 1

    # --- Execute searches ---
    print(
        f"[INFO] Executing {len(queries)} parallel searches "
        f"(num_results={num_results} each)...",
        file=sys.stderr,
    )

    if HAS_AIOHTTP:
        results = asyncio.run(
            run_searches_async(queries, num_results, api_key)
        )
    else:
        print(
            "[INFO] aiohttp not available, using sync fallback "
            "(urllib + ThreadPool).",
            file=sys.stderr,
        )
        results = run_searches_sync(queries, num_results, api_key)

    # --- Check if all failed ---
    successful = sum(1 for r in results if r is not None)
    if successful == 0:
        print(
            "[FATAL] All Tavily searches failed. "
            "Check API key and network connectivity.",
            file=sys.stderr,
        )
        return 1

    print(
        f"[INFO] {successful}/{len(queries)} searches succeeded.",
        file=sys.stderr,
    )

    # --- Build and output synthesis prompt ---
    synthesis_prompt = build_synthesis_prompt(args.question, results, queries)
    print(synthesis_prompt)
    return 0


# ---------------------------------------------------------------------------
# Main — argparse with subcommands
# ---------------------------------------------------------------------------
def main():
    parser = argparse.ArgumentParser(
        description="Max Search: parallel Tavily search & result synthesis"
    )
    subparsers = parser.add_subparsers(dest="command", help="Available subcommands")

    # --- search subcommand ---
    search_parser = subparsers.add_parser(
        "search", help="Execute parallel Tavily searches and output synthesis prompt"
    )
    search_parser.add_argument(
        "--question",
        required=True,
        help="The user's original question (plain text)",
    )
    search_parser.add_argument(
        "--search-json",
        required=True,
        help='JSON string: {"search_queries": [...], "num_results": N}',
    )

    # --- config subcommand ---
    config_parser = subparsers.add_parser(
        "config", help="Manage Tavily API key configuration"
    )
    config_parser.add_argument(
        "--set-api-key",
        default=None,
        help="Save a Tavily API key to ~/.tavily_api_key",
    )

    args = parser.parse_args()

    if args.command == "search":
        sys.exit(cmd_search(args))
    elif args.command == "config":
        sys.exit(cmd_config(args))
    else:
        parser.print_help()
        sys.exit(1)


if __name__ == "__main__":
    main()