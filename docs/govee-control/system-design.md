# Govee Lamp Control System Design

## Interfaces

The CLI supports `setup`, `devices`, `status`, `on`, `off`, `brightness`,
`color`, and `temperature`. Device commands accept repeatable `--device`; power
and status commands also accept `--all`. With no selector, exactly one
compatible light may be selected automatically.

Exit code `0` means success, `1` means the API or a device refused the request,
and `2` means configuration, input, selection, or capability validation failed.
Multi-device commands continue in a stable order and return `1` if any target
fails.

## Security

`setup` prompts without echo and sends the key to the local encrypted vault over
standard input. An environment variable may override the vault for temporary
use. The CLI validates the fixed vault executable before running it, never
accepts an API key argument, and never includes request headers in output.

## Reliability

Requests time out after ten seconds. HTTP 401/403, 429, and 5xx responses have
specific guidance. The tool does not retry writes. It respects Govee's current
limits by performing sequential writes and avoiding duplicate targets.

The discovery endpoint is limited to 30 requests per minute per account;
control is limited to 12 requests per second per account and 2 per second per
device. Normal interactive use stays well below those limits.
