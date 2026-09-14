---
name: tailnet
description: >-
  Switch between Owen's Tailscale tailnets and reach machines that live on them.
  Use when an ssh to a Tailscale host hangs, times out, or is refused; when a host
  "resolves but will not connect"; when a task needs a remote GPU box, work machine,
  or fleet node; or when asked to switch, check, or list tailnets. Being on the wrong
  tailnet fails SILENTLY — the host still resolves and still answers ping — so check
  `tn` BEFORE debugging ssh keys, sshd, or the remote machine. Trigger on tailnet,
  tailscale, MagicDNS, ssh hangs, connection timed out, cannot resolve hostname,
  permission denied publickey, switch tailnet, remote GPU box. Read ~/.zshrc.local and
  ~/.ssh/config for host aliases; never hardcode tailnet or host names.
---

# tailnet — switching tailnets and reaching hosts on them

Owen's account belongs to more than one tailnet. Tailscale calls each membership a
**profile**, and exactly one is active at a time, machine-wide. A machine on a
tailnet you are not currently in is simply unreachable.

## Check this FIRST, before debugging anything else

**Being on the wrong profile does not look like a network problem.** Every obvious
signal says the host is fine:

| What you try | What happens on the wrong profile | What you would wrongly conclude |
|---|---|---|
| `dig` / `dscacheutil` | **Resolves.** Tailscale serves a public wildcard for `*.ts.net` | DNS is fine |
| `ping` | **Replies.** You are pinging Tailscale's public endpoint | The box is up |
| `ssh` | Hangs, then `Operation timed out` | The box is down, or sshd is wedged |

So the loop to avoid is: host pings, ssh times out, and you go and debug sshd, keys,
firewalls, or the remote machine — none of which are the problem.

```bash
zsh -ic 'tn'          # → tailnet: <name>  (<magicdns-suffix>)
```

If that is not the tailnet the target host lives on, nothing else matters yet.

A second, different symptom of the same root cause: `Permission denied
(publickey,password)` when you used a host's **FQDN** instead of its short alias.
`~/.ssh/config` blocks are keyed on exact host strings, so the FQDN can miss the
block that sets `User` and `IdentityFile`, and ssh silently falls back to the local
username. Check the `Host` line before assuming a key problem.

## Non-interactive shells do not have these commands

**This is the main thing to get right when running as an agent.** `tn`, `tn_ensure`,
`tn_await`, and the per-host wrappers are **zsh functions** defined in
`~/.zshrc` — they are not on `PATH` and not in any `bash -c` or plain tool shell:

```bash
tn                    # "command not found" — WRONG
zsh -ic 'tn -'        # correct
zsh -ic 'spark_like_wrapper "nvidia-smi"'
```

`zsh -ic` prints `can't change option: zle` to stderr when there is no tty. That is
harmless noise, not a failure — do not chase it.

If you would rather not go through zsh, drive Tailscale directly (see *Doing it
without the helpers* below).

## Commands

```bash
zsh -ic 'tn'              # show the active tailnet + MagicDNS suffix
zsh -ic 'tn ls'           # list profiles, * marks the active one
zsh -ic 'tn -'            # toggle to the other profile (there are two)
zsh -ic 'tn <substring>'  # switch to the profile whose tailnet matches
zsh -ic 'tn <n>'          # switch to profile #n from `tn ls`
zsh -ic 'tn --help'
```

`tn <substring>` is a case-insensitive regex matched against `"<tailnet> <nickname>"`.
Ambiguous or unmatched input prints the profile list and exits non-zero rather than
guessing — surface that to the user instead of picking one.

Friendly names (`tn personal`, `tn work`, …) come from `$TAILNET_ALIASES`. Run
`zsh -ic 'tn ls'` to see what actually exists on this machine rather than assuming.

## Finding host aliases — do not hardcode them

Host names, tailnet names, and per-host wrapper functions are deliberately **not in
this file**: it ships in a PUBLIC dotfiles repo, and `scripts/check-secrets.sh`
treats tailnet identifiers as leaks. To discover what this machine can reach:

```bash
cat ~/.zshrc.local              # $TAILNET_ALIASES + per-host wrapper functions
cat ~/.ssh/config               # Host blocks: aliases, User, IdentityFile
cat ~/.ssh/config.d/fleet       # generated from hosts/fleet.conf, if present
zsh -ic 'tn ls'                 # the profiles that exist here
tailscale status                # machines on the ACTIVE tailnet only
```

If `~/.zshrc.local` is absent, this machine has no work-host setup — say so rather
than inventing a hostname. Note `tailscale status` shows only the *active* tailnet;
a machine missing from it may simply be on the other profile.

Prefer an existing wrapper (they switch the tailnet and wait for DNS for you) over
hand-rolling `tailscale switch` + `ssh`.

## Scripting against it

```bash
tn_ensure <pattern> [host]   # switch only if needed; with [host], also wait for it
tn_await  <host>             # block until <host> resolves to a tailnet address
```

Both return non-zero on failure, so `||` works. A per-host wrapper is one line:

```zsh
myhost() { tn_ensure 'some-tailnet-substring' myhost.example.ts.net || return 1; ssh myhost "$@"; }
```

Put wrappers in `~/.zshrc.local`, never in the tracked dotfiles.

### Why you must wait, and why `tn_await` checks the address

After a switch, **`BackendState: Running` is not enough.** macOS reconfigures its
resolver a beat later, and an `ssh` fired in that window dies with `could not resolve
hostname` — which reads like a typo. Measured, roughly one run in three raced.

`tn_await` therefore waits for the name to resolve to a **CGNAT `100.64.0.0/10`**
address, not merely to resolve at all. That single check rejects both failure modes:
the empty answer mid-switch, and the stale public-wildcard answer left over from the
previous profile. If you script your own switch, reproduce this wait.

## Doing it without the helpers

```bash
tailscale switch --list --json     # [{id, nickname, tailnet, account, selected}]
tailscale switch <id>              # <id> is the 4-char handle
tailscale status --json | jq -r '.BackendState, .MagicDNSSuffix, .Self.DNSName'
```

Switch **by id**, never by name: both of Owen's profiles share one nickname and
account string, so a name is ambiguous. Ids are also not stable across a
logout/login — always read them from `--list --json` at call time.

## Gotchas

- **Switching is global and exclusive.** Moving to one tailnet drops MagicDNS for
  every host on the other. Tell the user when a task forces a switch, and switch back
  (`tn -`) if it was incidental. Long-running work over the old tailnet will break.
- **Two tailscaled daemons run on these Macs**: the GUI app's (default socket, owns
  system DNS) and a Homebrew userspace one on `/tmp/tailscaled.sock` that a couple of
  ssh `ProxyCommand`s use. `tn` drives the GUI one only; connections over the other
  survive a switch. Target it explicitly with `tailscale --socket=/tmp/tailscaled.sock`.
- **Do not create a `tns` alias** — it is already `tmux new-session -s`.
- `tailscale switch` needs no sudo. If a command wants sudo here, you are on the
  wrong path.
- The client/daemon version-mismatch warning on stderr is expected and harmless.

## Editing the tracked side

`~/dotfiles/base/zsh/tailnet.zsh` is public. Keep every tailnet name, host name, and
tailnet id out of it — profiles are matched against live `tailscale switch --list`
output precisely so nothing identifying is committed. Anything machine- or
work-specific belongs in `~/.zshrc.local`, which `~/.zshrc` sources last and which is
not in the repo. Run `~/dotfiles/scripts/check-secrets.sh` before committing; see the
**dotfiles-sync** skill for the mirror-and-commit flow.
