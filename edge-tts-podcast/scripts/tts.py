#!/usr/bin/env python
"""
Edge TTS Podcast — TTS Generation Script

Usage:
  python tts.py <workdir>           # Process all undone lines
  python tts.py <workdir> --line N  # Process a specific line (1-indexed)
  python tts.py --check             # Check env var configuration

Environment variables (priority: system env > ~/.env):
  TTS_BASE_URL  — Edge TTS Cloudflare Worker base URL
  TTS_API_KEY   — Bearer token for TTS service
"""

import os
import sys
import csv
import time
import json
import tempfile
import urllib.request
import urllib.error

# ---------------------------------------------------------------------------
# Env loading
# ---------------------------------------------------------------------------

def load_env():
    """Load TTS_BASE_URL and TTS_API_KEY.
    Priority: system env → ~/.env
    Returns (base_url, api_key) or raises SystemExit with instructions.
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

    missing = []
    if not base_url:
        missing.append("TTS_BASE_URL")
    if not api_key:
        missing.append("TTS_API_KEY")

    if missing:
        print(f"[FATAL] 缺少环境变量: {', '.join(missing)}")
        print("请在 ~/.env 或系统环境变量中配置：")
        print("  TTS_BASE_URL=https://your-worker.workers.dev")
        print("  TTS_API_KEY=your_api_key_here")
        sys.exit(1)

    return base_url.rstrip("/"), api_key


# ---------------------------------------------------------------------------
# CSV helpers
# ---------------------------------------------------------------------------

HEADER = ["done", "voice_id", "content", "speed", "pitch"]

def read_csv(workdir):
    """Read lines.csv, return (header_present, rows).
    rows is a list of dicts with keys matching HEADER.
    """
    csv_path = os.path.join(workdir, "lines.csv")
    if not os.path.isfile(csv_path):
        print(f"[FATAL] 找不到 lines.csv: {csv_path}")
        sys.exit(1)

    rows = []
    with open(csv_path, encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f, delimiter="\t")
        for row in reader:
            rows.append(dict(row))
    return rows


def write_csv(workdir, rows):
    """Write rows back to lines.csv (preserves all columns)."""
    csv_path = os.path.join(workdir, "lines.csv")
    if not rows:
        return
    # Collect all fieldnames (preserve order, HEADER cols first)
    all_keys = list(rows[0].keys())
    fieldnames = [k for k in HEADER if k in all_keys]
    for k in all_keys:
        if k not in fieldnames:
            fieldnames.append(k)

    with open(csv_path, encoding="utf-8", newline="") as f:
        original = f.read()

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
# TTS API call
# ---------------------------------------------------------------------------

def call_tts(base_url, api_key, voice_id, content, speed, pitch, output_path,
             max_retries=3):
    """Call the Edge TTS API and save the MP3 to output_path.
    Returns True on success, False on failure.
    """
    url = f"{base_url}/v1/audio/speech"

    payload = {
        "voice": voice_id,
        "input": content,
        "speed": 1.0,
        "pitch": 1.0,
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
    if speed:
        try:
            payload["speed"] = float(speed)
        except (ValueError, TypeError):
            pass
    if pitch:
        try:
            payload["pitch"] = float(pitch)
        except (ValueError, TypeError):
            pass

    body = json.dumps(payload, ensure_ascii=False).encode("utf-8")

    # 从 base_url 提取 origin 用于 Referer/Origin headers
    from urllib.parse import urlparse
    parsed = urlparse(base_url)
    origin = f"{parsed.scheme}://{parsed.netloc}"

    req = urllib.request.Request(
        url,
        data=body,
        headers={
            "Content-Type": "application/json; charset=utf-8",
            "Authorization": f"Bearer {api_key}",
            "Accept": "*/*",
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
            "Origin": origin,
            "Referer": f"{origin}/",
        },
        method="POST",
    )

    for attempt in range(1, max_retries + 1):
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
                audio_data = resp.read()
            # Ensure voices/ directory exists
            os.makedirs(os.path.dirname(output_path), exist_ok=True)
            with open(output_path, "wb") as f:
                f.write(audio_data)
            return True
        except urllib.error.HTTPError as e:
            body_text = e.read().decode("utf-8", errors="replace")
            print(f"  [错误] HTTP {e.code}: {body_text[:200]}")
            if e.code in (401, 403):
                print("  [提示] 请检查 TTS_API_KEY 是否正确。")
                return False  # Don't retry auth errors
        except urllib.error.URLError as e:
            print(f"  [错误] 网络错误: {e.reason}")
        except Exception as e:
            print(f"  [错误] 未知错误: {e}")

        if attempt < max_retries:
            wait = attempt * 10
            print(f"  [重试] 第 {attempt} 次失败，{wait}s 后重试…")
            time.sleep(wait)

    return False


# ---------------------------------------------------------------------------
# Core processing
# ---------------------------------------------------------------------------

def process_lines(workdir, base_url, api_key, target_line=None):
    """Process undone lines in lines.csv.

    target_line: int (1-indexed) to process only that line, or None for all.
    """
    rows = read_csv(workdir)
    voices_dir = os.path.join(workdir, "voices")
    os.makedirs(voices_dir, exist_ok=True)

    total = len(rows)
    done_count   = sum(1 for r in rows if str(r.get("done", "")).strip() == "1")
    undone_count = total - done_count

    if target_line is not None:
        idx = target_line - 1
        if idx < 0 or idx >= total:
            print(f"[FATAL] 行号 {target_line} 超出范围（共 {total} 行）")
            sys.exit(1)
        indices = [idx]
        print(f"[INFO] 处理第 {target_line} 行（共 {total} 行）")
    else:
        indices = [i for i, r in enumerate(rows)
                   if str(r.get("done", "")).strip() != "1"]
        print(f"[INFO] 共 {total} 行，已完成 {done_count} 行，待处理 {len(indices)} 行")

    if not indices:
        print("[INFO] 没有需要处理的行，全部已完成。")
        return

    success = 0
    failed  = []

    for i, row_idx in enumerate(indices, 1):
        row      = rows[row_idx]
        line_num = row_idx + 1  # 1-indexed for filename
        voice_id = row.get("voice_id", "").strip()
        content  = row.get("content",  "").strip()
        speed    = row.get("speed",    "").strip()
        pitch    = row.get("pitch",    "").strip()

        if not voice_id or not content:
            print(f"  [{i}/{len(indices)}] 行 {line_num}: 跳过（voice_id 或 content 为空）")
            continue

        output_path = os.path.join(voices_dir, f"{line_num}.mp3")
        print(f"  [{i}/{len(indices)}] 行 {line_num} [{voice_id}]: {content[:40]}{'…' if len(content)>40 else ''}")

        ok = call_tts(base_url, api_key, voice_id, content, speed, pitch, output_path)
        if ok:
            mark_done(workdir, row_idx, rows)
            success += 1
            print(f"    ✓ 已保存 voices/{line_num}.mp3")
        else:
            failed.append(line_num)
            print(f"    ✗ 行 {line_num} 生成失败，已跳过")

    print(f"\n[完成] 成功 {success} 行，失败 {len(failed)} 行。")
    if failed:
        print(f"[警告] 失败行号: {failed}")
        print("       可重新运行此脚本，将自动跳过已完成的行。")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    args = sys.argv[1:]

    if not args or args[0] == "--check":
        base_url, api_key = load_env()
        masked = api_key[:4] + "****" + api_key[-4:] if len(api_key) > 8 else "****"
        print("[已配置] TTS 环境变量检查通过")
        print(f"  TTS_BASE_URL = {base_url}")
        print(f"  TTS_API_KEY  = {masked}")
        return

    workdir     = None
    target_line = None

    i = 0
    while i < len(args):
        if args[i] == "--line" and i + 1 < len(args):
            try:
                target_line = int(args[i + 1])
            except ValueError:
                print(f"[FATAL] --line 参数必须是整数，收到: {args[i+1]}")
                sys.exit(1)
            i += 2
        else:
            workdir = args[i]
            i += 1

    if not workdir:
        print("用法: python tts.py <workdir> [--line N]")
        print("      python tts.py --check")
        sys.exit(1)

    workdir = os.path.abspath(workdir)
    if not os.path.isdir(workdir):
        print(f"[FATAL] 工作目录不存在: {workdir}")
        sys.exit(1)

    base_url, api_key = load_env()
    process_lines(workdir, base_url, api_key, target_line=target_line)


if __name__ == "__main__":
    main()
