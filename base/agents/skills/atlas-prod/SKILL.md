---
name: atlas-prod
description: Look at the production atlas app (origin: ATLAS_ORIGIN in ~/.config/atlas/env) signed in with Claude's own passkey in a phone-sized headless Chromium. NOT for testing — Owen does not want changes tested in prod; test on a local instance instead. Use only for read-only looks at prod when Owen asks ("what does prod show", "screenshot prod"), or a final glance after he has shipped.
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

**Do not test changes here.** Owen (2026-09-25): "we shouldnt test in prod" — verify on a
local instance before shipping; prod is for a read-only look when asked. Tables that run off the right edge, raw numbers, dashes where data should be and
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
