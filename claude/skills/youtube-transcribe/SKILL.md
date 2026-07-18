---
name: youtube-transcribe
description: "Transcribe YouTube videos to plain-text files, for free, entirely on-device — a single video, or the N most recent videos from a channel. Use when the user asks to transcribe a YouTube video/link/channel, get a transcript, 'summarize this video' (transcribe first), or pull captions/transcripts from a channel. Triggers on YouTube URLs or channel handles paired with transcribe/transcript/captions/subtitles requests."
---

# YouTube Transcribe

Turns YouTube videos into `.txt` transcripts. Two-tier approach, both free and local — no paid API, no account, no third-party service:

1. **Captions first** — pulls YouTube's own manual or auto-generated captions via `yt-dlp`. Instant, no download of audio/video needed.
2. **Local Whisper fallback** — if the video has no captions at all, downloads just the audio (`yt-dlp -x`) and transcribes it on-device with `openai-whisper`. Slower (real compute, scales with video length and whisper model size) but works on anything.

Two commands: one video at a time, or a whole channel's recent uploads.

## CLI usage — single video

Installed as a global terminal command (`~/.local/bin/yt-transcribe`, symlinked from this skill's script):

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

## CLI usage — whole channel (N most recent videos)

`yt-transcribe-channel` (symlinked the same way) transcribes the **N most recent** videos from a channel. If the channel has fewer than N videos, it transcribes all of them — it never errors out for asking too many.

```bash
yt-transcribe-channel "@mkbhd" -n 5
# -> lists the 5 most recent videos, transcribes each (captions, else whisper),
#    writes ./mkbhd/001-<id>.txt ... 005-<id>.txt + ./mkbhd/_manifest.tsv, prints the dir

yt-transcribe-channel "https://www.youtube.com/channel/UC..." -n 20 -o ~/Desktop/channel-dump
yt-transcribe-channel "@handle" -n 10 --whisper-model small --lang en
```

Accepts a channel URL, an `@handle`, or a bare channel ID (`UC...`). Videos are pulled from the channel's "videos" tab, most recent first. Each video is transcribed as an independent subprocess call to `transcribe.py`, so one private/deleted/failed video is logged and skipped in `_manifest.tsv` rather than aborting the whole batch.

Directly, without the symlink:

```bash
python3 ~/.claude-personal/skills/youtube-transcribe/scripts/transcribe_channel.py <channel> -n <N>
```

## When invoked as a skill (not a raw terminal request)

Run the script exactly as the CLI above via Bash, using the resolved skill path:
`~/.claude-personal/skills/youtube-transcribe/scripts/transcribe.py` (single video) or
`~/.claude-personal/skills/youtube-transcribe/scripts/transcribe_channel.py` (channel batch).
Report back the output file path(s)/directory — don't paste full transcripts into chat unless asked, they can be long. For a channel batch, summarize the manifest (how many succeeded/failed) rather than dumping every transcript.

## Requirements

- `yt-dlp`, `ffmpeg` on PATH (both already installed on this machine)
- `whisper` CLI on PATH — only needed for videos with zero captions (already installed here)

## Notes

- Whisper model sizes trade speed for accuracy: `tiny` < `base` (default) < `small` < `medium` < `large`. Bump it for noisy audio or non-English content if `base` mistranscribes.
- Auto-generated YouTube captions are usually good enough and much faster than the Whisper fallback — the script always tries them first.
- Channel batches can be slow if many videos fall back to Whisper (each one is real on-device compute). Keep N modest, or accept a smaller/faster `--whisper-model`, for large batches.
