# ---------- studio-only config ----------
# Sourced by zsh/zshrc when ~/.dotfiles-host contains "studio".
# Shared by every machine of this type — nothing device-specific.

# Where `newproj` puts new projects. Machine types do NOT share a folder
# layout, so this belongs here rather than in the shared zshrc. Non-interactive
# shells (Claude, cron) never source this file — for those, newproj falls back
# to ~/.config/newproj/root, then to whichever common project dir exists.
export NEWPROJ_ROOT="$HOME/Desktop/Projects"
