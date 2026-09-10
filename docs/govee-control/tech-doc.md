# Govee Lamp Control Technical Notes

## API

Base URL: `https://openapi.api.govee.com/router/api/v1`

- `GET /user/devices` returns device IDs, SKUs, names, types, and capabilities.
- `POST /device/state` returns current capability state.
- `POST /device/control` applies one capability value.

Every request uses the `Govee-API-Key` header. POST bodies contain a UUID
`requestId` and a `payload`. Control payloads include `sku`, `device`, and a
capability object with `type`, `instance`, and `value`.

Lamp capability instances used by the first release are `powerSwitch`,
`brightness`, `colorRgb`, and `colorTemperatureK`. RGB is packed as
`(red << 16) | (green << 8) | blue`.

## Compatibility rules

Unknown capabilities are preserved during parsing. A control operation is sent
only when its instance is advertised by that device. Ranges come from the
discovered capability schema rather than global assumptions. A response with
top-level code 200 can still contain a nested capability state with
`status: failure`; this is treated as an error and its `errorMsg` is surfaced.

As of May 15, 2026, generating a new Govee API key invalidates older active
keys for the same account.
