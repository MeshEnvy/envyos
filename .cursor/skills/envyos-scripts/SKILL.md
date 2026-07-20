---
name: envyos-scripts
description: >-
  Ota repo bench scripts: build.sh, build-mota.sh, build-bl.sh, run-mota.sh, build/ layout,
  EnvyOS versioning via envycore/envyos/version.sh. Use when building firmware,
  packaging .mota, flashing OTAFIX, or running the 3-tag bench.
---

# EnvyOS bench scripts

All scripts live in **`scripts/`**; they resolve repo root as `$(dirname "$0")/..`.

## Prerequisites

| Tool | Used by |
|------|---------|
| PlatformIO (`pio`) | `build-mota.sh` |
| Docker | `build-bl.sh` |
| `motatool/target/release/motatool` (from `motatool/` submodule; auto-built) | `build-mota.sh`, `run-mota.sh` |
| `envycore/` submodule on `envyos/main` | firmware source |
| `bootloader/` submodule | bootloader build |

Initialize submodules: `git submodule update --init --recursive`

## Versioning

All component versions live in **`ENVYOS_VERSIONS`** at ota repo root:

| Key | Role |
|-----|------|
| `distro` | Git release tag `v<distro>` → `build/motas/<distro>/` |
| `firmware` | `-DFIRMWARE_VERSION` stamp (sync `envycore/envyos/VERSION`) |
| `bootloader` | `build/bootloader/<bootloader>/` |
| `motatool` | `motatool/Cargo.toml` + `build/motatool/<motatool>/` |

Helpers: **`scripts/version.sh`** — `read_distro_version`, `read_firmware_version`, `read_bootloader_version`, `read_motatool_version`, `list_envyos_versions`

```bash
source scripts/version.sh && list_envyos_versions
./scripts/build-mota.sh --list-targets
./scripts/build-mota.sh                    # distro from ENVYOS_VERSIONS
./scripts/build-mota.sh v0.1.1             # override for one-off build
./scripts/build-mota.sh --target wismesh-tag-repeater
./scripts/build-mota.sh v0.1.2 --base v0.1.0
./scripts/build-mota.sh --hex-only           # stock MeshCore — hex/uf2 only, no .mota
```

## `scripts/build.sh`

Consolidated entry point — runs **`build-bl.sh`** then **`build-mota.sh`** from **`ENVYOS_VERSIONS`**.

```bash
./scripts/build.sh                       # full build
./scripts/build.sh --bootloader-only
./scripts/build.sh --mota-only
./scripts/build.sh --list-versions
./scripts/build.sh v0.1.1 --target rak4631-repeater-slim
```

Lower-level: `scripts/build-mota.sh`, `scripts/build-bl.sh`.

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

Output: `build/motas/<ver>/<slug>/`. Default build = **all lines**. Override with `--target <slug>` (repeatable) or `--targets-file`.

## `scripts/build-mota.sh`

Builds OTA firmware from `envycore/` and packages `.mota` into `build/motas/<version>/<slug>/`.

**Steps (per target):**

1. `pio run -e <env>` (+ `create_uf2`)
2. Copy `firmware.hex`, `.uf2`, `.zip` → `build/motas/<ver>/<slug>/`
3. `motatool build --fw … --out-dir` → full `.mota`
4. If base version exists: `motatool build --base <prev.hex> --fw … --patch-type in-place` → `delta_from_<base>.mota`

**Output layout (`build/motas/<ver>/<slug>/`):**

| File | Purpose |
|------|---------|
| `firmware.hex` | **Keep as delta base** for next patch (same slug) |
| `firmware.uf2` | USB drag-flash (initial flash or recovery) |
| `fw_*_full_*.mota` | Full OTA image |
| `delta_from_v0.1.0.mota` | In-place patch from prior version |
| `version.txt` | Normalized tag |

Legacy flat layout (`build/motas/<ver>/firmware.hex`) still works as a delta base for `wismesh-tag-repeater`.

`build/` is gitignored — artifacts stay local.

## `scripts/build-bl.sh`

Builds **OTAFIX** nRF52 bootloader via Docker (`bootloader/`).

```bash
./scripts/build-bl.sh                    # → build/bootloader/<bootloader>/
./scripts/build-bl.sh v0.9.3             # override bootloader version for one build
./scripts/build-bl.sh --list-boards
./scripts/build-bl.sh wiscore_rak4631_board   # explicit board override
```

Env prefix → otafix `BOARD=` mapping lives in **`scripts/targets-lib.sh`** (`RAK_4631_*` → `wiscore_rak4631_board`, `RAK_WisMesh_Tag_*` → `wismesh_tag`).

- Docker image: `vk-otafix-build` (cached after first build)
- UF2: `bootloader/_build/build-<board>/update-*_nosd.uf2`
- Copied to **`build/bootloader/<ver>/`** for bench flash

**Only Tag B (DUT)** needs OTAFIX to apply in-place deltas. Flash: double-tap reset → drag UF2.

If coming from companion/Ripple firmware, **erase ExtraFS** before flashing bench repeater.

## `scripts/run-mota.sh`

Wraps **`motatool serve`** for Tag A seeder.

```bash
./scripts/run-mota.sh /dev/cu.usbmodem1444301
./scripts/run-mota.sh usbmodem1444301           # → /dev/cu.usbmodem1444301
./scripts/run-mota.sh /dev/cu.… ./build/motas/v0.1.1  # serve one version dir
```

Default dir: `./build/motas` (recursive `.mota` scan). Sends `ota folder on` on serial start; Ctrl-C sends off.

**Port conflict:** only one process per serial device — Tag A for serve, Tag B for `screen`/`pio device monitor`.

## Typical bench sequence

```bash
./scripts/build.sh
# flash build/bootloader/v0.1.0/*.uf2 on Tag B (match board profile)

./scripts/build-mota.sh v0.1.0
# flash Tag B from build/motas/v0.1.0/wismesh-tag-repeater/firmware.uf2
# flash Tag C from build/motas/v0.1.0/wismesh-tag-client-ble/firmware.uf2

./scripts/build-mota.sh v0.1.1
# produces delta_from_v0.1.0.mota

./scripts/run-mota.sh /dev/cu.… ./build/motas/v0.1.1   # Tag A USB

# Tag B serial:
ota ls → ota get N flash → ota install → ota status  # expect v0.1.1
```

## Troubleshooting

| Symptom | Check |
|---------|-------|
| Delta rejected at apply | `base_hash` vs `ota self` on device; hex base must be exact prior build |
| No entries in `ota ls` | Tag A has OTA build + `ota folder on`; serve dir contains valid `.mota`; mesh path |
| `bootloader: apply` missing | Tag B not on OTAFIX |
| motatool not found | `git submodule update --init motatool`; scripts auto-run `cargo build --release` |
| Wrong `[yours]` tag | `target_id` / env name mismatch |

## Related skills

- OTA protocol & CLI → `envyos-ota`
- motatool flags & delta encoding → `motatool`
- Firmware git workflow → `envyos-meshcore`
