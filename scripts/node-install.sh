#!/usr/bin/env bash
# node-install.sh — run install.sh on a node whose sudo needs a password.
#
# Runs ON THE NODE. The password arrives on stdin, never in argv, so it is not
# visible in `ps` on the target.
#
# WHY THIS IS NOT JUST `sudo -v` FIRST:
# Fedora's sudo defaults to timestamp_type=tty, and a non-interactive ssh has no
# tty, so sudo cannot record a credential timestamp at all. `sudo -S -v` reports
# success and `sudo -n true` immediately after still misses — measured on gpu1.
# Priming is therefore useless here; every single sudo call needs its own
# password.
#
# WHY NOT ALLOCATE A TTY (ssh -tt):
# That fixes caching, but the pty echoes whatever is piped in back onto the
# output stream — which would put the password in the caller's terminal and
# logs. Worse than the problem.
#
# WHAT THIS DOES INSTEAD:
# Defines a `sudo` wrapper that feeds the password to `sudo -S` on each call,
# and exports it so the installer's child processes inherit it.
#
# The tradeoff, stated plainly: the password lives in this process tree's
# environment for the duration, readable via /proc by the same user and by root.
# Root already has everything, and these are single-user nodes. It never touches
# disk, never enters argv, and never reaches the caller's terminal. Accept it
# for an unattended fleet install; do not copy this pattern onto a shared host.
set -uo pipefail

read -r NODE_SUDO_PW || { echo "no password on stdin" >&2; exit 2; }

if ! printf '%s\n' "$NODE_SUDO_PW" | command sudo -S -p '' true 2>/dev/null; then
  echo "SUDO-REJECTED: the stored password did not work on this host" >&2
  unset NODE_SUDO_PW
  exit 4
fi
echo "sudo verified"

export NODE_SUDO_PW
sudo() { printf '%s\n' "$NODE_SUDO_PW" | command sudo -S -p '' "$@"; }
export -f sudo

cd "$HOME/dotfiles" || { echo "no ~/dotfiles" >&2; exit 1; }

# stdin is closed for the installer: it was consumed by the password read, and
# anything that tries to prompt should fail rather than inherit the remainder of
# the pipe.
./install.sh </dev/null
rc=$?

unset NODE_SUDO_PW
echo "install.sh exited $rc"
exit "$rc"
