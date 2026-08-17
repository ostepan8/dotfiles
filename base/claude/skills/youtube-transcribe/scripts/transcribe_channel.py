#!/usr/bin/env python3
"""Transcribe the N most recent videos from a YouTube channel to plain-text files.

If the channel has fewer than N videos, transcribes all of them.
Reuses transcribe.py (captions first, local Whisper fallback) per video, run
as a subprocess so one failing/private/deleted video doesn't abort the batch.
"""
import argparse
import re
import shutil
import subprocess
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
TRANSCRIBE_SCRIPT = SCRIPT_DIR / "transcribe.py"


def die(msg: str) -> None:
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(1)


def check_dependencies() -> None:
    if shutil.which("yt-dlp") is None:
        die("missing required tool: yt-dlp")


def normalize_channel_url(channel: str) -> str:
    if channel.startswith("http://") or channel.startswith("https://"):
        base = channel.rstrip("/")
    elif channel.startswith("@"):
        base = f"https://www.youtube.com/{channel}"
    elif channel.startswith("UC") and len(channel) == 24:
        base = f"https://www.youtube.com/channel/{channel}"
    else:
        base = f"https://www.youtube.com/@{channel}"
    if not re.search(r"/(videos|streams|shorts)$", base):
        base = f"{base}/videos"
    return base


def list_recent_videos(channel_url: str, count: int) -> tuple[str, list[tuple[str, str]]]:
    """Returns (channel_name, [(video_id, title), ...])."""
    cmd = [
        "yt-dlp", "--flat-playlist", "--playlist-end", str(count),
        "--print", "%(id)s\t%(title)s\t%(playlist_channel)s",
        channel_url,
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        die(f"could not list videos for {channel_url}:\n{result.stderr.strip()}")
    videos = []
    channel_name = ""
    for line in result.stdout.splitlines():
        parts = line.split("\t")
        if len(parts) < 2:
            continue
        vid, title = parts[0].strip(), parts[1].strip()
        if len(parts) > 2 and parts[2].strip():
            channel_name = parts[2].strip()
        videos.append((vid, title))
    if not videos:
        die(f"no videos found for {channel_url}")
    return channel_name, videos


def slugify(title: str) -> str:
    slug = re.sub(r"[^\w\s-]", "", title).strip().lower()
    slug = re.sub(r"[\s_-]+", "-", slug)
    return slug or "video"


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Transcribe the N most recent videos from a YouTube channel (fewer if the channel has less than N)."
    )
    parser.add_argument("channel", help="Channel URL, @handle, or channel ID (UC...)")
    parser.add_argument("-n", "--count", type=int, default=10, help="max number of recent videos to transcribe (default: 10)")
    parser.add_argument("-o", "--output-dir", help="directory to write transcripts into (default: ./<channel-slug>/)")
    parser.add_argument("--lang", default="en", help="caption/spoken language code (default: en)")
    parser.add_argument("--whisper-model", default="base",
                         choices=["tiny", "base", "small", "medium", "large"],
                         help="whisper model size for videos with no captions (default: base)")
    parser.add_argument("--keep-audio", action="store_true", help="keep downloaded audio for videos transcribed via whisper")
    args = parser.parse_args()

    check_dependencies()

    channel_url = normalize_channel_url(args.channel)
    print(f"listing up to {args.count} most recent videos from {channel_url}...", file=sys.stderr)
    channel_name, videos = list_recent_videos(channel_url, args.count)
    print(f"found {len(videos)} video(s)" + (" (channel has fewer than requested)" if len(videos) < args.count else ""), file=sys.stderr)

    default_dir_name = slugify(channel_name) if channel_name else slugify(args.channel.lstrip("@"))
    out_dir = Path(args.output_dir) if args.output_dir else Path.cwd() / default_dir_name
    out_dir.mkdir(parents=True, exist_ok=True)

    manifest_lines = ["index\tvideo_id\tstatus\ttitle\tfile"]
    for i, (vid, title) in enumerate(videos, start=1):
        url = f"https://www.youtube.com/watch?v={vid}"
        out_file = out_dir / f"{i:03d}-{vid}.txt"
        print(f"\n[{i}/{len(videos)}] {title} ({vid})", file=sys.stderr)

        cmd = [
            sys.executable, str(TRANSCRIBE_SCRIPT), url,
            "-o", str(out_file),
            "--lang", args.lang,
            "--whisper-model", args.whisper_model,
        ]
        if args.keep_audio:
            cmd.append("--keep-audio")

        result = subprocess.run(cmd)
        status = "ok" if result.returncode == 0 and out_file.exists() else "failed"
        if status == "failed":
            print(f"  -> failed, skipping", file=sys.stderr)
        manifest_lines.append(f"{i}\t{vid}\t{status}\t{title}\t{out_file.name if status == 'ok' else ''}")

    manifest_path = out_dir / "_manifest.tsv"
    manifest_path.write_text("\n".join(manifest_lines) + "\n", encoding="utf-8")

    ok_count = sum(1 for line in manifest_lines[1:] if "\tok\t" in line)
    print(f"\ndone: {ok_count}/{len(videos)} transcribed successfully", file=sys.stderr)
    print(str(out_dir))


if __name__ == "__main__":
    main()
