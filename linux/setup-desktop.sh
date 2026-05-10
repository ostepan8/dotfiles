#!/usr/bin/env bash
set -euo pipefail

need() { command -v "$1" >/dev/null 2>&1; }

if ! need gnome-shell; then
    echo "This script is for GNOME desktops only."
    exit 1
fi

echo "[1/4] Installing Forge tiling extension..."
if need dnf; then
    sudo dnf install -y gnome-shell-extension-forge
elif need apt; then
    sudo apt install -y gnome-shell-extension-forge
elif need pacman; then
    sudo pacman -S --noconfirm gnome-shell-extension-forge
fi

echo "[2/4] Enabling Forge..."
gnome-extensions enable forge@jmmaranan.com 2>/dev/null || true

echo "[3/4] Setting 9 fixed workspaces..."
gsettings set org.gnome.mutter dynamic-workspaces false
gsettings set org.gnome.desktop.wm.preferences num-workspaces 9

echo "[4/4] Binding Alt+1-9 to switch workspace, Alt+Shift+1-9 to move window..."
for i in $(seq 1 9); do
    gsettings set org.gnome.desktop.wm.keybindings switch-to-workspace-$i "['<Alt>$i']"
    gsettings set org.gnome.desktop.wm.keybindings move-to-workspace-$i "['<Alt><Shift>$i']"
done

for i in $(seq 1 9); do
    gsettings set org.gnome.shell.keybindings switch-to-application-$i "[]"
done

echo ""
echo "Done! Log out and back in to activate Forge."
echo ""
echo "Keybinds:"
echo "  Alt+1-9          → switch to workspace 1-9"
echo "  Alt+Shift+1-9    → move window to workspace 1-9"
echo "  (Forge auto-tiles all new windows)"
