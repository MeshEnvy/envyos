# EnvyOS — agent memory

MeshEnvy's MeshCore distro: OTA over LoRa, routing improvements, and repeater enhancements. Firmware lives in `envycore/` (submodule); this repo (`ota`) holds build tooling, `.mota` artifacts, and the bench workflow.

## Repo layout

| Path | Role |
|------|------|
| `envycore/` | MeshCore firmware submodule (`MeshEnvy/meshcore-firmware`); **`envyos/main`** is distro head |
| `ENVYOS_VERSIONS` | Component semver manifest — `distro`, `firmware`, `bootloader`, `motatool` (all `0.1.0` at reset) |
| `build/` | Local build outputs (gitignored) — `build/motas/<distro>/`, `build/bootloader/<bootloader>/`, `build/motatool/<motatool>/` |
| `motatool/` | Rust CLI — pack/serve `.mota` (`MeshEnvy/motatool`; **`envyos/main`**) |
| `vendor/detools/` | Delta/diff encoding library (in-place `.mota` patches) |
| `bootloader/` | nRF52 OTAFIX bootloader submodule (`MeshEnvy/Adafruit_nRF52_Bootloader_OTAFIX`; **`envyos/main`**) |
| `scripts/` | Bench scripts — `build.sh`, `build-mota.sh`, `build-bl.sh`, `seeder.sh`, `targets.txt` |

## Git remotes (`envycore/`)

| Remote | Repository | Role |
|--------|------------|------|
| `origin` | `MeshEnvy/meshcore-firmware` | EnvyOS fork — push features here |
| `vk496` | `vk496/MeshCore` | OTA / vk496 stack |
| `meshcore` | `meshcore-dev/MeshCore` | Upstream MeshCore |

## Git remotes (`bootloader/`)

| Remote | Repository | Role |
|--------|------------|------|
| `origin` | `MeshEnvy/Adafruit_nRF52_Bootloader_OTAFIX` | EnvyOS fork — head **`envyos/main`** |
| `vk496` | `vk496/Adafruit_nRF52_Bootloader_OTAFIX` | OTA delta apply — **`feature/ota-delta-apply`** |
| `oltaco` | `oltaco/Adafruit_nRF52_Bootloader_OTAFIX` | Official OTAFIX releases (`0.9.2-OTAFIX*` tags) |

**`envyos/main`** = merged union of shipped EnvyOS features on **each MeshEnvy fork** (firmware, motatool, otafix). GitHub default branch is `envyos/main` on all three. Feature branches merge here even while vk496 PRs are open. See `.cursor/skills/envyos-meshcore/SKILL.md`.

## Distro git (`envyos/main` + vk496 PRs)

Each OTA-stack repo has **two branch roles**:

| Role | Branch | Where |
|------|--------|-------|
| **Distro integration** | `envyos/main` | MeshEnvy fork (`origin` / `meshenvy`) — always merge features here |
| **Upstream PR** | `feature/<name>` | Same fork; PR targets vk496 base (below) |

**vk496 PR bases** (not the same as `envyos/main`):

| Submodule | vk496 remote | PR base branch |
|-----------|--------------|----------------|
| `envycore/` | `vk496/MeshCore` | `feature/ota-lora` |
| `motatool/` | `vk496/motatool` | `main` |
| `bootloader/` | `vk496/Adafruit_nRF52_Bootloader_OTAFIX` | `feature/ota-delta-apply` |

Workflow: branch feature from vk496 base → implement → open cross-fork PR (`MeshEnvy:feature/<name>`) → **also merge into `envyos/main`** and push. Monorepo (`ota`) pins submodule SHAs; bump at release freshen or when intentionally advancing pins.

**Do not** clone a standalone otafix checkout — only the **`bootloader/`** submodule.

## Versioning

- **`ENVYOS_VERSIONS`** at repo root — bump together on `/freshen`:
  - `distro` → git tags `v0.1.x`, **`build/motas/<distro>/`**
  - `firmware` → `-DFIRMWARE_VERSION` (must match `envycore/envyos/VERSION`)
  - `bootloader` → **`build/bootloader/<bootloader>/`** — passed to otafix as `GIT_VERSION` (artifact names + embedded BL version)
  - `motatool` → must match `motatool/Cargo.toml`; bench scripts use **`motatool/` submodule only** (never PATH); staged to **`build/motatool/<motatool>/`**
- **Earns an EnvyOS version:** only a **release freshen** bundle — `companion-v*` + `vk496/feature/ota-lora` + EnvyOS overlay (`envycore/FRESHEN.lock`). Not companion tag alone; not `meshcore/dev`.
- **Not** upstream `companion-v1.17.x` — record companion tag in `FRESHEN.lock` for traceability
- Helpers: **`scripts/version.sh`** — `read_distro_version`, `read_firmware_version`, `read_bootloader_version`, `read_motatool_version`, `list_envyos_versions`
- `./scripts/build-mota.sh` reads `distro` + `firmware` from manifest; run only after release freshen passes validation
- Override: `./scripts/build-mota.sh v0.1.1` (without editing `ENVYOS_VERSIONS`)
- Stock MeshCore (no EndF/OTA): `./scripts/build-mota.sh --hex-only` → hex/uf2 only, no `.mota`
- `-DFIRMWARE_VERSION` stamped via `PLATFORMIO_BUILD_FLAGS` in `build-mota.sh`

## OTA targets (`scripts/targets.txt`)

| Slug | PlatformIO env | Role |
|------|----------------|------|
| `wismesh-tag-repeater` | `RAK_WisMesh_Tag_repeater` | WisMesh Tag repeater (bench DUT) |
| `rak4631-repeater` | `RAK_4631_repeater` | RAK4631 repeater |
| `rak4631-repeater-slim` | `RAK_4631_repeater_slim` | RAK4631 slim repeater — no OLED/sensors/BLE (`BLE_DFU_DISABLED`; MCU temp only); ~180 KB smaller → ~416 KB staging headroom (fits a full slim `.mota`) |
| `rak4631-client-ble` | `RAK_4631_companion_radio_ble` | RAK4631 companion (BLE) |
| `wismesh-tag-client-ble` | `RAK_WisMesh_Tag_companion_radio_ble` | WisMesh Tag companion (BLE) |

Add a line to `targets.txt` to ship another board/role.

## nRF52 OTA flash layout (RAK4631)

| Build | `MOTA_STAGE_CEILING` | Staging capacity |
|-------|----------------------|------------------|
| Companion (`*_companion_*`) | `0xD4000` (below ExtraFS) | ~696 KB − app |
| Repeater / room-server | `0xED000` (reclaims ExtraFS) | ~808 KB − app |

Bootloader scan ceiling: `0xED000` (InternalFS start). In-place `memory_size` is per-patch (motatool auto-computes from ceiling − staged `.mota` size).

## Mesh / next-hop retry

Direct-path repeaters: after forward, next hop sends zero-hop **`HOP_ACK`** (control `0xA0`, ~10 B). Upstream waits (`hop.retry.ms`, default 1500 ms) then retries (`hop.retry`, default 2). **Retry only for next hops that previously sent HOP_ACK** (runtime capability table; stock repeaters stay single-shot). CLI: `set hop.retry`, `set hop.retry.ms`. Branch: `feature/next-hop-retry` → upstream PR to `meshcore-dev/MeshCore`.

## OTA bench (WisMesh Tag)

| Tag | Role | Bootloader |
|-----|------|------------|
| A (seeder) | OTA-capable build + `OTA_FOLDER_SERIAL`; USB to laptop | stock OK |
| B (router) | `wismesh-tag-repeater` — device under test | **`bootloader/` OTAFIX required** |
| C (client) | `wismesh-tag-client-ble` — remote `ota` CLI over mesh | stock OK |

Flow: `motatool serve --dir ./build/motas/<ver> --serial …` → Tag A advertises `.mota` over LoRa → Tag B fetch/install → Tag C remote admin.

## Build commands

```bash
./scripts/build.sh                       # full build (bootloader + motas + motatool)
./scripts/build.sh --bootloader-only
./scripts/build.sh --mota-only --target rak4631-repeater-slim
./scripts/build.sh --list-versions
./scripts/build-bl.sh                    # lower-level: bootloader only
./scripts/build-bl.sh --list-boards
./scripts/build-mota.sh --list-targets
./scripts/build-mota.sh                    # all targets → build/motas/<distro>/
./scripts/build-mota.sh v0.1.1
./scripts/build-mota.sh --target wismesh-tag-repeater
./scripts/build-mota.sh --hex-only
./scripts/seeder.sh /dev/cu.usbmodem1444301
./scripts/seeder.sh /dev/cu.… ./build/motas/v0.1.1
```

## Conflict hotspots

When merging upstream into `envyos/main`: `Mesh.cpp`, `CommonCLI.*`, `platformio.ini`, OTA test mocks.

## Freshen (`/freshen`)

**Fleet policy:** `companion-v*` + `vk496/feature/ota-lora` + EnvyOS overlay → bump **`ENVYOS_VERSIONS`**, `./scripts/build-mota.sh`, tag **`v<distro>`**.

| Command | Purpose | EnvyOS version? |
|---------|---------|-----------------|
| `/freshen` | Release bundle + otafix | **Yes** |
| `/freshen dev` | `meshcore/dev` integration | **No** |

Manifest: `envycore/FRESHEN.lock`. Otafix: `0.9.2-OTAFIX*` + `vk496/feature/ota-delta-apply`. Skill: `.cursor/skills/envyos-freshen/SKILL.md`.

## OTA greenfield

Pre-deployment — **no production fleet, no field migrations**. Breaking `.mota`/protocol/EndF changes are OK; rebuild artifacts and update docs instead of compat shims. Skill: `.cursor/skills/ota-greenfield/SKILL.md`.

## Agent skills

| Skill | When to load |
|-------|----------------|
| `envyos-freshen` | `/freshen` — release bundle earns VERSION; `/freshen dev` integration only |
| `envyos-meshcore` | Git remotes, feature branches, upstream PRs |
| `envyos-ota` | OTA protocol, device CLI, codecs, bench roles |
| `ota-greenfield` | OTA format/protocol/tooling changes — no legacy or migration paths |
| `envyos-scripts` | `scripts/build-mota.sh`, `build-bl.sh`, `seeder.sh` |
| `motatool` | `.mota` build, deltas, verify, serve |

## Active threads

<!-- In-flight work only; delete when done -->
- vk496 PRs open for role-aware OTA staging ceiling (`feature/ota-stage-ceiling` → merged on MeshEnvy `envyos/main`; pending on vk496): MeshCore #3, motatool #1, OTAFIX #2
- vk496 MeshCore #4 (stacked on #3): slim RAK4631 repeater role (`feature/ota-slim-repeater` → merged on MeshEnvy `envyos/main`)
