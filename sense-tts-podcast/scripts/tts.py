#!/usr/bin/env python
"""
SenseAudio TTS Podcast — TTS Generation Script

Usage:
  python tts.py <workdir>              # Process all undone lines
  python tts.py <workdir> --line N     # Process a specific line (1-indexed)
  python tts.py <workdir> --delay 0.5  # Seconds to wait between lines
  python tts.py --check                # Verify token + list visible voices
  python tts.py --check --probe        # Additionally synthesize 3 chars (paid)

Backend: SenseAudio (SenseTime) non-streaming TTS
  POST https://api.senseaudio.cn/v1/t2a_v2   (stream=false)
  Bearer auth via SENSE_AUDIO_TOKEN. Paid API — billing is per character,
  so every line generated consumes quota; use --line N to regenerate
  single lines instead of whole runs.

The response embeds the MP3 as a hex string in data.audio. Returned files
carry a leading ID3v2 tag and trailing encoder padding; both are stripped
so saved files are bare MPEG frames (44.1kHz/128kbps/mono), safe to byte-
concatenate with scripts/silence/*.mp3 by concat.py.

Environment variables (priority: system env > ~/.env):
  SENSE_AUDIO_TOKEN  — required; SenseAudio API token (Bearer)
  SENSE_TTS_MODEL    — optional; defaults to sensenova-tts-2.0

lines.csv columns: done / voice_id / content / speed / pitch
  speed — rate multiplier, 0.5–2.0, blank = 1.0
  pitch — semitone offset, integer -12..+12, blank = 0

Python: 3.7+  (stdlib only, no third-party dependencies)
"""

from __future__ import annotations

import os
import re
import sys
import csv
import time
import json
import uuid
import urllib.request
import urllib.error

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

API_BASE = "https://api.senseaudio.cn"
DEFAULT_MODEL = "sensenova-tts-2.0"

# Match the silence assets in scripts/silence/ (44.1kHz mono 128kbps) so that
# raw byte concatenation in concat.py stays uniform.
AUDIO_FORMAT = "mp3"
AUDIO_SAMPLE_RATE = 44100
AUDIO_BITRATE = 128000
AUDIO_CHANNEL = 1

MAX_TEXT_CHARS = 10000  # API hard limit per request


def load_env():
    """Load SENSE_AUDIO_TOKEN and optional SENSE_TTS_MODEL.

    Priority: system env → ~/.env
    Returns (token, model); token is "" when unconfigured.
    """
    token = os.environ.get("SENSE_AUDIO_TOKEN", "").strip()
    model  = os.environ.get("SENSE_TTS_MODEL", "").strip()

    if not token or not model:
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
                    if k == "SENSE_AUDIO_TOKEN" and not token:
                        token = v
                    elif k == "SENSE_TTS_MODEL" and not model:
                        model = v

    return token, (model or DEFAULT_MODEL)


def require_token():
    """Load the token or exit with configuration instructions."""
    token, model = load_env()
    if not token:
        safe_print("[FATAL] 缺少环境变量: SENSE_AUDIO_TOKEN")
        safe_print("  请在 ~/.env 或系统环境变量中配置:")
        safe_print("    SENSE_AUDIO_TOKEN=your_senseaudio_api_token")
        safe_print("  参考: .env.example")
        sys.exit(1)
    return token, model


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
    """Read lines.csv into a list of dicts with keys matching HEADER.

    Structure validation (fatal on violation):
      - Header must contain the 3 required columns: done / voice_id / content.
        speed and pitch are optional (rows may omit trailing columns).
      - Every data row must provide at least those 3 fields. A stray Tab in
        content shifts columns into an extra field; an embedded newline
        truncates the row — both would synthesize wrong audio, so we abort
        with the physical file line number instead of guessing.
    """
    csv_path = os.path.join(workdir, "lines.csv")
    if not os.path.isfile(csv_path):
        safe_print(f"[FATAL] 找不到 lines.csv: {csv_path}")
        sys.exit(1)

    REQUIRED = HEADER[:3]  # done / voice_id / content
    rows = []
    errors = []
    with open(csv_path, encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f, delimiter="\t")
        if not reader.fieldnames:
            safe_print(f"[FATAL] lines.csv 为空或缺少表头: {csv_path}")
            sys.exit(1)
        missing_cols = [c for c in REQUIRED if c not in reader.fieldnames]
        if missing_cols:
            safe_print(f"[FATAL] lines.csv 表头缺少必需列 {missing_cols}，实际表头: {reader.fieldnames}")
            sys.exit(1)

        for row in reader:
            line_no = reader.line_num  # physical line number in the file
            # Extra fields land under the None key → content held a stray Tab
            # that pushed the row past 5 columns.
            if None in row:
                errors.append(f"第 {line_no} 行: 字段数超出表头（content 中可能混入了 Tab）")
                continue
            # Missing trailing columns become None values; speed/pitch may be
            # absent, but the 3 required columns must all exist.
            absent = [c for c in REQUIRED if row.get(c) is None]
            if absent:
                errors.append(f"第 {line_no} 行: 缺少必需字段 {absent}（可能被换行截断）")
                continue
            # A stray Tab inside content with exactly 5 total fields shifts
            # text into speed/pitch — detectable as non-numeric values there.
            for col in ("speed", "pitch"):
                val = (row.get(col) or "").strip()
                if val:
                    try:
                        float(val)
                    except ValueError:
                        errors.append(
                            f"第 {line_no} 行: {col} 列为非数值文本 {val[:20]!r}"
                            f"（content 中可能混入了 Tab 导致列错位）")
                        break
            if errors and errors[-1].startswith(f"第 {line_no} 行:"):
                continue
            # Normalize optional columns to "" so downstream code and
            # write_csv see a uniform shape (setdefault won't overwrite an
            # existing None key, hence the explicit assignment).
            for col in HEADER[3:]:
                if row.get(col) is None:
                    row[col] = ""
            rows.append(dict(row))

    if errors:
        safe_print(f"[FATAL] lines.csv 格式错误，共 {len(errors)} 行异常，已中止：")
        for msg in errors[:10]:
            safe_print(f"  - {msg}")
        if len(errors) > 10:
            safe_print(f"  - …另有 {len(errors) - 10} 行异常")
        safe_print("       请修复 lines.csv 后重新运行（content 内不得含 Tab 或换行）。")
        sys.exit(1)
    return rows


def write_csv(workdir, rows):
    """Write rows back to lines.csv atomically (preserves all columns)."""
    csv_path = os.path.join(workdir, "lines.csv")
    if not rows:
        return
    # Always emit the full 5-column header so optional speed/pitch survive
    # round-trips even when some rows omit them (DictWriter fills restval="").
    all_keys = list(rows[0].keys())
    fieldnames = list(HEADER)
    for k in all_keys:
        if k not in fieldnames:
            fieldnames.append(k)

    tmp_path = csv_path + ".tmp"
    with open(tmp_path, "w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames, delimiter="\t",
                                extrasaction="ignore", restval="")
        writer.writeheader()
        writer.writerows(rows)

    os.replace(tmp_path, csv_path)


def mark_done(workdir, row_index, rows):
    """Mark rows[row_index] as done=1 and persist immediately."""
    rows[row_index]["done"] = "1"
    write_csv(workdir, rows)


def check_meta_phase(workdir, phase_label):
    """Tick a phase checkbox in meta.md (e.g. 'Phase 4: TTS 生成').

    Best-effort: missing meta.md or unmatched label is silently ignored —
    progress tracking must never break audio generation. Only ticks an
    unticked box; already-checked phases are left untouched.
    """
    meta_path = os.path.join(workdir, "meta.md")
    if not os.path.isfile(meta_path):
        return
    try:
        with open(meta_path, encoding="utf-8") as f:
            content = f.read()
        # Match "- [ ] Phase 4: TTS 生成" allowing flexible spacing/label text
        pattern = re.compile(r"(- \[ \] )(Phase \d+[^\n]*)")
        def _tick(match):
            label = match.group(2)
            if label.startswith(phase_label):
                return f"- [x] {label}"
            return match.group(0)
        new_content = pattern.sub(_tick, content)
        if new_content != content:
            with open(meta_path, "w", encoding="utf-8", newline="") as f:
                f.write(new_content)
    except OSError:
        pass  # Non-critical


# ---------------------------------------------------------------------------
# Text cleaning (provider-agnostic podcast hygiene)
# ---------------------------------------------------------------------------

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
    """Strip markdown / emoji / urls / citation numbers before synthesis.

    <break time="ms"/> tags are NOT stripped: SenseAudio interprets them
    natively in the text field (min 100ms), so they remain a way for the
    script writer to request in-line pauses.
    """
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


# ---------------------------------------------------------------------------
# MP3 post-processing: strip ID3v2 header and trailing padding
# ---------------------------------------------------------------------------

# MPEG audio version → sample-rate table; bitrate index table (Layer III).
_MP3_RATES = {
    3: {0: 44100, 1: 48000, 2: 32000},   # MPEG 1
    2: {0: 22050, 1: 24000, 2: 16000},   # MPEG 2
    0: {0: 11025, 1: 12000, 2: 8000},    # MPEG 2.5
}
_MP3_BITRATES = [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 0]


def _strip_to_mpeg_frames(audio):
    """Return the [first_frame, end_of_last_frame) byte range of an MP3.

    SenseAudio (Lavf) output starts with an ID3v2 tag and ends with encoder
    padding. Embedding either inside a concatenated MP3 stream is invalid, so
    both ends are trimmed to raw MPEG frame boundaries — matching the silence
    assets and making plain byte concatenation safe. Falls back to the input
    (minus ID3) when no frame can be parsed, so audio is never lost.
    """
    start = 0
    if audio[:3] == b"ID3":
        # ID3v2 header: "ID3" ver(2) flags(1) syncsafe-size(4)
        sz = audio[6:10]
        start = 10 + ((sz[0] & 0x7F) << 21 | (sz[1] & 0x7F) << 14
                      | (sz[2] & 0x7F) << 7 | (sz[3] & 0x7F))

    first_frame = None
    last_end = None
    i = start
    n = len(audio)
    while i < n - 4:
        if audio[i] == 0xFF and (audio[i + 1] & 0xE0) == 0xE0:
            h = int.from_bytes(audio[i:i + 4], "big")
            ver = (h >> 19) & 3
            layer = (h >> 17) & 3
            br_i = (h >> 12) & 0xF
            sr_i = (h >> 10) & 3
            pad = (h >> 9) & 1
            if (ver in _MP3_RATES and layer == 1
                    and br_i not in (0, 15) and sr_i != 3):
                sr = _MP3_RATES[ver][sr_i]
                br = _MP3_BITRATES[br_i] * 1000
                flen = 144 * br // sr + pad
                if i + flen <= n:
                    if first_frame is None:
                        first_frame = i
                    last_end = i + flen
                    i += flen
                    continue
        i += 1

    if first_frame is None:
        return audio[start:]  # unparsable: best effort, keep everything

    return audio[first_frame:last_end]


# ---------------------------------------------------------------------------
# SenseAudio API client
# ---------------------------------------------------------------------------

class FatalAuthError(Exception):
    """Token invalid or voice-access denial severe enough to stop the run."""


def _api_post(path, token, payload, timeout=60):
    """POST JSON to the SenseAudio API and return the parsed body.

    Raises urllib.error.HTTPError as-is for caller-specific handling.
    """
    req = urllib.request.Request(
        f"{API_BASE}{path}",
        data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json; charset=utf-8",
            "User-Agent": "sense-tts-podcast/1.0",
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode("utf-8"))


def sense_synthesize(token, model, voice_id, content, speed, pitch):
    """Synthesize one line. Returns MP3 bytes (bare MPEG frames).

    Raises:
      FatalAuthError  — invalid token (HTTP 401) or no access to the voice
                        (HTTP 403 / base_resp 403): retrying cannot help.
      RuntimeError    — API-level refusal with the status message.
      urllib.error.URLError — transient network failure (caller retries).
    """
    if len(content) > MAX_TEXT_CHARS:
        raise RuntimeError(f"文本超过 {MAX_TEXT_CHARS} 字符上限")

    payload = {
        "model": model,
        "text": content,
        "stream": False,
        "voice_setting": {
            "voice_id": voice_id,
            "speed": speed,
            "vol": 1,
            "pitch": int(round(pitch)),
        },
        "audio_setting": {
            "format": AUDIO_FORMAT,
            "sample_rate": AUDIO_SAMPLE_RATE,
            "bitrate": AUDIO_BITRATE,
            "channel": AUDIO_CHANNEL,
        },
        # Do not let the API emit an extra aggregated-audio event field.
        "stream_options": {"exclude_aggregated_audio": True},
    }

    try:
        body = _api_post("/v1/t2a_v2", token, payload)
    except urllib.error.HTTPError as e:
        body_text = e.read().decode("utf-8", errors="replace")[:300]
        if e.code == 401:
            raise FatalAuthError(f"HTTP 401: token 无效（{body_text}）")
        if e.code == 403:
            raise FatalAuthError(
                f"HTTP 403: 无权使用音色 {voice_id}（套餐不含该音色，"
                f"参见 references/sense_tts_voices.md 的套餐分级）")
        raise RuntimeError(f"HTTP {e.code}: {body_text}")

    base = body.get("base_resp") or {}
    status_code = base.get("status_code", -1)
    if status_code != 0:
        msg = base.get("status_msg", "unknown")
        if status_code == 403 or "voice" in msg.lower() and "access" in msg.lower():
            raise FatalAuthError(f"base_resp {status_code}: {msg}（音色 {voice_id} 不在当前套餐内）")
        raise RuntimeError(f"API status_code={status_code}: {msg}")

    data = body.get("data") or {}
    audio_hex = data.get("audio") or ""
    if not audio_hex:
        raise RuntimeError("API 成功但未返回音频数据（data.audio 为空）")

    audio = bytes.fromhex(audio_hex)
    trimmed = _strip_to_mpeg_frames(audio)
    if not trimmed:
        raise RuntimeError("返回音频经帧裁剪后为空")

    # Cross-check the delivered format so a silent server-side change to the
    # audio settings surfaces as a warning instead of a broken podcast.
    extra = body.get("extra_info") or {}
    if extra.get("audio_sample_rate") not in (None, AUDIO_SAMPLE_RATE) or \
       extra.get("audio_channel") not in (None, AUDIO_CHANNEL):
        safe_print(f"  [警告] 返回音频参数与预期不符: {extra}")

    return trimmed


def get_voices(token):
    """Fetch the account's visible voice catalog (no synthesis billing)."""
    body = _api_post("/v1/get_voice", token, {"voice_type": "all"}, timeout=30)
    base = body.get("base_resp") or {}
    if base.get("status_code", -1) != 0:
        raise RuntimeError(f"get_voice 失败: {base.get('status_msg')}")
    return {
        "system_voice": body.get("system_voice") or [],
        "voice_cloning": body.get("voice_cloning") or [],
        "voice_generation": body.get("voice_generation") or [],
    }


# ---------------------------------------------------------------------------
# Backend dispatch
# ---------------------------------------------------------------------------

def _to_float(value, default):
    try:
        return float(value)
    except (ValueError, TypeError):
        return default


def call_tts(token, model, voice_id, content, speed, pitch, output_path,
             max_retries=3):
    """Synthesize one line and save it to output_path.

    Transient network/server errors retry with backoff (10s / 20s).
    FatalAuthError aborts the whole run. Returns True on success.
    """
    # SenseAudio speed is a 0.5–2.0 multiplier (same semantics as the CSV
    # column); pitch is a semitone offset clamped to the API's [-12, 12].
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
            audio = sense_synthesize(token, model, voice_id, cleaned,
                                     speed_f, pitch_f)
            os.makedirs(os.path.dirname(output_path), exist_ok=True)
            with open(output_path, "wb") as f:
                f.write(audio)
            return True

        except FatalAuthError as e:
            safe_print(f"  [错误] {e}")
            raise  # credentials/plan issues will not fix themselves

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
# Core processing
# ---------------------------------------------------------------------------

def process_lines(workdir, target_line=None, delay=None):
    """Process undone lines in lines.csv, one at a time.

    target_line: int (1-indexed) to process only that line, or None for all.
    delay:       seconds to sleep between lines; None → 0.3s default.
    """
    token, model = require_token()

    rows = read_csv(workdir)
    voices_dir = os.path.join(workdir, "voices")
    os.makedirs(voices_dir, exist_ok=True)

    if delay is None:
        # Modest spacing keeps us clear of API rate limits.
        delay = 0.3

    safe_print(f"[INFO] 后端: 商汤 SenseAudio（{model}，按字符计费）")

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
    char_count = 0  # billed characters this run (informational)

    try:
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

            ok = call_tts(token, model, voice_id, content, speed, pitch, output_path)
            if ok:
                mark_done(workdir, row_idx, rows)
                success += 1
                char_count += len(clean_text(content))
                safe_print(f"    ✓ 已保存 voices/{line_num}.mp3")
            else:
                failed.append(line_num)
                safe_print(f"    ✗ 行 {line_num} 生成失败，已跳过")

            if delay and i < len(indices):
                time.sleep(delay)
    except FatalAuthError as e:
        # Token/plan-level problem: stop the run instead of failing every line.
        safe_print(f"\n[FATAL] 鉴权/权限错误，中止本次运行: {e}")
        safe_print("       修正 token 或改用当前套餐可用音色后，重新运行本脚本即可续传。")
        sys.exit(1)

    safe_print(f"\n[完成] 成功 {success} 行，失败 {len(failed)} 行，本次消耗约 {char_count} 字符额度。")
    if failed:
        safe_print(f"[警告] 失败行号: {failed}")
        safe_print("       可重新运行此脚本，将自动跳过已完成的行。")
    # Tick the Phase 4 checkbox in meta.md (best-effort, never fatal)
    if success > 0:
        check_meta_phase(workdir, "Phase 4")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def run_check(probe=False):
    """Verify the token, list visible voice groups, optionally probe synthesis."""
    token, model = require_token()
    masked = (token[:4] + "****" + token[-4:]) if len(token) > 8 else "****"
    safe_print(f"[INFO] token: {masked}  model: {model}")

    try:
        catalog = get_voices(token)
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", errors="replace")[:200] if hasattr(e, "read") else ""
        safe_print(f"✗ 鉴权失败: HTTP {e.code} {detail}")
        safe_print("  请检查 SENSE_AUDIO_TOKEN 是否正确。")
        sys.exit(1)
    except Exception as e:
        safe_print(f"✗ 连接失败: {e}")
        sys.exit(1)

    system_voices = catalog["system_voice"]
    chars = {}
    for v in system_voices:
        chars.setdefault(v.get("voice_name") or v["voice_id"], []).append(v["voice_id"])
    safe_print(f"✓ 连接正常，账号可见 {len(system_voices)} 个系统音色（{len(chars)} 个角色）:")
    for name, vids in sorted(chars.items()):
        safe_print(f"    {name}: {', '.join(sorted(vids))}")
    if catalog["voice_cloning"] or catalog["voice_generation"]:
        safe_print(f"  另有克隆/生成音色 {len(catalog['voice_cloning']) + len(catalog['voice_generation'])} 个")
    safe_print("  [提示] get_voice 返回的是\"可见\"音色；能否实际合成取决于套餐等级，")
    safe_print("         详见 references/sense_tts_voices.md。预设组合默认使用免费档音色。")

    if probe:
        safe_print("[探测] 合成 3 个字符验证端到端可用性（消耗少量额度）…")
        try:
            audio = sense_synthesize(token, model, "male_0004_a", "你好呀", 1.0, 0)
            safe_print(f"✓ 合成成功，返回 {len(audio)} 字节 MP3（免费档音色可用）")
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
        safe_print("      python tts.py --check [--probe]")
        sys.exit(1)

    # Validate and normalize workdir (handles relative paths, creates subdirs)
    workdir = validate_workdir(workdir)

    process_lines(workdir, target_line=target_line, delay=delay)


if __name__ == "__main__":
    main()
