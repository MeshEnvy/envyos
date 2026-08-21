---
name: ota-greenfield
description: >-
  EnvyOS OTA wire/format backward compatibility — field fleet since v0.1.0 (OG devices).
  Use when changing LoRa OTA protocol, OTA_HAVE layout, motatool on-air behavior,
  or when tempted to break wire format without a versioned rollout plan.
---

# OTA backward compatibility

EnvyOS OTA has **not been greenfield since v0.1.0**. OG devices are deployed in the field.

**LoRa wire format and on-air catalog layouts require backward compatibility** unless the operator explicitly plans a coordinated fleet bump (typically v0.3.0+ for wire extensions).

Track deferred wire changes in `docs/planned/v0.3.0.md` § OTA protocol and CLI.

## Do

- Prefer behavior changes that need **no wire format change** (listener-side filtering, CLI, motatool host)
- Version or negotiate protocol extensions before changing row sizes or message bodies
- Document mixed-fleet rules (old nodes ignore new fields; new nodes tolerate old peers)
- Update `MEMORY.md`, `envycore/docs/ota_protocol.md`, and v0.3.0 planning in the same change set

## Don't

- Extend `OTA_HAVE` HaveRow or other fixed layouts without a rollout plan
- Assume the bench is the only fleet
- Drop dual-read paths mid-fleet without a migration milestone

## Still flexible (with care)

| Area | Notes |
|------|--------|
| `.mota` file format on disk/USB | Host tools can rebuild; device apply rules unchanged |
| motatool CLI / folder layout | No on-air impact |
| Staging flash layout | Coordinate with bootloader / EnvyBoot |

## Related skills

- `envyos-ota` — protocol, device CLI, bench roles
- `motatool` — `.mota` build, serve, verify
