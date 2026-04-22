-- Launches Ghostty if dead; creates a new window via Cmd+N if already running.
-- Compiled into ~/Applications/OpenGhostty.app by mac/setup.sh.
-- Needs Accessibility permission (to send the Cmd+N keystroke).

set wasRunning to application "Ghostty" is running
tell application "Ghostty" to activate
if wasRunning then
	delay 0.15
	tell application "System Events" to keystroke "n" using command down
end if
