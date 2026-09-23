#!/usr/bin/env python
"""
SenseAudio Web TTS Podcast — Web-channel TTS Generation Script

Usage:
  python web_tts.py <workdir>              # Process all undone lines
  python web_tts.py <workdir> --line N     # Process a specific line (1-indexed)
  python web_tts.py <workdir> --delay 0.5  # Seconds to wait between lines
  python web_tts.py --check                # Verify token + list voices
  python web_tts.py --check --probe        # Additionally synthesize 5 chars

Alternative backend to tts.py, driving the SenseAudio WEB console channel
(senseaudio.cn 语音应用 → 文本转语音) instead of the open API:

  POST https://platform.senseaudio.cn/api/voice/tts
  → JSON {download_url} → GET → WAV (24kHz/16bit/mono)

Why: the web channel exposes 74 voices (vs 34 via the open API) and honors
"限免使用" promotions, so SVIP voices are usable without a paid plan.

Caveats (inherent to the web channel, by design "取巧"):
  - Auth is a browser session token (SENSE_WEB_TOKEN, Paseto v2), NOT an
    API key. It expires (~60 days) and rotates on every re-login; refresh
    it in ~/.env when tts starts returning 401.
  - Undocumented endpoint; format/behavior may change without notice.
  - Segments are saved as NATIVE WAV (voices/{n}.wav) — lossless, stdlib
    only, no lameenc here. concat.py merges the WAVs (synthesizing exact
    sample-accurate silence inline) and performs the SINGLE MP3 encode at
    the very end; lameenc is only needed at that concat step.

lines.csv columns are identical to tts.py: done / voice_id (label codes
like male_0028_a; UUID mapping is resolved automatically via the web
voice catalog, cached in ~/.sense_web_voice_map.json) / content /
speed (0.5-2.0) / pitch (-12..+12 semitones).

Python: 3.7+  (stdlib only; lameenc required only by concat.py's final
MP3 encode — `pip install lameenc` if podcast.mp3 output is wanted)
"""

from __future__ import annotations

import base64
import json
import os
import re
import sys
import time
import urllib.request
import urllib.error
from datetime import datetime, timezone

# Shared helpers from the API-channel script (same directory).
from tts import (safe_print, validate_workdir, read_csv, write_csv, mark_done,
                 check_meta_phase, clean_text, _to_float, FatalAuthError)

WEB_API_BASE = "https://platform.senseaudio.cn"
WEB_TTS_URL = f"{WEB_API_BASE}/api/voice/tts"
WEB_VOICE_LIST_URL = f"{WEB_API_BASE}/api/voice?page=1&page_size=1000&keyword="
WEB_MODEL = "sensenova-tts-2.0"
CATALOG_CACHE = os.path.join(os.path.expanduser("~"), ".sense_web_voice_map.json")
CATALOG_TTL = 7 * 86400  # refresh weekly; hard-refreshed on voice-404


# ---------------------------------------------------------------------------
# Env / token
# ---------------------------------------------------------------------------

def load_web_token():
    """Load SENSE_WEB_TOKEN (system env → ~/.env). Strips a literal 'Bearer '."""
    token = os.environ.get("SENSE_WEB_TOKEN", "").strip()
    if not token:
        env_file = os.path.join(os.path.expanduser("~"), ".env")
        if os.path.isfile(env_file):
            with open(env_file, encoding="utf-8", errors="ignore") as f:
                for line in f:
                    line = line.strip()
                    if line.startswith("SENSE_WEB_TOKEN="):
                        token = line.partition("=")[2].strip().strip('"').strip("'")
                        break
    if token.startswith("Bearer "):
        token = token[7:].strip()
    return token


def require_web_token():
    token = load_web_token()
    if not token:
        safe_print("[FATAL] 缺少环境变量: SENSE_WEB_TOKEN")
        safe_print("  网页版通道使用 senseaudio.cn 的登录会话令牌（非 API Key）。")
        safe_print("  获取方法：浏览器登录 senseaudio.cn → F12 → Network → 试听任意音色 →")
        safe_print("  找到 api/voice/tts 请求 → 复制 authorization 头中 Bearer 后的整串 →")
        safe_print("  写入 ~/.env:  SENSE_WEB_TOKEN=v2.public.eyJ...")
        sys.exit(1)
    return token


def token_expiration(token):
    """Decode the Paseto v2.public payload locally → datetime (or None).

    The base64url payload segment is `message JSON + 64-byte Ed25519
    signature`; the signature bytes are stripped before decoding. The
    token's `expiration` claim has nanosecond precision, so the fraction
    is trimmed to microseconds before parsing.
    """
    try:
        parts = token.split(".")
        payload = parts[2] + "=" * (-len(parts[2]) % 4)
        raw = base64.urlsafe_b64decode(payload)
        meta = json.loads(raw[:-64].decode("utf-8"))
        exp = meta.get("expiration", "")
        exp = re.sub(r"(\.\d{6})\d+", r"\1", exp)  # ns → µs
        return datetime.fromisoformat(exp.replace("Z", "+00:00"))
    except Exception:
        return None


def check_token_lifetime(token):
    """Warn when close to expiry; raise FatalAuthError when already expired."""
    exp = token_expiration(token)
    if exp is None:
        safe_print("[提示] 无法本地解析 token 过期时间，跳过预检")
        return
    now = datetime.now(timezone.utc)
    remaining = exp - now
    if remaining.total_seconds() <= 0:
        raise FatalAuthError(
            f"SENSE_WEB_TOKEN 已于 {exp:%Y-%m-%d %H:%M} UTC 过期。"
            "请重新登录 senseaudio.cn 并更新 ~/.env 中的 SENSE_WEB_TOKEN。")
    days = remaining.total_seconds() / 86400
    if days < 7:
        safe_print(f"[警告] SENSE_WEB_TOKEN 将在 {days:.1f} 天后过期，请留意及时更换")


# ---------------------------------------------------------------------------
# Web API client
# ---------------------------------------------------------------------------

def _web_headers(token, content_type=None):
    h = {
        "authorization": "Bearer " + token,
        "user-agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                      "AppleWebKit/537.36 (KHTML, like Gecko) "
                      "Chrome/152.0.0.0 Safari/537.36",
        "x-platform": "WEB",
        "x-product": "SenseAudio",
        "accept-encoding": "identity",
    }
    if content_type:
        h["content-type"] = content_type
    return h


def _http_json(url, token, payload=None, timeout=90):
    """GET/POST JSON on the web API. Raises HTTPError for caller handling."""
    if payload is None:
        req = urllib.request.Request(url, headers=_web_headers(token), method="GET")
    else:
        req = urllib.request.Request(
            url, data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
            headers=_web_headers(token, "application/json"), method="POST")
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode("utf-8"))


# ---------------------------------------------------------------------------
# Voice catalog (label → UUID), with local cache
# ---------------------------------------------------------------------------

def fetch_voice_catalog(token, force=False):
    """Return {label: {"uuid","name","emotion"}} from the web voice list.

    Cached in ~/.sense_web_voice_map.json with a weekly TTL; a cache miss
    on synthesis (HTTP 404) triggers a force refresh in the caller.
    """
    now = time.time()
    if not force and os.path.isfile(CATALOG_CACHE):
        try:
            cache = json.load(open(CATALOG_CACHE, encoding="utf-8"))
            if now - cache.get("fetched_at", 0) < CATALOG_TTL:
                return cache["voices"]
        except Exception:
            pass  # corrupt cache → refetch

    body = _http_json(WEB_VOICE_LIST_URL, token)
    voices = {}
    for item in body.get("list", []):
        uuid = item.get("id", "")
        name = item.get("voice_name", "")
        for m in item.get("models", []):
            label = m.get("label", "")
            if label:
                voices[label] = {"uuid": uuid, "name": name,
                                 "emotion": m.get("emotion", "")}
    try:
        json.dump({"fetched_at": now, "voices": voices},
                  open(CATALOG_CACHE, "w", encoding="utf-8"), ensure_ascii=False)
    except OSError:
        pass  # cache write is best-effort
    return voices


# ---------------------------------------------------------------------------
# Synthesis
# ---------------------------------------------------------------------------

def web_synthesize(token, catalog, voice_label, content, speed, pitch):
    """Synthesize one line via the web channel. Returns raw WAV bytes.

    Raises FatalAuthError on 401/expired token; refreshes the catalog once
    and retries on 404 (voice uuid mismatch / stale cache).
    """
    entry = catalog.get(voice_label)
    if not entry:
        raise RuntimeError(
            f"音色 {voice_label} 不在网页版音色目录中（共 {len(catalog)} 个标签），"
            "请检查 references/sense_tts_voices.md 或运行 --check 查看可用音色")

    payload = {
        "text": content,
        "voice_id": entry["uuid"],
        "voice": voice_label,
        "latex_read": False,
        "dictionary": [],
        "model": WEB_MODEL,
        "params": {"speed": speed, "pitch": int(round(pitch)), "volume": 1},
    }

    for attempt in (1, 2):
        try:
            body = _http_json(WEB_TTS_URL, token, payload)
        except urllib.error.HTTPError as e:
            detail = e.read().decode("utf-8", errors="replace")[:200]
            if e.code == 401:
                raise FatalAuthError(
                    "HTTP 401 未登录：SENSE_WEB_TOKEN 无效或已过期。"
                    "请重新登录 senseaudio.cn，抓取新的 authorization 并更新 ~/.env。")
            if e.code == 404 and attempt == 1:
                # Stale catalog → uuid no longer matches the label.
                safe_print("  [提示] 音色 404，刷新音色目录后重试…")
                catalog.clear()
                catalog.update(fetch_voice_catalog(token, force=True))
                new = catalog.get(voice_label)
                if not new:
                    raise RuntimeError(f"刷新目录后仍未找到音色 {voice_label}")
                payload["voice_id"] = new["uuid"]
                continue
            raise RuntimeError(f"HTTP {e.code}: {detail}")

        url = body.get("download_url")
        if not url:
            raise RuntimeError(f"响应缺少 download_url: {json.dumps(body, ensure_ascii=False)[:200]}")

        req = urllib.request.Request(url, headers={"user-agent": "Mozilla/5.0",
                                                   "accept-encoding": "identity"})
        with urllib.request.urlopen(req, timeout=60) as resp:
            wav = resp.read()

        if wav[:4] != b"RIFF" or wav[8:12] != b"WAVE":
            raise RuntimeError("下载的音频不是 WAV 格式（网页通道格式可能已变化）")
        return wav

    raise RuntimeError("合成重试用尽（不应到达此处）")


def call_web_tts(token, catalog, voice_id, content, speed, pitch, output_path,
                 max_retries=3):
    """Synthesize one line and save WAV to output_path. True on success."""
    speed_f = _to_float(speed, 1.0)
    if not (0.5 <= speed_f <= 2.0):
        clamped = min(2.0, max(0.5, speed_f))
        safe_print(f"  [警告] speed {speed} 超出 [0.5, 2.0]，已钳制为 {clamped}")
        speed_f = clamped
    pitch_f = _to_float(pitch, 0.0)
    if not (-12 <= pitch_f <= 12):
        clamped = min(12, max(-12, pitch_f))
        safe_print(f"  [警告] pitch {pitch} 超出 [-12, 12]，已钳制为 {clamped}")
        pitch_f = clamped

    cleaned = clean_text(content)
    if not cleaned:
        safe_print("  [跳过] 清理后文本为空（原文无有效内容）")
        return False

    for attempt in range(1, max_retries + 1):
        try:
            audio = web_synthesize(token, catalog, voice_id, cleaned,
                                   speed_f, pitch_f)
            os.makedirs(os.path.dirname(output_path), exist_ok=True)
            with open(output_path, "wb") as f:
                f.write(audio)
            return True
        except FatalAuthError:
            raise  # abort the whole run; retrying with the same token is futile
        except urllib.error.URLError as e:
            safe_print(f"  [错误] 网络错误: {e.reason}")
        except RuntimeError as e:
            safe_print(f"  [错误] {e}")

        if attempt < max_retries:
            wait = attempt * 10
            safe_print(f"  [重试] 第 {attempt} 次失败，{wait}s 后重试…")
            time.sleep(wait)

    return False


# ---------------------------------------------------------------------------
# Core processing (mirrors tts.py process_lines)
# ---------------------------------------------------------------------------

def process_lines(workdir, target_line=None, delay=None):
    token = require_web_token()
    try:
        check_token_lifetime(token)
    except FatalAuthError as e:
        safe_print(f"[FATAL] {e}")
        sys.exit(1)

    catalog = fetch_voice_catalog(token)

    rows = read_csv(workdir)
    voices_dir = os.path.join(workdir, "voices")
    os.makedirs(voices_dir, exist_ok=True)

    if delay is None:
        delay = 0.3

    safe_print(f"[INFO] 后端: 商汤 SenseAudio 网页版通道（{WEB_MODEL}，"
               "限免期间通常免费；音色 {0} 个标签）".format(len(catalog)))

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
    failed = []
    char_count = 0

    try:
        for i, row_idx in enumerate(indices, 1):
            row = rows[row_idx]
            line_num = row_idx + 1
            voice_id = (row.get("voice_id") or "").strip()
            content = (row.get("content") or "").strip()
            speed = (row.get("speed") or "").strip()
            pitch = (row.get("pitch") or "").strip()

            if not voice_id or not content:
                safe_print(f"  [{i}/{len(indices)}] 行 {line_num}: 跳过（voice_id 或 content 为空）")
                continue

            output_path = os.path.join(voices_dir, f"{line_num}.wav")
            preview = content[:40] + ("…" if len(content) > 40 else "")
            safe_print(f"  [{i}/{len(indices)}] 行 {line_num} [{voice_id}]: {preview}")

            ok = call_web_tts(token, catalog, voice_id, content, speed, pitch,
                              output_path)
            if ok:
                mark_done(workdir, row_idx, rows)
                success += 1
                char_count += len(clean_text(content))
                safe_print(f"    ✓ 已保存 voices/{line_num}.wav")
            else:
                failed.append(line_num)
                safe_print(f"    ✗ 行 {line_num} 生成失败，已跳过")

            if delay and i < len(indices):
                time.sleep(delay)
    except FatalAuthError as e:
        safe_print(f"\n[FATAL] 鉴权错误，中止本次运行: {e}")
        safe_print("       更新 ~/.env 中的 SENSE_WEB_TOKEN 后重新运行即可续传。")
        sys.exit(1)

    safe_print(f"\n[完成] 成功 {success} 行，失败 {len(failed)} 行，"
               f"合成约 {char_count} 字符（限免期间通常不计费）。")
    if failed:
        safe_print(f"[警告] 失败行号: {failed}")
        safe_print("       可重新运行此脚本，将自动跳过已完成的行。")
    if success > 0:
        check_meta_phase(workdir, "Phase 4")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def run_check(probe=False):
    token = require_web_token()
    masked = (token[:12] + "…" + token[-6:]) if len(token) > 20 else "****"
    safe_print(f"[INFO] token: {masked}")
    check_token_lifetime(token)

    try:
        catalog = fetch_voice_catalog(token, force=True)
    except urllib.error.HTTPError as e:
        detail = ""
        if hasattr(e, "read"):
            detail = e.read().decode("utf-8", errors="replace")[:150]
        safe_print(f"✗ 鉴权失败: HTTP {e.code} {detail}")
        safe_print("  请重新登录 senseaudio.cn 抓取新 token 并更新 ~/.env 的 SENSE_WEB_TOKEN。")
        sys.exit(1)
    except Exception as e:
        safe_print(f"✗ 连接失败: {e}")
        sys.exit(1)

    names = {}
    for label, entry in catalog.items():
        names.setdefault(entry["name"], []).append(label)
    safe_print(f"✓ 连接正常，网页版音色目录共 {len(names)} 个角色 / {len(catalog)} 个标签")
    # Podcast-relevant voices worth surfacing (verified usable via web channel)
    highlights = ["播客才女", "专业女播", "利落青年", "青春女声", "可靠青叔",
                  "温柔御姐", "气质学姐", "魅力姐姐", "儒雅道长", "沙哑青年"]
    for name in highlights:
        if name in names:
            safe_print(f"    {name}: {', '.join(sorted(names[name]))}")
    safe_print("  [提示] 网页版通道包含开放 API 看不到的音色与限免 SVIP 音色；")
    safe_print("         完整清单与说明见 references/sense_tts_voices.md。")

    if probe:
        safe_print("[探测] 合成 5 个字符验证端到端可用性…")
        try:
            audio = web_synthesize(token, catalog, "female_0006_a", "你好，测试。", 1.0, 0)
            safe_print(f"✓ 合成成功，返回 {len(audio)} 字节 WAV")
        except Exception as e:
            safe_print(f"✗ 合成失败: {e}")
            sys.exit(1)


def main():
    args = sys.argv[1:]

    if args and args[0] == "--check":
        run_check(probe="--probe" in args[1:])
        return
    if not args:
        run_check()
        return

    workdir = None
    target_line = None
    delay = None

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
        safe_print("用法: python web_tts.py <workdir> [--line N] [--delay SECONDS]")
        safe_print("      python web_tts.py --check [--probe]")
        sys.exit(1)

    workdir = validate_workdir(workdir)
    process_lines(workdir, target_line=target_line, delay=delay)


if __name__ == "__main__":
    main()
