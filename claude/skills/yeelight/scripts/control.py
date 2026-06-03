#!/usr/bin/env python3
"""Control Yeelight bulbs. Requires: pip install yeelight"""

import argparse
import sys
from pathlib import Path
from yeelight import Bulb, BulbException

def load_bulbs(config_path: str | None, ips: list[str] | None) -> list[str]:
    """Load bulb IPs from config file and/or CLI args."""
    all_ips = []
    
    if config_path:
        config = Path(config_path)
        if config.exists():
            all_ips.extend(line.strip() for line in config.read_text().splitlines() if line.strip() and not line.startswith('#'))
    
    if ips:
        all_ips.extend(ips)
    
    return list(dict.fromkeys(all_ips))  # dedupe, preserve order

def run_action(ip: str, action: str, **kwargs) -> tuple[bool, str]:
    """Run an action on a single bulb. Returns (success, message)."""
    try:
        bulb = Bulb(ip, auto_on=True)
        
        if action == "on":
            bulb.turn_on()
        elif action == "off":
            bulb.turn_off()
        elif action == "brightness":
            bulb.set_brightness(kwargs["value"])
        elif action == "color":
            bulb.set_rgb(kwargs["r"], kwargs["g"], kwargs["b"])
        elif action == "status":
            props = bulb.get_properties()
            power = props.get("power", "unknown")
            bright = props.get("bright", "?")
            return True, f"power={power}, brightness={bright}%"
        
        return True, "ok"
    except BulbException as e:
        return False, str(e)
    except Exception as e:
        return False, str(e)

def parse_color(color_str: str) -> tuple[int, int, int]:
    """Parse color from hex (#ff0000) or r,g,b format."""
    color_str = color_str.strip()
    if color_str.startswith("#"):
        hex_val = color_str[1:]
        return int(hex_val[0:2], 16), int(hex_val[2:4], 16), int(hex_val[4:6], 16)
    parts = [int(x.strip()) for x in color_str.split(",")]
    return parts[0], parts[1], parts[2]

def main():
    parser = argparse.ArgumentParser(description="Control Yeelight bulbs")
    parser.add_argument("action", choices=["on", "off", "brightness", "color", "status"])
    parser.add_argument("--config", "-c", help="Path to bulbs.txt config file")
    parser.add_argument("--ip", "-i", action="append", help="Bulb IP (can specify multiple)")
    parser.add_argument("--brightness", "-b", type=int, help="Brightness 1-100")
    parser.add_argument("--color", help="Color as #rrggbb or r,g,b")
    
    args = parser.parse_args()
    
    ips = load_bulbs(args.config, args.ip)
    if not ips:
        print("Error: No bulb IPs provided. Use --config or --ip", file=sys.stderr)
        sys.exit(1)
    
    kwargs = {}
    if args.action == "brightness":
        if not args.brightness:
            print("Error: --brightness required for brightness action", file=sys.stderr)
            sys.exit(1)
        kwargs["value"] = max(1, min(100, args.brightness))
    elif args.action == "color":
        if not args.color:
            print("Error: --color required for color action", file=sys.stderr)
            sys.exit(1)
        kwargs["r"], kwargs["g"], kwargs["b"] = parse_color(args.color)
    
    errors = []
    for ip in ips:
        success, msg = run_action(ip, args.action, **kwargs)
        status = "✓" if success else "✗"
        print(f"{status} {ip}: {msg}")
        if not success:
            errors.append(ip)
    
    sys.exit(1 if errors else 0)

if __name__ == "__main__":
    main()
