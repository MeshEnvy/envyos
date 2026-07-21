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
| `apps/app/` | Flutter MeshCore client submodule (`zjs81/meshcore-open`) |

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

## Distro git (`envyos/main` + upstream PR branches)

Each OTA-stack repo has **two branch roles**:

| Role | Branch | Where | Use |
|------|--------|-------|-----|
| **Distro integration** | `envyos/main` | MeshEnvy fork (`origin`) | All features merged together; **bench builds**; default dev checkout |
| **Upstream PR** | `feature/<name>` | Same fork | One PR each; **pure** — only that feature's commits; branched from PR base |

**PR bases** (not the same as `envyos/main`):

| Submodule | Remote | PR base branch | Example PR branch |
|-----------|--------|----------------|-------------------|
| `envycore/` | `meshcore-dev/MeshCore` | `dev` | `feature/next-hop-retry`, `feature/log-tail-serial` |
| `envycore/` | `vk496/MeshCore` | `feature/ota-lora` | `feature/ota-stage-ceiling` |
| `motatool/` | `vk496/motatool` | `main` | … |
| `bootloader/` | `vk496/Adafruit_nRF52_Bootloader_OTAFIX` | `feature/ota-delta-apply` | … |

Workflow: branch `feature/<name>` from PR base → implement → open cross-fork PR → **merge into `envyos/main`** (do not fold other features into the PR branch). Monorepo pins submodule SHAs at release; day-to-day `envycore/` checkout = `envyos/main`.

Skill: `.cursor/skills/envyos-meshcore/SKILL.md`.

## Open upstream PRs (`envycore/`)

MeshEnvy fork: `origin` → `MeshEnvy/meshcore-firmware`. Cross-fork PRs use `--head MeshEnvy:feature/<name>`.

| Feature | PR branch | Upstream repo | PR | Base | Also on `envyos/main` |
|---------|-----------|---------------|-----|------|------------------------|
| Next-hop retry (echo-primary) | `feature/next-hop-retry` | [meshcore-dev/MeshCore](https://github.com/meshcore-dev/MeshCore) | [#2980](https://github.com/meshcore-dev/MeshCore/pull/2980) | `dev` | yes |
| Log tail serial | `feature/log-tail-serial` | [meshcore-dev/MeshCore](https://github.com/meshcore-dev/MeshCore) | [#2991](https://github.com/meshcore-dev/MeshCore/pull/2991) | `dev` | yes |
| FS corruption boot fsck (companion) | `feature/fs-corruption-check` | [meshcore-dev/MeshCore](https://github.com/meshcore-dev/MeshCore) | [#3012](https://github.com/meshcore-dev/MeshCore/pull/3012) (draft) | `dev` | yes |

**Sync rule:** while a PR is open, commits for that feature go to **`envyos/main` and the PR branch** (push both). Unrelated features stay separate. See skill § Open PR sync policy.

vk496 / motatool / otafix PRs: see **Active threads** below and `envyos-meshcore` skill PR table.

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

Direct-path repeaters: after forward, upstream waits for the next hop's **echo** (same packet retransmitted downstream, including zero-hop last-mile forwards overheard on RF). Missed echo → retry (`hop.retry`, default 2; base window `hop.retry.ms`, default 1500 ms, plus forward delay and packet airtime). Duplicate addressed to next hop → zero-hop **`HOP_ACK`** (control `0xA0`, ~14 B) instead of re-forwarding. Zero overhead when echo is heard. CLI: `set hop.retry`, `set hop.retry.ms`. Bench test: `set hop.ignore <count>` on downstream silently drops next N forward opportunities (not persisted).

- **PR branch:** `feature/next-hop-retry` → meshcore-dev [#2980](https://github.com/meshcore-dev/MeshCore/pull/2980) (hop retry only; based on `meshcore/dev`)
- **Distro:** merged on `envyos/main` (with log tail, OTA, etc.)

Repeater USB debug: `log start` → `log tail on` mirrors packet log lines to serial (CRLF); `log tail off` or Ctrl+C stops. `log tail on` also enables logging if not already on.

- **PR branch:** `feature/log-tail-serial` → meshcore-dev [#2991](https://github.com/meshcore-dev/MeshCore/pull/2991)
- **Distro:** merged on `envyos/main`

## Mesh routing bench (WisMesh Tag)

Repeaters and companions used for direct-path / hop-retry testing (`log tail on` over USB). OTA roles below are separate when running the OTA bench.

| Tag | Role | Firmware |
|-----|------|----------|
| A | repeater (inline) | `wismesh-tag-repeater` |
| B | repeater (inline) | `wismesh-tag-repeater` |
| E | repeater (inline) | `wismesh-tag-repeater` |
| C | companion (source) | `wismesh-tag-client-ble` |
| D | companion (dest) | `wismesh-tag-client-ble` |

Typical 3-hop direct path: **C→A→B→E→D**. USB `tio` tails on repeaters in the path (e.g. A, B, E).

## OTA bench (WisMesh Tag)

| Tag | Role | Bootloader |
|-----|------|------------|
| A (seeder) | `wismesh-tag-repeater` — OTA-capable + `OTA_FOLDER_SERIAL`; USB to laptop | stock OK |
| B (DUT) | `wismesh-tag-repeater` — device under test | **`bootloader/` OTAFIX required** (WisMesh Tag BL beeps 3× on DFU entry) |
| C (companion) | `wismesh-tag-client-ble` — remote `ota` CLI over mesh | stock OK |
| D (companion) | `wismesh-tag-client-ble` — second companion on deck | stock OK |

Flow: `motatool serve --dir ./build/motas/<ver> --serial …` → Tag A advertises `.mota` over LoRa → Tag B fetch/install → Tag C/D remote admin.

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
- meshcore-dev PRs (sync `feature/*` + `envyos/main` while open): [#2980](https://github.com/meshcore-dev/MeshCore/pull/2980) next-hop retry, [#2991](https://github.com/meshcore-dev/MeshCore/pull/2991) log tail, [#3012](https://github.com/meshcore-dev/MeshCore/pull/3012) boot fsck (draft — pending bench verify of recovery path; root cause: corrupt lfs + lazy `lfs_deorphan` on first FS write → freeze; corruption source incl. repeater `.mota` staging over ExtraFS 0xD4000 then re-role to companion)
- vk496 PRs open for role-aware OTA staging ceiling (`feature/ota-stage-ceiling` → merged on MeshEnvy `envyos/main`; pending on vk496): MeshCore #3, motatool #1, OTAFIX #2
- vk496 MeshCore #4 (stacked on #3): slim RAK4631 repeater role (`feature/ota-slim-repeater` → merged on MeshEnvy `envyos/main`)
