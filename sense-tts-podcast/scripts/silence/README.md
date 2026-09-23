# Silence MP3 Files

These assets are used **only in MP3 mode** — when `voices/` holds `.mp3`
segments produced by `tts.py` (API channel). `concat.py` byte-concatenates
those bare MPEG frames and inserts one of these files between segments.

| Directory | Format | Used by |
|-----------|--------|---------|
| `silence/` | MPEG1 L3, 44100 Hz, 128 kbps CBR, mono | `tts.py` (API channel, 44.1kHz MP3) |

WAV mode (`web_tts.py` segments) needs **no silence assets at all**:
`concat.py` merges the WAVs losslessly and synthesizes sample-accurate
zero PCM for the gaps inline, then performs the single final MP3 encode.

Files:

| File | Duration | Use case |
|------|----------|----------|
| `250ms.mp3` | ~250 milliseconds | Fast-paced dialogue, minimal pause |
| `500ms.mp3` | ~500 milliseconds | Standard between-speaker pause (default) |
| `750ms.mp3` | ~750 milliseconds | Relaxed pacing |
| `1000ms.mp3` | ~1000 milliseconds | Long pause, topic transitions |

The 44100 Hz / 128 kbps / mono parameters exactly match the audio settings
requested from SenseAudio TTS in `tts.py` (`audio_setting: mp3 / 44100 /
128000 / channel 1`). Keeping one uniform format across speech segments
and silence gaps is what makes the raw byte concatenation in `concat.py`
valid, so do not regenerate these files at a different sample rate,
bitrate, or channel count.

## How to Regenerate

One-time generation-time dependency (`pip install lameenc`); the skill
itself stays stdlib-only:

```python
import lameenc, os

for ms in (250, 500, 750, 1000):
    pcm = b"\x00\x00" * int(44100 * ms / 1000)   # 16-bit mono silence
    enc = lameenc.Encoder()
    enc.set_bit_rate(128)
    enc.set_in_sample_rate(44100)
    enc.set_channels(1)
    enc.set_quality(2)
    data = enc.encode(pcm) + enc.flush()
    open(f"{ms}ms.mp3", "wb").write(bytes(data))
```

Durations come out a few tens of ms longer than nominal (LAME encoder
delay); `concat.py` measures actual MPEG frame durations, so SRT timing
stays correct.

## Fallback Behavior

If the matching silence file is missing, `concat.py` will:
1. Print a warning indicating which file is missing
2. Skip silence insertion for that run (segments are still concatenated)
3. Suggest the nearest available duration

The final podcast will still be generated correctly — just without inter-segment pauses.


