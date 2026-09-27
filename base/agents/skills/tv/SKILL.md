---
name: tv
description: Put something on Owen's TV and check it worked — "play X", "put on Totoro", "turn on the TV", "open Hulu", "pause", "volume up", "what's on", "what can I watch", "is X on anything I have". Goes through praxis (Owen's home-device service): wakes a TV that is off, finds which of Owen's services streams a title, and looks at the 75" through the Studio camera to confirm each step. Works from a terminal, atlas's agent, workq, or any tailnet machine. Use for any TV request, even casual ones.
---

# tv

Owen talks; you drive the TV. Everything goes through one script, which only calls
**praxis** (the service on the Mac Studio that holds the LAN and camera permissions):

```bash
TV=~/.agents/skills/tv/scripts/tv.py
$TV status            # power, open app, playing/paused — no side effects
$TV devices           # every TV and lamp with health (reachable / asleep / offline)
$TV on | off          # `on` wakes an off TV (takes 3-15s); `off` on an off TV is a no-op
$TV where "ponyo"     # which services stream it, each marked [have] / [dont_have] / [unknown]
$TV have crunchyroll yes      # record Owen's answer about a service
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
   - Only `[unknown]` services: **ask him** (`where` prints the question), then record
     it with `$TV have <service> yes|no`. Ask once per service, ever.
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
- **Hulu:** the rail has Search above Home, and it **collapses within ~3s**. Send
  `key Left Up Select` as one burst; a snapshot in between is too slow and Select then
  opens a tile instead.
- **Netflix** currently needs a sign-in code on the 75". Tell Owen instead of trying.

## Services

praxis keeps what Owen has (`GET /services`; `have` changes it). Several are on his mom's
accounts, already signed in on the TV, so email can't tell. His list (2026-09-26): Netflix,
Hulu, Max, Prime Video, Peacock, YouTube Premium, WNBA League Pass, NBA League Pass,
Paramount+, ESPN. Don't infer from email or installed apps; ask him.

## Setup and limits

- Needs `~/.config/praxis/api-key` (a praxis key with tv,read,lights; 0600) on the machine
  running the script. On the Studio praxis is `http://127.0.0.1:8097`. On any other
  machine, set `PRAXIS_URL` to the Studio's tailnet name on port 8097.
- Optional `~/.config/praxis/tvs.json` gives aliases ("big", "small") and the default TV.
  It's machine-local, not in dotfiles.
- `snap` only works for the 75" (the TV the camera sees). If it looks skewed or cut off,
  the camera moved: with the TV on Roku Home, run `~/projects/praxis/scripts/tvcam
  --calibrate` on the Studio.
- An error like `could not reach praxis` means the service is down: `nephos ps | grep
  praxisd`, `nephos logs praxisd`. praxis's own docs are in `~/projects/praxis/README.md`.
