#!/usr/bin/env python
"""
Sense TTS Podcast — Audio Concatenation Script

Concatenates all voices/{n}.* files in a podcast workdir into a single
podcast.mp3, inserting silence between each segment. After a successful
concatenation, also exports a readable transcript.md and timestamped
podcast.srt from lines.csv.

Two segment formats are supported, picked by what voices/ contains:

  - MP3 (tts.py / API channel): bare MPEG frames are byte-concatenated;
    inter-segment silence comes from pre-rendered assets in scripts/silence/
    (44.1kHz, matching the API output).

  - WAV (web_tts.py / web channel): segments are merged losslessly as PCM;
    silence is synthesized inline (sample-accurate zeros — no assets
    needed) and the merged stream is encoded to MP3 ONCE at the end
    (requires lameenc; falls back to writing podcast.wav with a hint if
    it is missing).

voices/ must not mix .mp3 and .wav segments.

Usage:
  python concat.py <workdir>                        # default 500ms silence
  python concat.py <workdir> --silence 250          # 250ms silence
  python concat.py <workdir> --silence 0            # no silence
  python concat.py <workdir> --output out.mp3       # custom output path
  python concat.py <workdir> --output out.wav       # WAV output (WAV mode only)
  python concat.py <workdir> --subtitle-max-length 25  # subtitle line length
  python concat.py <workdir> --list                 # list files only, no concat

MP3-mode silence files are looked up relative to this script:
  scripts/silence/250ms.mp3
  scripts/silence/500ms.mp3
  scripts/silence/750ms.mp3
  scripts/silence/1000ms.mp3

If the silence file is missing, a warning is printed and silence is skipped.
SRT timing uses durations parsed from actual audio frames/samples. Long text
is split near its midpoint at punctuation and allocated proportionally,
because neither TTS channel includes word-boundary timestamps.

Python: 3.7+  (PEP 604 annotations deferred via __future__ import)
"""

from __future__ import annotations

import os
import sys
import glob
import re
import csv
import struct


# ---------------------------------------------------------------------------
# Safe print for mixed-encoding environments
# ---------------------------------------------------------------------------

def safe_print(text):
    """Print text, gracefully downgrading Unicode on encoding errors.

    Same wrapper as tts.py: Windows GBK consoles (or redirected stdout using
    the system code page) cannot encode ✓/✗ and some Chinese punctuation.
    Catches UnicodeEncodeError and retries with ASCII-safe fallbacks.
    """
    try:
        print(text)
    except UnicodeEncodeError:
        fallback = text.replace("✓", "[OK]").replace("✗", "[X]")
        print(fallback.encode(sys.stdout.encoding or "utf-8", "replace").decode(sys.stdout.encoding or "utf-8", "ignore"))

# 默认的逐条字幕最大可见单位数。中文按单字、英文按单词计；可直接修改本
# 常量以调试观看节奏，也可以通过 --subtitle-max-length 在单次运行时覆盖。
DEFAULT_SUBTITLE_MAX_UNITS = 40

# 按 DEFAULT_SUBTITLE_MAX_UNITS 切分的字幕使用该文件名；完整句子版固定
# 使用标准文件名 podcast.srt，适合严肃阅读、检索与校对。
SPLITTED_SRT_FILENAME = "podcast_splitted.srt"


# ---------------------------------------------------------------------------
# meta.md progress ticking (best-effort)
# ---------------------------------------------------------------------------

def check_meta_phase(workdir: str, phase_label: str) -> None:
    """Tick a phase checkbox in meta.md (e.g. 'Phase 5: 音频拼合').

    Mirrors tts.py's helper: missing meta.md or unmatched label is silently
    ignored; only unticked boxes matching the label prefix get ticked.
    """
    meta_path = os.path.join(workdir, "meta.md")
    if not os.path.isfile(meta_path):
        return
    try:
        with open(meta_path, encoding="utf-8") as f:
            content = f.read()
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
# Workdir validation
# ---------------------------------------------------------------------------

def validate_workdir(workdir_arg: str) -> str:
    """Validate and normalize the working directory (same logic as tts.py)."""
    workdir = os.path.abspath(workdir_arg)
    dirname = os.path.basename(workdir)
    if not re.match(r'^\d{4}-\d{2}-\d{2}_', dirname):
        safe_print(f"[警告] 工作目录命名不符合技能约定（应为 YYYY-MM-DD_topic）: {dirname}")
        safe_print(f"       当前路径: {workdir}")

    # concat.py 只验证目录存在，不负责创建（创建应由 tts.py 或 agent 在 Phase 1 完成）
    if not os.path.isdir(workdir):
        safe_print(f"[FATAL] 工作目录不存在: {workdir}")
        safe_print(f"       请确认路径正确，或先运行 tts.py 创建目录结构。")
        sys.exit(1)

    safe_print(f"[INFO] 工作目录（已规范化）: {workdir}")
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

def find_voice_files(voices_dir: str) -> tuple[list, str] | None:
    """Return (sorted segment paths, format) for voices/, or None when empty.

    format is "mp3" (tts.py / API channel) or "wav" (web_tts.py / web
    channel). Mixing both in one workdir is fatal — they cannot be
    concatenated together.
    """
    mp3s = glob.glob(os.path.join(voices_dir, "*.mp3"))
    wavs = glob.glob(os.path.join(voices_dir, "*.wav"))

    def extract_num(p):
        name = os.path.splitext(os.path.basename(p))[0]
        try:
            return int(name)
        except ValueError:
            return float("inf")  # non-numeric files sorted last

    if mp3s and wavs:
        safe_print("[FATAL] voices/ 中同时存在 .mp3 与 .wav 片段，无法拼合。")
        safe_print("       .mp3 来自 tts.py（API 通道）、.wav 来自 web_tts.py（网页通道）；")
        safe_print("       请清空 voices/ 后用同一后端重新生成，或删除另一格式的文件。")
        sys.exit(1)

    if mp3s:
        return sorted(mp3s, key=extract_num), "mp3"
    if wavs:
        return sorted(wavs, key=extract_num), "wav"
    return None


def detect_sample_rate(path: str) -> int | None:
    """Return the sample rate of the first valid MPEG frame in an MP3 file.

    Used to pick silence assets whose sample rate matches the speech
    segments: the API backend (tts.py) produces 44.1kHz MP3s while the web
    backend (web_tts.py) re-encodes 24kHz WAVs, and mixing sample rates in
    one raw-concatenated stream is not valid MP3.
    """
    try:
        with open(path, "rb") as f:
            data = strip_id3v1(strip_id3v2(f.read(4096)))
    except OSError:
        return None
    for offset in range(len(data) - 4):
        header = int.from_bytes(data[offset:offset + 4], byteorder="big")
        if (header >> 21) != 0x7FF:
            continue
        version_bits = (header >> 19) & 0x3
        sample_rate_index = (header >> 10) & 0x3
        bitrate_index = (header >> 12) & 0xF
        if (version_bits in (1, 0) or sample_rate_index == 3
                or bitrate_index in (0, 15)):
            continue
        rates = {3: [44100, 48000, 32000],
                 2: [22050, 24000, 16000],
                 0: [11025, 12000, 8000]}
        return rates[version_bits][sample_rate_index]
    return None


def find_silence_file(silence_ms: int) -> str | None:
    """Return path to the silence MP3 for the given duration, or None.

    Only used in MP3 mode (tts.py / API channel), whose segments are
    44.1kHz; the assets in scripts/silence/ match that rate. WAV mode
    synthesizes silence inline and needs no files.
    """
    script_dir = os.path.dirname(os.path.abspath(__file__))
    candidate = os.path.join(script_dir, "silence", f"{silence_ms}ms.mp3")
    if os.path.isfile(candidate):
        return candidate
    return None


# ---------------------------------------------------------------------------
# MPEG audio duration parsing
# ---------------------------------------------------------------------------

# concat.py deliberately has no third-party dependencies. SenseAudio TTS
# produces MPEG Layer III frames; their sample counts and sample rates give a
# stable duration without relying on unreliable file-size/bitrate estimates.
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
        safe_print(f"[警告] 无法读取 MP3 时长: {path}: {error}")
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
        safe_print(f"[警告] 未从 MP3 中识别到有效音频帧，无法计算时长: {path}")
        return None
    return duration, frame_count


# ---------------------------------------------------------------------------
# WAV handling (web_tts.py / web channel)
# ---------------------------------------------------------------------------

def get_wav_info(path: str) -> dict | None:
    """Parse a RIFF/WAVE file → {sample_rate, channels, bits, byte_rate, pcm}.

    Only 16-bit PCM is accepted (what the web channel delivers). Returns
    None on parse failure.
    """
    try:
        with open(path, "rb") as f:
            data = f.read()
    except OSError as error:
        safe_print(f"[警告] 无法读取 WAV: {path}: {error}")
        return None
    if data[:4] != b"RIFF" or data[8:12] != b"WAVE":
        safe_print(f"[警告] 不是有效的 WAV 文件: {path}")
        return None

    info = {}
    pos = 12
    while pos + 8 <= len(data):
        cid = data[pos:pos + 4]
        size = struct.unpack("<I", data[pos + 4:pos + 8])[0]
        body = data[pos + 8:pos + 8 + size]
        if cid == b"fmt ":
            if len(body) < 16:
                safe_print(f"[警告] WAV fmt 块过短: {path}")
                return None
            audio_fmt, ch, sr, byte_rate, _, bits = struct.unpack("<HHIIHH", body[:16])
            if audio_fmt != 1 or bits != 16:
                safe_print(f"[警告] 仅支持 16 位 PCM WAV（实际 fmt={audio_fmt} bits={bits}）: {path}")
                return None
            info = {"sample_rate": sr, "channels": ch, "bits": bits,
                    "byte_rate": byte_rate}
        elif cid == b"data":
            info["pcm"] = body
        pos += 8 + size + (size & 1)

    if "sample_rate" not in info or "pcm" not in info:
        safe_print(f"[警告] WAV 缺少 fmt/data 块: {path}")
        return None
    return info


def get_audio_duration(path: str) -> tuple[float, int] | None:
    """Format-aware (duration_seconds, sample/frame count) for MP3 or WAV."""
    if path.lower().endswith(".wav"):
        info = get_wav_info(path)
        if not info:
            return None
        block_align = info["channels"] * info["bits"] // 8
        samples = len(info["pcm"]) // block_align
        return samples / info["sample_rate"], samples
    return get_mp3_duration(path)


def concat_wav_files(voice_files: list, silence_ms: int, output_path: str) -> None:
    """Merge WAV segments (same format) into one WAV, zeros as gaps.

    Silence is synthesized inline — sample-accurate and asset-free. All
    segments must share the sample rate/channel count of the first file.
    """
    infos = []
    fmt = None
    for path in voice_files:
        info = get_wav_info(path)
        if not info:
            safe_print(f"[FATAL] 无法解析 WAV 片段，已中止拼合: {path}")
            sys.exit(1)
        if fmt is None:
            fmt = {k: info[k] for k in ("sample_rate", "channels", "bits")}
        elif (info["sample_rate"], info["channels"], info["bits"]) != \
                (fmt["sample_rate"], fmt["channels"], fmt["bits"]):
            safe_print(f"[FATAL] WAV 片段格式不一致: {path} 是 "
                       f"{info['sample_rate']}Hz/{info['channels']}ch/{info['bits']}bit，"
                       f"首个片段是 {fmt['sample_rate']}Hz/{fmt['channels']}ch/{fmt['bits']}bit")
            sys.exit(1)
        infos.append(info)

    block_align = fmt["channels"] * fmt["bits"] // 8
    silence_pcm = (b"\x00" * (int(fmt["sample_rate"] * silence_ms / 1000)
                              * block_align)) if silence_ms > 0 else b""

    parts = []
    total = 0
    for idx, info in enumerate(infos):
        parts.append(info["pcm"])
        total += len(info["pcm"])
        if silence_pcm and idx < len(infos) - 1:
            parts.append(silence_pcm)
            total += len(silence_pcm)
    pcm = b"".join(parts)

    data_size = len(pcm)
    riff = (b"RIFF" + struct.pack("<I", 36 + data_size) + b"WAVE"
            + b"fmt " + struct.pack("<IHHIIHH", 16, 1, fmt["channels"],
                                    fmt["sample_rate"],
                                    fmt["sample_rate"] * block_align,
                                    block_align, fmt["bits"])
            + b"data" + struct.pack("<I", data_size) + pcm)

    os.makedirs(os.path.dirname(os.path.abspath(output_path)), exist_ok=True)
    with open(output_path, "wb") as f:
        f.write(riff)

    duration = data_size / (fmt["sample_rate"] * block_align)
    size_mb = len(riff) / 1024 / 1024
    safe_print(f"[完成] WAV 拼合: {output_path}  ({duration:.1f}s, {size_mb:.1f} MB, "
               f"{fmt['sample_rate']}Hz/{fmt['channels']}ch/16bit)")


def encode_wav_to_mp3(wav_path: str, mp3_path: str, bitrate: int = 128) -> bool:
    """Single-pass MP3 encode of a WAV file via lameenc (lazy import).

    Returns True on success; False when lameenc is unavailable (caller
    falls back to keeping the WAV).
    """
    try:
        import lameenc
    except ImportError:
        return False
    info = get_wav_info(wav_path)
    if not info:
        return False
    enc = lameenc.Encoder()
    enc.set_bit_rate(bitrate)
    enc.set_in_sample_rate(info["sample_rate"])
    enc.set_channels(info["channels"])
    enc.set_quality(2)
    data = bytes(enc.encode(info["pcm"]) + enc.flush())
    os.makedirs(os.path.dirname(os.path.abspath(mp3_path)), exist_ok=True)
    with open(mp3_path, "wb") as f:
        f.write(data)
    safe_print(f"[完成] MP3 编码: {mp3_path}  ({len(data)/1024/1024:.1f} MB, {bitrate}kbps)")
    return True


# ---------------------------------------------------------------------------
# Transcript export
# ---------------------------------------------------------------------------

# Keep the body of transcript.md readable. The full SenseAudio voice IDs
# remain in the speaker list at the top, so the compact labels do not lose
# traceability. Emotional variants (_a.._f) of one character share its name.
VOICE_DISPLAY_NAMES = {
    "child_0001_a": "可爱萌娃",
    "child_0001_b": "可爱萌娃",
    "child_0002_a": "学语牙牙",
    "female_0001_a": "战场指挥",
    "female_0002_a": "天真少女",
    "female_0003_a": "傲娇少女",
    "female_0004_a": "乐天女孩",
    "female_0005_a": "傲娇小姐",
    "female_0006_a": "温柔御姐",
    "female_0007_a": "庄严女帝",
    "female_0007_b": "庄严女帝",
    "female_0007_c": "庄严女帝",
    "female_0008_a": "气质学姐",
    "female_0008_b": "气质学姐",
    "female_0008_c": "气质学姐",
    "female_0009_a": "羞涩少女",
    "female_0010_a": "优雅台妹",
    "female_0011_a": "美艳女人",
    "female_0012_a": "刁蛮小姐",
    "female_0013_a": "书香才女",
    "female_0014_a": "明艳御姐",
    "female_0014_b": "明艳御姐",
    "female_0014_c": "明艳御姐",
    "female_0015_a": "哭泣少女",
    "female_0015_b": "哭泣少女",
    "female_0016_a": "俏皮女孩",
    "female_0016_b": "俏皮女孩",
    "female_0016_c": "俏皮女孩",
    "female_0017_a": "冷酷少女",
    "female_0017_b": "冷酷少女",
    "female_0017_c": "冷酷少女",
    "female_0018_a": "森系少女",
    "female_0018_b": "森系少女",
    "female_0019_a": "冷艳御姐",
    "female_0020_a": "韵味姐姐",
    "female_0021_a": "管家女仆",
    "female_0021_b": "管家女仆",
    "female_0021_c": "管家女仆",
    "female_0022_a": "赛博少女",
    "female_0022_b": "赛博少女",
    "female_0022_c": "赛博少女",
    "female_0022_d": "赛博少女",
    "female_0022_e": "赛博少女",
    "female_0022_f": "赛博少女",
    "female_0023_a": "羞涩甜妹",
    "female_0023_b": "羞涩甜妹",
    "female_0023_c": "羞涩甜妹",
    "female_0024_a": "成熟姐姐",
    "female_0024_b": "成熟姐姐",
    "female_0024_c": "成熟姐姐",
    "female_0025_a": "播客才女",
    "female_0026_a": "专业女播",
    "female_0027_a": "魅力姐姐",
    "female_0027_b": "魅力姐姐",
    "female_0027_c": "魅力姐姐",
    "female_0027_d": "魅力姐姐",
    "female_0027_e": "魅力姐姐",
    "female_0027_f": "魅力姐姐",
    "female_0028_a": "温柔月光",
    "female_0028_b": "温柔月光",
    "female_0028_c": "温柔月光",
    "female_0028_d": "温柔月光",
    "female_0028_e": "温柔月光",
    "female_0028_f": "温柔月光",
    "female_0029_a": "低沉御姐",
    "female_0029_b": "低沉御姐",
    "female_0029_c": "低沉御姐",
    "female_0029_d": "低沉御姐",
    "female_0029_e": "低沉御姐",
    "female_0030_a": "凌厉御姐",
    "female_0030_b": "沉稳帅姐",
    "female_0030_c": "高能姐姐",
    "female_0030_d": "霸道御姐",
    "female_0030_e": "贴心女人",
    "female_0030_f": "心机少女",
    "female_0031_a": "清新少女",
    "female_0032_a": "阳光少女",
    "female_0033_a": "嗲嗲台妹",
    "female_0033_b": "嗲嗲台妹",
    "female_0033_c": "嗲嗲台妹",
    "female_0033_d": "嗲嗲台妹",
    "female_0033_e": "嗲嗲台妹",
    "female_0033_f": "嗲嗲台妹",
    "female_0034_a": "清风少女",
    "female_0034_b": "清风少女",
    "female_0034_c": "清风少女",
    "female_0034_d": "清风少女",
    "female_0034_e": "清风少女",
    "female_0034_f": "清风少女",
    "female_0035_a": "知心少女",
    "female_0035_b": "知心少女",
    "female_0035_c": "知心少女",
    "female_0035_d": "知心少女",
    "female_0035_e": "知心少女",
    "female_0035_f": "知心少女",
    "female_0036_a": "青春女声",
    "female_0036_b": "青春女声",
    "female_0036_c": "青春女声",
    "female_0036_d": "青春女声",
    "female_0036_e": "青春女声",
    "female_0036_f": "青春女声",
    "female_0037_a": "自然少女",
    "female_0037_b": "自然少女",
    "female_0037_c": "自然少女",
    "female_0037_d": "自然少女",
    "female_0037_e": "自然少女",
    "female_0038_a": "亲切女孩",
    "female_0038_b": "亲切女孩",
    "female_0038_c": "亲切女孩",
    "female_0038_d": "亲切女孩",
    "female_0038_e": "亲切女孩",
    "female_0038_f": "亲切女孩",
    "male_0001_a": "酷痞青年",
    "male_0002_a": "可靠大叔",
    "male_0003_a": "暴躁大叔",
    "male_0004_a": "儒雅道长",
    "male_0005_a": "惬意老翁",
    "male_0006_a": "纨绔青年",
    "male_0007_a": "病娇青年",
    "male_0008_a": "霸道男神",
    "male_0009_a": "潇洒青叔",
    "male_0010_a": "深情青叔",
    "male_0011_a": "冷面霸总",
    "male_0012_a": "清爽暖男",
    "male_0013_a": "深沉帅哥",
    "male_0013_b": "深沉帅哥",
    "male_0013_c": "深沉帅哥",
    "male_0014_a": "风流浪子",
    "male_0014_b": "风流浪子",
    "male_0014_c": "风流浪子",
    "male_0015_a": "英武老者",
    "male_0016_a": "开朗青叔",
    "male_0017_a": "温柔青年",
    "male_0018_a": "沙哑青年",
    "male_0019_a": "孔武青年",
    "male_0020_a": "阳光甜弟",
    "male_0021_a": "柔弱公子",
    "male_0021_b": "柔弱公子",
    "male_0021_c": "柔弱公子",
    "male_0021_d": "柔弱公子",
    "male_0021_e": "柔弱公子",
    "male_0022_a": "阳光少年",
    "male_0023_a": "撒娇青年",
    "male_0024_a": "粘人男友",
    "male_0024_b": "粘人男友",
    "male_0024_c": "粘人男友",
    "male_0025_a": "温柔霸总",
    "male_0025_b": "温柔霸总",
    "male_0025_c": "温柔霸总",
    "male_0026_a": "乐观少年",
    "male_0026_b": "乐观少年",
    "male_0026_c": "乐观少年",
    "male_0027_a": "亢奋主播",
    "male_0027_b": "亢奋主播",
    "male_0027_c": "亢奋主播",
    "male_0028_a": "可靠青叔",
    "male_0028_b": "可靠青叔",
    "male_0028_c": "可靠青叔",
    "male_0028_d": "可靠青叔",
    "male_0028_e": "可靠青叔",
    "male_0028_f": "可靠青叔",
    "male_0029_a": "利落青年",
    "male_0029_b": "利落青年",
    "male_0029_c": "利落青年",
    "male_0029_d": "利落青年",
    "male_0029_e": "利落青年",
    "male_0029_f": "利落青年",
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
        safe_print(f"[警告] 未找到 lines.csv，跳过文字稿导出: {csv_path}")
        return None

    try:
        with open(csv_path, encoding="utf-8-sig", newline="") as f:
            rows = list(csv.DictReader(f, delimiter="\t"))
    except (OSError, csv.Error, UnicodeError) as error:
        safe_print(f"[警告] 无法读取 lines.csv，跳过文字稿导出: {error}")
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
        safe_print("[警告] lines.csv 中没有可导出的 content，跳过文字稿导出")
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
        safe_print(f"[警告] 无法写入文字稿，音频已保留: {error}")
        return None

    safe_print(f"[完成] 文字稿: {output_path}  ({len(entries)} 行)")
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
    """Read CSV rows for subtitle generation without making audio fail.

    Same structural rules as tts.py: header must contain done/voice_id/content
    (speed/pitch optional), and every data row must provide at least those 3
    fields. Malformed rows are dropped with a warning; if ALL rows are bad the
    export is skipped — audio concatenation itself is never affected.
    """
    csv_path = os.path.join(workdir, "lines.csv")
    if not os.path.isfile(csv_path):
        safe_print(f"[警告] 未找到 lines.csv，跳过字幕导出: {csv_path}")
        return None
    try:
        with open(csv_path, encoding="utf-8-sig", newline="") as f:
            reader = csv.DictReader(f, delimiter="\t")
            if not reader.fieldnames:
                safe_print(f"[警告] lines.csv 为空或缺少表头，跳过字幕导出")
                return None
            required = ("done", "voice_id", "content")
            missing_cols = [c for c in required if c not in reader.fieldnames]
            if missing_cols:
                safe_print(f"[警告] lines.csv 表头缺少必需列 {missing_cols}，跳过字幕导出")
                return None

            rows = []
            dropped = 0
            for row in reader:
                # Extra fields land under the None key → stray Tab in content.
                if None in row or any(row.get(c) is None for c in required):
                    dropped += 1
                    continue
                # Column-shift detection: text landing in speed/pitch means a
                # stray Tab inside content (row still has exactly 5 fields).
                shifted = False
                for col in ("speed", "pitch"):
                    val = (row.get(col) or "").strip()
                    if val:
                        try:
                            float(val)
                        except ValueError:
                            dropped += 1
                            shifted = True
                            break
                if shifted:
                    continue
                for col in ("speed", "pitch"):
                    if row.get(col) is None:
                        row[col] = ""
                rows.append(row)
            if dropped:
                safe_print(f"[警告] lines.csv 有 {dropped} 行字段数异常（content 混入 Tab/换行?），已跳过这些行的字幕")
            return rows or None
    except (OSError, csv.Error, UnicodeError) as error:
        safe_print(f"[警告] 无法读取 lines.csv，跳过字幕导出: {error}")
        return None


def export_srt(workdir: str, voice_files: list, silence_duration: float,
               max_units: int | None = DEFAULT_SUBTITLE_MAX_UNITS,
               output_filename: str = "podcast.srt") -> str | None:
    """Export a timestamped SRT using measured voice and silence durations.

    Time anchors are computed from the exact same segments concatenated into
    the final podcast rather than by dividing total duration across CSV rows.
    That avoids a severe timing drift for podcasts with differently sized
    sentences or a non-default silence length. Cuts *inside* one TTS segment
    are proportional to subtitle text units; their boundary is approximate
    because the TTS service supplies no per-word timing metadata. Pass
    ``max_units=None`` to retain each lines.csv content as one subtitle.
    """
    rows = _read_subtitle_rows(workdir)
    if rows is None:
        return None
    if max_units is not None and max_units < 1:
        safe_print(f"[警告] 字幕长度阈值必须大于 0，跳过字幕导出: {max_units}")
        return None

    numbered_files = {}
    for voice_path in voice_files:
        filename = os.path.splitext(os.path.basename(voice_path))[0]
        try:
            numbered_files[int(filename)] = voice_path
        except ValueError:
            continue

    subtitles = []
    timeline = 0.0
    usable_row_count = 0
    total_rows = len(rows)
    for row_index, row in enumerate(rows, 1):
        content = normalize_transcript_text(row.get("content", ""))
        voice_path = numbered_files.get(row_index)
        if not content or not voice_path:
            if content and not voice_path:
                safe_print(f"[警告] 缺少 voices/{row_index} 音频片段，已跳过该行字幕")
            continue

        parsed_duration = get_audio_duration(voice_path)
        if not parsed_duration:
            safe_print(f"[警告] 无法测量 voices/{row_index} 音频，已跳过该行字幕")
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
        safe_print("[警告] 没有可导出的字幕内容，跳过 SRT 导出")
        return None

    output_path = os.path.join(workdir, output_filename)
    try:
        with open(output_path, "w", encoding="utf-8-sig", newline="\n") as f:
            for index, (start, end, text) in enumerate(subtitles, 1):
                f.write(f"{index}\n{format_srt_timestamp(start)} --> {format_srt_timestamp(end)}\n{text}\n\n")
    except OSError as error:
        safe_print(f"[警告] 无法写入 SRT 字幕，音频已保留: {error}")
        return None

    safe_print(
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

    safe_print(f"[完成] 输出文件: {output_path}  ({size_str})")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    args = sys.argv[1:]

    if not args:
        safe_print("用法: python concat.py <workdir> [--silence N] [--output path] [--subtitle-max-length N] [--list]")
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
                safe_print(f"[FATAL] --silence 参数必须是整数，收到: {args[i+1]}")
                sys.exit(1)
            i += 2
        elif a == "--output" and i + 1 < len(args):
            output_path = args[i + 1]
            i += 2
        elif a == "--subtitle-max-length" and i + 1 < len(args):
            try:
                subtitle_max_length = int(args[i + 1])
            except ValueError:
                safe_print(f"[FATAL] --subtitle-max-length 参数必须是整数，收到: {args[i+1]}")
                sys.exit(1)
            if subtitle_max_length < 1:
                safe_print("[FATAL] --subtitle-max-length 参数必须大于 0")
                sys.exit(1)
            i += 2
        elif a == "--list":
            list_only = True
            i += 1
        else:
            workdir = a
            i += 1

    if not workdir:
        safe_print("[FATAL] 未指定工作目录")
        sys.exit(1)

    # Validate and normalize workdir
    workdir = validate_workdir(workdir)

    voices_dir = os.path.join(workdir, "voices")
    if not os.path.isdir(voices_dir):
        safe_print(f"[FATAL] voices/ 目录不存在: {voices_dir}")
        sys.exit(1)

    found = find_voice_files(voices_dir)
    if not found:
        safe_print(f"[FATAL] voices/ 目录中没有 .mp3 / .wav 音频片段: {voices_dir}")
        sys.exit(1)
    voice_files, audio_format = found

    safe_print(f"[INFO] 找到 {len(voice_files)} 个音频片段（{'WAV / 网页通道' if audio_format == 'wav' else 'MP3 / API 通道'}）")
    for vf in voice_files:
        size = os.path.getsize(vf)
        safe_print(f"  {os.path.basename(vf):>10}  ({size/1024:.0f} KB)")

    if list_only:
        return

    if output_path is None:
        output_path = os.path.join(workdir, "podcast.mp3")

    if audio_format == "wav":
        # --- WAV mode (web_tts.py): lossless merge + single final encode ---
        first_info = get_wav_info(voice_files[0])
        if not first_info:
            sys.exit(1)
        safe_print(f"[INFO] 语音参数: {first_info['sample_rate']} Hz / "
                   f"{first_info['channels']} ch / 16 bit")

        silence_duration = silence_ms / 1000.0 if silence_ms > 0 else 0.0
        if silence_ms > 0:
            safe_print(f"[INFO] 行间静音: {silence_ms}ms（按采样精确生成，无需资产文件）")
        else:
            safe_print("[INFO] 行间静音: 0ms（不插入）")

        if output_path.lower().endswith(".wav"):
            safe_print(f"[INFO] 开始拼合 → {output_path}")
            concat_wav_files(voice_files, silence_ms, output_path)
        else:
            # Always keep the lossless merged WAV next to the MP3 — it is
            # the re-encode/edit master, so future bitrate changes or cuts
            # never have to go back to TTS.
            merged_wav = os.path.join(workdir, "podcast.wav")
            safe_print(f"[INFO] 开始拼合（无损合并 WAV → 单次 MP3 编码）→ {output_path}")
            concat_wav_files(voice_files, silence_ms, merged_wav)
            if not encode_wav_to_mp3(merged_wav, output_path):
                safe_print("[警告] 未安装 lameenc，无法编码 MP3；已保留无损 WAV 拼合结果:")
                safe_print(f"       {merged_wav}")
                safe_print("       安装后重跑即可得到 MP3: pip install lameenc")
            else:
                safe_print(f"[INFO] 无损 WAV 已保留: {merged_wav}（重编码/剪辑可直接使用）")
        silence_path = None  # WAV mode synthesizes silence inline
    else:
        # --- MP3 mode (tts.py): byte-concat frames + silence asset files ---
        silence_path = None
        if silence_ms > 0:
            valid_durations = [250, 500, 750, 1000]
            # Round to nearest valid duration
            nearest = min(valid_durations, key=lambda x: abs(x - silence_ms))
            if nearest != silence_ms:
                safe_print(f"[INFO] 静音时长 {silence_ms}ms → 使用最近可用值 {nearest}ms")
                silence_ms = nearest
            sample_rate = detect_sample_rate(voice_files[0])
            if sample_rate:
                safe_print(f"[INFO] 语音采样率: {sample_rate} Hz")
            silence_path = find_silence_file(silence_ms)
            if silence_path:
                safe_print(f"[INFO] 使用静音文件: {silence_path} ({silence_ms}ms)")
            else:
                safe_print(f"[警告] 未找到 silence/{silence_ms}ms.mp3，将不插入静音间隔")
                safe_print(f"       请将静音文件放置于: {os.path.join(os.path.dirname(os.path.abspath(__file__)), 'silence')}/")
        if silence_path:
            parsed = get_mp3_duration(silence_path)
            silence_duration = parsed[0] if parsed else 0.0
        else:
            silence_duration = 0.0

        safe_print(f"[INFO] 开始拼合 → {output_path}")
        concat_mp3_files(voice_files, silence_path, output_path)

    # Tick the Phase 5 checkbox in meta.md (best-effort, never fatal)
    check_meta_phase(workdir, "Phase 5")
    # Text export is deliberately best-effort: it must not invalidate an
    # already completed audio render when lines.csv is absent or malformed.
    export_transcript(workdir)
    # SRT timing is based on the actual audio written above. Its export
    # is also best-effort so subtitle failures never discard the podcast.
    # 完整句子版占用标准字幕文件名；按阅读阈值切分的版本另存，供播放场景使用。
    export_srt(workdir, voice_files, silence_duration, None)
    export_srt(workdir, voice_files, silence_duration, subtitle_max_length,
               SPLITTED_SRT_FILENAME)


if __name__ == "__main__":
    main()
