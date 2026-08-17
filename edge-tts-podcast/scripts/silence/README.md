# Silence MP3 Files

This directory should contain the following silence MP3 files for use during audio concatenation:

| File | Duration | Use case |
|------|----------|----------|
| `250ms.mp3` | 250 milliseconds | Fast-paced dialogue, minimal pause |
| `500ms.mp3` | 500 milliseconds | Standard between-speaker pause (default) |
| `750ms.mp3` | 750 milliseconds | Relaxed pacing |
| `1000ms.mp3` | 1000 milliseconds | Long pause, topic transitions |

## How to Generate

These files are small (1-5 KB each). Generate with ffmpeg if available:

```bash
ffmpeg -f lavfi -i anullsrc=r=24000:cl=mono -t 0.25 -q:a 9 -acodec libmp3lame 250ms.mp3
ffmpeg -f lavfi -i anullsrc=r=24000:cl=mono -t 0.50 -q:a 9 -acodec libmp3lame 500ms.mp3
ffmpeg -f lavfi -i anullsrc=r=24000:cl=mono -t 0.75 -q:a 9 -acodec libmp3lame 750ms.mp3
ffmpeg -f lavfi -i anullsrc=r=24000:cl=mono -t 1.00 -q:a 9 -acodec libmp3lame 1000ms.mp3
```

Or with Python (requires `pydub` + ffmpeg):

```python
from pydub import AudioSegment
for ms in [250, 500, 750, 1000]:
    AudioSegment.silent(duration=ms).export(f"{ms}ms.mp3", format="mp3")
```

## Fallback Behavior

If any silence file is missing, `concat.py` will:
1. Print a warning indicating which file is missing
2. Skip silence insertion for that run (segments are still concatenated)
3. Suggest the nearest available duration

The final podcast will still be generated correctly — just without inter-segment pauses.
