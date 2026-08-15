# ---------- studio-only config ----------
# Sourced by zsh/zshrc when ~/.dotfiles-host contains "studio".
# Shared by every machine of this type — nothing device-specific.

# Where `newproj` puts new projects. Machine types do NOT share a folder
# layout, so this belongs here rather than in the shared zshrc. Non-interactive
# shells (Claude, cron) never source this file — for those, newproj falls back
# to ~/.config/newproj/root, then to whichever common project dir exists.
export NEWPROJ_ROOT="$HOME/Desktop/Projects"

# ---------- local LLM shortcuts (MLX on Apple Silicon) ----------
#   qwen          interactive chat (4-bit MoE, ~22GB, ~97 tok/s)  <- daily driver
#   qwen "..."    one-shot answer
#   qwen8         8-bit (~38GB) — measured NO code-quality gain over 4-bit at this size
#   qwen38        Qwen3.8-27B 4-bit (~15GB, ~39 tok/s) — stronger on agentic/coding
#                 benchmarks, but dense, so ~2.5x fewer tok/s than the A3B MoE
#   gptoss        gpt-oss-120b (~62GB) — deepest reasoning, eats the machine
#
# MLX benches ~30% faster than Ollama on identical weights, hence the venv.
export MLX_VENV="$HOME/.mlx-env"
_mlx() {  # _mlx <model-repo> [prompt...]
  local model="$1"; shift
  source "$MLX_VENV/bin/activate"
  if [ "$#" -eq 0 ]; then
    python -m mlx_lm chat --model "$model"
  else
    # These models think verbosely (~4-5k tokens before code); give them headroom.
    python -m mlx_lm generate --model "$model" --max-tokens 8000 --prompt "$*"
  fi
}
qwen()   { _mlx mlx-community/Qwen3.6-35B-A3B-OptiQ-4bit "$@"; }
qwen8()  { _mlx mlx-community/Qwen3.6-35B-A3B-8bit       "$@"; }
# Qwen3.8-27B is natively multimodal; the vision path needs mlx_vlm.generate, not mlx_lm.
qwen38() { _mlx mlx-community/Qwen3.8-27B-4bit           "$@"; }
gptoss() { _mlx mlx-community/gpt-oss-120b-MXFP4-Q4      "$@"; }
