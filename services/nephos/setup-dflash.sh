#!/bin/sh
# Reproduce the DFlash (mlx-dspark) serving stack for the nephos `big` tier.
# Isolated venv so it never collides with the mlx_lm.server env that serves `fast`.
set -e
python3 -m venv "$HOME/.local/share/nephos/dspark-env"
"$HOME/.local/share/nephos/dspark-env/bin/pip" install --upgrade pip
"$HOME/.local/share/nephos/dspark-env/bin/pip" install mlx-dspark
# First `mlx-dspark serve` auto-downloads the DFlash2 drafter (incoai/Qwen3.8-27B-DFlash2).
echo "done — com.nephos.llm.big.plist runs: mlx-dspark serve --model mlx-community/Qwen3.8-27B-4bit --port 8005 --max-batch 4"
