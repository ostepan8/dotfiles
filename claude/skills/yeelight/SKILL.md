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

Bulb IPs are listed in `references/bulbs.txt`, one per line.

## Usage

Use `scripts/control.py` for all operations:

```bash
# Turn all bulbs on/off
python scripts/control.py on --config references/bulbs.txt
python scripts/control.py off --config references/bulbs.txt

# Set brightness (1-100)
python scripts/control.py brightness --config references/bulbs.txt --brightness 50

# Set color (hex or r,g,b)
python scripts/control.py color --config references/bulbs.txt --color "#ff0000"
python scripts/control.py color --config references/bulbs.txt --color "255,0,0"

# Check status
python scripts/control.py status --config references/bulbs.txt

# Target specific bulbs instead of config file
python scripts/control.py on --ip 192.168.1.100 --ip 192.168.1.101
```

## Color Reference

Common colors: red `#ff0000`, green `#00ff00`, blue `#0000ff`, warm white `#ffaa55`, cool white `#aaccff`, purple `#8800ff`, orange `#ff6600`, pink `#ff66cc`.

## Notes

- Bulbs must have LAN control enabled in the Yeelight app
- The script sets `auto_on=True`, so color/brightness commands will turn on bulbs that are off
- Operations run sequentially; expect ~0.5s per bulb
