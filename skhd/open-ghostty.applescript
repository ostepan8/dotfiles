-- Open a Ghostty window on the CURRENT Aerospace workspace (not wherever
-- Ghostty's existing windows live). Works in all cases:
--   - Ghostty dead:            activate launches the app (new window appears here)
--   - Ghostty alive elsewhere: activate pulls us to Ghostty's workspace,
--                              Cmd+N makes the new window, we move it back.
-- Compiled into ~/Applications/OpenGhostty.app by mac/setup.sh.
-- Needs Accessibility permission (for Cmd+N keystroke) and assumes
-- aerospace is installed at /opt/homebrew/bin/aerospace.

set aero to "/opt/homebrew/bin/aerospace"

-- Capture the workspace we started on BEFORE activating Ghostty,
-- because `activate` may jump us to Ghostty's existing workspace.
set startWs to do shell script aero & " list-workspaces --focused"

set wasRunning to application "Ghostty" is running
tell application "Ghostty" to activate
if wasRunning then
	delay 0.15
	tell application "System Events" to keystroke "n" using command down
end if

-- Wait for the new window to materialize, then move it back to the
-- workspace we started on and refocus there.
delay 0.3
do shell script aero & " move-node-to-workspace " & startWs
do shell script aero & " workspace " & startWs
