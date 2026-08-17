#!/usr/bin/env bash
# vault-backup.sh — passphrase-encrypted, off-machine backup of ~/.vault.
#
# WHY: the vault is age-encrypted, but the private key that opens it
# (~/.vault/identity.txt) exists on exactly one machine. Lose the Studio and
# every secret in it is gone — the encrypted values on other machines are then
# unreadable forever. The vault's own README documents this design, and lives
# inside the vault, so it dies with it.
#
# WHAT THIS PRODUCES: one .age file containing the whole vault, encrypted with a
# PASSPHRASE rather than the vault's own key. That matters — encrypting the
# backup with the key it protects would be circular and restore nothing.
#
#   ./scripts/vault-backup.sh /Volumes/Backup            # external drive
#   ./scripts/vault-backup.sh ~/Desktop                  # then move it somewhere else
#
# MUST BE RUN INTERACTIVELY: age prompts for the passphrase on a terminal. It is
# never passed as an argument and never touches this script's environment, so it
# cannot leak into process listings, logs, or an agent's transcript.
#
# The passphrase is the whole backup. Put it somewhere that does not depend on
# this machine — a password manager on your phone, or paper. A backup whose
# passphrase is only in the vault it backs up protects nothing.
set -uo pipefail

VAULT="$HOME/.vault"
DEST="${1:-}"

if [ -z "$DEST" ]; then
  echo "usage: vault-backup.sh <destination-directory>" >&2
  echo "  e.g. ./scripts/vault-backup.sh /Volumes/Backup" >&2
  exit 2
fi
[ -d "$VAULT" ]  || { echo "no vault at $VAULT" >&2; exit 1; }
[ -d "$DEST" ]   || { echo "destination is not a directory: $DEST" >&2; exit 1; }
command -v age >/dev/null 2>&1 || { echo "age is not installed" >&2; exit 1; }

if [ ! -t 0 ]; then
  echo "This must be run interactively — age needs a terminal to read the" >&2
  echo "passphrase. Run it yourself; do not pipe a passphrase in." >&2
  exit 3
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="$DEST/vault-backup-$STAMP.age"

echo "Backing up $VAULT"
echo "  secrets:   $(ls "$VAULT/secrets" 2>/dev/null | wc -l | tr -d ' ')"
echo "  target:    $OUT"
echo
echo "Choose a passphrase you can recover WITHOUT this machine."
echo

# --exclude bin: rebuildable tooling, not data. Everything that cannot be
# regenerated — identity.txt, the encrypted secrets, the project map, the audit
# log — goes in.
if ! tar -C "$HOME" --exclude='.vault/bin' -czf - .vault | age -p -o "$OUT"; then
  echo "backup FAILED" >&2
  rm -f "$OUT"
  exit 1
fi
chmod 600 "$OUT"

# Verify by decrypting, not by trusting that the pipeline exited 0. An
# unverified backup is a guess.
echo
echo "Verifying (enter the same passphrase)..."
TMP="$(mktemp -d)"
if age -d "$OUT" 2>/dev/null | tar -C "$TMP" -xzf - 2>/dev/null \
   && [ -s "$TMP/.vault/identity.txt" ] \
   && cmp -s "$TMP/.vault/identity.txt" "$VAULT/identity.txt"; then
  n="$(ls "$TMP/.vault/secrets" 2>/dev/null | wc -l | tr -d ' ')"
  echo "  verified: identity key matches, $n secrets restored readable"
  rm -rf "$TMP"
else
  rm -rf "$TMP"
  echo "  VERIFY FAILED — the archive did not decrypt to a matching identity." >&2
  echo "  Treat $OUT as untrustworthy." >&2
  exit 1
fi

echo
echo "Done: $OUT  ($(du -h "$OUT" | cut -f1))"
echo
echo "Now move it OFF this machine. It is useless sitting next to the vault:"
echo "  - external drive kept elsewhere, or"
echo "  - cloud storage (it is already encrypted), or"
echo "  - another machine that is not part of this fleet"
echo
echo "Restore:  age -d $(basename "$OUT") | tar -C \$HOME -xzf -"
