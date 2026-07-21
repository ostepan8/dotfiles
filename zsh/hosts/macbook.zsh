# ---------- macbook-only config ----------
# Sourced by zsh/zshrc when ~/.dotfiles-host contains "macbook".
# Shared by every machine of this type — nothing device-specific.

# Offline local-LLM chat (Qwen3.6-35B-A3B via MLX) for flights/no-signal use.
# Wraps mlx_lm.chat's stream_generate loop to hide the raw <think> reasoning
# trace it dumps unfiltered — see zsh/scripts/mlx-chat-clean.py.
ccd-airplane() {
    python3 "$HOME/dotfiles/zsh/scripts/mlx-chat-clean.py" \
        --model mlx-community/Qwen3.6-35B-A3B-4bit \
        --max-tokens 4096 \
        "$@"
}
