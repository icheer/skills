#!/usr/bin/env python
"""
Edge TTS Podcast — Audio Concatenation Script

Concatenates all voices/{n}.mp3 files in a podcast workdir into a single
podcast.mp3, inserting silence between each segment. After a successful
concatenation, also exports a readable transcript.md and timestamped
podcast.srt from lines.csv.

Usage:
  python concat.py <workdir>                        # default 500ms silence
  python concat.py <workdir> --silence 250          # 250ms silence
  python concat.py <workdir> --silence 0            # no silence
  python concat.py <workdir> --output out.mp3       # custom output path
  python concat.py <workdir> --subtitle-max-length 25  # subtitle line length
  python concat.py <workdir> --list                 # list files only, no concat

Silence files are looked up relative to this script:
  scripts/silence/250ms.mp3
  scripts/silence/500ms.mp3
  scripts/silence/750ms.mp3
  scripts/silence/1000ms.mp3

If the silence file is missing, a warning is printed and silence is skipped.
SRT timing uses durations parsed from actual MPEG audio frames. Long text is
split near its midpoint at punctuation and allocated proportionally, because
the Edge TTS MP3 response does not include word-boundary timestamps.

Python: 3.7+  (PEP 604 annotations deferred via __future__ import)
"""

from __future__ import annotations

import os
import sys
import glob
import re
import csv

# 默认的逐条字幕最大可见单位数。中文按单字、英文按单词计；可直接修改本
# 常量以调试观看节奏，也可以通过 --subtitle-max-length 在单次运行时覆盖。
DEFAULT_SUBTITLE_MAX_UNITS = 40

# 按 DEFAULT_SUBTITLE_MAX_UNITS 切分的字幕使用该文件名；完整句子版固定
# 使用标准文件名 podcast.srt，适合严肃阅读、检索与校对。
SPLITTED_SRT_FILENAME = "podcast_splitted.srt"

# ---------------------------------------------------------------------------
# Workdir validation
# ---------------------------------------------------------------------------

def validate_workdir(workdir_arg: str) -> str:
    """Validate and normalize the working directory (same logic as tts.py)."""
    workdir = os.path.abspath(workdir_arg)
    dirname = os.path.basename(workdir)
    if not re.match(r'^\d{4}-\d{2}-\d{2}_', dirname):
        print(f"[警告] 工作目录命名不符合技能约定（应为 YYYY-MM-DD_topic）: {dirname}")
        print(f"       当前路径: {workdir}")

    # concat.py 只验证目录存在，不负责创建（创建应由 tts.py 或 agent 在 Phase 1 完成）
    if not os.path.isdir(workdir):
        print(f"[FATAL] 工作目录不存在: {workdir}")
        print(f"       请确认路径正确，或先运行 tts.py 创建目录结构。")
        sys.exit(1)

    print(f"[INFO] 工作目录（已规范化）: {workdir}")
    return workdir

# ---------------------------------------------------------------------------
# ID3 tag stripping
# ---------------------------------------------------------------------------

def strip_id3v2(data: bytes) -> bytes:
    """Strip ID3v2 tag from the start of MP3 data."""
    if len(data) < 10:
        return data
    if data[:3] != b"ID3":
        return data
    # Synchsafe integer in bytes 6-9
    size = (
        ((data[6] & 0x7F) << 21)
        | ((data[7] & 0x7F) << 14)
        | ((data[8] & 0x7F) << 7)
        | (data[9] & 0x7F)
    )
    # 10-byte header + optional extended header flag in byte 5 bit 6
    # We just skip the declared size (already includes extended header if any)
    offset = 10 + size
    return data[offset:] if offset <= len(data) else data


def strip_id3v1(data: bytes) -> bytes:
    """Strip ID3v1 tag from the end of MP3 data (last 128 bytes, 'TAG')."""
    if len(data) >= 128 and data[-128:-125] == b"TAG":
        return data[:-128]
    return data


def clean_mp3(data: bytes) -> bytes:
    """Strip both ID3v1 and ID3v2 tags."""
    data = strip_id3v2(data)
    data = strip_id3v1(data)
    return data


# ---------------------------------------------------------------------------
# File discovery
# ---------------------------------------------------------------------------

def find_voice_files(voices_dir: str) -> list:
    """Return sorted list of voices/{n}.mp3 paths (sorted by integer n)."""
    pattern = os.path.join(voices_dir, "*.mp3")
    files = glob.glob(pattern)

    def extract_num(p):
        name = os.path.splitext(os.path.basename(p))[0]
        try:
            return int(name)
        except ValueError:
            return float("inf")  # non-numeric files sorted last

    return sorted(files, key=extract_num)


def find_silence_file(silence_ms: int) -> str | None:
    """Return path to the silence MP3 for the given duration, or None."""
    script_dir = os.path.dirname(os.path.abspath(__file__))
    silence_dir = os.path.join(script_dir, "silence")
    candidate = os.path.join(silence_dir, f"{silence_ms}ms.mp3")
    if os.path.isfile(candidate):
        return candidate
    return None


# ---------------------------------------------------------------------------
# MPEG audio duration parsing
# ---------------------------------------------------------------------------

# concat.py deliberately has no third-party dependencies. Edge TTS produces
# MPEG Layer III frames; their sample counts and sample rates give a stable
# duration without relying on unreliable file-size/bitrate estimates.
_BITRATES = {
    "v1_l1": [0, 32, 64, 96, 128, 160, 192, 224, 256, 288, 320, 352, 384, 416, 448, 0],
    "v1_l2": [0, 32, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 384, 0],
    "v1_l3": [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 0],
    "v2_l1": [0, 32, 48, 56, 64, 80, 96, 112, 128, 144, 160, 176, 192, 224, 256, 0],
    "v2_l2_l3": [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160, 0],
}


def get_mp3_duration(path: str) -> tuple[float, int] | None:
    """Return ``(duration_seconds, frame_count)`` from valid MPEG frames."""
    try:
        with open(path, "rb") as f:
            data = f.read()
    except OSError as error:
        print(f"[警告] 无法读取 MP3 时长: {path}: {error}")
        return None

    data = strip_id3v1(strip_id3v2(data))
    offset = 0
    duration = 0.0
    frame_count = 0
    data_length = len(data)

    while offset + 4 <= data_length:
        header = int.from_bytes(data[offset:offset + 4], byteorder="big")
        if (header >> 21) != 0x7FF:
            offset += 1
            continue

        version_bits = (header >> 19) & 0x3
        layer_bits = (header >> 17) & 0x3
        bitrate_index = (header >> 12) & 0xF
        sample_rate_index = (header >> 10) & 0x3
        padding = (header >> 9) & 0x1
        if (version_bits == 1 or layer_bits == 0 or bitrate_index in (0, 15)
                or sample_rate_index == 3):
            offset += 1
            continue

        if version_bits == 3:
            version = "v1"
            sample_rate = [44100, 48000, 32000][sample_rate_index]
        elif version_bits == 2:
            version = "v2"
            sample_rate = [22050, 24000, 16000][sample_rate_index]
        else:
            version = "v2.5"
            sample_rate = [11025, 12000, 8000][sample_rate_index]

        if layer_bits == 3:
            bitrate_key = "v1_l1" if version == "v1" else "v2_l1"
            samples_per_frame = 384
            frame_length = ((12 * _BITRATES[bitrate_key][bitrate_index] * 1000
                             // sample_rate) + padding) * 4
        elif layer_bits == 2:
            bitrate_key = "v1_l2" if version == "v1" else "v2_l2_l3"
            samples_per_frame = 1152
            frame_length = ((144 * _BITRATES[bitrate_key][bitrate_index] * 1000
                             // sample_rate) + padding)
        else:
            bitrate_key = "v1_l3" if version == "v1" else "v2_l2_l3"
            samples_per_frame = 1152 if version == "v1" else 576
            coefficient = 144 if version == "v1" else 72
            frame_length = ((coefficient * _BITRATES[bitrate_key][bitrate_index] * 1000
                             // sample_rate) + padding)

        if frame_length < 4 or offset + frame_length > data_length:
            offset += 1
            continue

        duration += samples_per_frame / sample_rate
        frame_count += 1
        offset += frame_length

    if not frame_count:
        print(f"[警告] 未从 MP3 中识别到有效音频帧，无法计算时长: {path}")
        return None
    return duration, frame_count


# ---------------------------------------------------------------------------
# Transcript export
# ---------------------------------------------------------------------------

# Keep the body of transcript.md readable. The full Edge voice IDs remain in
# the speaker list at the top, so the compact labels do not lose traceability.
VOICE_DISPLAY_NAMES = {
    "zh-CN-YunyangNeural": "云扬",
    "zh-CN-YunxiNeural": "云希",
    "zh-CN-XiaoxiaoNeural": "晓晓",
    "zh-CN-XiaohanNeural": "晓涵",
    "zh-CN-XiaomoNeural": "晓墨",
    "zh-CN-YunjianNeural": "云健",
    "zh-CN-YunxiaNeural": "云夏",
    "zh-CN-XiaoyiNeural": "晓伊",
    "zh-CN-liaoning-XiaobeiNeural": "晓北",
    "zh-CN-shaanxi-XiaoniNeural": "晓妮",
    "zh-HK-HiuGaaiNeural": "晓佳",
    "zh-HK-HiuMaanNeural": "晓曼",
    "zh-HK-WanLungNeural": "云龙",
    "zh-TW-HsiaoChenNeural": "晓臻",
    "zh-TW-HsiaoYuNeural": "晓雨",
    "zh-TW-YunJheNeural": "云哲",
}


def normalize_transcript_text(text: str) -> str:
    """Collapse accidental line breaks while preserving a readable paragraph."""
    return re.sub(r"\s+", " ", (text or "")).strip()


def export_transcript(workdir: str) -> str | None:
    """Export lines.csv as transcript.md without affecting audio output.

    Speaker labels use a familiar localized voice name where available. Unknown
    voices are assigned stable ``说话人 N`` labels in first-appearance order,
    while their complete voice IDs are retained in the Markdown speaker list.
    Any malformed or unreadable CSV is reported as a warning and deliberately
    does not turn a successfully rendered podcast into a failed run.
    """
    csv_path = os.path.join(workdir, "lines.csv")
    output_path = os.path.join(workdir, "transcript.md")

    if not os.path.isfile(csv_path):
        print(f"[警告] 未找到 lines.csv，跳过文字稿导出: {csv_path}")
        return None

    try:
        with open(csv_path, encoding="utf-8-sig", newline="") as f:
            rows = list(csv.DictReader(f, delimiter="\t"))
    except (OSError, csv.Error, UnicodeError) as error:
        print(f"[警告] 无法读取 lines.csv，跳过文字稿导出: {error}")
        return None

    entries = []
    speaker_labels = {}
    used_labels = set()
    unknown_speaker_count = 0

    for row in rows:
        content = normalize_transcript_text(row.get("content", ""))
        voice_id = (row.get("voice_id") or "").strip()
        if not content:
            continue

        # A missing voice ID should remain visible instead of silently being
        # attributed to another speaker.
        speaker_key = voice_id or "__missing_voice_id__"
        if speaker_key not in speaker_labels:
            label = VOICE_DISPLAY_NAMES.get(voice_id)
            if not label:
                unknown_speaker_count += 1
                label = f"说话人 {unknown_speaker_count}"
            base_label = label
            suffix = 2
            while label in used_labels:
                label = f"{base_label} {suffix}"
                suffix += 1
            speaker_labels[speaker_key] = label
            used_labels.add(label)

        entries.append((speaker_key, content))

    if not entries:
        print("[警告] lines.csv 中没有可导出的 content，跳过文字稿导出")
        return None

    try:
        with open(output_path, "w", encoding="utf-8", newline="\n") as f:
            f.write("# 播客文字稿\n\n")
            f.write(
                "> 此文件由 `lines.csv` 自动生成；音频拼合成功后导出。"
                "说话人名称为便于阅读的简写，完整音色 ID 见下方。\n\n"
            )
            f.write("## 说话人\n\n")
            for speaker_key, label in speaker_labels.items():
                voice_description = speaker_key if speaker_key != "__missing_voice_id__" else "未填写 voice_id"
                f.write(f"- **{label}**：`{voice_description}`\n")

            f.write("\n## 正文\n\n")
            for speaker_key, content in entries:
                f.write(f"**{speaker_labels[speaker_key]}：** {content}\n\n")
    except OSError as error:
        print(f"[警告] 无法写入文字稿，音频已保留: {error}")
        return None

    print(f"[完成] 文字稿: {output_path}  ({len(entries)} 行)")
    return output_path


# ---------------------------------------------------------------------------
# SRT subtitle export
# ---------------------------------------------------------------------------

# SRT limits text by visible CJK characters or whitespace-delimited words.
# Punctuation is included in its surrounding unit, so it does not create an
# ugly standalone subtitle character.
_SRT_LATIN_WORD_RE = r"[A-Za-z0-9]+(?:['’-][A-Za-z0-9]+)*"
_SRT_WORD_RE = re.compile(rf"[\u3400-\u9fff]|{_SRT_LATIN_WORD_RE}|[^\s]")
_SRT_PREFERRED_BREAKS = frozenset("。！？!?；;，,")
_SRT_SENTENCE_BREAKS = frozenset("。！？!?；;")


def tokenize_subtitle_text(text: str) -> list[str]:
    """Tokenize Chinese characters, Latin words, and punctuation for SRT."""
    return _SRT_WORD_RE.findall(normalize_transcript_text(text))


def subtitle_unit_count(text: str) -> int:
    """Count visible subtitle units, treating an English word as one unit."""
    return len(tokenize_subtitle_text(text))


def join_subtitle_tokens(tokens: list[str]) -> str:
    """Join tokens without spaces for CJK and with spaces between Latin words."""
    text = ""
    previous_word = False
    for token in tokens:
        current_word = bool(re.fullmatch(_SRT_LATIN_WORD_RE, token))
        if text and previous_word and current_word:
            text += " "
        text += token
        previous_word = current_word
    return text


def split_subtitle_text(text: str, max_units: int) -> list[str]:
    """Split a long line near midpoint, preferring sentence then comma breaks.

    The normal target is ``max_units``. When a line exceeds it, the first cut
    searches around the 50% position, matching the requested reading rhythm.
    If punctuation is absent, the nearest valid token boundary is used.
    """
    tokens = tokenize_subtitle_text(text)
    if not tokens:
        return []
    if len(tokens) <= max_units:
        return [join_subtitle_tokens(tokens)]

    parts = []
    while len(tokens) > max_units:
        midpoint = max(1, len(tokens) // 2)
        # A line only slightly over the threshold should honor the requested
        # midpoint break. For very long lines, cap each emitted part at the
        # threshold and continue splitting the remaining text.
        search_limit = (len(tokens) - 1 if len(tokens) <= max_units * 2
                        else max_units)
        candidates = [i for i in range(1, search_limit + 1)
                      if tokens[i - 1] in _SRT_PREFERRED_BREAKS]
        sentence_candidates = [i for i in candidates if tokens[i - 1] in _SRT_SENTENCE_BREAKS]
        preferred = sentence_candidates or candidates
        if preferred:
            cut = min(preferred, key=lambda i: (abs(i - midpoint), -i))
        else:
            cut = min(search_limit, max(1, midpoint))

        parts.append(join_subtitle_tokens(tokens[:cut]))
        tokens = tokens[cut:]

    if tokens:
        parts.append(join_subtitle_tokens(tokens))
    return parts


def format_srt_timestamp(seconds: float) -> str:
    """Format non-negative seconds as the standard ``HH:MM:SS,mmm`` SRT time."""
    milliseconds = max(0, int(round(seconds * 1000)))
    hours, remainder = divmod(milliseconds, 3_600_000)
    minutes, remainder = divmod(remainder, 60_000)
    seconds, milliseconds = divmod(remainder, 1000)
    return f"{hours:02d}:{minutes:02d}:{seconds:02d},{milliseconds:03d}"


def _read_subtitle_rows(workdir: str) -> list[dict] | None:
    """Read CSV rows for subtitle generation without making audio fail."""
    csv_path = os.path.join(workdir, "lines.csv")
    if not os.path.isfile(csv_path):
        print(f"[警告] 未找到 lines.csv，跳过字幕导出: {csv_path}")
        return None
    try:
        with open(csv_path, encoding="utf-8-sig", newline="") as f:
            return list(csv.DictReader(f, delimiter="\t"))
    except (OSError, csv.Error, UnicodeError) as error:
        print(f"[警告] 无法读取 lines.csv，跳过字幕导出: {error}")
        return None


def export_srt(workdir: str, voice_files: list, silence_path: str | None,
               max_units: int | None = DEFAULT_SUBTITLE_MAX_UNITS,
               output_filename: str = "podcast.srt") -> str | None:
    """Export a timestamped SRT using measured voice and silence durations.

    Time anchors are computed from the exact same segments concatenated into
    ``podcast.mp3`` rather than by dividing total duration across CSV rows.
    That avoids a severe timing drift for podcasts with differently sized
    sentences or a non-default silence file. Cuts *inside* one TTS segment
    are proportional to subtitle text units; their boundary is approximate
    because the TTS service supplies no per-word timing metadata. Pass
    ``max_units=None`` to retain each lines.csv content as one subtitle.
    """
    rows = _read_subtitle_rows(workdir)
    if rows is None:
        return None
    if max_units is not None and max_units < 1:
        print(f"[警告] 字幕长度阈值必须大于 0，跳过字幕导出: {max_units}")
        return None

    numbered_files = {}
    for voice_path in voice_files:
        filename = os.path.splitext(os.path.basename(voice_path))[0]
        try:
            numbered_files[int(filename)] = voice_path
        except ValueError:
            continue

    silence_duration = 0.0
    if silence_path:
        parsed_silence = get_mp3_duration(silence_path)
        if parsed_silence:
            silence_duration = parsed_silence[0]
        else:
            print("[警告] 无法测量静音片段，字幕将不计入行间静音")

    subtitles = []
    timeline = 0.0
    usable_row_count = 0
    total_rows = len(rows)
    for row_index, row in enumerate(rows, 1):
        content = normalize_transcript_text(row.get("content", ""))
        voice_path = numbered_files.get(row_index)
        if not content or not voice_path:
            if content and not voice_path:
                print(f"[警告] 缺少 voices/{row_index}.mp3，已跳过该行字幕")
            continue

        parsed_duration = get_mp3_duration(voice_path)
        if not parsed_duration:
            print(f"[警告] 无法测量 voices/{row_index}.mp3，已跳过该行字幕")
            continue
        voice_duration = parsed_duration[0]
        # The full-text variant keeps one source row as one subtitle so it
        # remains convenient for reading, searching, and editorial review.
        parts = [content] if max_units is None else split_subtitle_text(content, max_units)
        part_weights = [max(1, subtitle_unit_count(part)) for part in parts]
        total_weight = sum(part_weights)
        cursor = timeline
        for part_index, (part, weight) in enumerate(zip(parts, part_weights)):
            # Let the final part absorb floating-point remainder so the next
            # voice clip always starts at the actual frame-derived boundary.
            end = (timeline + voice_duration if part_index == len(parts) - 1
                   else cursor + voice_duration * weight / total_weight)
            subtitles.append((cursor, end, part))
            cursor = end

        timeline += voice_duration
        usable_row_count += 1
        # concat_mp3_files inserts silence after each audio segment except the
        # physical final file. Use numbered file order, not CSV count.
        if silence_duration and any(number > row_index for number in numbered_files):
            timeline += silence_duration

    if not subtitles:
        print("[警告] 没有可导出的字幕内容，跳过 SRT 导出")
        return None

    output_path = os.path.join(workdir, output_filename)
    try:
        with open(output_path, "w", encoding="utf-8-sig", newline="\n") as f:
            for index, (start, end, text) in enumerate(subtitles, 1):
                f.write(f"{index}\n{format_srt_timestamp(start)} --> {format_srt_timestamp(end)}\n{text}\n\n")
    except OSError as error:
        print(f"[警告] 无法写入 SRT 字幕，音频已保留: {error}")
        return None

    print(
        f"[完成] SRT 字幕: {output_path}  ({len(subtitles)} 条，"
        f"{usable_row_count}/{total_rows} 行音频，时长 {timeline:.3f}s)"
    )
    return output_path


# ---------------------------------------------------------------------------
# Concatenation
# ---------------------------------------------------------------------------

def concat_mp3_files(voice_files: list, silence_path: str | None,
                     output_path: str) -> None:
    """Concatenate MP3 files with optional silence between them."""
    silence_data = b""
    if silence_path:
        with open(silence_path, "rb") as f:
            silence_data = clean_mp3(f.read())

    os.makedirs(os.path.dirname(os.path.abspath(output_path)), exist_ok=True)

    total_bytes = 0
    with open(output_path, "wb") as out:
        for idx, path in enumerate(voice_files):
            with open(path, "rb") as f:
                data = clean_mp3(f.read())
            out.write(data)
            total_bytes += len(data)

            # Insert silence between segments (not after the last one)
            if silence_data and idx < len(voice_files) - 1:
                out.write(silence_data)
                total_bytes += len(silence_data)

    size_kb = total_bytes / 1024
    size_mb = size_kb / 1024
    if size_mb >= 1:
        size_str = f"{size_mb:.1f} MB"
    else:
        size_str = f"{size_kb:.0f} KB"

    print(f"[完成] 输出文件: {output_path}  ({size_str})")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    args = sys.argv[1:]

    if not args:
        print("用法: python concat.py <workdir> [--silence N] [--output path] [--subtitle-max-length N] [--list]")
        sys.exit(1)

    workdir              = None
    silence_ms           = 500
    output_path          = None
    subtitle_max_length  = DEFAULT_SUBTITLE_MAX_UNITS
    list_only            = False

    i = 0
    while i < len(args):
        a = args[i]
        if a == "--silence" and i + 1 < len(args):
            try:
                silence_ms = int(args[i + 1])
            except ValueError:
                print(f"[FATAL] --silence 参数必须是整数，收到: {args[i+1]}")
                sys.exit(1)
            i += 2
        elif a == "--output" and i + 1 < len(args):
            output_path = args[i + 1]
            i += 2
        elif a == "--subtitle-max-length" and i + 1 < len(args):
            try:
                subtitle_max_length = int(args[i + 1])
            except ValueError:
                print(f"[FATAL] --subtitle-max-length 参数必须是整数，收到: {args[i+1]}")
                sys.exit(1)
            if subtitle_max_length < 1:
                print("[FATAL] --subtitle-max-length 参数必须大于 0")
                sys.exit(1)
            i += 2
        elif a == "--list":
            list_only = True
            i += 1
        else:
            workdir = a
            i += 1

    if not workdir:
        print("[FATAL] 未指定工作目录")
        sys.exit(1)

    # Validate and normalize workdir
    workdir = validate_workdir(workdir)

    voices_dir = os.path.join(workdir, "voices")
    if not os.path.isdir(voices_dir):
        print(f"[FATAL] voices/ 目录不存在: {voices_dir}")
        sys.exit(1)

    voice_files = find_voice_files(voices_dir)
    if not voice_files:
        print(f"[FATAL] voices/ 目录中没有 .mp3 文件: {voices_dir}")
        sys.exit(1)

    print(f"[INFO] 找到 {len(voice_files)} 个音频片段")
    for vf in voice_files:
        size = os.path.getsize(vf)
        print(f"  {os.path.basename(vf):>10}  ({size/1024:.0f} KB)")

    if list_only:
        return

    # Silence file
    silence_path = None
    if silence_ms > 0:
        valid_durations = [250, 500, 750, 1000]
        # Round to nearest valid duration
        nearest = min(valid_durations, key=lambda x: abs(x - silence_ms))
        if nearest != silence_ms:
            print(f"[INFO] 静音时长 {silence_ms}ms → 使用最近可用值 {nearest}ms")
            silence_ms = nearest
        silence_path = find_silence_file(silence_ms)
        if silence_path:
            print(f"[INFO] 使用静音文件: {silence_path} ({silence_ms}ms)")
        else:
            print(f"[警告] 未找到 silence/{silence_ms}ms.mp3，将不插入静音间隔")
            print(f"       请将静音文件放置于: {os.path.join(os.path.dirname(os.path.abspath(__file__)), 'silence')}/")

    if output_path is None:
        output_path = os.path.join(workdir, "podcast.mp3")

    print(f"[INFO] 开始拼合 → {output_path}")
    concat_mp3_files(voice_files, silence_path, output_path)
    # Text export is deliberately best-effort: it must not invalidate an
    # already completed audio render when lines.csv is absent or malformed.
    export_transcript(workdir)
    # SRT timing is based on the actual MPEG frames written above. Its export
    # is also best-effort so subtitle failures never discard podcast.mp3.
    # 完整句子版占用标准字幕文件名；按阅读阈值切分的版本另存，供播放场景使用。
    export_srt(workdir, voice_files, silence_path, None)
    export_srt(workdir, voice_files, silence_path, subtitle_max_length,
               SPLITTED_SRT_FILENAME)


if __name__ == "__main__":
    main()
