#!/usr/bin/env bash
# layers: base
#
# Establish this machine's type. Everything else keys off it: which layers apply
# (hosts/layers.conf), which shell overrides load (hosts/<type>.zsh), and which
# nephos tier the machine claims.

[ -f "$HOME/.dotfiles-host" ] && return 0

echo
echo "  This machine has no type set (~/.dotfiles-host)."
echo "  Known types:"
awk '!/^[[:space:]]*#/ && NF > 1 { printf "    %-10s %s\n", $1, substr($0, index($0,$2)) }' \
  "$DOTFILES/hosts/layers.conf"
echo

_host=""
if ask _host "machine type"; then
  printf '%s\n' "$_host" > "$HOME/.dotfiles-host"
  echo "    wrote ~/.dotfiles-host = $_host"
  echo "    re-run install.sh to pick up this machine's full layer set"
else
  echo "    skipped — this machine gets the 'base' layer only until it is set"
fi
unset _host
