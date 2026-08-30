---
name: envyos-scripts
description: >-
  EnvyOS bench orchestration: ./envyos CLI, packages-meta/<pkg>/build.sh recipes,
  publish.sh, version.sh; seeder in packages/motatool. Use when building firmware,
  packaging .mota, flashing OTAFIX, or running the 3-tag bench.
---

# EnvyOS bench scripts

**Ownership split:**

| Component | Source | Recipe |
|-----------|--------|--------|
| Firmware + `.mota` | `packages/meshcore/` | `packages-meta/meshcore/build.sh` → `build/<branch>/bench/firmware-<ver>/` |
| Bootloader | `packages/bootloader/` | `packages-meta/bootloader/build.sh` → `build/<branch>/bench/bootloader-<ver>/` |
| motatool | `packages/motatool/` | `packages-meta/motatool/build.sh`; staged + **`motatool` on PATH** |
| peaky | release cache | `packages-meta/peaky/build.sh` (only when `peaky=` pinned) |
| USB seeder | `packages/motatool/scripts/seeder.sh` | |
| Distro manifest / publish | envyos | `MANIFEST.json`, `scripts/version.sh`, `scripts/publish.sh` |

All builds go through **`./envyos build [pkg…]`** — it dispatches to `packages-meta/<pkg>/build.sh`. Shared machinery (`version.sh`, `build-lib.sh`, `packages-meta-lib.sh`, `targets.txt`, `targets-lib.sh`) stays in `scripts/`.

Materialize forks: `./envyos fetch meshcore bootloader motatool`

## Prerequisites

| Tool | Used by |
|------|---------|
| PlatformIO (`pio`) | meshcore recipe |
| Docker | bootloader recipe (and motatool linux targets) |
| `motatool` on PATH (or `MOTATOOL=` override) | meshcore recipe, seeder |
| `packages/meshcore/` checkout on `envyos/main` (or `envyos/dev`) | firmware source |
| `packages/bootloader/` checkout | bootloader build |

## Versioning

Package pins live in **`MANIFEST.json` `releases.next`** (mirrors `packages-meta/<pkg>/VERSION`). **Bench output** uses `build/<git-branch>/bench/` (see `docs/distro-semver.md`). **Published** trees live at `build/vX.Y.Z/`.

| Key | Role |
|-----|------|
| `distro` | Draft/published git tag — set at `./envyos publish` |
| `meshcore` | `upstream-evN` — `-DFIRMWARE_VERSION` stamp; `build/<branch>/bench/firmware-<ver>/<slug>/` |
| `bootloader` | `upstream-evN` — `build/<branch>/bench/bootloader-<ver>/` |
| `motatool` | `upstream-evN` — `build/<branch>/bench/motatool-<ver>/` |
| `peaky` | optional semver pin — staged from GitHub release cache |

Helpers: **`scripts/version.sh`** — `read_build_slot`, `read_bench_tree_key`, `read_firmware_version`, `list_manifest`, `propose_next_distro_version`, `is_released_version`. Overlay bump: **`./envyos bump-ev <pkg>`**. Meshcore overlay notes: **`packages/meshcore/CHANGELOG.md`** (publish folds the pin section into distro release notes).

**Publish** — `./envyos publish [vX.Y.Z]` (run **`./envyos build`** first). `./envyos publish --dry-run` prints the plan, `releases.next` pins, and the GitHub notes body.

1. Suggest tag: `./envyos semver suggest` (CHANGELOG + bundle policy)
2. Promote `build/<branch>/bench/` → `build/<ver>/`
3. Verify delta matrix, lock `releases.next` SHAs, snapshot to `releases[vX.Y.Z]`, zip, GitHub Release (+ `envyos-<ver>-full.tgz`)
4. Git tag `v<ver>`; records release in `MANIFEST.json` `releases`

```bash
source scripts/version.sh && list_manifest
./envyos build meshcore --list-targets
./envyos build meshcore                    # version from packages-meta/meshcore/VERSION
./envyos build meshcore v0.1.1             # override output dir + FIRMWARE_VERSION stamp
./envyos build meshcore --target wismesh-tag-repeater
./envyos build meshcore v0.1.2 --base v0.1.0
./envyos build meshcore --hex-only
```

## `./envyos build` (scripts/build-all.sh)

Orchestration entry point — bootloader → motatool → firmware → peaky (if pinned) → release tree.

```bash
./envyos build                       # pinned packages
./envyos build --bootloader-only
./envyos build --mota-only
./envyos build --list-targets
./envyos build meshcore bootloader   # explicit package list
```

## `scripts/targets.txt`

Target map for the meshcore recipe. One line per shipped board/role:

```text
slug  platformio_env  [description…]
```

Output: `build/<branch>/bench/firmware-<ver>/<slug>/`. Default build = **all lines**. Override with `--target <slug>`.

## `packages-meta/meshcore/build.sh`

Builds OTA firmware from `packages/meshcore/` and packages `.mota` per slug.

**Steps (per target):**

1. `pio run -e <env>` (+ `create_uf2`)
2. Copy `firmware.hex`, `.uf2`, `.zip` → output dir
3. `motatool build --fw … --out-dir` → full `.mota`
4. Delta from each prior release with base hex for that slug

Requires **`motatool` on PATH** (staged build or `MOTATOOL=`).

## `packages-meta/bootloader/build.sh`

Builds **OTAFIX** nRF52 bootloader via Docker. Reads **`scripts/targets.txt`** for board list.

Env prefix → otafix `BOARD=` mapping: **`scripts/targets-lib.sh`**.

## `packages/motatool/scripts/seeder.sh`

Wraps **`motatool serve`** for Tag A USB seeder.

```bash
packages/motatool/scripts/seeder.sh /dev/cu.usbmodem1444301
packages/motatool/scripts/seeder.sh usbmodem1444301 build/main/bench/firmware-<ver>
```

## Typical bench sequence

```bash
./envyos build
# flash bench bootloader UF2 on Tag B

./envyos build meshcore v0.1.0
# flash Tag B from bench firmware-v0.1.0/wismesh-tag-repeater/firmware.uf2

./envyos build meshcore v0.1.1

packages/motatool/scripts/seeder.sh /dev/cu.… build/main/bench/firmware-v0.1.1

# Tag B serial: ota ls → ota get N flash → ota install
```

## Troubleshooting

| Symptom | Check |
|---------|-------|
| motatool not found | `./envyos build motatool --host-only`; or `MOTATOOL=` |
| Delta rejected at apply | `base_hash` vs `ota self` on device |
| `bootloader: apply` missing | Tag B not on OTAFIX |

## Related skills

- OTA protocol & CLI → `envyos-ota`
- motatool flags & delta encoding → `motatool`
- Firmware git workflow → `envyos-meshcore`
