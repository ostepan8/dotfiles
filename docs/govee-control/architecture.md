# Govee Lamp Control Architecture

## Components

`govee_api.py` owns HTTP transport, Govee response validation, immutable device
models, and command payload construction. `control.py` owns argument parsing,
Keychain access, target selection, output, and exit codes. `SKILL.md` maps
natural-language requests to the CLI.

The implementation uses Python's standard library so the shared skill needs no
package install. The dotfiles manifest exposes `control.py` as
`~/.local/bin/govee`; the existing skills tree distributes the source.

## Data flow

1. Read `GOVEE_API_KEY`, falling back to the macOS Keychain service
   `codex-govee`.
2. Discover devices through `GET /router/api/v1/user/devices`.
3. Resolve an exact device ID, an unambiguous case-insensitive name, or an
   explicit `--all` set of light devices.
4. Find the requested capability in the discovered device schema.
5. Validate the value against that capability's advertised range or options.
6. Send a UUID-tagged request to `/device/control` or `/device/state`.
7. Validate HTTP status, the top-level Govee envelope, and nested capability
   refusal state before reporting success.

All transformation functions return new values. Frozen dataclasses and tuples
keep parsed device state immutable.
