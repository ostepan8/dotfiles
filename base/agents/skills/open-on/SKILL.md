---
name: open-on
description: Put something in front of Owen — open a file, URL, video, folder, or app on a specific machine (the Studio or the MacBook) and in a specific aerospace workspace, or hand it to their phone. Use for "open it", "open them on the studio", "open it in workspace 3", "play em", "show me", "put it on my phone", "open it on the macbook".
---

# open-on

## Which machine

Owen means the machine they are **sitting at**, which is often not the one this session
runs on. "On the studio" is `Owens-Mac-Studio.local`, "on the macbook" is the ssh host
`macbook`. If they don't say and this session is remote (ssh or a fleet node), open it on
the Studio.

```bash
open <path-or-url>                                  # this Mac
ssh macbook "open '<path-or-url>'"                  # the MacBook (path must exist THERE — scp it first)
```

Files made on a Linux node (gpu1, gpu2, fedora) have to be copied to the Mac first:
`scp gpu2:<path> ~/Downloads/`, then `open`.

## URLs: open them in the right Dia profile

Dia is the browser. It keeps accounts as profiles, so pick the profile from what the
link is for, then open it with the skhd helper:

```bash
~/.config/skhd/dia-profile.sh <profile> '<url>'     # this Mac
ssh macbook "~/.config/skhd/dia-profile.sh <profile> '<url>'"
```

| The link is for | Profile |
|---|---|
| Subconscious work: `*.subconscious.dev`, Linear, the company GitHub org, Vercel/Axiom/Datadog for work, work Google Docs | `subconscious.dev` |
| School (`.edu`, Canvas, course pages) | `School` |
| Anything else | `Personal` |

If the helper fails with `no profile named`, its error lists the real names. Use the
closest one. Do not use a plain `open <url>` for these: Finicky sends it to Chrome.

## Which workspace (aerospace)

When they name a workspace, open the thing and then move its window there:

```bash
open -a "<App>" <path>
for i in $(seq 20); do
  id=$(aerospace list-windows --all --format '%{window-id} %{app-name}' | awk -v a="<App>" '$0 ~ a {print $1; exit}')
  [ -n "$id" ] && break; sleep 0.5
done
aerospace move-node-to-workspace 3 --window-id "$id" && aerospace workspace 3
```

## Several media files ("play em", "open them")

Open all of them in one go (`open a.mp4 b.mp4 …`) and list them with a one-line label
each, so they know which is which.

## To their phone

Don't use AirDrop or a hosted page. Write a local HTML page with a QR code for the URL or
file (served over the tailnet) and `open` it on the machine they're at. They scan it. See the
QR handoff memory.

## Confirm

Check it actually opened (`aerospace list-windows --workspace N`, or the app's window
appearing) before saying it did.
