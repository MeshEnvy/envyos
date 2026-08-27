# EnvyOS — agent memory

MeshEnvy's MeshCore distro: OTA over LoRa, routing improvements, and repeater enhancements. **Distro repo** — `./envyos` CLI, `ENVYOS_VERSIONS`, `packages-meta/`, `COMPONENTS.lock`, publish/verify. Upstream forks live under **`packages/`** (gitignored checkouts); identity and overlay notes live in **`packages-meta/`**.

## Layout

| Path | Role |
|------|------|
| `packages/` | Gitignored workbenches — `meshcore`, `bootloader`, `motatool`, `mcmt-gateway`, `meshcore-open` |
| `packages-meta/<pkg>/` | Tracked recipe — `PACKAGE`, **`build.sh`**, `VERSION` (`upstream` + `ev`), `CHANGELOG.md`, `RELEASED`, `BACKLOG.md` (meshcore) |
| `scripts/` | Shared distro machinery — `envyos` CLI, `version.sh`, `build-lib.sh`, `build-all.sh`, `publish.sh`, `targets.txt` (recipes live in `packages-meta/<pkg>/build.sh`) |
| `build/` | Bench (`build/<branch>/bench/…`) and immutable `build/vX.Y.Z/` after publish |
| `ENVYOS_VERSIONS` | Pinned package versions (`meshcore=1.16.0-ev1`, …) |
| `peaky_finders/` | Workspace sibling — GitHub releases when `peaky=` pinned |
| `packages/meshcore-open/` | Flutter MeshCore client workbench (`MeshEnvy/meshcore-open`; `./envyos fetch meshcore-open`) |

Doctrine: [`docs/distro-packaging.md`](docs/distro-packaging.md).

## Branch model

| Repo | Release | Integration |
|------|---------|-------------|
| envyos | `main` | `dev` |
| `packages/*` forks | `envyos/main` | `envyos/dev` |

Bench day-to-day: checkout **`dev`** on envyos and **`envyos/dev`** on package forks. Publish cherry-picks to release branches.

Policy: [`docs/component-release-policy.md`](docs/component-release-policy.md). Packaging: [`docs/distro-packaging.md`](docs/distro-packaging.md) (replaces retired package-maintainer guide).

## Git remotes (`packages/meshcore`)

| Remote | Repository | Role |
|--------|------------|------|
| `origin` | `MeshEnvy/meshcore-firmware` | EnvyOS fork — push features here |
| `vk496` | `vk496/MeshCore` | OTA / vk496 stack |
| `meshcore` | `meshcore-dev/MeshCore` | Upstream MeshCore |

## Git remotes (`packages/bootloader`)

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
| **Distro integration** | `dev` (envyos) / `envyos/dev` (components) | MeshEnvy fork | Bench WIP |
| **Distro release** | `main` / `envyos/main` | Same | Published pins in `COMPONENTS.lock` |

**PR bases** (not the same as `envyos/main`):

| Component | Remote | PR base branch | Example PR branch |
|-----------|--------|----------------|-------------------|
| `packages/meshcore` | `meshcore-dev/MeshCore` | `dev` | `feature/next-hop-retry`, `feature/log-tail-serial` |
| `packages/meshcore` | `vk496/MeshCore` | `feature/ota-lora` | `feature/ota-stage-ceiling` |
| motatool (external) | `vk496/motatool` | `main` | … |
| `bootloader/` | `vk496/Adafruit_nRF52_Bootloader_OTAFIX` | `feature/ota-delta-apply` | … |

Workflow: branch `feature/<name>` from PR base → implement → open cross-fork PR → merge into **`envyos/dev`**. Pin SHAs in `COMPONENTS.lock` at distro publish.

Skill: `.cursor/skills/envyos-meshcore/SKILL.md`.

## Open upstream PRs (`packages/meshcore`)

MeshEnvy fork: `origin` → `MeshEnvy/meshcore-firmware`. Cross-fork PRs use `--head MeshEnvy:feature/<name>`.

| Feature | PR branch | Upstream repo | PR | Base | Also on `envyos/dev` |
|---------|-----------|---------------|-----|------|------------------------|
| Next-hop retry (echo-primary) | `feature/next-hop-retry` | [meshcore-dev/MeshCore](https://github.com/meshcore-dev/MeshCore) | [#2980](https://github.com/meshcore-dev/MeshCore/pull/2980) | `dev` | yes |
| Log tail serial | `feature/log-tail-serial` | [meshcore-dev/MeshCore](https://github.com/meshcore-dev/MeshCore) | [#2991](https://github.com/meshcore-dev/MeshCore/pull/2991) | `dev` | yes |
| FS corruption boot fsck (companion) | `feature/fs-corruption-check` | [meshcore-dev/MeshCore](https://github.com/meshcore-dev/MeshCore) | [#3012](https://github.com/meshcore-dev/MeshCore/pull/3012) (draft) | `dev` | yes |

**Sync rule:** while a PR is open, commits for that feature go to **`envyos/dev` and the PR branch** (push both). Unrelated features stay separate. See skill § Open PR sync policy.

vk496 / motatool / otafix PRs: see **Active threads** below and `envyos-meshcore` skill PR table.

Sibling checkouts live at ``packages/{meshcore,bootloader,motatool,mcmt-gateway,meshcore-open}` (+ peaky sibling)`.

## Released versions (immutable)

| Version | Status | Canonical artifacts |
|---------|--------|---------------------|
| **v0.1.0** | **Released** — frozen, do not rebuild or delete | [GitHub Release](https://github.com/MeshEnvy/envyos/releases/tag/v0.1.0) · **`firmware-v0.1.0.zip`** · **`build/motas/v0.1.0/`** |
| **v0.1.1** | **Released** — frozen, do not rebuild or delete | [GitHub Release](https://github.com/MeshEnvy/envyos/releases/tag/v0.1.1) · **`firmware-v0.1.1.zip`** · **`build/motas/v0.1.1/`** |

- Listed in **`RELEASED_VERSIONS`**; released component trees (`.released` markers) are immutable.
- **Canonical off-machine copy:** GitHub Release on **`v<distro>`** — `firmware-*.zip`, `bootloader-*.zip`, `motatool-*.zip`, optional `peaky-*.zip`. Local caches: **`packages/meshcore/build/motas/`**, **`build/…/bench/bootloader-…/`**, **`build/…/bench/motatool-…/`**, **`peaky_finders/dist/`**.
- **`./scripts/publish.sh [version]`** — after `./envyos build`: promote `build/<branch>/bench/` → `build/vX.Y.Z/`, lock, GitHub Release. Suggests tag from CHANGELOG when version omitted (`docs/distro-semver.md`). Sets `distro=` + `firmware=` in `ENVYOS_VERSIONS` at publish.

## Versioning

- **`ENVYOS_VERSIONS`** — component pins (`firmware`, `bootloader`, `motatool`, optional `peaky`, `mcmt-gateway`). **`distro=`** is the draft/published git tag, written at publish.
- **Dev bench path:** `build/<git-branch>/bench/{firmware,bootloader,motatool}-<ver>/` (not `build/<distro>/`).
- **Published path:** `build/vX.Y.Z/` (immutable after lock).
- `meshcore=` in `ENVYOS_VERSIONS` → `packages-meta/meshcore/VERSION`; built by **`packages-meta/meshcore/build.sh`**
- `bootloader` → **`build/<branch>/bench/bootloader-<ver>/`**
- `motatool` → **`build/<branch>/bench/motatool-<ver>/`** (artifact); working copy under bench motatool tree
- `peaky` → local `cargo build` when pinned
- **Firmware build:** `./envyos build meshcore` (dispatches to `packages-meta/meshcore/build.sh`). Requires staged **`motatool`** on PATH (`./envyos build motatool`) or **`MOTATOOL=`** override.

## OTA targets (`scripts/targets.txt`)

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
./envyos build                             # pinned packages (motatool before meshcore)
./envyos build --bootloader-only
./envyos build --mota-only --target rak4631-repeater-slim
./envyos build bootloader
./envyos build meshcore                    # firmware only → bench firmware tree
./envyos build meshcore --list-targets
./scripts/publish.sh v0.1.2
# USB seeder — motatool repo:
/path/to/motatool/scripts/seeder.sh /dev/cu.usbmodem1444301
packages/meshcore/scripts/seeder.sh or motatool serve on bench firmware dir
```

## Conflict hotspots

When merging upstream into `envyos/main`: `Mesh.cpp`, `CommonCLI.*`, `platformio.ini`, OTA test mocks.

## Integrate (`/integrate`, `/freshen`)

**Policy:** meshcore `companion-v*` merged into `envyos/main` (preserve OTA + overlay). vk496 = OTA upstream PR target only, not integrate remote. Integrate manifest: tracked in meshcore fork workflow (see `envyos-freshen` skill). Skill: `.cursor/skills/envyos-freshen/SKILL.md`. Doc: [`docs/integration-policy.md`](docs/integration-policy.md).

| Command | Purpose | EnvyOS version? |
|---------|---------|-----------------|
| `/integrate` | Companion bump + overlay | **After** bench + publish |
| `/freshen dev` | `meshcore/dev` spike | **No** |

## OTA greenfield

Pre-deployment — **no production fleet, no field migrations**. Breaking `.mota`/protocol/EndF changes are OK; rebuild artifacts and update docs instead of compat shims. Skill: `.cursor/skills/ota-greenfield/SKILL.md`.

## Agent skills

| Skill | When to load |
|-------|----------------|
| `envyos-package` | Legacy component harness (retired — see `distro-packaging`) |
| `envyos-freshen` | `/integrate` / `/freshen` — companion merge; `/freshen dev` spike only |
| `envyos-meshcore` | Git remotes, feature branches, upstream PRs |
| `envyos-ota` | OTA protocol, device CLI, codecs, bench roles |
| `ota-greenfield` | OTA format/protocol/tooling changes — no legacy or migration paths |
| `envyos-scripts` | `./envyos build`, `packages-meta/*/build.sh` recipes, `publish.sh` |
| `motatool` | `.mota` build, deltas, verify, serve |

## Active threads

<!-- In-flight work only; delete when done -->
- **Meshcore backlog split (2026-08-25):** EC-001–EC-009 on separate `feature/*` branches; canonical queue `packages/meshcore/BACKLOG.md`. **`envyos/main` stays v1.16 / 0.1.3** until items pulled deliberately. Monolith preserved at tag `envyos/dev-pre-split`.
- **P0 (operator, 2026-07-31): advert lockup on `rak4631-repeater-slim`** — admin settings change then advert → freeze; **adverts disabled in field**. Ops: `initiatives/envyos-field-stability.md`.
- **Watchdog:** port from meshcore [#1417](https://github.com/meshcore-dev/MeshCore/pull/1417), [#2405](https://github.com/meshcore-dev/MeshCore/pull/2405), [#1962](https://github.com/meshcore-dev/MeshCore/pull/1962); note [#2952](https://github.com/meshcore-dev/MeshCore/pull/2952) merged (power-saving feed change).
- **Hop retry / mcsim:** [#2980](https://github.com/meshcore-dev/MeshCore/pull/2980) — usrflo mcsim ACK regression; keep **hop.retry=0** on fleet. Doc: `ops/docs/2026-07-31-meshcore-pr-2980-mcsim-discussion.md`.
- **Mota matrix:** `packages-meta/meshcore/build.sh` emits `delta_from_<B>.mota` for every prior version B that has base hex for that slug (new targets skip older bases).
- meshcore-dev PRs (sync `feature/*` + `envyos/main` while open): [#2980](https://github.com/meshcore-dev/MeshCore/pull/2980) next-hop retry, [#2991](https://github.com/meshcore-dev/MeshCore/pull/2991) log tail, [#3012](https://github.com/meshcore-dev/MeshCore/pull/3012) boot fsck (draft — pending bench verify of recovery path; root cause: corrupt lfs + lazy `lfs_deorphan` on first FS write → freeze; corruption source incl. repeater `.mota` staging over ExtraFS 0xD4000 then re-role to companion)
- vk496 OTA PRs (contribution target; merged on `envyos/main`): MeshCore #3 staging ceiling, motatool #1, OTAFIX #2, #4 slim, [#5](https://github.com/vk496/MeshCore/pull/5) superseeder
- **Direction (operator, 2026-07-23): firmware SD superseeders (32 GB cards) replace `motatool serve` as the seeding path** — "being tethered to an external device is a chronic failure point." Don't invest further in serve-based seeding; motatool remains for pack/verify/delta. Enterprise context: `ops/initiatives/regional-ingestors.md`.
- **Candidate enhancement (operator, 2026-07-25): compressed-full codec (heatshrink) for self-serve** — firmware produces a heatshrink `.mota` of its own running image (like motatool would), closing the ~55 KB gap that stops same-target peers from staging a full slim image (~426 KB mota vs ~372 KB headroom). Enables laptop-free epidemic full-image seeding between identical repeaters. Scope: new codec in OtaFormat + motatool parity + decode in the apply path (OTAFIX applies staged motas, so the bootloader is in scope too). Greenfield rules apply. **Not a showstopper — delta seeder covers today's need**; candidate for pre-Orlando OTA polish or later.
- **Candidate feature (operator, 2026-07-23): MeshCore MQTT client** — publish/subscribe channel messages ↔ broker topics, incl. parsing Meshtastic JSON topics for cross-mesh bridging. Likely home is **Lotato** (`lobbs/lotato/lotato/` — has WiFi/batching/dedup; today HTTP-POSTs to PotatoMesh), not EnvyOS; EnvyOS relevance is if the feature later lands in the distro. Consumers: ingestor edge, Burning Mesh bridge (~Aug 16), Elko interop. Context: `ops/initiatives/regional-ingestors.md`.
