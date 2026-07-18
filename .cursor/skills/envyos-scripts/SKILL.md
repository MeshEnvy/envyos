---
name: envyos-scripts
description: >-
  Ota repo bench scripts: build-mota.sh, build-bl.sh, run-mota.sh, motas/ layout,
  EnvyOS versioning via envyos/envyos/version.sh. Use when building firmware,
  packaging .mota, flashing OTAFIX, or running the 3-tag bench.
---

# EnvyOS bench scripts

All scripts live in **`scripts/`**; they resolve repo root as `$(dirname "$0")/..`.

## Prerequisites

| Tool | Used by |
|------|---------|
| PlatformIO (`pio`) | `build-mota.sh` |
| Docker | `build-bl.sh` |
| `motatool` on PATH or `vendor/motatool/target/release/motatool` | `build-mota.sh`, `run-mota.sh` |
| `envyos/` submodule on `envyos/main` | firmware source |
| `vendor/otafix/` submodule | bootloader build |

Initialize submodules: `git submodule update --init --recursive`

## Versioning

- Canonical semver file: **`envyos/envyos/VERSION`** (e.g. `0.1.0`)
- Helpers: **`envyos/envyos/version.sh`** — `normalize_version`, `previous_patch_version`
- **Not** upstream MeshCore `v1.17.x` tags
- `build-mota.sh` passes `-DFIRMWARE_VERSION='"v0.1.0"'` via `PLATFORMIO_BUILD_FLAGS`

```bash
./scripts/build-mota.sh v0.1.0    # → motas/v0.1.0/
./scripts/build-mota.sh v0.1.1    # auto-delta from v0.1.0 if motas/v0.1.0/firmware.hex exists
./scripts/build-mota.sh v0.1.2 --base v0.1.0   # explicit delta base
```

## `scripts/build-mota.sh`

Builds **`RAK_WisMesh_Tag_repeater`** from `envyos/` and packages `.mota` into `motas/<version>/`.

**Steps:**

1. `pio run -e RAK_WisMesh_Tag_repeater` (+ `create_uf2`)
2. Copy `firmware.hex`, `.uf2`, `.zip` → `motas/<ver>/`
3. `motatool build --fw … --out-dir` → full `.mota`
4. If base version exists: `motatool build --base <prev.hex> --fw … --patch-type in-place` → `delta_from_<base>.mota`

**Output layout (`motas/<ver>/`):**

| File | Purpose |
|------|---------|
| `firmware.hex` | **Keep as delta base** for next patch |
| `firmware.uf2` | USB drag-flash (initial flash or recovery) |
| `fw_*_full_*.mota` | Full OTA image |
| `delta_from_v0.1.0.mota` | In-place patch from prior version |
| `version.txt` | Normalized tag |

`motas/` is gitignored except `.gitignore` — artifacts stay local.

## `scripts/build-bl.sh`

Builds **OTAFIX** nRF52 bootloader via Docker (`vendor/otafix/`).

```bash
./scripts/build-bl.sh              # BOARD=wismesh_tag (default)
./scripts/build-bl.sh wismesh_tag
```

- Docker image: `vk-otafix-build` (cached after first build)
- UF2: `vendor/otafix/_build/build-<board>/update-*_nosd.uf2`
- Copied to **`motas/bootloader/`** for bench flash

**Only Tag B (DUT)** needs OTAFIX to apply in-place deltas. Flash: double-tap reset → drag UF2.

If coming from companion/Ripple firmware, **erase ExtraFS** before flashing bench repeater.

## `scripts/run-mota.sh`

Wraps **`motatool serve`** for Tag A seeder.

```bash
./scripts/run-mota.sh /dev/cu.usbmodem1444301
./scripts/run-mota.sh usbmodem1444301           # → /dev/cu.usbmodem1444301
./scripts/run-mota.sh /dev/cu.… ./motas/v0.1.1  # serve one version dir
```

Default dir: `./motas` (recursive `.mota` scan). Sends `ota folder on` on serial start; Ctrl-C sends off.

**Port conflict:** only one process per serial device — Tag A for serve, Tag B for `screen`/`pio device monitor`.

## Typical bench sequence

```bash
./scripts/build-bl.sh
# flash motas/bootloader/*.uf2 on Tag B

./scripts/build-mota.sh v0.1.0
# flash Tag B from motas/v0.1.0/firmware.uf2

./scripts/build-mota.sh v0.1.1
# produces delta_from_v0.1.0.mota

./scripts/run-mota.sh /dev/cu.… ./motas/v0.1.1   # Tag A USB

# Tag B serial:
ota ls → ota get N flash → ota install → ota status  # expect v0.1.1
```

## Troubleshooting

| Symptom | Check |
|---------|-------|
| Delta rejected at apply | `base_hash` vs `ota self` on device; hex base must be exact prior build |
| No entries in `ota ls` | Tag A has OTA build + `ota folder on`; serve dir contains valid `.mota`; mesh path |
| `bootloader: apply` missing | Tag B not on OTAFIX |
| motatool not found | `cargo build --release` in `vendor/motatool` or install to PATH |
| Wrong `[yours]` tag | `target_id` / env name mismatch |

## Related skills

- OTA protocol & CLI → `envyos-ota`
- motatool flags & delta encoding → `motatool`
- Firmware git workflow → `envyos-meshcore`
