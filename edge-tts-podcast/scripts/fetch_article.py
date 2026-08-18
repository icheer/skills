#!/usr/bin/env python
"""
Edge TTS Podcast — Article Fetcher

Fetches a URL using WeChat browser impersonation, extracts plain text
(no HTML tags, no Markdown), and saves to an output file.

Usage:
  python fetch_article.py <url> [output_file]
  python fetch_article.py <url>             # prints JSON to stdout
  python fetch_article.py <url> sources/1.md  # saves plain text to file

Output JSON (stdout): {"title": "...", "url": "...", "content": "...", "content_length": N}
Saved file: plain text only (title header + body lines)

Dependencies: requests, beautifulsoup4  (auto-installed if missing)
Python: 3.7+  (PEP 604 annotations deferred via __future__ import)
"""

from __future__ import annotations

import sys
import re
import os
import json
import subprocess


def _ensure_deps():
    """Auto-install requests + beautifulsoup4 if missing."""
    try:
        import requests       # noqa: F401
        from bs4 import BeautifulSoup  # noqa: F401
    except ImportError:
        print("[INFO] Installing dependencies: requests, beautifulsoup4 ...", file=sys.stderr)
        subprocess.check_call(
            [sys.executable, "-m", "pip", "install", "-q", "requests", "beautifulsoup4"]
        )


def fetch_html(url: str) -> bytes:
    """Fetch raw HTML bytes, impersonating WeChat browser."""
    import requests
    headers = {
        "User-Agent": (
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
            "(KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36 "
            "NetType/WIFI MicroMessenger/7.0.20.1781(0x6700143B) "
            "WindowsWechat(0x63090a13) UnifiedPCWindowsWechat(0xf254101f) "
            "XWEB/16389 SideBar Flue"
        ),
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
        "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
        "Cache-Control": "no-cache",
        "Pragma": "no-cache",
        "Referer": "https://www.bing.com/",
        "Upgrade-Insecure-Requests": "1",
    }
    resp = requests.get(url, headers=headers, timeout=15, allow_redirects=True)
    resp.raise_for_status()
    return resp.content


def extract_title(soup) -> str:
    """Extract page title, strip common site-name suffixes."""
    tag = soup.find("title")
    if tag:
        t = tag.get_text(strip=True)
        t = re.split(r"\s*[-|_–—]\s*", t)[0].strip()
        if t:
            return t
    h1 = soup.find("h1")
    if h1:
        return h1.get_text(strip=True)
    return ""


def extract_wechat_content(soup) -> str | None:
    """Decode WeChat's hex-encoded content_noencode JS injection."""
    for s in soup.find_all("script"):
        if s.string and "content_noencode" in s.string:
            m = re.search(
                r"content_noencode\s*:\s*JsDecode\s*\(\s*['\"]([^'\"]+)['\"]\s*\)",
                s.string,
            )
            if m:
                hex_str = m.group(1)
                def _decode(x):
                    try:
                        return bytes.fromhex(x.group(1)).decode("utf-8", errors="replace")
                    except Exception:
                        return x.group(0)
                return re.sub(r"\\x([0-9a-fA-F]{2})", _decode, hex_str)
    return None


def html_to_plaintext(html_bytes: bytes) -> tuple[str, str]:
    """
    Parse HTML bytes → (title, plain_text).

    Strategy:
    1. WeChat content_noencode special case
    2. Known rich-content containers (article, main, id/class patterns)
    3. Fallback: <body>

    Returns plain text with meaningful line breaks, all tags stripped.
    """
    from bs4 import BeautifulSoup

    soup = BeautifulSoup(html_bytes, "html.parser")
    title = extract_title(soup)

    # Remove noise elements before any text extraction
    for tag in soup.find_all(["script", "style", "noscript", "iframe",
                               "nav", "header", "footer", "aside",
                               "menu", "svg", "canvas", "form", "button"]):
        tag.decompose()

    # --- WeChat special case ---
    wechat_html = extract_wechat_content(soup)
    if wechat_html:
        inner = BeautifulSoup(wechat_html, "html.parser")
        text = inner.get_text(separator="\n", strip=True)
        return title, _clean_lines(text)

    # --- Semantic containers (priority order) ---
    fragment = (
        soup.find("article")
        or soup.find("main")
        or soup.find(id=re.compile(r"rich_media_content|img-content|article[-_]content|post[-_]content", re.I))
        or soup.find(class_=re.compile(r"rich_media_content|article[-_]body|post[-_]body|entry[-_]content", re.I))
        or soup.find("body")
    )
    if fragment is None:
        fragment = soup

    text = fragment.get_text(separator="\n", strip=True)
    return title, _clean_lines(text)


def _clean_lines(text: str, max_lines: int = 500, max_chars: int = 48000) -> str:
    """
    Post-process extracted plain text:
    - Remove blank / whitespace-only lines
    - Collapse repeated whitespace within each line
    - Truncate to max_lines or max_chars
    """
    lines = []
    for line in text.splitlines():
        line = line.strip()
        # Collapse internal whitespace runs to a single space
        line = re.sub(r"[ \t]{2,}", " ", line)
        if line:
            lines.append(line)

    # Truncate by line count first
    if len(lines) > max_lines:
        lines = lines[:max_lines]

    result = "\n".join(lines)

    # Truncate by character count
    if len(result) > max_chars:
        result = result[:max_chars] + "\n\n... (内容过长，已截断)"

    return result


def count_words(text: str) -> int:
    """Count Chinese chars + English word tokens."""
    zh = len(re.findall(r"[一-鿿㐀-䶿豈-﫿]", text))
    without_cjk = re.sub(r"[一-鿿㐀-䶿豈-﫿]", " ", text)
    en = len([w for w in without_cjk.split()
              if w and w[0].isascii() and (w[0].isalpha() or w[0].isdigit())])
    return zh + en


def main():
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass

    if len(sys.argv) < 2:
        print("Usage: python fetch_article.py <url> [output_file]", file=sys.stderr)
        sys.exit(1)

    url = sys.argv[1]
    output_file = sys.argv[2] if len(sys.argv) >= 3 else None

    if not re.match(r"^https?://", url):
        print("Error: Invalid URL (must start with http:// or https://)", file=sys.stderr)
        sys.exit(1)

    try:
        _ensure_deps()

        html_bytes = fetch_html(url)
        title, content = html_to_plaintext(html_bytes)
        content_length = count_words(content)

        if output_file:
            # Save plain text to file (for sources/ directory)
            os.makedirs(os.path.dirname(os.path.abspath(output_file)), exist_ok=True)
            with open(output_file, "w", encoding="utf-8") as f:
                if title:
                    f.write(f"# {title}\n\n")
                f.write(f"来源: {url}\n\n")
                f.write(content)
            print(f"[OK] 已保存 ({content_length} 字词): {output_file}", file=sys.stderr)
            # Still emit JSON to stdout for the agent to read
            result = {"title": title, "url": url,
                      "content": content, "content_length": content_length}
            print(json.dumps(result, ensure_ascii=False))
        else:
            result = {"title": title, "url": url,
                      "content": content, "content_length": content_length}
            print(json.dumps(result, ensure_ascii=False))

    except subprocess.CalledProcessError as e:
        print(f"Error: Failed to install dependencies: {e}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
