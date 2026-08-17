---
name: yeelight
description: Control Yeelight smart bulbs. Use when the user wants to turn lights on/off, change brightness, or set colors. Triggers on requests like "turn on my lights", "make my lights red", "dim the lights to 50%", "turn off the lights".
---

# Yeelight Control

Control Yeelight bulbs via the `yeelight` Python library.

## Setup

Ensure `yeelight` is installed:
```bash
pip install yeelight --break-system-packages
```

**Bulb addresses live in `~/.config/yeelight/bulbs.txt`, one per line** — outside this
repo, which is public. A bulb list is an inventory of the home LAN, so it follows the
same rule as `~/.config/nephos/env`: never committed.

If that file is missing, yeelight isn't set up on this machine. Say so rather than
guessing addresses — see `references/bulbs.txt.template` for how to create it.

## Usage

Use `scripts/control.py` for all operations. It reads the default config path above,
so no `--config` flag is needed:

```bash
# Turn all bulbs on/off
python scripts/control.py on
python scripts/control.py off

# Set brightness (1-100)
python scripts/control.py brightness --brightness 50

# Set color (hex or r,g,b)
python scripts/control.py color --color "#ff0000"
python scripts/control.py color --color "255,0,0"

# Check status
python scripts/control.py status

# Target specific bulbs, or a different config file
python scripts/control.py on --ip 10.0.0.10 --ip 10.0.0.11
python scripts/control.py on --config /path/to/other-bulbs.txt
```

## Color Reference

Common colors: red `#ff0000`, green `#00ff00`, blue `#0000ff`, warm white `#ffaa55`, cool white `#aaccff`, purple `#8800ff`, orange `#ff6600`, pink `#ff66cc`.

## Notes

- Bulbs must have LAN control enabled in the Yeelight app
- The script sets `auto_on=True`, so color/brightness commands will turn on bulbs that are off
- Operations run sequentially; expect ~0.5s per bulb
