# Govee Lamp Control Architecture

## Components

`govee_api.py` owns HTTP transport, Govee response validation, immutable device
models, and command payload construction. `govee_lan.py` owns validated UDP
discovery, status, and control. `govee_hybrid.py` merges both sources by
normalized device ID. `control.py` owns argument parsing, vault access, target
selection, transport routing, output, and exit codes. `SKILL.md` maps
natural-language requests to the CLI.

The implementation uses Python's standard library so the shared skill needs no
package install. The dotfiles manifest exposes `control.py` as
`~/.local/bin/govee`; the existing skills tree distributes the source.

## Data flow

1. Discover LAN-enabled devices over Govee UDP ports 4001-4003.
2. Read an explicit `GOVEE_API_KEY` override or retrieve `GOVEE_API_KEY` from
   the local encrypted vault, then discover cloud-supported devices.
3. Merge the sources by canonical device ID while retaining cloud names and
   capabilities. Add deterministic metadata for LAN-only devices.
4. Resolve an exact device ID, an unambiguous case-insensitive name, or an
   explicit `--all` set of light devices.
5. Validate the value against the advertised or LAN-supported capability.
6. Prefer LAN for local devices and use cloud for cloud-only devices.
7. Validate UDP messages and HTTP envelopes. Cloud writes validate device
   refusal state; LAN writes report that the datagram was sent because the UDP
   protocol provides no acknowledgement.

All transformation functions return new values. Frozen dataclasses and tuples
keep parsed device state immutable.
