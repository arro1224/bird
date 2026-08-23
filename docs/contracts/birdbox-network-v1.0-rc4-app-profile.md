# BirdBox Network v1.0-rc4 App Profile

Status: frozen App-side interface baseline for preparation batch 0 (S0).

This profile is independent from the immutable `birdbox-v1@1.0.0` business API freeze. It defines discovery, authorization and network provisioning only. Existing photo, job and `/api/v1/events` semantics remain unchanged.

## Discovery and identity

- The primary discovery key is BirdBox Network Service UUID `6f7d0001-7a66-4c45-a1b9-5f4d2e3c1000`.
- A compact advertisement containing Local Name and Service UUID is sufficient.
- Manufacturer Data is an optional development extension. Missing, malformed or unknown extensions never reject a candidate.
- Local Name, short ID, Bluetooth MAC and Manufacturer Data are not trusted identity.
- The complete GATT `Device Info.device_id` is authoritative identity. GATT `Network Status` is authoritative state.
- Subscribe to required notifications before issuing an asynchronous command.

## Frozen transport

- Protocol version: `1.0-rc4`.
- Six UUIDs: one primary service and five characteristics, all compared as lowercase strings.
- Fragment header: 12 bytes, little-endian integer fields, magic `42 42`, version `1`.
- Reassembled UTF-8 JSON limit: 4096 bytes; fragment count limit: 256; reassembly timeout: 5 seconds.
- Identical duplicate fragments are idempotent. Missing, conflicting, out-of-range or oversized fragments produce `BLE_FRAGMENT_INVALID`.
- A retry reuses its UUID v4 `request_id`; a new user action creates a new ID.
- Long-running events are correlated by box-generated `operation_id`; stale operations cannot overwrite the active operation.

## Commands

The Repository exposes exactly these nine protocol commands:

1. `open_pairing`
2. `authorize_pairing`
3. `get_network_status`
4. `start_direct_ap`
5. `stop_direct_ap`
6. `scan_wifi`
7. `set_sta_config`
8. `start_dpp_provisioning`
9. `cancel_network_operation`

`set_sta_config` is shared by scan selection, manual/hidden Wi-Fi and standard Wi-Fi QR input. Android DPP never calls it.

## Completion semantics

- `pairing_opened` only opens the code entry step.
- `pairing_authorized` only establishes a temporary in-memory pairing session.
- `command_accepted` only establishes an operation ID; it is never final success.
- Android Wi-Fi/DPP success is never final success.
- Direct AP or STA completion requires a matching terminal BLE event, correct Android network routing and successful `/health.device_id` comparison.
- A BLE disconnect never cancels a command already accepted by the box. Reconnect and call `get_network_status`.

## Secrets

- Pairing codes are never persisted or sent over HTTP.
- Pairing session IDs and full DPP URIs exist only in transient memory.
- Tokens and installation `client_id` use secure storage.
- Logs, errors, analytics, screenshots and fixtures must not contain pairing codes, pairing sessions, Wi-Fi/AP passwords, complete DPP URIs or real tokens.

## App ownership boundary

Presentation code consumes `ProvisioningRepository` and the domain models. It must not call BLE, Wi-Fi, DPP MethodChannels or data sources directly. Repository implementation owns identifiers, retries, authorization selection, event correlation and secret lifetime.

Schemas and valid fixtures:

- `schemas/ble-device-info.schema.json`
- `schemas/ble-network-status.schema.json`
- `schemas/ble-command-envelope.schema.json`
- `schemas/health.schema.json`
- `schemas/pairing-token.schema.json`
