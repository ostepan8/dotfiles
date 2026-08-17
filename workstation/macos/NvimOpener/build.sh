#!/usr/bin/env bash
# Builds NvimOpener.app — a Finder helper that opens double-clicked files in
# nvim inside a new Ghostty window — and registers it as the default handler
# for a set of code/text extensions. Idempotent: safe to re-run.
#
# Built with osacompile (bundled with macOS) rather than Platypus: Platypus's
# Homebrew cask fails Gatekeeper checks and is scheduled for removal
# (2026-09-01), which would break reproducibility of this setup.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="NvimOpener"
BUNDLE_ID="com.ostepan.nvimopener"
DEST="/Applications/$APP_NAME.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"

# Extensions this app becomes the default opener for ("common code + text").
EXTENSIONS=(sh py js ts tsx go rs c cpp h swift lua md json yaml yml toml txt conf)

if [ ! -x /opt/homebrew/bin/nvim ]; then
  echo "  WARN: /opt/homebrew/bin/nvim not found; skipping NvimOpener build"
  exit 0
fi
if ! command -v duti >/dev/null 2>&1; then
  echo "  WARN: duti not found; skipping NvimOpener default-app registration"
  exit 0
fi

rm -rf "$DEST"
osacompile -o "$DEST" "$SCRIPT_DIR/$APP_NAME.applescript"

/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string $BUNDLE_ID" "$DEST/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$DEST/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :LSUIElement bool true" "$DEST/Contents/Info.plist" 2>/dev/null || true

# Re-sign after editing Info.plist — osacompile's seal breaks once contents change.
codesign --force --deep --sign - "$DEST"

"$LSREGISTER" -f "$DEST"

for ext in "${EXTENSIONS[@]}"; do
  duti -s "$BUNDLE_ID" ".$ext" all
done

echo "  NvimOpener.app installed; default for: ${EXTENSIONS[*]}"
