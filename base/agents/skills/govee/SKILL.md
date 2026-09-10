---
name: govee
description: Control Govee lamps through the official cloud API. Use when the user asks to turn Govee lights on or off, check their status, change brightness, color, or color temperature, list Govee devices, or configure Govee API access.
---

# Govee Lamp Control

Use the `govee` CLI for every Govee operation. It discovers capabilities from
Govee before issuing a command and stores the API key in macOS Keychain.

## First-time setup

If a command reports that no API key exists, tell the user to run this once in
their own terminal:

```bash
govee setup
```

The command prompts without echo, verifies the key with a read-only device
request, and saves it under the Keychain service `codex-govee`. Do not ask the
user to paste an API key into chat or pass one as a command argument. The key is
available in Govee Home under Settings > Apply for API Key.

On non-macOS machines, provide `GOVEE_API_KEY` through the machine's secret
manager. The interactive Keychain setup command is macOS-only.

Generating a new Govee API key invalidates every older active key for the
account. Run setup again after rotating it.

## Commands

```bash
govee devices
govee status --device "Desk Lamp"
govee status --all
govee on --device "Desk Lamp"
govee off --device "Desk Lamp"
govee off --all
govee brightness 50 --device "Desk Lamp"
govee color '#ff0080' --device "Desk Lamp"
govee color '255,0,128' --device "Desk Lamp"
govee temperature 2700 --device "Desk Lamp"
```

`--device` may be repeated. With exactly one compatible lamp, the selector may
be omitted. With multiple lamps, name them or use explicit `--all`. Never infer
`--all` from a singular request.

Names match case-insensitively but do not fuzzy-match. If a name is missing or
ambiguous, run `govee devices` and ask the user which Govee Home name they mean.

## Natural-language defaults

- "warm white" -> 2700 K
- "cool white" -> 5000 K
- "dim" without a percentage -> 30% brightness
- named colors -> standard RGB values

After a successful write, report the lamp name and resulting requested value.
For vague relative changes such as "a little brighter," read status first and
choose a modest 10-point change within the lamp's advertised range.

## Errors

Exit code 2 is a setup, selector, input, or unsupported-capability error. Exit
code 1 means Govee or the lamp refused the request. Surface the CLI message. If
the key was rejected, direct the user to rerun `govee setup`. Do not blindly
retry writes or exceed Govee's reported rate limits.

Official API documentation: <https://developer.govee.com/>
