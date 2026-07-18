---
name: youtube-transcribe
description: "Transcribe a YouTube video to a plain-text file, for free, entirely on-device. Use when the user asks to transcribe a YouTube video/link, get a transcript, 'summarize this video' (transcribe first), or pull captions from a video. Triggers on YouTube URLs paired with transcribe/transcript/captions/subtitles requests."
---

# YouTube Transcribe

Turns a YouTube video into a `.txt` transcript. Two-tier approach, both free and local — no paid API, no account, no third-party service:

1. **Captions first** — pulls YouTube's own manual or auto-generated captions via `yt-dlp`. Instant, no download of audio/video needed.
2. **Local Whisper fallback** — if the video has no captions at all, downloads just the audio (`yt-dlp -x`) and transcribes it on-device with `openai-whisper`. Slower (real compute, scales with video length and whisper model size) but works on anything.

## CLI usage

Also installed as a global terminal command (`~/.local/bin/yt-transcribe`, symlinked from this skill's script):

```bash
yt-transcribe "https://www.youtube.com/watch?v=VIDEO_ID"
# -> writes ./<video-title>.txt, prints the path

yt-transcribe <url> -o ~/Desktop/transcript.txt   # custom output path
yt-transcribe <url> --lang es                      # non-English captions/audio
yt-transcribe <url> --whisper-model small           # bigger/slower/more accurate fallback model
yt-transcribe <url> --keep-audio                    # keep the downloaded mp3 (fallback path only)
```

Directly, without the symlink:

```bash
python3 ~/.claude-personal/skills/youtube-transcribe/scripts/transcribe.py <url>
```

## When invoked as a skill (not a raw terminal request)

Run the script exactly as the CLI above via Bash, using the resolved skill path:
`~/.claude-personal/skills/youtube-transcribe/scripts/transcribe.py`. Report back the output file path — don't paste the full transcript into chat unless asked, it can be long.

## Requirements

- `yt-dlp`, `ffmpeg` on PATH (both already installed on this machine)
- `whisper` CLI on PATH — only needed for videos with zero captions (already installed here)

## Notes

- Whisper model sizes trade speed for accuracy: `tiny` < `base` (default) < `small` < `medium` < `large`. Bump it for noisy audio or non-English content if `base` mistranscribes.
- Auto-generated YouTube captions are usually good enough and much faster than the Whisper fallback — the script always tries them first.
