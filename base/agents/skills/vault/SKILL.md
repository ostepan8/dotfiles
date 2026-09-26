---
name: vault
description: Owen's secrets and root access. ALWAYS check here before asking Owen for a password, API key, token, or sudo — they have already stored them. Use whenever a task needs sudo/root on any fleet machine (fedora, gpu1, gpu2, pi, the Studio), a reboot, an API key (ElevenLabs, OpenRouter, Resend, Kalshi, GitHub PAT, freesound, Anthropic…), a login, or a project .env; and whenever Owen hands over a new secret. Trigger on sudo, root, reboot, password, api key, token, credentials, .env, "it's in the vault", "load the keys", "store this key".
---

# vault

An age-encrypted secret store on the Mac Studio (`~/.vault`). Clients reach it over ssh
(host alias `vault`). **The answer to "I need a password/key" is almost always "it is
already in the vault".** Owen has had to say "it's in the vault bro" 19 times. Look
before asking.

## Find a secret

```bash
~/.vault/bin/vault list                 # NAMES only, never values
~/.vault/bin/vault projects             # project -> key names
```

Names look like `NAME@label`, e.g. `FEDORA_SUDO_PASSWORD@fedora-sudo`. Use `grep -i` on
the list for the service you need.

## Use a secret without printing it

Never echo a value, and never put it in argv, a file you commit, or the chat.

```bash
KEY=$(~/.vault/bin/vault get ELEVENLABS_API_KEY) some-command    # into one process's env
cd project && vault-env                   # write the project's .env (chmod 600, gitignored)
vault-env myproj -o .env.local
```

On a client machine (MacBook), `vault-env` fetches from the Studio over
ssh. `vault get` only works on the Studio itself.

## Root on a machine

The password is piped from the vault into `sudo -S`, so it never shows up anywhere:

| Machine | Command |
|---|---|
| Mac Studio | `~/.vault/bin/msudo '<cmd>'` |
| fedora | `~/.vault/bin/fsudo '<cmd>'` |
| gpu1 | `~/.vault/bin/g1sudo '<cmd>'` |
| gpu2 | `~/.vault/bin/g2sudo '<cmd>'` |
| pi | `~/.vault/bin/psudo '<cmd>'` |

A reboot is `fsudo 'systemctl reboot'` and so on. Owen has said to do these yourself: they
are their machines and they built the guardrails.

## Store a new secret

When Owen has a new key, run this and let them type it into the popup:

```bash
~/.vault/bin/vault-add NAME [-p project]    # native hidden popup; works on Studio or MacBook
```

If they paste a secret into chat instead, store it the same way, then tell them to rotate
it, because the transcript now holds it in plain text. If a key sits in a file (e.g.
`~/Desktop/openrouterkey.txt`), use `vault import-file NAME path -p proj` on the Studio,
then delete the file.

## Logging into Owen's web apps

Passkey-only apps (atlas) are not a password lookup. Use the `app-login` skill. It keeps
Claude's production passkey here as `ATLAS_CLAUDE_PASSKEY` and handles it, sign count
included. Never read or print that value yourself.

## When it really isn't there

Say which name you looked for, then run `vault-add NAME` so they can fill it in. Don't ask
them to paste it.
