---
name: envyos-ota
description: >-
  MeshCore LoRa OTA on envyos/main: .mota containers, device CLI, discovery/fetch/install,
  codecs (full/sequential/in-place), EndF identity, OTAFIX bootloader apply, seeder link.
  Use when debugging OTA on devices, writing OTA firmware, or explaining the bench flow.
---

# EnvyOS OTA

Authoritative specs live in the **`envyos/` submodule** (`envyos/main`):

- Operator guide: `envyos/docs/ota_user_guide.md`
- Wire format: `envyos/docs/ota_protocol.md`
- Firmware OTA engine: `envyos/src/helpers/ota/`

## Mental model

1. Host builds a **`.mota`** container (merkle-blocked firmware image or delta).
2. A **seeder** advertises available `.mota` files over LoRa (from on-device flash or via `motatool serve` + `ota folder on`).
3. Target nodes **discover** → **fetch** blocks at lowest mesh priority → **install** only on explicit `ota install`.
4. Integrity is **content-addressed** (merkle proofs per block); transport relays need not be trusted.

Nothing auto-installs unless `ota config autoinstall trusted` and the image is signed by a trusted key.

## EndF identity (critical for deltas)

Every OTA-capable build has a **56-byte `EndF` trailer** on the flashed image (`tools/mota/pio_endf.py`).

| Field | Role |
|-------|------|
| `body_hash` (8 B) | Hash of image body — **delta `base_hash` must match this on the device** |
| `target_id` (4 B) | `sha256:4(platformio_env_name)` — routing / `[yours]` in `ota ls` |
| `fw_version` | From `-DFIRMWARE_VERSION` (EnvyOS: `v0.1.x`) |

motatool reads identity from the hex/bin **EndF**; do not rely on filenames.

## Codecs (`codec_id`)

| ID | Name | Platform | Apply path |
|----|------|----------|------------|
| 0 | full | Any | Whole image staged then installed |
| 1 | sequential | ESP32 A/B | detools decoder → inactive OTA slot |
| 2 | **in-place** | **nRF52** (WisMesh Tag) | Staged in flash → reboot → **OTAFIX bootloader** applies patch |

EnvyOS WisMesh bench uses **`in-place`** deltas. Tag B needs **`vendor/otafix`** bootloader (`MOTABLDR` + codec bit 2).

**nRF52 staging:** companion builds stage below ExtraFS (`MOTA_STAGE_CEILING=0xD4000`); repeaters use `0xED000`.
motatool auto-derives each delta's `memory_size` from the target ceiling minus the staged `.mota` size.

## Device CLI (USB serial 115200)

```
ota status          # version, fetch progress, bootloader capability
ota ls              # discovered updates ([yours] = matching target_id)
ota get 1 flash     # download entry #1 to local flash (alias: pull)
ota install         # verify + apply + reboot
ota cancel          # abort fetch
ota folder on       # enable host seeder link (needs motatool serve on USB)
ota self            # print EndF / base_hash
ota help
```

Remote admin over mesh uses the same commands via companion/repeater admin (password-gated for `ota stats` on remote nodes).

## Seeder link (bench Tag A)

`motatool serve --dir ./motas --serial …` speaks **mota-seeder** over USB. Firmware with `OTA_FOLDER_SERIAL` accepts `ota folder on`; the node then **relays** every valid `.mota` in that folder to the mesh without storing them.

Flow: laptop → USB → Tag A (`ota folder on`) → LoRa ads/blocks → Tag B fetches/installs.

## nRF52 apply contract (OTAFIX)

Running app **never** patches itself. `ota install`:

1. Verifies merkle + `image_hash` + `base_hash == EndF.body_hash` + optional signature
2. Writes `approval = APRV` on staged container
3. Reboots into OTAFIX bootloader, which locates staged `.mota`, re-checks hashes, applies in-place detools patch, boots if result matches `image_hash`

**False positive trap:** X→X “delta” always succeeds — test with a **real version bump**.

## EnvyOS bench roles (WisMesh Tag)

| Tag | Build | Bootloader | Job |
|-----|-------|------------|-----|
| A | OTA + `OTA_FOLDER_SERIAL` | stock OK | `./scripts/run-mota.sh` USB seeder |
| B | `RAK_WisMesh_Tag_repeater` | **OTAFIX required** | DUT — `ota get` / `ota install` |
| C | companion (optional) | stock OK | remote `ota status` over mesh |

## What must match (delta path)

- Delta manifest `base_hash` == Tag B running firmware `EndF.body_hash`
- `[yours]` row: `target_id` for `RAK_WisMesh_Tag_repeater`
- Base hex saved from **exact** prior build (`motas/v0.1.0/firmware.hex`) — rebuilds can change `body_hash` even if source “looks” the same
- OTAFIX present: `ota status` shows bootloader apply OK for in-place codec

## Key source files

| Concern | Path under `envyos/` |
|---------|----------------------|
| Constants | `src/helpers/ota/OtaFormat.h` |
| Session engine | `src/helpers/ota/OtaManager.*` |
| CLI | `src/helpers/ota/OtaCli.cpp` |
| Apply (ESP32) | `src/helpers/ota/OtaApply.*` |
| detools decoder (device) | `src/helpers/ota/detools/` |
| Post-build EndF | `tools/mota/pio_endf.py` |

## Related skills

- **Greenfield policy** (no legacy/migrations) → `ota-greenfield`
- `./scripts/*` workflow → `envyos-scripts`
- `.mota` build/serve/verify → `motatool`
- Git/PR workflow → `envyos-meshcore`
