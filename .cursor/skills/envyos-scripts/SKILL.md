---
name: envyos-scripts
description: >-
  Ota repo bench scripts and ./envyos CLI: build, bump, publish, info; build/ layout,
  EnvyOS versioning via scripts/version.sh. Use when building firmware,
  packaging .mota, flashing OTAFIX, or running the 3-tag bench.
---

# EnvyOS bench scripts

All scripts live in **`scripts/`**; primary entry point is **`./envyos`** (symlink at repo root).

## `./envyos` CLI

```bash
./envyos info
./envyos build [firmware|bootloader|motatool]   # default: all
./envyos bump patch|minor|major distro|firmware|bootloader|motatool
./envyos publish [--dry-run]
./envyos publish stage
./envyos publish finalize
./envyos publish upload vX.Y.Z
```

| Command | Role |
|---------|------|
| `info` | Dev HEAD, last published distro manifest, artifact readiness |
| `build` | Wraps `build.sh`, `build-mota.sh`, `build-bl.sh`, `build-motatool.sh` |
| `bump` | Independent component semver + sidecar sync (`VERSION`, `Cargo.toml`) |
| `publish` | Distro bundle lock, stage assets, git tag, GitHub upload; ENVYOS_VERSIONS unchanged |

**Publish workflow:**

```bash
./envyos publish --dry-run      # verify + list assets (no writes)
./envyos publish stage          # copy flat files to build/releases/<distro>/
./envyos publish finalize       # lock RELEASED_* + RELEASE_MANIFEST + git tag
./envyos publish upload v0.1.2  # GitHub Release
./envyos publish                # stage + finalize + upload
```

Legacy scripts remain callable directly.

## Prerequisites

| Tool | Used by |
|------|---------|
| PlatformIO (`pio`) | `build-mota.sh` |
| Docker | `build-bl.sh` |
| `motatool/target/release/motatool` (from `motatool/` submodule; auto-built) | `build-mota.sh` |
| `build/motatool/<motatool>/motatool` (staged by build) | `seeder.sh`, `build-mota.sh` |
| `envycore/` submodule on `envyos/main` | firmware source |
| `bootloader/` submodule | bootloader build |

Initialize submodules: `git submodule update --init --recursive`

## Versioning

All component versions live in **`ENVYOS_VERSIONS`** at ota repo root:

| Key | Role |
|-----|------|
| `distro` | Next bundle to publish — git tag `v<distro>`, manifest at `build/releases/<distro>/` |
| `firmware` | `-DFIRMWARE_VERSION` → `build/firmware/<firmware>/` (sync `envycore/envyos/VERSION`) |
| `bootloader` | `build/bootloader/<bootloader>/` |
| `motatool` | `motatool/Cargo.toml` + `build/motatool/<motatool>/motatool-<platform>` |

Helpers: **`scripts/version.sh`** — `bump_component`, `read_*_version`, `list_envyos_versions`, `is_released_distro`, `is_released_firmware`

**Released distros** (`RELEASED_DISTROS`): **`v0.1.0`**, **`v0.1.1`**. **Released firmware** (`RELEASED_FIRMWARE`): immutable `build/firmware/<ver>/` trees.

**Publish** — after **`./envyos build`**:

1. `./envyos publish --dry-run` — verify delta matrix + list planned assets
2. `./envyos publish stage` — copy flat files + `ASSETS` to `build/releases/<distro>/`
3. `./envyos publish finalize` — append `RELEASED_DISTROS`, lock `.released`, write `RELEASE_MANIFEST`, git tag
4. `./envyos publish upload v<distro>` — GitHub Release
5. Or `./envyos publish` — steps 2–4 in one shot

Does **not** change `ENVYOS_VERSIONS` (bump distro manually when ready).

```bash
./envyos info
./envyos build firmware --target wismesh-tag-repeater
./envyos bump patch firmware
./scripts/build-mota.sh v0.1.2 --base v0.1.0
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
| `rak4631-repeater-slim` | `RAK_4631_repeater_slim` |
| `sensecap-p1pro-repeater-slim` | `SenseCap_Solar_repeater_slim` |
| `sensecap-p1pro-superseeder` | `SenseCap_Solar_superseeder` |
| `rak4631-superseeder` | `RAK_4631_superseeder` |
| `rak4631-client-ble` | `RAK_4631_companion_radio_ble` |
| `wismesh-tag-client-ble` | `RAK_WisMesh_Tag_companion_radio_ble` |

Output: `build/firmware/<ver>/<slug>/`. Default build = **all lines**. Override with `--target <slug>` (repeatable) or `--targets-file`.

## `scripts/build-mota.sh`

Builds OTA firmware from `envycore/` and packages `.mota` into `build/firmware/<version>/<slug>/`.

**Steps (per target):**

1. `pio run -e <env>` (+ `create_uf2`)
2. Copy `firmware.hex`, `.uf2`, `.zip` → `build/firmware/<ver>/<slug>/`
3. `motatool build --fw … --out-dir` → full `.mota`
4. For each prior version with base hex for that slug: `motatool build --base <B.hex> …` → `delta_from_<B>.mota` (new targets skip older bases; `--base` limits to one)

**Output layout (`build/firmware/<ver>/<slug>/`):**

| File | Purpose |
|------|---------|
| `firmware.hex` | **Keep as delta base** for next patch (same slug) |
| `firmware.uf2` | USB drag-flash (initial flash or recovery) |
| `fw_*_full_*.mota` | Full OTA image |
| `delta_from_v0.1.0.mota` | In-place patch from an older release (one per prior version) |
| `version.txt` | Semver (line 1), UTC build stamp (line 2), envycore git sha (line 3) |

Legacy flat layout (`build/firmware/<ver>/firmware.hex`) still works as a delta base for `wismesh-tag-repeater`.

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

## `scripts/seeder.sh`

Wraps **`motatool serve`** for Tag A seeder. Uses staged **`build/motatool/<motatool>/motatool-<platform>`** (host platform).

```bash
./envyos build motatool                 # linux via Docker; darwin native on macOS
./envyos build motatool --host-only     # host only (firmware bench path)
./envyos build motatool --target linux-x86_64
```

Linux targets use **`docker/motatool-build/`** (same idea as **`bootloader/Dockerfile`**). Release matrix is four platforms (no Windows).

Default dir: `./build/firmware` (recursive `.mota` scan). Sends `ota folder on` on serial start; Ctrl-C sends off.

**Port conflict:** only one process per serial device — Tag A for serve, Tag B for `screen`/`pio device monitor`.

## Typical bench sequence

```bash
./scripts/build.sh
# flash build/bootloader/v0.1.0/*.uf2 on Tag B (match board profile)

./scripts/build-mota.sh v0.1.0
# flash Tag B from build/firmware/v0.1.0/wismesh-tag-repeater/firmware.uf2
# flash Tag C from build/firmware/v0.1.0/wismesh-tag-client-ble/firmware.uf2

./scripts/build-mota.sh v0.1.1
# produces delta_from_v0.1.0.mota

./scripts/seeder.sh /dev/cu.… ./build/firmware/v0.1.1   # Tag A USB

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
