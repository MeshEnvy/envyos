# EnvyOS — agent memory

MeshEnvy's MeshCore distro: OTA over LoRa, routing improvements, and repeater enhancements. **Orchestration repo** — `ENVYOS_VERSIONS`, `COMPONENTS.lock`, distro publish/verify. Component repos are **workspace siblings** under `$MESHENVY_ROOT/`.

## Workspace siblings (`$MESHENVY_ROOT` = parent of `envyos/`)

| Path | Role |
|------|------|
| `envycore/` | Firmware — `scripts/build-mota.sh`, `build/motas/` |
| `bootloader/` | EnvyBoot OTAFIX — `scripts/build-bl.sh`, `build/` |
| `motatool/` | Bench CLI — CI releases; local cache `dist/<ver>/` |
| `peaky_finders/` | RF planner — CI releases; mirrored into distro when `peaky=` pinned |
| `mcmt-gateway/` | MT↔MC bridge (distro bundle from v0.2.0) |
| `envyos/envyos17/` | This repo — orchestration only |

## Repo layout (envyos17)

| Path | Role |
|------|------|
| `ENVYOS_VERSIONS` | Component semver — `distro`, `firmware`, `bootloader`, `motatool`; optional `peaky=`, `mcmt-gateway=` |
| `COMPONENTS.lock` | Git SHAs for git-pinned siblings (updated at publish) |
| `scripts/` | `build.sh` (delegates to siblings), `publish.sh`, `version.sh`, `verify-components.sh` |
| `apps/app/` | Flutter MeshCore client submodule |

## Branch model

| Repo | Release | Integration |
|------|---------|-------------|
| envyos17 | `main` | `dev` |
| envycore, bootloader, motatool, mcmt-gateway | `envyos/main` | `envyos/dev` |

Bench day-to-day: checkout **`dev`** / **`envyos/dev`**. Publish cherry-picks to release branches.

Policy: [`docs/component-release-policy.md`](docs/component-release-policy.md).

## Git remotes (`envycore/` — `$MESHENVY_ROOT/envycore`)

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

**`envyos/main`** on each fork = **release line**. **`envyos/dev`** = integration WIP. Feature branches merge into **`envyos/dev`**; publish cherry-picks to **`envyos/main`**. See `.cursor/skills/envyos-meshcore/SKILL.md`.

## Distro git (`main` / `dev` + upstream PR branches)

Each OTA-stack repo has **two branch roles**:

| Role | Branch | Where | Use |
|------|--------|-------|-----|
| **Distro integration** | `dev` (envyos17) / `envyos/dev` (components) | MeshEnvy fork | Bench WIP |
| **Distro release** | `main` / `envyos/main` | Same | Published pins in `COMPONENTS.lock` |

**PR bases** (not the same as `envyos/main`):

| Component | Remote | PR base branch | Example PR branch |
|-----------|--------|----------------|-------------------|
| `envycore/` | `meshcore-dev/MeshCore` | `dev` | `feature/next-hop-retry`, `feature/log-tail-serial` |
| `envycore/` | `vk496/MeshCore` | `feature/ota-lora` | `feature/ota-stage-ceiling` |
| motatool (external) | `vk496/motatool` | `main` | … |
| `bootloader/` | `vk496/Adafruit_nRF52_Bootloader_OTAFIX` | `feature/ota-delta-apply` | … |

Workflow: branch `feature/<name>` from PR base → implement → open cross-fork PR → merge into **`envyos/dev`**. Pin SHAs in `COMPONENTS.lock` at distro publish.

Skill: `.cursor/skills/envyos-meshcore/SKILL.md`.

## Open upstream PRs (`envycore/`)

MeshEnvy fork: `origin` → `MeshEnvy/meshcore-firmware`. Cross-fork PRs use `--head MeshEnvy:feature/<name>`.

| Feature | PR branch | Upstream repo | PR | Base | Also on `envyos/dev` |
|---------|-----------|---------------|-----|------|------------------------|
| Next-hop retry (echo-primary) | `feature/next-hop-retry` | [meshcore-dev/MeshCore](https://github.com/meshcore-dev/MeshCore) | [#2980](https://github.com/meshcore-dev/MeshCore/pull/2980) | `dev` | yes |
| Log tail serial | `feature/log-tail-serial` | [meshcore-dev/MeshCore](https://github.com/meshcore-dev/MeshCore) | [#2991](https://github.com/meshcore-dev/MeshCore/pull/2991) | `dev` | yes |
| FS corruption boot fsck (companion) | `feature/fs-corruption-check` | [meshcore-dev/MeshCore](https://github.com/meshcore-dev/MeshCore) | [#3012](https://github.com/meshcore-dev/MeshCore/pull/3012) (draft) | `dev` | yes |

**Sync rule:** while a PR is open, commits for that feature go to **`envyos/dev` and the PR branch** (push both). Unrelated features stay separate. See skill § Open PR sync policy.

vk496 / motatool / otafix PRs: see **Active threads** below and `envyos-meshcore` skill PR table.

Sibling checkouts live at `$MESHENVY_ROOT/{envycore,bootloader,motatool,mcmt-gateway}/`.

## Released versions (immutable)

| Version | Status | Canonical artifacts |
|---------|--------|---------------------|
| **v0.1.0** | **Released** — frozen, do not rebuild or delete | [GitHub Release](https://github.com/MeshEnvy/envyos/releases/tag/v0.1.0) · **`firmware-v0.1.0.zip`** · **`build/motas/v0.1.0/`** |
| **v0.1.1** | **Released** — frozen, do not rebuild or delete | [GitHub Release](https://github.com/MeshEnvy/envyos/releases/tag/v0.1.1) · **`firmware-v0.1.1.zip`** · **`build/motas/v0.1.1/`** |

- Listed in **`RELEASED_VERSIONS`**; released component trees (`.released` markers) are immutable.
- **Canonical off-machine copy:** GitHub Release on **`v<distro>`** — `firmware-*.zip`, `bootloader-*.zip`, `motatool-*.zip`, optional `peaky-*.zip`. Local caches: **`envycore/build/motas/`**, **`bootloader/build/`**, **`motatool/dist/`**, **`peaky_finders/dist/`**.
- **`./scripts/publish.sh [version]`** — after `./scripts/build.sh` + bench verify: lock components, zip, GitHub Release, bump **`ENVYOS_VERSIONS`**. mcmt-gateway from distro v0.2.0; peaky when `peaky=` is set.

## Versioning

- **`ENVYOS_VERSIONS`** at repo root — bump together on `/freshen`:
  - `distro` → git tags `v0.1.x`; firmware artifacts under **`envycore/build/motas/<distro>/`**
  - `firmware` → must match `envycore/envyos/VERSION`; built by **`envycore/scripts/build-mota.sh`**
  - `bootloader` → **`$MESHENVY_ROOT/bootloader/build/<bootloader>/`**
  - `motatool` → mirrored into distro release; cache **`motatool/dist/<ver>/`**
  - `peaky` → mirrored when `peaky=` pinned; cache **`peaky_finders/dist/<ver>/`** via `gh release download`
- **Firmware build:** `$MESHENVY_ROOT/envycore/scripts/build-mota.sh` (or `./scripts/build.sh` from envyos bench). Requires **`motatool` on PATH** (or `motatool/dist/` fallback).

## OTA targets (`envycore/scripts/targets.txt`)

| Slug | PlatformIO env | Role |
|------|----------------|------|
| `wismesh-tag-repeater` | `RAK_WisMesh_Tag_repeater` | WisMesh Tag repeater (bench DUT) |
| `rak4631-repeater` | `RAK_4631_repeater` | RAK4631 repeater |
| `rak4631-repeater-slim` | `RAK_4631_repeater_slim` | RAK4631 slim repeater — no OLED/sensors/BLE (`BLE_DFU_DISABLED`; MCU temp only); ~180 KB smaller. **Staging headroom ~372 KB at current app size (434 KB app in the 815 KB 0x26000–0xED000 region) — a full slim `.mota` (~426 KB) does NOT fit; deltas only** (corrected 2026-07-25; full fits only if app ≤ ~406 KB) |
| `sensecap-p1pro-repeater-slim` | `SenseCap_Solar_repeater_slim` | SenseCAP Solar P1-Pro slim repeater — no GPS/sensors/BLE; S140 v7 app @ `0x27000`; OTAFIX `sensecap_solar_p1`. ~384 KB app → ~416 KB staging headroom (full `.mota` ~386 KB fits) |
| `rak4631-superseeder` | `RAK_4631_superseeder` | RAK4631 slim + RAK15002 SD — field superseeder (`OTA_SD_SEEDER`; promiscuous capture to `/motas/` on SD, serve all; flash staging reserved for self-update) |
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

Direct-path repeaters: after forward, upstream waits for the next hop's **echo** (same packet retransmitted downstream, including zero-hop last-mile forwards overheard on RF). Missed echo → retry (`hop.retry`, **default 0 = disabled, opt-in** — flipped 2026-07-25 for first EnvyOS 0.1.0 field units; base window `hop.retry.ms`, default 1500 ms, plus forward delay and packet airtime). Duplicate addressed to next hop → zero-hop **`HOP_ACK`** (control `0xA0`, ~14 B) instead of re-forwarding. Zero overhead when echo is heard. CLI: `set hop.retry`, `set hop.retry.ms`. Bench test: `set hop.ignore <count>` on downstream silently drops next N forward opportunities (not persisted).

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

## OTA field superseeder (RAK4631 + SD)

| Node | Role | Build | Bootloader |
|------|------|-------|------------|
| Superseeder | RAK4631 + RAK15002 SD module | `RAK_4631_superseeder` | OTAFIX if self-update needed |
| DUT | slim repeater in mesh | `RAK_4631_repeater_slim` | OTAFIX required |
| Laptop seeder (optional) | USB `motatool serve` + `ota folder on` | `wismesh-tag-repeater` or any OTA repeater | stock OK |

Superseeder auto-queries heard beacons, captures missing `.mota` files to SD (`/motas/<midhex>.mota`), and serves them over LoRa. CLI: `ota sd`. Flash staging below `MOTA_STAGE_CEILING` is for this node's own update only.

**Self-serve (any OTA node, no `.mota` file needed):** at announce time (`Mesh.cpp`) a node auto-runs `ota_serve_self()` — scans its app region for the EndF trailer (target/version/hw_id), builds merkle leaves + a synthetic full **unsigned** manifest, and serves its own running firmware from memory-mapped flash. Full image only, **uncompressed** (`CODEC_FULL` payload == raw image; only detools delta codecs are CRLE-compressed). Consequence: same-target peers of similar app size **cannot stage it** (full mota > their headroom) — self-serve full images feed SD superseeders / smaller-app roles; same-target version bumps travel as **motatool deltas**. Manual `ota install` accepts unsigned (merkle+hash integrity still enforced); auto-install requires signed+allowlisted.

Bench: laptop seeder advertises → superseeder captures (`ota sd` shows files) → detach laptop → DUT fetches/installs from superseeder alone (real version bump).

## Build commands

```bash
./scripts/build.sh                       # bootloader + envycore motas (motatool on PATH)
./scripts/build.sh --bootloader-only
./scripts/build.sh --mota-only --target rak4631-repeater-slim
./scripts/build-bl.sh
cd envycore && ./scripts/build-mota.sh   # firmware only → envycore/build/motas/<distro>/
cd envycore && ./scripts/build-mota.sh --list-targets
./scripts/publish.sh v0.1.2
# USB seeder — motatool repo:
/path/to/motatool/scripts/seeder.sh /dev/cu.usbmodem1444301
/path/to/motatool/scripts/seeder.sh usbmodem1444301 envycore/build/motas/v0.1.2
```

## Conflict hotspots

When merging upstream into `envyos/main`: `Mesh.cpp`, `CommonCLI.*`, `platformio.ini`, OTA test mocks.

## Freshen (`/freshen`)

**Fleet policy:** `companion-v*` + cherry-picked OTA commits + EnvyOS overlay → bump **`ENVYOS_VERSIONS`**, `envycore/scripts/build-mota.sh`, tag **`v<distro>`**. Backup of pre-reset main: `envyos/main-pre-companion-reset` in `envycore/`.

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
| `envyos-scripts` | `scripts/build.sh`, `build-bl.sh`, `publish.sh`; firmware in `envycore/scripts/build-mota.sh` |
| `motatool` | `.mota` build, deltas, verify, serve |

## Active threads

<!-- In-flight work only; delete when done -->
- **P0 (operator, 2026-07-31): advert lockup on `rak4631-repeater-slim`** — admin settings change then advert → freeze; **adverts disabled in field**. Ops: `initiatives/envyos-field-stability.md`.
- **Watchdog:** port from meshcore [#1417](https://github.com/meshcore-dev/MeshCore/pull/1417), [#2405](https://github.com/meshcore-dev/MeshCore/pull/2405), [#1962](https://github.com/meshcore-dev/MeshCore/pull/1962); note [#2952](https://github.com/meshcore-dev/MeshCore/pull/2952) merged (power-saving feed change).
- **Hop retry / mcsim:** [#2980](https://github.com/meshcore-dev/MeshCore/pull/2980) — usrflo mcsim ACK regression; keep **hop.retry=0** on fleet. Doc: `ops/docs/2026-07-31-meshcore-pr-2980-mcsim-discussion.md`.
- **Mota matrix:** `envycore/scripts/build-mota.sh` emits `delta_from_<B>.mota` for every prior version B that has base hex for that slug (new targets skip older bases).
- meshcore-dev PRs (sync `feature/*` + `envyos/main` while open): [#2980](https://github.com/meshcore-dev/MeshCore/pull/2980) next-hop retry, [#2991](https://github.com/meshcore-dev/MeshCore/pull/2991) log tail, [#3012](https://github.com/meshcore-dev/MeshCore/pull/3012) boot fsck (draft — pending bench verify of recovery path; root cause: corrupt lfs + lazy `lfs_deorphan` on first FS write → freeze; corruption source incl. repeater `.mota` staging over ExtraFS 0xD4000 then re-role to companion)
- vk496 PRs open for role-aware OTA staging ceiling (`feature/ota-stage-ceiling` → merged on MeshEnvy `envyos/main`; pending on vk496): MeshCore #3, motatool #1, OTAFIX #2
- vk496 MeshCore #4 (stacked on #3): slim RAK4631 repeater role (`feature/ota-slim-repeater` → merged on MeshEnvy `envyos/main`)
- vk496 MeshCore [#5](https://github.com/vk496/MeshCore/pull/5) (stacked on `feature/ota-lora`): SD superseeder (`feature/ota-superseeder` → merged on MeshEnvy `envyos/main`; bench pending)
- **Direction (operator, 2026-07-23): firmware SD superseeders (32 GB cards) replace `motatool serve` as the seeding path** — "being tethered to an external device is a chronic failure point." Don't invest further in serve-based seeding; motatool remains for pack/verify/delta. Enterprise context: `ops/initiatives/regional-ingestors.md`.
- **Candidate enhancement (operator, 2026-07-25): compressed-full codec (heatshrink) for self-serve** — firmware produces a heatshrink `.mota` of its own running image (like motatool would), closing the ~55 KB gap that stops same-target peers from staging a full slim image (~426 KB mota vs ~372 KB headroom). Enables laptop-free epidemic full-image seeding between identical repeaters. Scope: new codec in OtaFormat + motatool parity + decode in the apply path (OTAFIX applies staged motas, so the bootloader is in scope too). Greenfield rules apply. **Not a showstopper — delta seeder covers today's need**; candidate for pre-Orlando OTA polish or later.
- **Candidate feature (operator, 2026-07-23): MeshCore MQTT client** — publish/subscribe channel messages ↔ broker topics, incl. parsing Meshtastic JSON topics for cross-mesh bridging. Likely home is **Lotato** (`lobbs/lotato/lotato/` — has WiFi/batching/dedup; today HTTP-POSTs to PotatoMesh), not EnvyOS; EnvyOS relevance is if the feature later lands in the distro. Consumers: ingestor edge, Burning Mesh bridge (~Aug 16), Elko interop. Context: `ops/initiatives/regional-ingestors.md`.
