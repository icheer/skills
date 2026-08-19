#!/usr/bin/env python
"""
Edge TTS Podcast — Audio Concatenation Script

Concatenates all voices/{n}.mp3 files in a podcast workdir into a single
podcast.mp3, inserting silence between each segment. Also exports a readable
transcript.md from lines.csv after a successful concatenation.

Usage:
  python concat.py <workdir>                        # default 500ms silence
  python concat.py <workdir> --silence 250          # 250ms silence
  python concat.py <workdir> --silence 0            # no silence
  python concat.py <workdir> --output out.mp3       # custom output path
  python concat.py <workdir> --list                 # list files only, no concat

Silence files are looked up relative to this script:
  scripts/silence/250ms.mp3
  scripts/silence/500ms.mp3
  scripts/silence/750ms.mp3
  scripts/silence/1000ms.mp3

If the silence file is missing, a warning is printed and silence is skipped.

Python: 3.7+  (PEP 604 annotations deferred via __future__ import)
"""

from __future__ import annotations

import os
import sys
import glob
import re
import csv

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
        print("用法: python concat.py <workdir> [--silence N] [--output path] [--list]")
        sys.exit(1)

    workdir     = None
    silence_ms  = 500
    output_path = None
    list_only   = False

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


if __name__ == "__main__":
    main()
