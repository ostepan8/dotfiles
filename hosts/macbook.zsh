# ---------- macbook-only config ----------
# Sourced by zsh/zshrc when ~/.dotfiles-host contains "macbook".
# Shared by every machine of this type — nothing device-specific.

# Where `newproj` puts new projects. Left unset: this machine type has no
# agreed project root yet, so newproj auto-detects (first existing of
# ~/Desktop/Projects ~/Projects ~/projects ~/code ~/dev ~/src ~/Developer).
# Set it here — or in ~/.config/newproj/root, which also applies to
# non-interactive shells — once this machine's layout is settled.
# export NEWPROJ_ROOT="$HOME/Projects"

# Offline local-LLM chat (Qwen3.6-35B-A3B via MLX) for flights/no-signal use.
# Wraps mlx_lm.chat's stream_generate loop to hide the raw <think> reasoning
# trace it dumps unfiltered — see zsh/scripts/mlx-chat-clean.py.
ccd-airplane() {
    python3 "$HOME/dotfiles/workstation/zsh/scripts/mlx-chat-clean.py" \
        --model mlx-community/Qwen3.6-35B-A3B-4bit \
        --max-tokens 4096 \
        "$@"
}

# Open a tmux session on the Studio and reconnect after a dropped connection.
# `s` shows a picker. `s <name>` attaches to that session or creates it, and opens
# its ports at localhost (see hosts/studio-ports.conf).
s() { "$HOME/dotfiles/workstation/zsh/scripts/studio-attach" "$@"; }

# Open an app that runs on the Studio at localhost in the MacBook's browser.
# `sf 3000` opens a tunnel, `sf` lists tunnels, `sf stop` stops them.
sf() { "$HOME/dotfiles/workstation/zsh/scripts/studio-forward" "$@"; }
