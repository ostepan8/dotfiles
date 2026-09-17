#!/usr/bin/env bash
# layers: workstation
#
# Register Finicky as this machine's http/https handler.
#
# Everything in workstation/finicky/ is inert until this happens. Installing the
# cask does NOT make it the handler, and the failure is silent and confusing:
# links keep working, they just land in whichever Chrome profile was touched
# last, which is exactly the behaviour finicky.js exists to eliminate. That is
# how this machine sat for days with a rendered ~/.finicky.js that nothing ever
# consulted -- hence a setup step rather than a README line.
#
# macOS will not let a script change the default browser behind the user's back:
# the call below raises a system confirmation dialog. So this only runs with a
# terminal attached, and reports what is pending otherwise.

_db_handler() {
  # Bundle id currently registered for https, lowercased by LaunchServices.
  python3 - <<'PY' 2>/dev/null
import os, plistlib, subprocess
path = os.path.expanduser(
    "~/Library/Preferences/com.apple.LaunchServices/com.apple.launchservices.secure.plist"
)
try:
    out = subprocess.run(
        ["plutil", "-convert", "xml1", "-o", "-", path], capture_output=True
    )
    handlers = plistlib.loads(out.stdout).get("LSHandlers", [])
except Exception:
    raise SystemExit(0)
for h in handlers:
    if h.get("LSHandlerURLScheme") == "https":
        print(h.get("LSHandlerRoleAll", ""))
        break
PY
}

_db_want="se.johnste.finicky"

if [ ! -d "/Applications/Finicky.app" ]; then
  echo "  Finicky is not installed — links will not be profile-routed."
  echo "    brew install --cask finicky, then re-run install.sh"
elif [ "$(_db_handler)" = "$_db_want" ]; then
  : # already the handler
elif ! setup_is_interactive; then
  SETUP_DEFERRED=1
  echo "  Finicky is installed but is not the default browser."
  echo "    Re-run install.sh from a terminal to set it (macOS asks to confirm)."
else
  echo
  echo "  Finicky is installed but macOS still opens links with $(_db_handler)."
  echo "  Setting it as the default browser — macOS will ask you to confirm."

  # Deprecated in favour of NSWorkspace.setDefaultApplication, which is macOS 14
  # only; this call still works and keeps the fleet's older machines covered.
  swift -suppress-warnings - "$_db_want" <<'SWIFT' 2>/dev/null
import Foundation
import CoreServices

let bundleId = CommandLine.arguments[1] as CFString
for scheme in ["http", "https"] {
    LSSetDefaultHandlerForURLScheme(scheme as CFString, bundleId)
}
SWIFT

  if [ "$(_db_handler)" = "$_db_want" ]; then
    echo "    default browser is now Finicky"
  else
    echo "    not applied — confirm the dialog, or set it in"
    echo "    System Settings > Desktop & Dock > Default web browser"
  fi
fi

unset _db_want
unset -f _db_handler
