-- Opens files dropped/double-clicked in Finder inside a new Ghostty window running nvim.
-- Ghostty runs the "command" property through `bash --noprofile --norc -c "exec -l <command>"`,
-- so PATH is minimal — nvim must be referenced by absolute path.

property nvimPath : "/opt/homebrew/bin/nvim"

on open theFiles
	set posixPaths to {}
	repeat with aFile in theFiles
		set end of posixPaths to quoted form of (POSIX path of aFile)
	end repeat

	set AppleScript's text item delimiters to " "
	set fileArgs to posixPaths as string
	set AppleScript's text item delimiters to ""

	if (count of posixPaths) > 1 then
		set cmd to nvimPath & " -p " & fileArgs
	else
		set cmd to nvimPath & " " & fileArgs
	end if

	tell application "Ghostty"
		new window with configuration {command:cmd}
		activate
	end tell
end open

on run
	display dialog "NvimOpener is a Finder helper — it has no window of its own." & return & return & "Drag a file onto it, or set it as the default app for a file type (Get Info → Open With → Change All)." buttons {"OK"} default button 1 with icon note
end run
