#!/usr/bin/env bash
# layers: studio
#
# Keep the Studio on, so agents keep running while the MacBook is away.
#
# WHY THIS EXISTS: the default sleep timer stayed in place because caffeinate
# processes happened to hold it off, and one of them belongs to a bot. If those
# processes stop, the Studio sleeps within a minute and every agent pauses.
# autorestart brings the machine back after a power cut. FileVault still waits
# for a login at the Studio before remote access works.

_pm_value() { pmset -g | awk -v key="$1" '$1 == key { print $2; exit }'; }
_msudo="$HOME/.vault/bin/msudo"

if [ "$(_pm_value sleep)" != "0" ] || [ "$(_pm_value autorestart)" != "1" ]; then
  if [ -x "$_msudo" ]; then
    "$_msudo" 'pmset -a sleep 0 autorestart 1' && echo "    set sleep 0, autorestart 1"
  else
    echo "    pending: run sudo pmset -a sleep 0 autorestart 1"
  fi
fi
