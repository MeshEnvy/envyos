---
name: ota-greenfield
description: >-
  EnvyOS OTA is pre-deployment greenfield — no legacy fleet or migration paths.
  Use when changing .mota format, LoRa OTA protocol, motatool, OTAFIX apply, EndF
  identity, or OTA firmware; or when tempted to add backward-compat shims.
---

# OTA greenfield policy

The EnvyOS OTA stack is **pre-deployment greenfield**. Nothing is deployed in production yet; the 3-tag WisMesh bench is the only real environment.

**Do not design for legacy devices, field migrations, or rolling upgrades.**

## Do

- Prefer clean breaks over compatibility shims
- Remove or rename APIs, wire formats, and on-disk layouts when it simplifies the design
- Invalidate old `.mota` bases and rebuild from source after breaking changes
- Update `MEMORY.md`, `envycore/docs/ota_*.md`, and related skills in the same change set

## Don't

- Add migration paths for "devices already in the field"
- Keep deprecated code paths unless the user explicitly asks
- Dual-read old/new protocol or format versions, or add upgrade transformers
- Preserve stale artifact compatibility across breaking format changes

## Scope

| In scope | Out of scope |
|----------|--------------|
| `.mota` container format | Upstream MeshCore merges (handle normally) |
| LoRa OTA wire protocol | Stock `--hex-only` builds (no OTA) |
| `motatool`, `vendor/detools` usage for OTA | Non-OTA firmware features |
| Device OTA engine (`envycore/src/helpers/ota/`) | |
| OTAFIX bootloader apply path | |
| OTA build scripts, EndF / delta identity | |

## Related skills

- Protocol and bench flow → `envyos-ota`
- `.mota` pack/serve → `motatool`
- Build scripts → `envyos-scripts`
