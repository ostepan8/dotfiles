# Govee Lamp Control PRD

## Problem

Codex and Claude can control the household's Roku and Yeelight devices, but
cannot discover or control Govee lamps. The user wants natural-language lamp
control without exposing an API key, including models omitted from Govee's
cloud API.

## Outcome

Add a shared `govee` agent skill and CLI that can:

- securely save a Govee API key as `GOVEE_API_KEY` in the local encrypted vault;
- discover LAN-enabled models that the cloud API omits;
- list supported devices and their capabilities;
- read lamp status;
- turn one lamp or all Govee lights on and off;
- set brightness, RGB color, and color temperature when advertised by a lamp;
- fail clearly on ambiguous names, unsupported operations, invalid input, and
  API errors.

## Acceptance criteria

- Device names come from Govee Home and resolve case-insensitively only when
  unambiguous; LAN-only H8022 devices use the deterministic `Bedside Lamp`
  alias.
- Cloud and LAN records for one physical lamp merge by normalized device ID.
- LAN control is preferred when available, with cloud retained for remote or
  cloud-only devices.
- Multi-device writes require `--all`; no command silently selects among
  multiple devices.
- Control payloads use capabilities returned by device discovery.
- The API key never enters the repository, command arguments, logs, or errors.
- Unit, integration, and CLI-flow tests pass with at least 80% line coverage.
- The shared dotfiles apply flow installs the skill and CLI on configured
  machines.

## Out of scope

Music synchronization, segmented light-strip control, account room management,
and background automation are deferred until requested.
