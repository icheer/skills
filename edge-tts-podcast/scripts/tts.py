#!/usr/bin/env python
"""
Edge TTS Podcast — TTS Generation Script

Usage:
  python tts.py <workdir>              # Process all undone lines
  python tts.py <workdir> --line N     # Process a specific line (1-indexed)
  python tts.py <workdir> --delay 0.5  # Seconds to wait between lines
  python tts.py --check                # Check backend configuration

Two backends, selected automatically:

  1. DIRECT (default, zero-config)
     Talks to Microsoft Edge TTS directly, reproducing the auth flow of the
     MS Translator Android app. No environment variables, no proxy service.

  2. PROXY (opt-in fallback)
     If TTS_BASE_URL is set, requests go to an edgetts-cloudflare-workers
     deployment instead. Use this when direct access is blocked or rate
     limited. TTS_API_KEY is optional (only needed if the worker sets one).

Environment variables (priority: system env > ~/.env):
  TTS_BASE_URL  — optional; Edge TTS Cloudflare Worker base URL
  TTS_API_KEY   — optional; Bearer token, only if the worker requires one

Python: 3.7+  (stdlib only, no third-party dependencies)
"""

from __future__ import annotations

import os
import re
import sys
import csv
import time
import json
import base64
import hashlib
import hmac
import uuid
import urllib.request
import urllib.error
from email.utils import formatdate
from urllib.parse import urlparse, quote

# ---------------------------------------------------------------------------
# Safe print for mixed-encoding environments
# ---------------------------------------------------------------------------

def safe_print(text):
    """Print text, gracefully downgrading Unicode on encoding errors.

    Windows GBK consoles can't encode ✓/✗ and many Chinese chars. This
    wrapper catches UnicodeEncodeError and retries with ASCII-safe fallbacks.
    """
    try:
        print(text)
    except UnicodeEncodeError:
        # Replace common symbols, then force ASCII with backslashreplace
        fallback = text.replace("✓", "[OK]").replace("✗", "[X]")
        print(fallback.encode(sys.stdout.encoding or "utf-8", "replace").decode(sys.stdout.encoding or "utf-8", "ignore"))

# ---------------------------------------------------------------------------
# Env loading
# ---------------------------------------------------------------------------

def load_env():
    """Load optional TTS_BASE_URL / TTS_API_KEY.

    Priority: system env → ~/.env
    Both are optional: an empty base_url selects the direct backend.
    Returns (base_url, api_key), either of which may be "".
    """
    base_url = os.environ.get("TTS_BASE_URL", "").strip()
    api_key  = os.environ.get("TTS_API_KEY",  "").strip()

    if not base_url or not api_key:
        env_file = os.path.join(os.path.expanduser("~"), ".env")
        if os.path.isfile(env_file):
            with open(env_file, encoding="utf-8", errors="ignore") as f:
                for line in f:
                    line = line.strip()
                    if line.startswith("#") or "=" not in line:
                        continue
                    k, _, v = line.partition("=")
                    k = k.strip()
                    v = v.strip().strip('"').strip("'")
                    if k == "TTS_BASE_URL" and not base_url:
                        base_url = v
                    elif k == "TTS_API_KEY" and not api_key:
                        api_key = v

    return base_url.rstrip("/"), api_key


# ---------------------------------------------------------------------------
# Workdir validation and normalization
# ---------------------------------------------------------------------------

def validate_workdir(workdir_arg):
    """Validate and normalize the working directory.

    1. Convert to absolute path (relative paths resolved against CWD)
    2. Check directory name follows YYYY-MM-DD_topic convention
    3. Create workdir and subdirectories (sources/, voices/) if missing
    4. Write a .workdir_anchor file containing the absolute path

    This prevents agent hallucination paths from scattering files across
    wrong locations during multi-turn conversations.

    Args:
        workdir_arg: path string from command line (relative or absolute)

    Returns:
        str: normalized absolute path

    Raises:
        SystemExit: if the resolved path is clearly invalid
    """
    # 1. Convert to absolute path
    workdir = os.path.abspath(workdir_arg)

    # 2. Check naming convention (YYYY-MM-DD_topic)
    dirname = os.path.basename(workdir)
    if not re.match(r'^\d{4}-\d{2}-\d{2}_', dirname):
        safe_print(f"[警告] 工作目录命名不符合技能约定（应为 YYYY-MM-DD_topic）: {dirname}")
        safe_print(f"       当前路径: {workdir}")
        safe_print("       这可能是 Agent 上下文污染导致的幻觉路径。")
        # Don't exit — just warn. The user may have a valid reason for a custom name.

    # 3. Create directory structure
    try:
        os.makedirs(workdir, exist_ok=True)
        os.makedirs(os.path.join(workdir, "sources"), exist_ok=True)
        os.makedirs(os.path.join(workdir, "voices"), exist_ok=True)
    except OSError as e:
        safe_print(f"[FATAL] 无法创建工作目录: {workdir}")
        safe_print(f"        错误: {e}")
        sys.exit(1)

    # 4. Write anchor file
    anchor_file = os.path.join(workdir, ".workdir_anchor")
    try:
        with open(anchor_file, "w", encoding="utf-8") as f:
            f.write(f"{workdir}\n")
    except Exception:
        pass  # Non-critical; continue even if anchor write fails

    safe_print(f"[INFO] 工作目录（已规范化）: {workdir}")
    return workdir


# ---------------------------------------------------------------------------
# CSV helpers
# ---------------------------------------------------------------------------

HEADER = ["done", "voice_id", "content", "speed", "pitch"]

def read_csv(workdir):
    """Read lines.csv into a list of dicts with keys matching HEADER."""
    csv_path = os.path.join(workdir, "lines.csv")
    if not os.path.isfile(csv_path):
        safe_print(f"[FATAL] 找不到 lines.csv: {csv_path}")
        sys.exit(1)

    rows = []
    with open(csv_path, encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f, delimiter="\t")
        for row in reader:
            rows.append(dict(row))
    return rows


def write_csv(workdir, rows):
    """Write rows back to lines.csv atomically (preserves all columns)."""
    csv_path = os.path.join(workdir, "lines.csv")
    if not rows:
        return
    # Collect all fieldnames (preserve order, HEADER cols first)
    all_keys = list(rows[0].keys())
    fieldnames = [k for k in HEADER if k in all_keys]
    for k in all_keys:
        if k not in fieldnames:
            fieldnames.append(k)

    tmp_path = csv_path + ".tmp"
    with open(tmp_path, "w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames, delimiter="\t",
                                extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)

    os.replace(tmp_path, csv_path)


def mark_done(workdir, row_index, rows):
    """Mark rows[row_index] as done=1 and persist immediately."""
    rows[row_index]["done"] = "1"
    write_csv(workdir, rows)


# ---------------------------------------------------------------------------
# Backend 1: direct Microsoft Edge TTS
#
# Port of the non-streaming path in edgetts-cloudflare-workers-webui/worker.js.
# Concurrency and streaming are deliberately omitted: podcast lines are short
# and processed one at a time, so a sequential chunk loop is enough.
# ---------------------------------------------------------------------------

# HMAC key of the MS Translator Android app, same one the worker uses.
_SIGN_KEY = base64.b64decode(
    "oik6PdDdMnOXemTbwvMn9de/h9lFnfBaCWbGMMZqqoSaQaqUOqjVGm5NqsmjcBI1x"
    "+sS9ugjB55HEJWRiFXYFw=="
)
_ENDPOINT_URL = "https://dev.microsofttranslator.com/apps/endpoint?api-version=1.0"
_OUTPUT_FORMAT = "audio-24khz-48kbitrate-mono-mp3"
_CHUNK_SIZE = 300
_TOKEN_REFRESH_MARGIN = 300  # refresh the token 5 min before it expires

# Process-wide token cache. A token lasts ~40 min, so one fetch covers a
# whole podcast run.
_token_cache = {"endpoint": None, "expired_at": 0.0}


def _ms_signature(url_str):
    """Build the X-MT-Signature header value.

    Mirrors worker.js sign(): only the string being signed is lowercased —
    the date and uuid echoed back in the header keep their original case.
    """
    url = url_str.split("://", 1)[1]
    # encodeURIComponent leaves -_.!~*'() untouched; urllib.quote does not.
    encoded_url = quote(url, safe="-_.!~*'()")
    uuid_str = uuid.uuid4().hex
    formatted_date = formatdate(usegmt=True)  # same shape as JS toUTCString()

    to_sign = f"MSTranslatorAndroidApp{encoded_url}{formatted_date}{uuid_str}".lower()
    digest = hmac.new(_SIGN_KEY, to_sign.encode("utf-8"), hashlib.sha256).digest()
    sig_b64 = base64.b64encode(digest).decode("ascii")

    return f"MSTranslatorAndroidApp::{sig_b64}::{formatted_date}::{uuid_str}"


def _jwt_expiry(token):
    """Extract the exp claim from a JWT without verifying it."""
    payload_b64 = token.split(".")[1]
    payload_b64 += "=" * (-len(payload_b64) % 4)  # base64url has no padding
    return json.loads(base64.urlsafe_b64decode(payload_b64))["exp"]


def _ms_get_endpoint(force=False):
    """Fetch (and cache) the Microsoft TTS region + auth token."""
    now = time.time()
    if (not force and _token_cache["endpoint"]
            and now < _token_cache["expired_at"] - _TOKEN_REFRESH_MARGIN):
        return _token_cache["endpoint"]

    req = urllib.request.Request(
        _ENDPOINT_URL,
        data=b"",
        method="POST",
        headers={
            "Accept-Language": "zh-Hans",
            "X-ClientVersion": "4.0.530a 5fe1dc6c",
            "X-UserId": "0f04d16a175c411e",
            "X-HomeGeographicRegion": "zh-Hans-CN",
            "X-ClientTraceId": uuid.uuid4().hex,
            "X-MT-Signature": _ms_signature(_ENDPOINT_URL),
            "User-Agent": "okhttp/4.5.0",
            "Content-Type": "application/json; charset=utf-8",
            "Content-Length": "0",
            # No Accept-Encoding: urllib will not decompress gzip for us.
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            data = json.loads(resp.read().decode("utf-8"))
        _token_cache["endpoint"] = data
        _token_cache["expired_at"] = _jwt_expiry(data["t"])
        return data
    except Exception:
        # Fall back to a stale token rather than failing outright.
        if _token_cache["endpoint"]:
            safe_print("  [提示] 换取新 token 失败，沿用缓存的旧 token")
            return _token_cache["endpoint"]
        raise


_EMOJI_RE = re.compile(
    "["
    "\U0001F300-\U0001F5FF"  # symbols & pictographs
    "\U0001F600-\U0001F64F"  # emoticons
    "\U0001F680-\U0001F6FF"  # transport & map
    "\U0001F900-\U0001F9FF"  # supplemental symbols
    "\U0001FA70-\U0001FAFF"  # extended-A
    "\U0001F1E6-\U0001F1FF"  # regional indicators (flags)
    "☀-➿"          # misc symbols & dingbats
    "⬀-⯿"          # misc symbols & arrows
    "️"                 # variation selector-16
    "]+",
    flags=re.UNICODE,
)


def clean_text(text):
    """Port of worker.js cleanText() with all options enabled."""
    t = text
    t = re.sub(r"https?://\S+", "", t)              # urls
    t = re.sub(r"!\[.*?\]\(.*?\)", "", t)           # md images
    t = re.sub(r"\[(.*?)\]\(.*?\)", r"\1", t)       # md links → text
    t = re.sub(r"(\*\*|__)(.*?)\1", r"\2", t)       # bold
    t = re.sub(r"(\*|_)(.*?)\1", r"\2", t)          # italic
    t = re.sub(r"`{1,3}(.*?)`{1,3}", r"\1", t)      # code
    t = re.sub(r"#{1,6}\s", "", t)                  # headings
    t = _EMOJI_RE.sub("", t)                        # emoji
    t = re.sub(r"\s\d{1,2}(?=[.。，,;；:：]|$)", "", t)  # citation numbers
    t = re.sub(r"\s+", " ", t)                      # collapse whitespace
    return t.strip()


def chunk_text(text, max_len=_CHUNK_SIZE):
    """Port of worker.js smartChunkText(): split on punctuation boundaries."""
    if not text:
        return []

    chunks = []
    current = ""
    # Capturing group keeps the separators, same as the JS split.
    for part in re.split(r"([.?!,;:\n。？！，；：\r]+)", text):
        if not part:
            continue
        if len(current) + len(part) <= max_len:
            current += part
        else:
            if current.strip():
                chunks.append(current.strip())
            current = part
    if current.strip():
        chunks.append(current.strip())

    # A run with no punctuation never splits above, so it can still exceed
    # max_len. worker.js leaves it oversized; hard split it here instead so
    # the SSML body stays bounded. No effect on normal punctuated text.
    out = []
    for c in chunks:
        if len(c) <= max_len:
            out.append(c)
        else:
            out.extend(c[i:i + max_len] for i in range(0, len(c), max_len))

    return [c for c in out if c]


def build_ssml(text, voice, rate, pitch, style="general"):
    """Port of worker.js getSsml(), preserving literal <break> tags."""
    breaks = []

    def _stash(m):
        breaks.append(m.group(0))
        return f"__BREAK_TAG_{len(breaks) - 1}__"

    staged = re.sub(
        r"<break\s+time=\"[^\"]*\"\s*/?>|<break\s*/?>|<break\s+time='[^']*'\s*/?>",
        _stash, text, flags=re.IGNORECASE,
    )
    escaped = staged.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    for i, tag in enumerate(breaks):
        escaped = escaped.replace(f"__BREAK_TAG_{i}__", tag)

    return (
        '<speak xmlns="http://www.w3.org/2001/10/synthesis" '
        'xmlns:mstts="http://www.w3.org/2001/mstts" version="1.0" xml:lang="en-US">'
        f'<voice name="{voice}">'
        f'<mstts:express-as style="{style}">'
        f'<prosody rate="{rate}%" pitch="{pitch}%">{escaped}</prosody>'
        "</mstts:express-as></voice></speak>"
    )


def _ms_synth_chunk(endpoint, text, voice, rate, pitch):
    """Synthesize one chunk, returning raw MP3 bytes."""
    url = f"https://{endpoint['r']}.tts.speech.microsoft.com/cognitiveservices/v1"
    req = urllib.request.Request(
        url,
        data=build_ssml(text, voice, rate, pitch).encode("utf-8"),
        method="POST",
        headers={
            "Authorization": endpoint["t"],  # raw JWT, no "Bearer " prefix
            "Content-Type": "application/ssml+xml",
            "User-Agent": "okhttp/4.5.0",
            "X-Microsoft-OutputFormat": _OUTPUT_FORMAT,
        },
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        return resp.read()


def direct_synthesize(content, voice_id, speed, pitch):
    """Direct backend entry point. Returns MP3 bytes."""
    rate = f"{(speed - 1) * 100:.0f}"
    pit  = f"{(pitch - 1) * 100:.0f}"

    chunks = chunk_text(clean_text(content))
    if not chunks:
        return b""

    endpoint = _ms_get_endpoint()
    parts = []
    for chunk in chunks:
        try:
            parts.append(_ms_synth_chunk(endpoint, chunk, voice_id, rate, pit))
        except urllib.error.HTTPError as e:
            if e.code == 401:
                # Token went stale mid-run; refresh once and retry this chunk.
                endpoint = _ms_get_endpoint(force=True)
                parts.append(_ms_synth_chunk(endpoint, chunk, voice_id, rate, pit))
            else:
                raise
    # Microsoft returns bare MPEG frames, so plain concatenation is valid.
    return b"".join(parts)


# ---------------------------------------------------------------------------
# Backend 2: edgetts-cloudflare-workers proxy
# ---------------------------------------------------------------------------

def proxy_synthesize(base_url, api_key, content, voice_id, speed, pitch):
    """Proxy backend entry point. Returns MP3 bytes."""
    payload = {
        "voice": voice_id,
        "input": content,
        "speed": speed,
        "pitch": pitch,
        "stream": False,
        "cleaning_options": {
            "remove_markdown": True,
            "remove_emoji": True,
            "remove_urls": True,
            "remove_line_breaks": True,
            "remove_citation_numbers": True,
            "custom_keywords": "",
        },
    }
    parsed = urlparse(base_url)
    origin = f"{parsed.scheme}://{parsed.netloc}"

    headers = {
        "Content-Type": "application/json; charset=utf-8",
        "Accept": "*/*",
        # A browser-ish UA keeps Cloudflare from challenging the request.
        "User-Agent": ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                       "AppleWebKit/537.36 (KHTML, like Gecko) "
                       "Chrome/131.0.0.0 Safari/537.36"),
        "Origin": origin,
        "Referer": f"{origin}/",
    }
    if api_key:  # the worker only enforces auth when it has an API_KEY set
        headers["Authorization"] = f"Bearer {api_key}"

    req = urllib.request.Request(
        f"{base_url}/v1/audio/speech",
        data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
        headers=headers,
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        return resp.read()


# ---------------------------------------------------------------------------
# Backend dispatch
# ---------------------------------------------------------------------------

def _to_float(value, default):
    try:
        return float(value)
    except (ValueError, TypeError):
        return default


def call_tts(base_url, api_key, voice_id, content, speed, pitch, output_path,
             max_retries=3):
    """Synthesize one line and save it to output_path.

    Routes to the proxy backend when base_url is set, otherwise direct.
    Returns True on success, False on failure.
    """
    speed_f = _to_float(speed, 1.0)
    pitch_f = _to_float(pitch, 1.0)
    direct  = not base_url

    for attempt in range(1, max_retries + 1):
        try:
            if direct:
                audio = direct_synthesize(content, voice_id, speed_f, pitch_f)
            else:
                audio = proxy_synthesize(base_url, api_key, content, voice_id,
                                         speed_f, pitch_f)
            if not audio:
                raise RuntimeError("TTS 返回空音频")

            os.makedirs(os.path.dirname(output_path), exist_ok=True)
            with open(output_path, "wb") as f:
                f.write(audio)
            return True

        except urllib.error.HTTPError as e:
            body_text = e.read().decode("utf-8", errors="replace")
            safe_print(f"  [错误] HTTP {e.code}: {body_text[:200]}")
            if direct:
                if e.code == 401:
                    _token_cache["endpoint"] = None  # force a fresh token
                elif e.code == 429:
                    safe_print("  [提示] 被微软限流，建议加大 --delay 或改用 TTS_BASE_URL 代理。")
            elif e.code in (401, 403):
                safe_print("  [提示] 请检查 TTS_API_KEY 是否正确。")
                return False  # bad credentials will not fix themselves
        except urllib.error.URLError as e:
            safe_print(f"  [错误] 网络错误: {e.reason}")
        except Exception as e:
            safe_print(f"  [错误] 未知错误: {e}")

        if attempt < max_retries:
            wait = attempt * 10
            safe_print(f"  [重试] 第 {attempt} 次失败，{wait}s 后重试…")
            time.sleep(wait)

    return False


# ---------------------------------------------------------------------------
# Core processing
# ---------------------------------------------------------------------------

def process_lines(workdir, base_url, api_key, target_line=None, delay=None):
    """Process undone lines in lines.csv, one at a time.

    target_line: int (1-indexed) to process only that line, or None for all.
    delay:       seconds to sleep between lines; None picks a backend default.
    """
    rows = read_csv(workdir)
    voices_dir = os.path.join(workdir, "voices")
    os.makedirs(voices_dir, exist_ok=True)

    direct = not base_url
    if delay is None:
        # Space out direct calls a little — they all leave from one IP.
        delay = 0.3 if direct else 0.0

    safe_print(f"[INFO] 后端: {'直连微软 Edge TTS' if direct else base_url}")

    total = len(rows)
    done_count = sum(1 for r in rows if str(r.get("done", "")).strip() == "1")

    if target_line is not None:
        idx = target_line - 1
        if idx < 0 or idx >= total:
            safe_print(f"[FATAL] 行号 {target_line} 超出范围（共 {total} 行）")
            sys.exit(1)
        indices = [idx]
        safe_print(f"[INFO] 处理第 {target_line} 行（共 {total} 行）")
    else:
        indices = [i for i, r in enumerate(rows)
                   if str(r.get("done", "")).strip() != "1"]
        safe_print(f"[INFO] 共 {total} 行，已完成 {done_count} 行，待处理 {len(indices)} 行")

    if not indices:
        safe_print("[INFO] 没有需要处理的行，全部已完成。")
        return

    success = 0
    failed  = []

    for i, row_idx in enumerate(indices, 1):
        row      = rows[row_idx]
        line_num = row_idx + 1  # 1-indexed for filename
        voice_id = (row.get("voice_id") or "").strip()
        content  = (row.get("content")  or "").strip()
        speed    = (row.get("speed")    or "").strip()
        pitch    = (row.get("pitch")    or "").strip()

        if not voice_id or not content:
            safe_print(f"  [{i}/{len(indices)}] 行 {line_num}: 跳过（voice_id 或 content 为空）")
            continue

        output_path = os.path.join(voices_dir, f"{line_num}.mp3")
        preview = content[:40] + ("…" if len(content) > 40 else "")
        safe_print(f"  [{i}/{len(indices)}] 行 {line_num} [{voice_id}]: {preview}")

        ok = call_tts(base_url, api_key, voice_id, content, speed, pitch, output_path)
        if ok:
            mark_done(workdir, row_idx, rows)
            success += 1
            safe_print(f"    ✓ 已保存 voices/{line_num}.mp3")
        else:
            failed.append(line_num)
            safe_print(f"    ✗ 行 {line_num} 生成失败，已跳过")

        if delay and i < len(indices):
            time.sleep(delay)

    safe_print(f"\n[完成] 成功 {success} 行，失败 {len(failed)} 行。")
    if failed:
        safe_print(f"[警告] 失败行号: {failed}")
        safe_print("       可重新运行此脚本，将自动跳过已完成的行。")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def run_check():
    """Report which backend is active and verify it is reachable."""
    base_url, api_key = load_env()

    if base_url:
        masked = (api_key[:4] + "****" + api_key[-4:]) if len(api_key) > 8 else "****"
        safe_print("[模式] 代理服务（TTS_BASE_URL 已配置）")
        safe_print(f"  TTS_BASE_URL = {base_url}")
        safe_print(f"  TTS_API_KEY  = {masked if api_key else '(未设置，worker 需未启用鉴权)'}")
        return

    safe_print("[模式] 直连微软 Edge TTS（零配置，无需 TTS_BASE_URL / TTS_API_KEY）")
    try:
        ep = _ms_get_endpoint()
        ttl = (_token_cache["expired_at"] - time.time()) / 60
        safe_print(f"  ✓ 连接正常  region={ep['r']}  token 有效期 {ttl:.1f} 分钟")
    except Exception as e:
        safe_print(f"  ✗ 连接失败: {e}")
        safe_print("  [提示] 若你的网络无法直连微软，可配置 TTS_BASE_URL 改用代理服务：")
        safe_print("         TTS_BASE_URL=https://your-worker.workers.dev")
        sys.exit(1)


def main():
    args = sys.argv[1:]

    if not args or args[0] == "--check":
        run_check()
        return

    workdir     = None
    target_line = None
    delay       = None

    i = 0
    while i < len(args):
        if args[i] == "--line" and i + 1 < len(args):
            try:
                target_line = int(args[i + 1])
            except ValueError:
                safe_print(f"[FATAL] --line 参数必须是整数，收到: {args[i+1]}")
                sys.exit(1)
            i += 2
        elif args[i] == "--delay" and i + 1 < len(args):
            try:
                delay = float(args[i + 1])
            except ValueError:
                safe_print(f"[FATAL] --delay 参数必须是数字，收到: {args[i+1]}")
                sys.exit(1)
            i += 2
        else:
            workdir = args[i]
            i += 1

    if not workdir:
        safe_print("用法: python tts.py <workdir> [--line N] [--delay SECONDS]")
        safe_print("      python tts.py --check")
        sys.exit(1)

    # Validate and normalize workdir (handles relative paths, creates subdirs)
    workdir = validate_workdir(workdir)

    base_url, api_key = load_env()
    process_lines(workdir, base_url, api_key,
                  target_line=target_line, delay=delay)


if __name__ == "__main__":
    main()
