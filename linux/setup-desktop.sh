#!/usr/bin/env bash
set -euo pipefail

need() { command -v "$1" >/dev/null 2>&1; }

if ! need gnome-shell; then
    echo "This script is for GNOME desktops only."
    exit 1
fi

echo "[1/5] Installing Forge tiling extension..."
if need dnf; then
    sudo dnf install -y gnome-shell-extension-forge
elif need apt; then
    sudo apt install -y gnome-shell-extension-forge
elif need pacman; then
    sudo pacman -S --noconfirm gnome-shell-extension-forge
fi

echo "[2/5] Enabling Forge..."
gnome-extensions enable forge@jmmaranan.com 2>/dev/null || true

echo "[3/5] Disabling Forge's red focus-border outline..."
gsettings set org.gnome.shell.extensions.forge focus-border-toggle false
gsettings set org.gnome.shell.extensions.forge split-border-toggle false
gsettings set org.gnome.shell.extensions.forge preview-hint-enabled false

echo "[4/5] Setting 9 fixed workspaces..."
gsettings set org.gnome.mutter dynamic-workspaces false
gsettings set org.gnome.desktop.wm.preferences num-workspaces 9

echo "[5/5] Binding Alt+1-9 to switch workspace, Alt+Shift+1-9 to move window..."
for i in $(seq 1 9); do
    gsettings set org.gnome.desktop.wm.keybindings switch-to-workspace-$i "['<Alt>$i']"
    gsettings set org.gnome.desktop.wm.keybindings move-to-workspace-$i "['<Alt><Shift>$i']"
done

# Clear any GNOME defaults that conflict with Alt+N
for i in $(seq 1 9); do
    gsettings set org.gnome.shell.keybindings switch-to-application-$i "[]"
done

# Monitor navigation (matches Aerospace alt+[ / alt+])
gsettings set org.gnome.shell.extensions.forge.keybindings window-focus-left "['<Alt>bracketleft']"
gsettings set org.gnome.shell.extensions.forge.keybindings window-focus-right "['<Alt>bracketright']"
gsettings set org.gnome.desktop.wm.keybindings move-to-monitor-left "['<Alt><Shift>bracketleft']"
gsettings set org.gnome.desktop.wm.keybindings move-to-monitor-right "['<Alt><Shift>bracketright']"

echo ""
echo "Done! Log out and back in to activate Forge."
echo ""
echo "Keybinds:"
echo "  Alt+1-9            → switch to workspace 1-9"
echo "  Alt+Shift+1-9      → move window to workspace 1-9"
echo "  Alt+[ / Alt+]      → focus window on left/right monitor"
echo "  Alt+Shift+[ / ]    → move window to left/right monitor"
echo "  (Forge auto-tiles new windows, no red focus-border outline)"
