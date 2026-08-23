---
name: envyos-scripts
description: >-
<<<<<<< HEAD
  Ota repo bench scripts and ./envyos CLI: build, bump, publish, info; build/ layout,
  EnvyOS versioning via scripts/version.sh. Use when building firmware,
  packaging .mota, flashing OTAFIX, or running the 3-tag bench.
=======
  EnvyOS bench orchestration: build.sh, build-bl.sh, publish.sh, version.sh;
  firmware build in envycore/scripts/build-mota.sh; seeder in motatool repo.
  Use when building firmware, packaging .mota, flashing OTAFIX, or running the 3-tag bench.
>>>>>>> hotfix/v0.1.3
---

# EnvyOS bench scripts

<<<<<<< HEAD
All scripts live in **`scripts/`**; primary entry point is **`./envyos`** (symlink at repo root).

## `./envyos` CLI

```bash
./envyos info
./envyos restore firmware              # all RELEASED_FIRMWARE versions
./envyos restore firmware v0.1.0       # one version
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
| `restore firmware` | Hydrate missing `build/firmware/<released>/` from GitHub (skip if version dir exists; delete dir or `--force` to re-download) |
| `restore bootloader` | Hydrate `build/bootloader/<released>/` from GitHub (bench flash / publish) |
| `restore` | Both firmware and bootloader |
| `bump` | Independent component semver + sidecar sync (`VERSION`, `Cargo.toml`) |
| `publish` | Distro bundle lock, stage assets, git tag, GitHub upload; ENVYOS_VERSIONS unchanged. GitHub notes come from `CHANGELOG.md` |

**Publish workflow:**

```bash
./envyos publish --dry-run      # verify + list assets (no writes)
./envyos publish stage          # copy flat files to build/releases/<distro>/
./envyos publish finalize       # lock RELEASED_* + RELEASE_MANIFEST + git tag + GUCP gate
./envyos publish upload v0.1.2  # GitHub Release
./envyos publish                # stage + finalize + upload
./envyos gucp check vX.Y.Z
./envyos gucp audit [vX.Y.Z] [N]
./envyos gucp list
```

Legacy scripts remain callable directly.
=======
**Ownership split:**

| Component | Repo | Build / serve |
|-----------|------|----------------|
| Firmware + `.mota` | `envycore/` submodule | `envycore/scripts/build-mota.sh` → `envycore/build/motas/` |
| Bootloader | `envyos17/bootloader/` | `scripts/build-bl.sh` → `build/bootloader/` |
| motatool | [MeshEnvy/motatool](https://github.com/MeshEnvy/motatool) | install release or `cargo build`; **`motatool` on PATH** |
| USB seeder | motatool repo | `motatool/scripts/seeder.sh` |
| Distro manifest / publish | envyos17 | `ENVYOS_VERSIONS`, `scripts/version.sh`, `scripts/publish.sh` |

Initialize submodules: `git submodule update --init envycore bootloader`
>>>>>>> hotfix/v0.1.3

## Prerequisites

| Tool | Used by |
|------|---------|
<<<<<<< HEAD
| PlatformIO (`pio`) | `build-mota.sh` |
| Docker | `build-bl.sh` |
| `motatool/target/release/motatool` (from `motatool/` submodule; auto-built) | `build-mota.sh` |
| `build/motatool/<motatool>/motatool` (staged by build) | `seeder.sh`, `build-mota.sh` |
=======
| PlatformIO (`pio`) | `envycore/scripts/build-mota.sh` |
| Docker | `scripts/build-bl.sh` |
| `motatool` on PATH (or `MOTATOOL=` override) | `envycore/scripts/build-mota.sh`, `motatool/scripts/seeder.sh` |
>>>>>>> hotfix/v0.1.3
| `envycore/` submodule on `envyos/main` | firmware source |
| `bootloader/` submodule | bootloader build |

## Versioning

All component versions live in **`ENVYOS_VERSIONS`** at envyos17 root:

| Key | Role |
|-----|------|
<<<<<<< HEAD
| `distro` | Next bundle to publish — git tag `v<distro>`, manifest at `build/releases/<distro>/` |
| `firmware` | device `ver` / `-DFIRMWARE_VERSION` + `build/firmware/<firmware>/` (sync `envycore/envyos/VERSION`). Not `distro`. |
| `bootloader` | `build/bootloader/<bootloader>/` |
| `motatool` | `motatool/Cargo.toml` + `build/motatool/<motatool>/motatool-<platform>` |

Helpers: **`scripts/version.sh`** — `bump_component`, `read_*_version`, `list_envyos_versions`, `is_released_distro`, `is_released_firmware`

**Released distros** (`RELEASED_DISTROS`): **`v0.1.0`**, **`v0.1.1`**, **`v0.1.2`** (latest on [GitHub](https://github.com/MeshEnvy/envyos/releases)). **In progress:** v0.2.0 dev HEAD. **Internal only:** v0.1.3 (no distro tag). **Released firmware** (`RELEASED_FIRMWARE`): immutable `build/firmware/<ver>/` trees.
=======
| `distro` | Git release tag `v<distro>` → `envycore/build/motas/<distro>/` |
| `firmware` | `-DFIRMWARE_VERSION` stamp (sync `envycore/envyos/VERSION`) |
| `bootloader` | `build/bootloader/<bootloader>/` |
| `motatool` | semver pin only — install from [MeshEnvy/motatool releases](https://github.com/MeshEnvy/motatool/releases) |

Helpers: **`scripts/version.sh`** (sources `envycore/scripts/version.sh` for firmware paths) — `read_distro_version`, `read_firmware_version`, `read_bootloader_version`, `read_motatool_version`, `list_envyos_versions`, `is_released_version`

**Released versions** (`RELEASED_VERSIONS`): shipped distro tags with immutable `envycore/build/motas/<ver>/` trees.
>>>>>>> hotfix/v0.1.3

**Changelog** — policy [`docs/change-management.md`](../../../docs/change-management.md). Package changelogs (firmware `envycore/envyos/CHANGELOG.md`, `bootloader/CHANGELOG.md`, `motatool/CHANGELOG.md`) own per-package detail; root [`CHANGELOG.md`](../../../CHANGELOG.md) carries package-tagged highlights. Before finalize, promote Unreleased to `## [vX.Y.Z] - YYYY-MM-DD` with **`### Packages`** (`./envyos changelog delta` prints it) and **`### Upstream PRs`**. Finalize fails unless `./envyos changelog check` and `./envyos gucp check` pass.

<<<<<<< HEAD
**GUCP** — [`docs/good-upstream-contributor-policy.md`](../../../docs/good-upstream-contributor-policy.md). Triage on commit (`candidate` OK); open PRs at release prep. `./envyos gucp audit` before finalize. Skill: [`envyos-good-upstream-contributor`](../envyos-good-upstream-contributor/SKILL.md).

**Publish** — after **`./envyos build`**:

1. Promote `CHANGELOG.md` Unreleased → `## [v<distro>]`
2. `./envyos publish --dry-run` — verify delta matrix + list planned assets + preview notes
3. `./envyos publish stage` — copy flat files + `ASSETS` to `build/releases/<distro>/`
4. `./envyos publish finalize` — append `RELEASED_DISTROS`, lock `.released`, write `RELEASE_MANIFEST`, git tag
5. `./envyos publish upload v<distro>` — GitHub Release (notes = changelog section + component table + assets)
6. Or `./envyos publish` — steps 3–5 in one shot

Does **not** change `ENVYOS_VERSIONS` (bump distro manually when ready).

```bash
./envyos info
./envyos build firmware --target wismesh-tag-repeater
./envyos build firmware --release
./envyos build firmware --debug
./envyos bump patch firmware
./scripts/build-mota.sh v0.1.2 --base v0.1.0
=======
1. Verify firmware delta matrix + bootloader tree
2. Append to `RELEASED_VERSIONS`, write `.released` + `RELEASE_MANIFEST` (includes motatool pin)
3. Zip firmware + bootloader → GitHub Release assets
4. Git tag `v<distro>`, bump `ENVYOS_VERSIONS` + `envycore/envyos/VERSION`

```bash
source scripts/version.sh && list_envyos_versions
cd envycore && ./scripts/build-mota.sh --list-targets
cd envycore && ./scripts/build-mota.sh                    # distro from ENVYOS_VERSIONS
cd envycore && ./scripts/build-mota.sh v0.1.1             # override output dir + FIRMWARE_VERSION stamp
cd envycore && ./scripts/build-mota.sh --target wismesh-tag-repeater
cd envycore && ./scripts/build-mota.sh v0.1.2 --base v0.1.0
cd envycore && ./scripts/build-mota.sh --hex-only
>>>>>>> hotfix/v0.1.3
```

## `scripts/build.sh`

Orchestration entry point — runs **`build-bl.sh`** then delegates firmware to **`envycore/scripts/build-mota.sh`**.

```bash
./scripts/build.sh                       # bootloader + envycore motas
./scripts/build.sh --bootloader-only
./scripts/build.sh --mota-only
./scripts/build.sh --list-targets
./scripts/build.sh v0.1.1 --target rak4631-repeater-slim
```

## `envycore/scripts/targets.txt`

Target map for **`envycore/scripts/build-mota.sh`**. One line per shipped board/role:

```text
slug  platformio_env  [description…]
```

<<<<<<< HEAD
| Slug | PlatformIO env |
|------|----------------|
| `wismesh-tag-repeater` | `RAK_WisMesh_Tag_repeater` |
| `rak4631-repeater-slim` | `RAK_4631_repeater_slim` |
| `sensecap-p1pro-repeater-slim` | `SenseCap_Solar_repeater_slim` |
| `wismesh-tag-repeater` | `RAK_WisMesh_Tag_repeater` (bench USB relay only) |
| `rak4631-client-ble` | `RAK_4631_companion_radio_ble` |
| `wismesh-tag-client-ble` | `RAK_WisMesh_Tag_companion_radio_ble` |

`*-debug` twins mirror every release slug in `targets.txt` (e.g. `wismesh-tag-client-ble-debug`). Distinct MOTA `target_id`. Default build includes them; publish skips them.

Output: `build/firmware/<ver>/<slug>/`. Default build = **field + debug** slugs. `--release` or `--debug` limits to one set. `--target <slug>` (repeatable) or `--targets-file`.

## `scripts/build-mota.sh`

Builds OTA firmware from `envycore/` and packages `.mota` into `build/firmware/<version>/<slug>/`.
=======
Output: `envycore/build/motas/<ver>/<slug>/`. Default build = **all lines**. Override with `--target <slug>`.

## `envycore/scripts/build-mota.sh`

Builds OTA firmware from envycore repo root and packages `.mota` into `envycore/build/motas/<version>/<slug>/`.
>>>>>>> hotfix/v0.1.3

**Steps:**

<<<<<<< HEAD
1. **pio (serial):** `pio run -e <env>` (+ `create_uf2`) per target, one at a time
2. **motatool (pipelined):** as soon as each target's hex is saved, queue full `.mota` + all in-place deltas for that slug into a shared worker pool (runs in parallel with later pio builds)
3. After the last pio build, drain remaining motatool jobs

Concurrency: `--mota-jobs` / `$ENVYOS_MOTA_JOBS` (alias `--delta-jobs` / `$ENVYOS_DELTA_JOBS`; default CPU count). One pool slot = one `motatool build` (full or delta).

**Output layout (`build/firmware/<ver>/<slug>/`):**

| File | Purpose |
|------|---------|
| `fw-<slug>-<ver>.hex` | **Keep as delta base** for next patch (same slug) |
| `fw-<slug>-<ver>.uf2` | USB drag-flash (initial flash or recovery) |
| `fw-<slug>-<ver>-full-<mid8>.mota` | Full OTA image |
| `fw-<slug>-<ver>-delta-from-<base>-<base8>.mota` | In-place patch; `base8` matches that base's full-mota merkle |
| `version.txt` | Semver (line 1), UTC build stamp (line 2), envycore git sha (line 3) |

Legacy flat layout (`build/firmware/<ver>/firmware.hex`) still works as a delta base for `wismesh-tag-repeater`.

`build/` is gitignored — artifacts stay local.

## `scripts/build-bl.sh`

Builds **EnvyBoot** nRF52 bootloaders via Docker (`bootloader/`).

```bash
./scripts/build-bl.sh                    # → build/bootloader/<bootloader>/
./scripts/build-bl.sh v0.1.3             # override bootloader version for one build
./scripts/build-bl.sh --list-boards
./scripts/build-bl.sh rak4631   # explicit board override
```

Env prefix → EnvyBoot `BOARD=` mapping lives in **`scripts/targets-lib.sh`** (`RAK_4631_*` → `rak4631`, `RAK_WisMesh_Tag_*` → `wismesh_tag`).

- Docker image: `vk-otafix-build` (cached after first build)
- UF2: `bootloader/_build/build-<board>/*_bootloader-*.uf2` (normal EnvyBoot upgrade)
- Recovery: `*_bootloader-*.recovery.zip` (break-glass BL+SD; `README.txt` inside)
- Copied to **`build/bootloader/<ver>/`** for bench flash

**Only Tag B (DUT)** needs **EnvyBoot** to apply in-place deltas. Flash: double-tap reset → drag UF2.

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

=======
1. `pio run -e <env>` (+ `create_uf2`)
2. Copy `firmware.hex`, `.uf2`, `.zip` → output dir
3. `motatool build --fw … --out-dir` → full `.mota`
4. Delta from each prior release with base hex for that slug

Requires **`motatool` on PATH** (release install or `MOTATOOL=`).

## `scripts/build-bl.sh`

Builds **OTAFIX** nRF52 bootloader via Docker. Reads **`envycore/scripts/targets.txt`** for board list.

Env prefix → otafix `BOARD=` mapping: **`scripts/targets-lib.sh`**.

## `motatool/scripts/seeder.sh`

Wraps **`motatool serve`** for Tag A USB seeder (motatool repo, not envyos17).

```bash
/path/to/motatool/scripts/seeder.sh /dev/cu.usbmodem1444301
/path/to/motatool/scripts/seeder.sh usbmodem1444301 envycore/build/motas/v0.1.1
```

>>>>>>> hotfix/v0.1.3
## Typical bench sequence

```bash
./scripts/build.sh
# flash build/bootloader/<ver>/*.uf2 on Tag B

<<<<<<< HEAD
./scripts/build-mota.sh v0.1.0
# flash Tag B from build/firmware/v0.1.0/wismesh-tag-repeater/fw-wismesh-tag-repeater-v0.1.0.uf2
# flash Tag C from build/firmware/v0.1.0/wismesh-tag-client-ble/fw-wismesh-tag-client-ble-v0.1.0.uf2

./scripts/build-mota.sh v0.1.1
# produces fw-<slug>-v0.1.1-delta-from-v0.1.0-<base8>.mota per prior base

./scripts/seeder.sh /dev/cu.… ./build/firmware/v0.1.1   # Tag A USB
=======
cd envycore && ./scripts/build-mota.sh v0.1.0
# flash Tag B from envycore/build/motas/v0.1.0/wismesh-tag-repeater/firmware.uf2

cd envycore && ./scripts/build-mota.sh v0.1.1

/path/to/motatool/scripts/seeder.sh /dev/cu.… envycore/build/motas/v0.1.1
>>>>>>> hotfix/v0.1.3

# Tag B serial: ota ls → ota get N flash → ota install
```

## Troubleshooting

| Symptom | Check |
|---------|-------|
<<<<<<< HEAD
| Delta rejected at apply | `base_hash` vs `ota self` on device; hex base must be exact prior build |
| No entries in `ota ls` | Tag A has OTA build + `ota folder on`; serve dir contains valid `.mota`; mesh path |
| `bootloader: apply` missing | Tag B not on EnvyBoot |
| motatool not found | `git submodule update --init motatool`; scripts auto-run `cargo build --release` |
| Wrong `[yours]` tag | `target_id` / env name mismatch |
=======
| motatool not found | Install [MeshEnvy/motatool release](https://github.com/MeshEnvy/motatool/releases) or `cargo build --release` in motatool repo; or `MOTATOOL=` |
| Delta rejected at apply | `base_hash` vs `ota self` on device |
| `bootloader: apply` missing | Tag B not on OTAFIX |
>>>>>>> hotfix/v0.1.3

## Related skills

- OTA protocol & CLI → `envyos-ota`
- motatool flags & delta encoding → `motatool` (motatool repo)
- Firmware git workflow → `envyos-meshcore`
