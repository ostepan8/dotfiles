---
name: app-login
description: Sign an agent into one of Owen's web apps (atlas today) and look at it — a local copy built from the code you are changing, or a read-only look at production. Use for EVERY screenshot or UI check of atlas: "screenshot it", "check the UI", "does it look right on a phone", PR screenshots, "what does prod show". It handles the passkey (Claude's own, kept in the vault), a fresh local database, dark mode and phone size. Never mock the app's API or invent data to get a screenshot — use this.
---

# app-login

Owen's apps sign in with passkeys only, so an agent cannot type a password. That is why
agents used to mock the API and screenshot invented data, and Owen threw those PRs back.
`app-login` gives every agent a real, signed-in session:

- **Local** (`up`): builds the checkout you are in (your worktree, your change), starts it
  on its own database and ports, and enrols a throwaway passkey for `claude`. Nothing to store:
  the next `up` makes a new one.
- **Production** (`--prod`): Claude's passkey on the live app lives in the vault as
  `ATLAS_CLAUDE_PASSKEY`. Each run takes it out for that run only and puts it back with
  its new sign count; a stale count is refused.

```bash
app-login atlas up                       # from inside an atlas checkout (or --src DIR)
app-login atlas shot work                # → PNG path; Read it
app-login atlas shot work/new out.png    # hash route, optional output path
app-login atlas eval home 'document.title'
app-login atlas run flow.mjs             # click through, then shot()
app-login atlas status | down
app-login atlas --prod shot money        # read-only look at production
app-login --list                         # apps with a recipe
```

Flags anywhere after the command: `--wide` (1440×900 desktop), `--full` (whole page, not
just what fits on screen), `--light` (light theme). The default is Owen's phone: 430×932,
2× scale, **dark**.

A `run` script is an ES module whose default export gets `{ page, shot, goto, origin }`
(Playwright `page`, `shot(path)`, `goto(route)` which lands signed in):

```js
export default async ({ page, shot, goto }) => {
  await goto("work");
  await page.getByRole("button", { name: "New task" }).click();
  await shot("/tmp/new-task.png");
};
```

## Screenshots for a PR

Owen reads these on his phone. What he rejected: ten near-identical images, desktop views of
a phone app, and fake data.

1. Phone size and dark, which is the default. Add `--wide` only when the change is about the desktop layout.
2. **Only screens the change touches**, showing the change, at most 3. A "before" only when
   the difference is not obvious from the "after" alone.
3. Real data only. A local copy starts empty, and panels backed by outside services (lights,
   TV, Kalshi, weather, the fleet) say "not configured". That is the truth, so say it in the PR. To show
   data, create it through the app itself (`run` a script that fills in the form) or through
   its API. Never mock responses.
4. Look at every image (Read the PNG) before attaching it, and cut any that show nothing new.

## Rules

- **Test locally, never in production.** `--prod` is for a read-only look when Owen asks, or
  a final glance after he has shipped. Never click anything that changes state there.
- A local copy runs with `env -i` and only its own settings, so it cannot reach a real lamp,
  TV, Kalshi account or the fleet.
- The enrol link and the credential never go to stdout, logs, git or chat.
- Local copies are keyed by source directory, so parallel worktrees each get their own.
  `down` when you are done. They share one Postgres container, `app-login-pg`.
- Each local copy's `env` file (`~/.cache/app-login/<app>/<key>/env`, mode 600) holds its
  database URLs and, for atlas, the local workq URL and tokens, for seeding data through the API.

## atlas specifics

- `up` builds `apps/pwa` (embedded into the server), the server, and workqd when the tree has it.
  It fills in the Work screen's project list from `~/projects`, the same way the Studio runner does.
- `APPLOGIN_ATLAS_ENV=<file>` adds `ATLAS_*=value` lines from that file to the local server's
  environment, e.g. `ATLAS_CHAT_AGENT_URL`/`ATLAS_CHAT_AGENT_TOKEN` for a local studio-agent.
- Routes are the hash routes: `home`, `work`, `work/new`, `money`, `school`, `fleet`,
  `lights`, `roku`, `settings`, and custom screens by slug.
- The sign-in gate is the "Sign in with passkey" button. If it still shows after pressing it,
  the passkey was refused. For a local copy, run `up` again. For prod, re-enrol it.

## Enrolling Claude's production passkey (lost or revoked)

```bash
OUT=$(ssh fedora 'podman exec systemd-nephos-atlas-app /atlas passkey enroll --label claude')
LINK=$(printf '%s\n' "$OUT" | grep -oE 'https://[^ ]+#[^ ]+' | head -1)
D=~/.cache/app-login/atlas/prod; mkdir -p "$D"; C=$(mktemp "$D/cred.XXXXXX")
APPLOGIN_ORIGIN=$(grep ^ATLAS_ORIGIN= ~/.config/atlas/env | cut -d= -f2-) APPLOGIN_CRED="$C" \
  APPLOGIN_STATE="$D/state.json" node ~/.agents/skills/app-login/browser.mjs enroll "$LINK"
~/.vault/bin/vault store --replace ATLAS_CLAUDE_PASSKEY < "$C"; rm -f "$C"
```

Never print `$OUT` or the link: the code in the fragment is a one-time credential. Revoke
with `ssh fedora 'podman exec systemd-nephos-atlas-app /atlas passkey ls'`, then
`... passkey revoke <id>`.

## Adding another app

Write `apps/<app>.sh` defining `app_up SRC` (start it under `$INST`, write
`$INST/env` with `ORIGIN=`, and write the enrol URL to `$INST/enroll.url`), `app_down`, and for
production `app_prod_origin` and `app_prod_secret` (a vault name). `browser.mjs` is shared
and expects a passkey sign-in button and a passkey enrol page. An app that signs in
differently needs its own branch there.
