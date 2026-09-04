---
name: roku
description: Control Roku TVs - play, pause, volume, launch apps, navigate, power, search, switch inputs. Multi-device support. Use when the user wants to control their TV, Roku, change channel, adjust volume, open Netflix/YouTube/Hulu, turn TV on/off, or asks what's playing. Triggers on "turn on the TV", "pause", "play", "open Netflix", "volume up", "what's playing", "switch to HDMI", "turn off bedroom TV", "mute all TVs".
---

# Roku TV Control

Control Roku devices via the External Control Protocol (ECP) using `roku.py` in the assistant project directory.

## Tool Location

The CLI tool is at: `/Users/ostepan/Desktop/projects/claude-code/claude-code-living-directory/roku.py`

## Interactive Remote (keybind TUI)

For hands-on remote control, launch the keybind TUI:

```bash
# Opens a new Terminal window with the remote running
/Users/ostepan/.claude/skills/roku/open-remote.sh              # default device
/Users/ostepan/.claude/skills/roku/open-remote.sh "bedroom"    # specific device
```

Triggers: "open the remote", "launch remote", "remote control mode",
"give me a keybind interface". Always launch via `open-remote.sh` so the
user has a real TTY — never `python3 remote.py` directly from this session
(the Bash tool has no keyboard input).

Keymap: arrows = D-pad, Enter = select, h = home, b = back, space = play/pause,
+/- = volume, m = mute, , / . = rewind/ff, / = instant replay, P/O = power on/off,
n y u = Netflix/YouTube/Hulu, 1-4 = HDMI, s = search, t = type, i = now-playing,
d = switch device, r = re-discover, ? = help, q = quit.

Source: `remote.py` (same skill dir) — shells out to `roku.py` per keypress.

## Quick Reference

```bash
# Device management
python3 roku.py discover                          # Find Rokus on network
python3 roku.py devices                           # List registered devices
python3 roku.py name <serial_or_name> <name>      # Assign friendly name
python3 roku.py default <name>                    # Set default device

# Playback
python3 roku.py play                              # Resume
python3 roku.py pause                             # Pause
python3 roku.py rewind                            # Rewind
python3 roku.py fast-forward                      # Fast forward
python3 roku.py instant-replay                    # Jump back

# Navigation
python3 roku.py home                              # Home screen
python3 roku.py back                              # Go back
python3 roku.py select                            # OK/Select
python3 roku.py up / down / left / right          # D-pad

# Volume & Power
python3 roku.py volume-up --count 5               # Volume up (repeat)
python3 roku.py volume-down --count 3             # Volume down (repeat)
python3 roku.py mute                              # Toggle mute
python3 roku.py power-on                          # Turn on
python3 roku.py power-off                         # Turn off

# Apps & Content
python3 roku.py launch Netflix                    # Launch app by name
python3 roku.py search "breaking bad"             # Search content
python3 roku.py type "hello"                      # Type text
python3 roku.py apps                              # List installed apps

# Info
python3 roku.py info                              # Device info
python3 roku.py now-playing                       # Current app
python3 roku.py player-info                       # Playback state

# Input switching
python3 roku.py switch-input HDMI1                # Switch input

# Raw key
python3 roku.py key Enter                         # Send any ECP key
```

## Multi-Device Targeting

```bash
# Target a specific device by friendly name
python3 roku.py pause --device "bedroom"
python3 roku.py launch Netflix --device "living room"

# Target ALL devices
python3 roku.py power-off --all
python3 roku.py mute --all

# No flag = uses default device
python3 roku.py play
```

## Device Setup

First time or when adding a new TV:
1. `python3 roku.py discover` — finds Rokus via SSDP network scan
2. `python3 roku.py devices` — see what was found
3. `python3 roku.py name <serial> "Living Room"` — assign friendly names
4. `python3 roku.py default "Living Room"` — set default

Device config is persisted in `roku_devices.json` (same directory as roku.py).

## Natural Language Mapping

When the user says:
- "pause the TV" / "pause" -> `python3 roku.py pause`
- "turn on the bedroom TV" -> `python3 roku.py power-on --device bedroom`
- "open Netflix" / "put on Netflix" -> `python3 roku.py launch Netflix`
- "turn it up" / "volume up" -> `python3 roku.py volume-up --count 5`
- "mute" -> `python3 roku.py mute`
- "what's on?" / "what's playing?" -> `python3 roku.py now-playing`
- "go home" / "home screen" -> `python3 roku.py home`
- "turn off all TVs" -> `python3 roku.py power-off --all`
- "switch to HDMI 2" -> `python3 roku.py switch-input HDMI2`
- "search for breaking bad" -> `python3 roku.py search "breaking bad"`

For volume changes without a specific number, use count 5 as a reasonable step.

## Error Handling

If a command fails with "No device found", run `python3 roku.py discover` first to refresh the device registry. The device may have changed IP or gone offline.

## Dependencies

None beyond Python 3 stdlib (uses urllib, no pip installs needed).
