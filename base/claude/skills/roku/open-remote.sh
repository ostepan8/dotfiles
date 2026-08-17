#!/bin/bash
# Launch the Roku remote GUI (Tkinter window).
# Usage: ./open-remote.sh [device_name]

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REMOTE="${HERE}/remote.py"

if [[ $# -ge 1 ]]; then
    exec nohup python3 "${REMOTE}" --device "$1" >/dev/null 2>&1 &
else
    exec nohup python3 "${REMOTE}" >/dev/null 2>&1 &
fi
