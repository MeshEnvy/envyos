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
| Bootloader | `bootloader/` sibling | `scripts/build-bl.sh` → `build/<branch>/bench/bootloader-<ver>/` |
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

Component pins live in **`ENVYOS_VERSIONS`**. **Bench output** uses `build/<git-branch>/bench/` (see `docs/distro-semver.md`). **Published** trees live at `build/vX.Y.Z/`.

| Key | Role |
|-----|------|
| `distro` | Draft/published git tag — set at `./envyos publish` |
| `firmware` | `-DFIRMWARE_VERSION` stamp (sync `envycore/envyos/VERSION`) |
| `bootloader` | `build/<branch>/bench/bootloader-<ver>/` |
| `motatool` | `build/<branch>/bench/motatool-<ver>/` |
| `firmware` | `build/<branch>/bench/firmware-<ver>/<slug>/` |

Helpers: **`scripts/version.sh`** — `read_build_slot`, `read_bench_tree_key`, `read_firmware_version`, `list_envyos_versions`, `propose_next_distro_version`, `is_released_version`

**Publish** — `./envyos publish [vX.Y.Z]` (run **`./envyos build`** first):

1. Suggest tag: `./envyos semver suggest` (CHANGELOG + bundle policy)
2. Promote `build/<branch>/bench/` → `build/<ver>/`
3. Verify delta matrix, lock `RELEASED_VERSIONS`, zip, GitHub Release (+ `envyos-<ver>-full.tgz`)
4. Git tag `v<ver>`; writes `distro=` + `firmware=` in `ENVYOS_VERSIONS`

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
