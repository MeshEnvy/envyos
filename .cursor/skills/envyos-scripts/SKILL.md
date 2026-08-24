---
name: envyos-scripts
description: >-
  EnvyOS bench orchestration: build.sh, build-bl.sh, publish.sh, version.sh;
  firmware build in envycore/scripts/build-mota.sh; seeder in motatool repo.
  Use when building firmware, packaging .mota, flashing OTAFIX, or running the 3-tag bench.
---

# EnvyOS bench scripts

**Ownership split:**

| Component | Repo | Build / serve |
|-----------|------|----------------|
| Firmware + `.mota` | `envycore/` submodule | `envycore/scripts/build-mota.sh` → `envycore/build/motas/` |
| Bootloader | `envyos17/bootloader/` | `scripts/build-bl.sh` → `build/bootloader/` |
| motatool | [MeshEnvy/motatool](https://github.com/MeshEnvy/motatool) | install release or `cargo build`; **`motatool` on PATH** |
| USB seeder | motatool repo | `motatool/scripts/seeder.sh` |
| Distro manifest / publish | envyos17 | `ENVYOS_VERSIONS`, `scripts/version.sh`, `scripts/publish.sh` |

Initialize submodules: `git submodule update --init envycore bootloader`

## Prerequisites

| Tool | Used by |
|------|---------|
| PlatformIO (`pio`) | `envycore/scripts/build-mota.sh` |
| Docker | `scripts/build-bl.sh` |
| `motatool` on PATH (or `MOTATOOL=` override) | `envycore/scripts/build-mota.sh`, `motatool/scripts/seeder.sh` |
| `envycore/` submodule on `envyos/main` | firmware source |
| `bootloader/` submodule | bootloader build |

## Versioning

All component versions live in **`ENVYOS_VERSIONS`** at envyos17 root:

| Key | Role |
|-----|------|
| `distro` | Git release tag `v<distro>` → `envycore/build/motas/<distro>/` |
| `firmware` | `-DFIRMWARE_VERSION` stamp (sync `envycore/envyos/VERSION`) |
| `bootloader` | `build/bootloader/<bootloader>/` |
| `motatool` | semver pin only — install from [MeshEnvy/motatool releases](https://github.com/MeshEnvy/motatool/releases) |

Helpers: **`scripts/version.sh`** (sources `envycore/scripts/version.sh` for firmware paths) — `read_distro_version`, `read_firmware_version`, `read_bootloader_version`, `read_motatool_version`, `list_envyos_versions`, `is_released_version`

**Released versions** (`RELEASED_VERSIONS`): shipped distro tags with immutable `envycore/build/motas/<ver>/` trees.

**Publish a distro release** — `./scripts/publish.sh [version]` (run **`./scripts/build.sh`** first):

1. Verify firmware delta matrix + bootloader tree
2. Append to `RELEASED_VERSIONS`, write `.released` + `RELEASE_MANIFEST` (includes motatool pin)
3. Zip firmware + bootloader → GitHub Release assets (includes \`envyos-<ver>-full.tgz\` complete bench bundle)
4. Git tag `v<distro>`, bump `ENVYOS_VERSIONS` + `envycore/envyos/VERSION`

```bash
source scripts/version.sh && list_envyos_versions
cd envycore && ./scripts/build-mota.sh --list-targets
cd envycore && ./scripts/build-mota.sh                    # distro from ENVYOS_VERSIONS
cd envycore && ./scripts/build-mota.sh v0.1.1             # override output dir + FIRMWARE_VERSION stamp
cd envycore && ./scripts/build-mota.sh --target wismesh-tag-repeater
cd envycore && ./scripts/build-mota.sh v0.1.2 --base v0.1.0
cd envycore && ./scripts/build-mota.sh --hex-only
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

Output: `envycore/build/motas/<ver>/<slug>/`. Default build = **all lines**. Override with `--target <slug>`.

## `envycore/scripts/build-mota.sh`

Builds OTA firmware from envycore repo root and packages `.mota` into `envycore/build/motas/<version>/<slug>/`.

**Steps (per target):**

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

## Typical bench sequence

```bash
./scripts/build.sh
# flash build/bootloader/<ver>/*.uf2 on Tag B

cd envycore && ./scripts/build-mota.sh v0.1.0
# flash Tag B from envycore/build/motas/v0.1.0/wismesh-tag-repeater/firmware.uf2

cd envycore && ./scripts/build-mota.sh v0.1.1

/path/to/motatool/scripts/seeder.sh /dev/cu.… envycore/build/motas/v0.1.1

# Tag B serial: ota ls → ota get N flash → ota install
```

## Troubleshooting

| Symptom | Check |
|---------|-------|
| motatool not found | Install [MeshEnvy/motatool release](https://github.com/MeshEnvy/motatool/releases) or `cargo build --release` in motatool repo; or `MOTATOOL=` |
| Delta rejected at apply | `base_hash` vs `ota self` on device |
| `bootloader: apply` missing | Tag B not on OTAFIX |

## Related skills

- OTA protocol & CLI → `envyos-ota`
- motatool flags & delta encoding → `motatool` (motatool repo)
- Firmware git workflow → `envyos-meshcore`
