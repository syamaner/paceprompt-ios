---
name: ftms-safe-development
description: Implement, review or plan Bluetooth FTMS behaviour for PacePrompt while preserving non-motion boundaries, explicit capability states and physical-device evidence requirements. Use whenever work touches CoreBluetooth, FTMS payloads or treadmill state.
---

# FTMS Safe Development

## Verify protocol authority

Before implementing UUID mappings, bit fields, scaling or binary layouts, verify them against the current Bluetooth SIG Fitness Machine Service/Profile specifications. Record the specification revision used. The FR30z observations in `design/prompt.md` show characteristic presence and properties only; they do not prove decoded capabilities or command behaviour.

## Preserve the motion boundary

Apply `AGENTS.md` first. A discovery/capability slice may, when explicitly authorised:

- scan only after a user action and prioritise FTMS service `0x1826`;
- let the user select and connect to a peripheral;
- discover services and characteristics;
- read `0x2ACC`, `0x2AD4` and `0x2AD5`;
- subscribe to passive notifications from `0x2ACD`, `0x2AD3` and `0x2ADA` when available.

It must not write `0x2AD9` or send Request Control, Start, Stop, Pause, target-speed or target-inclination commands. A later motion-control slice requires fresh, explicit authorisation and its own safety/acceptance contract.

Do not add automatic reconnection. The console and safety key remain authoritative.

## Keep evidence and code layers explicit

- Let a CoreBluetooth client own scan, connection, discovery, reads and subscriptions.
- Decode bytes in pure parser types with no UI or Bluetooth dependency.
- Adapt client events into observable presentation state.
- Keep SwiftUI views declarative; do not parse bytes or call CoreBluetooth directly.
- Preserve raw hexadecimal data beside decoded values for diagnostics.
- Model Bluetooth unavailable, permission-limited, scanning, connecting, connected, disconnected, failed, malformed and unknown states explicitly.
- Treat characteristic presence, feature bits, protocol acknowledgement and observed machine state as distinct evidence.

Use synthetic byte fixtures for signed and unsigned little-endian decoding, scaling, short payloads, malformed data, unsupported fields and unavailable presentation. Simulator tests can validate parsers and state presentation, but only real-device captures can validate FR30z behaviour.
