---
name: atlas-prod
description: See and test the production atlas app (atlas.onephos.com) exactly as Owen does, signed in with Claude's own passkey in a phone-sized headless Chromium — screenshots, clicking through screens, reading what a screen shows, checking console errors. Use after every atlas deploy that changes anything visible, whenever Owen says a screen "looks wrong/bogus/broken", or when asked to "look at prod", "test prod", "check the app", "screenshot the money tab". Testing prod is non-negotiable for atlas UI work: never report a visible change as done without a screenshot of it on prod.
---

# atlas-prod

Claude has its own passkey on production atlas, labelled `claude`. `prod.mjs` holds it in a
Chromium virtual authenticator, signs in, and drives the real app at a 430×932 phone size.

```bash
P=~/.agents/skills/atlas-prod/prod.mjs
node $P shot <route> [out.png]         # full-page screenshot of /#<route>; prints the path
node $P eval <route> '<js expression>' # evaluate in the signed-in page, print JSON
```

Routes are the app's hash routes: `home`, `money`, `school`, `fleet`, `lights`, `roku`,
custom screens by slug (`money-history`), `settings`. Then `Read` the PNG to look at it.
Console errors are printed after each run (the Cloudflare beacon CSP error is expected noise).

**After a deploy:** screenshot every screen the change touches and look at it before saying
it is done. Tables that run off the right edge, raw numbers, dashes where data should be and
duplicate rows are the usual failures — generic screen blocks print values verbatim.

## Files and revocation

- `~/.config/atlas/claude-passkey.json` — the credential (private key), mode 600. Never copy
  it into git, dotfiles, logs, or chat.
- `~/.config/atlas/claude-session.json` — the cookie session; refreshed on each run.
- Revoke: `ssh fedora 'podman exec systemd-nephos-contextd /contextd passkey ls'`, then
  `... /contextd passkey revoke <id>`. Revoking ends its sessions too.

## Re-enrolling (credential lost or revoked)

```bash
OUT=$(ssh fedora 'podman exec systemd-nephos-contextd /contextd passkey enroll --label claude')
LINK=$(printf '%s\n' "$OUT" | grep -oE 'https://[^ ]+#[^ ]+' | head -1)
node ~/.agents/skills/atlas-prod/prod.mjs enroll "$LINK"
```

Never print `$OUT` or the link: the code in the fragment is a one-time credential. The
container has no shell — call `/contextd` directly.
