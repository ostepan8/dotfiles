#!/usr/bin/env python3
"""Transcribe a YouTube video to a plain-text file, for free, entirely locally.

Strategy:
  1. Try to pull YouTube's own captions (manual, then auto-generated) via yt-dlp.
     Free, instant, no audio download needed.
  2. If no captions exist at all, download just the audio via yt-dlp and
     transcribe it locally with openai-whisper. Free, runs on-device, no API key.

Requires: yt-dlp, ffmpeg, whisper (CLI) all on PATH.
"""
import argparse
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


def die(msg: str) -> None:
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(1)


def check_dependencies() -> None:
    missing = [tool for tool in ("yt-dlp", "ffmpeg") if shutil.which(tool) is None]
    if missing:
        die(f"missing required tool(s): {', '.join(missing)} (install with brew/pip)")


def video_id(url: str) -> str:
    result = subprocess.run(
        ["yt-dlp", "--get-id", url],
        capture_output=True, text=True,
    )
    if result.returncode != 0 or not result.stdout.strip():
        die(f"could not resolve video id for {url}:\n{result.stderr.strip()}")
    return result.stdout.strip()


def video_title(url: str) -> str:
    result = subprocess.run(
        ["yt-dlp", "--get-title", url],
        capture_output=True, text=True,
    )
    if result.returncode != 0 or not result.stdout.strip():
        return "transcript"
    return result.stdout.strip()


def slugify(title: str) -> str:
    slug = re.sub(r"[^\w\s-]", "", title).strip().lower()
    slug = re.sub(r"[\s_-]+", "-", slug)
    return slug or "transcript"


def download_captions(url: str, lang: str, workdir: Path) -> Path | None:
    """Try manual captions first, then auto-generated. Returns the .vtt path or None."""
    for auto_flag in ("--no-write-auto-subs", "--write-auto-subs"):
        out_tmpl = str(workdir / "%(id)s.%(ext)s")
        cmd = [
            "yt-dlp", "--skip-download",
            "--write-subs", auto_flag,
            "--sub-langs", lang,
            "--sub-format", "vtt",
            "-o", out_tmpl,
            url,
        ]
        subprocess.run(cmd, capture_output=True, text=True)
        vtt_files = list(workdir.glob("*.vtt"))
        if vtt_files:
            return vtt_files[0]
    return None


TAG_RE = re.compile(r"<[^>]+>")
TIMESTAMP_LINE_RE = re.compile(r"-->")


def vtt_to_text(vtt_path: Path) -> str:
    lines = vtt_path.read_text(encoding="utf-8", errors="ignore").splitlines()
    cues: list[str] = []
    last_line = ""
    for raw in lines:
        line = raw.strip()
        if not line or line == "WEBVTT" or line.isdigit():
            continue
        if TIMESTAMP_LINE_RE.search(line) or line.startswith(("Kind:", "Language:")):
            continue
        text = TAG_RE.sub("", line).strip()
        if not text or text == last_line:
            continue
        cues.append(text)
        last_line = text
    return " ".join(cues)


def download_audio(url: str, workdir: Path) -> Path:
    out_tmpl = str(workdir / "%(id)s.%(ext)s")
    cmd = [
        "yt-dlp", "-x", "--audio-format", "mp3",
        "-o", out_tmpl,
        url,
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        die(f"audio download failed:\n{result.stderr.strip()}")
    audio_files = list(workdir.glob("*.mp3"))
    if not audio_files:
        die("audio download reported success but no mp3 file was found")
    return audio_files[0]


def transcribe_audio(audio_path: Path, workdir: Path, model: str, lang: str) -> str:
    if shutil.which("whisper") is None:
        die("openai-whisper not found on PATH (pip install openai-whisper)")
    cmd = [
        "whisper", str(audio_path),
        "--model", model,
        "--output_format", "txt",
        "--output_dir", str(workdir),
    ]
    if lang:
        cmd += ["--language", lang]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        die(f"whisper transcription failed:\n{result.stderr.strip()}")
    txt_path = workdir / f"{audio_path.stem}.txt"
    if not txt_path.exists():
        die("whisper reported success but no .txt output was found")
    return txt_path.read_text(encoding="utf-8", errors="ignore").strip()


def main() -> None:
    parser = argparse.ArgumentParser(description="Transcribe a YouTube video to a plain-text file, for free, locally.")
    parser.add_argument("url", help="YouTube video URL (or ID)")
    parser.add_argument("-o", "--output", help="output .txt path (default: <video-title>.txt in cwd)")
    parser.add_argument("--lang", default="en", help="caption/spoken language code (default: en)")
    parser.add_argument("--whisper-model", default="base",
                         choices=["tiny", "base", "small", "medium", "large"],
                         help="whisper model size for audio fallback (default: base)")
    parser.add_argument("--keep-audio", action="store_true", help="keep the downloaded audio file")
    args = parser.parse_args()

    check_dependencies()

    with tempfile.TemporaryDirectory(prefix="yt-transcribe-") as tmp:
        workdir = Path(tmp)

        print("resolving video...", file=sys.stderr)
        title = video_title(args.url)

        print("checking for existing captions...", file=sys.stderr)
        vtt_path = download_captions(args.url, args.lang, workdir)

        if vtt_path is not None:
            print(f"found captions ({vtt_path.name}), extracting text...", file=sys.stderr)
            text = vtt_to_text(vtt_path)
        else:
            print("no captions available, downloading audio for local transcription...", file=sys.stderr)
            audio_path = download_audio(args.url, workdir)
            print(f"transcribing with whisper ({args.whisper_model} model, this may take a while)...", file=sys.stderr)
            text = transcribe_audio(audio_path, workdir, args.whisper_model, args.lang)
            if args.keep_audio:
                dest = Path.cwd() / audio_path.name
                shutil.copy(audio_path, dest)
                print(f"kept audio file: {dest}", file=sys.stderr)

        if not text:
            die("transcription produced no text")

        output_path = Path(args.output) if args.output else Path.cwd() / f"{slugify(title)}.txt"
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(text + "\n", encoding="utf-8")

        print(str(output_path))


if __name__ == "__main__":
    main()
