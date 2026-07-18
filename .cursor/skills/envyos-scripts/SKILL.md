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

- Canonical semver: **`VERSION`** at ota repo root (e.g. `0.1.0`)
- Helpers: **`scripts/version.sh`** — `read_version_file`, `normalize_version`, `previous_patch_version`
- **Not** upstream MeshCore `v1.17.x` tags
- `build-mota.sh` reads `VERSION` by default; passes `-DFIRMWARE_VERSION` via `PLATFORMIO_BUILD_FLAGS`

```bash
./scripts/build-mota.sh --list-targets
./scripts/build-mota.sh                    # version from ./VERSION
./scripts/build-mota.sh v0.1.1             # override for one-off build
./scripts/build-mota.sh --target wismesh-tag-repeater
./scripts/build-mota.sh v0.1.2 --base v0.1.0
./scripts/build-mota.sh --hex-only           # stock MeshCore — hex/uf2 only, no .mota
```

## `scripts/targets.txt`

Target map for **`build-mota.sh`**. One line per shipped board/role:

```text
slug  platformio_env  [description…]
```

| Slug | PlatformIO env |
|------|----------------|
| `wismesh-tag-repeater` | `RAK_WisMesh_Tag_repeater` |
| `rak4631-repeater` | `RAK_4631_repeater` |
| `rak4631-client-ble` | `RAK_4631_companion_radio_ble` |
| `wismesh-tag-client-ble` | `RAK_WisMesh_Tag_companion_radio_ble` |

Output: `motas/<ver>/<slug>/`. Default build = **all lines**. Override with `--target <slug>` (repeatable) or `--targets-file`.

## `scripts/build-mota.sh`

Builds OTA firmware from `envyos/` and packages `.mota` into `motas/<version>/<slug>/`.

**Steps (per target):**

1. `pio run -e <env>` (+ `create_uf2`)
2. Copy `firmware.hex`, `.uf2`, `.zip` → `motas/<ver>/<slug>/`
3. `motatool build --fw … --out-dir` → full `.mota`
4. If base version exists: `motatool build --base <prev.hex> --fw … --patch-type in-place` → `delta_from_<base>.mota`

**Output layout (`motas/<ver>/<slug>/`):**

| File | Purpose |
|------|---------|
| `firmware.hex` | **Keep as delta base** for next patch (same slug) |
| `firmware.uf2` | USB drag-flash (initial flash or recovery) |
| `fw_*_full_*.mota` | Full OTA image |
| `delta_from_v0.1.0.mota` | In-place patch from prior version |
| `version.txt` | Normalized tag |

Legacy flat layout (`motas/<ver>/firmware.hex`) still works as a delta base for `wismesh-tag-repeater`.

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
# flash Tag B from motas/v0.1.0/wismesh-tag-repeater/firmware.uf2
# flash Tag C from motas/v0.1.0/wismesh-tag-client-ble/firmware.uf2

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
