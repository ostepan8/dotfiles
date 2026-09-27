---
name: tv
description: Put something on Owen's TV and check it worked — "play X", "put on Totoro", "turn on the TV", "open Hulu", "pause", "volume up", "what's on", "what can I watch", "is X on anything I have". Drives the two Roku TVs over ECP, wakes a TV that is off (Wake-on-LAN), finds which of Owen's services streams a title (TMDB), and looks at the 75" through the MX Brio camera on the Mac Studio to confirm each step. Use for any TV request, even casual ones.
---

# tv

Owen talks; you drive the TV. Everything goes through one script:

```bash
TV=~/.agents/skills/tv/scripts/tv.py
$TV status            # power, open app, playing/paused — no side effects
$TV on | off          # `on` wakes an off TV (takes 3-15s); `off` on an off TV is a no-op
$TV where "ponyo"     # which services stream it, each marked [have] / [UNKNOWN-ask Owen]
$TV launch "hbo max"  # by name or id; turns the TV on first
$TV key Left Up Select        # keys in order (--gap secs between, default 0.35)
$TV type "ponyo"              # into a focused search box
$TV apps              # installed apps with ids
$TV snap              # camera frame of the 75", flattened to fill the image → Read it
```

Default TV is the 75" in the living room (the one the camera sees). The other is
"small"/"55"/"owens roku": `$TV status small`, `--tv small` on key/type/launch.

## Playing a title

1. `$TV where "<title>"`. Pick the service marked `[have]`.
   - Only `[UNKNOWN-ask Owen]` services: **ask him** ("Is Crunchyroll one you have?"),
     then record the answer in `~/.config/praxis/services.json` (`"crunchyroll": true`).
     Ask once per service, ever.
   - Nothing he has: say where it rents instead. Don't buy or rent anything.
2. `$TV launch "<app>"`, wait ~8s, `$TV snap`, Read the image.
3. Drive the app, **one screen at a time**: snap → decide 1-3 keys → send → snap. Never
   chain keys across a screen you have not seen. Menus open, close and move focus on
   their own; the two misfires on 2026-09-26 were both a guess made from a stale frame.
   Act within ~2s of a snapshot.
4. Confirm with `$TV status` (`player=play`) plus a final snap, then tell Owen in one line.

Deep links skip the menus when you know the app's own id for the title:
`$TV launch hulu --content-id <id> --media-type series` jumped straight into Rick and
Morty. TMDB does not give these ids. Roku's own search (`/search/browse`) returned
nothing on this TV for every query, so don't use it.

## App notes (learned live)

- **Profiles:** Hulu opens on "Who's watching?" with Owen Stepan highlighted, and Max
  with **owen** highlighted. Press Select.
- **Max:** from the home screen, press Left to open the rail with Home highlighted, then
  Up for Search, then Select. Type the title. Right ×6 leaves the keyboard for the
  first result. Its page shows **Resume** or **Watch Now**.
- **Hulu:** the rail has Search above Home. Left, Up, Select.
- **Netflix** currently needs a sign-in code on the 75". Tell Owen instead of trying.

## Services

`~/.config/praxis/services.json` holds what Owen has. Several are on his mom's accounts,
already signed in on the TV, so email can't tell. His list (2026-09-26): Netflix, Hulu,
Max, Prime Video, Peacock, YouTube Premium, WNBA League Pass, NBA League Pass,
Paramount+, ESPN. Don't infer from email or from installed apps; ask him.

## Setup and limits

- `~/.config/praxis/tvs.json` lists the TVs: serial, MAC (what wakes it), last address,
  aliases. The script re-finds a TV by serial if it moves address and updates the file.
  It is machine-local and not in dotfiles (MACs and LAN IPs stay out of the repo).
- The camera and `snap` exist only on the Mac Studio (`~/projects/praxis/scripts/tvcam`).
  If `snap` looks skewed or cut off, the camera moved: turn the TV on to Roku Home and
  run `~/projects/praxis/scripts/tvcam --calibrate`.
- `TMDB_API_KEY` comes from the vault. It is read by `where` and never printed.
- This is the hands-on path. The service version is **praxis** (`~/projects/praxis`),
  which does wake-first commands over an API for apps. Its agent endpoint (deepseek on
  Subconscious) will automate step 3.
