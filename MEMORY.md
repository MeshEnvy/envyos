# EnvyOS — agent memory

MeshEnvy's MeshCore distro: OTA over LoRa, routing improvements, and repeater enhancements. Firmware lives in `envycore/` (submodule); this repo (`ota`) holds build tooling, `.mota` artifacts, and the bench workflow.

## Repo layout

| Path | Role |
|------|------|
| `envycore/` | MeshCore firmware submodule (`MeshEnvy/meshcore-firmware`); **`envyos/main`** is distro head |
| `ENVYOS_VERSIONS` | Dev HEAD semver — independent `distro`, `firmware`, `bootloader`, `motatool` (currently **v0.1.3**) |
| `CHANGELOG.md` | EnvyOS-owned release notes. MeshCore companion bumps link upstream. |
| `envyos` | CLI symlink → `scripts/envyos` — `./envyos build|bump|publish|info` |
| `build/` | Local build outputs (gitignored) — `build/firmware/<firmware>/`, `build/bootloader/<bootloader>/`, `build/motatool/<motatool>/` (dev); **`build/releases/<distro>/`** (published bundle snapshot) |
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
| Defer remote admin CLI | `feature/defer-remote-cli` | [meshcore-dev/MeshCore](https://github.com/meshcore-dev/MeshCore) | [#3196](https://github.com/meshcore-dev/MeshCore/pull/3196) (draft) | `dev` | yes |
| FS corruption boot fsck (companion) | `feature/fs-corruption-check` | [meshcore-dev/MeshCore](https://github.com/meshcore-dev/MeshCore) | [#3012](https://github.com/meshcore-dev/MeshCore/pull/3012) (draft) | `dev` | yes |

**Sync rule:** while a PR is open, commits for that feature go to **`envyos/main` and the PR branch** (push both). Unrelated features stay separate. See skill § Open PR sync policy.

vk496 / motatool / otafix PRs: see **Active threads** below and `envyos-meshcore` skill PR table.

**Do not** clone a standalone otafix checkout — only the **`bootloader/`** submodule.

## Released versions (immutable)

| Version | Status | Canonical artifacts |
|---------|--------|---------------------|
| **v0.1.0** | **Released** distro — frozen firmware tree | [GitHub Release](https://github.com/MeshEnvy/envyos/releases/tag/v0.1.0) · flat assets · **`build/firmware/v0.1.0/`** |
| **v0.1.1** | **Released** distro — frozen firmware tree | [GitHub Release](https://github.com/MeshEnvy/envyos/releases/tag/v0.1.1) · flat assets · **`build/firmware/v0.1.1/`** |

- **Notes:** [`CHANGELOG.md`](CHANGELOG.md) — EnvyOS-owned only. MeshCore companion bumps link upstream. Publish requires a `## [vX.Y.Z]` section.
- Distro tags in **`RELEASED_DISTROS`**; firmware artifact trees in **`RELEASED_FIRMWARE`** (`.released` markers immutable).
- **Canonical local bundle:** `build/releases/<distro>/` — flat release files (GitHub uploads), local `ASSETS` manifest, `RELEASE_MANIFEST` after lock.
- **Canonical off-machine copy:** GitHub Release on **`v<distro>`** — flat files from `build/releases/<distro>/`.
- Delta bases read prior **released firmware** trees (`build/firmware/v0.1.0/`, …).
- **`./envyos publish --dry-run`** — verify + list planned assets (no writes)
- **`./envyos publish stage`** → **`finalize`** → **`upload v<distro>`** — stepwise publish
- **`./envyos publish`** — full publish. Does **not** change `ENVYOS_VERSIONS`.
- **Legacy migration:** if `build/motas/` exists, `mv build/motas build/firmware`.

## Versioning

- **`ENVYOS_VERSIONS`** — dev HEAD; components bump independently via **`./envyos bump patch|minor|major <component>`**:
  - `distro` → next bundle to publish (git tag `v<distro>`); bump via **`./envyos bump patch distro`**
  - `firmware` → `-DFIRMWARE_VERSION`, **`build/firmware/<firmware>/`** (must match `envycore/envyos/VERSION`)
  - `bootloader` → **`build/bootloader/<bootloader>/`**
  - `motatool` → `motatool/Cargo.toml` (first tracked **v0.1.0**), **`build/motatool/<motatool>/motatool-<platform>`** — default build stages all four release platforms; **linux-* via `docker/motatool-build/`**, **darwin-* native on macOS**; publish requires all four
- **Build identity:** `./scripts/build-mota.sh` stamps **`v<semver>-<envycore-sha>`** into `-DFIRMWARE_VERSION`, UTC time into `-DFIRMWARE_BUILD_DATE`; device `ver` → `v0.1.3-abc1234 (Build: 13 Aug 2026 05:00 UTC)`. Host copy: **`build/firmware/<ver>/<slug>/version.txt`** (semver, stamp, sha).
- **Publish** snapshots component versions into **`build/releases/<distro>/RELEASE_MANIFEST`** (includes submodule SHAs).
- **Earns firmware version:** release freshen bundle (`envycore/FRESHEN.lock`) + `./envyos bump firmware` + `./envyos build firmware`.
- Helpers: **`scripts/version.sh`** — `bump_component`, `read_*_version`, `list_envyos_versions`, `changelog_notes_for_distro`
- `./scripts/build-mota.sh` defaults to **`read_firmware_version`**; override: `./scripts/build-mota.sh v0.1.1`
- Stock MeshCore (no EndF/OTA): `./envyos build firmware --hex-only`

## OTA targets (`scripts/targets.txt`)

| Slug | PlatformIO env | Role |
|------|----------------|------|
| `wismesh-tag-repeater` | `RAK_WisMesh_Tag_repeater` | WisMesh Tag repeater (bench DUT) |
| `rak4631-repeater` | `RAK_4631_repeater` | RAK4631 repeater |
| `rak4631-repeater-slim` | `RAK_4631_repeater_slim` | RAK4631 slim repeater — no OLED/sensors/BLE (`BLE_DFU_DISABLED`; MCU temp only); ~180 KB smaller. **Staging headroom ~372 KB at current app size (434 KB app in the 815 KB 0x26000–0xED000 region) — a full slim `.mota` (~426 KB) does NOT fit; deltas only** (corrected 2026-07-25; full fits only if app ≤ ~406 KB) |
| `sensecap-p1pro-repeater-slim` | `SenseCap_Solar_repeater_slim` | SenseCAP Solar P1-Pro slim repeater — no GPS/sensors/BLE; S140 v7 app @ `0x27000`; OTAFIX `sensecap_solar_p1`. ~384 KB app → ~416 KB staging headroom (full `.mota` ~386 KB fits) |
| `sensecap-p1pro-superseeder` | `SenseCap_Solar_superseeder` | SenseCAP P1-Pro mini-superseeder — slim + 2 MB QSPI NOR LittleFS (`OTA_SUPERSEEDER` + `OTA_SUPERSEEDER_QSPI`); allowlisted **deltas only** to `/motas/`; flash staging for self-update |
| `rak4631-superseeder` | `RAK_4631_superseeder` | RAK4631 slim + RAK15002 SD — field superseeder (`OTA_SUPERSEEDER` + `OTA_SUPERSEEDER_SD`); allowlisted **deltas only** to `/motas/` on SD; flash staging for self-update |
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

Flow: `motatool serve --dir ./build/firmware/<firmware> --serial …` → Tag A advertises `.mota` over LoRa → Tag B fetch/install → Tag C/D remote admin.

## OTA field superseeder (SD or NOR)

| Node | Role | Build | Bootloader |
|------|------|-------|------------|
| SD superseeder | RAK4631 + RAK15002 SD | `RAK_4631_superseeder` | OTAFIX if self-update needed |
| NOR mini-superseeder | SenseCAP P1-Pro (2 MB QSPI) | `SenseCap_Solar_superseeder` | OTAFIX if self-update needed |
| DUT | slim repeater in mesh | `*_repeater_slim` | OTAFIX required |
| Laptop seeder (optional) | USB `motatool serve` + `ota folder on` | `wismesh-tag-repeater` or any OTA repeater | stock OK |

Superseeder auto-queries heard beacons and captures **deltas only** to external FS (`/motas/<midhex>.mota` on SD or QSPI LittleFS). Full snapshots are never stored (self-serve / USB bootstrap cover those). Default target filter is **all targets**; narrow with `ota seed allow add|rm|list|clear|reset` (persisted). `clear` = empty filter (admit none); `reset`/`defaults` = admit all. CLI: `ota seed` (alias `ota sd`). Flash staging below `MOTA_STAGE_CEILING` is for this node's own update only.

**Self-serve (any OTA node, no `.mota` file needed):** at announce time (`Mesh.cpp`) a node auto-runs `ota_serve_self()` — scans its app region for the EndF trailer (target/version/hw_id), builds merkle leaves + a synthetic full **unsigned** manifest, and serves its own running firmware from memory-mapped flash. Full image only, **uncompressed** (`CODEC_FULL` payload == raw image; only detools delta codecs are CRLE-compressed). Consequence: same-target peers of similar app size **cannot stage it** (full mota > their headroom) — self-serve full images feed SD superseeders / smaller-app roles; same-target version bumps travel as **motatool deltas**. Manual `ota install` accepts unsigned (merkle+hash integrity still enforced); auto-install requires signed+allowlisted.

Bench: laptop seeder advertises → superseeder captures (`ota seed` shows files) → detach laptop → DUT fetches/installs from superseeder alone (real version bump).

## Build commands

```bash
./envyos info
./envyos build                             # bootloader + firmware + motatool (all platforms)
./envyos build motatool --host-only        # bench: host platform only
./envyos build firmware --target rak4631-repeater-slim
./envyos bump patch firmware
./envyos publish --dry-run
./envyos publish stage
./envyos publish finalize
./envyos publish upload v0.1.2
./envyos publish                           # full publish after fleet deploy

./scripts/build.sh                         # same as envyos build (legacy entry)
./scripts/build-bl.sh --list-boards
./scripts/build-mota.sh --list-targets
./scripts/build-mota.sh                    # → build/firmware/<firmware>/
./scripts/build-mota.sh v0.1.2 --base v0.1.0
./scripts/seeder.sh /dev/cu.usbmodem1444301
./scripts/seeder.sh /dev/cu.… ./build/firmware/v0.1.2
```

## Conflict hotspots

When merging upstream into `envyos/main`: `Mesh.cpp`, `CommonCLI.*`, `platformio.ini`, OTA test mocks.

## Freshen (`/freshen`)

**Fleet policy:** `companion-v*` + cherry-picked OTA commits + EnvyOS overlay → bump **`ENVYOS_VERSIONS`**, `./scripts/build-mota.sh`, tag **`v<distro>`**. Backup of pre-reset main: `envyos/main-pre-companion-reset` in `envycore/`.

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
| `envyos-scripts` | `./envyos` CLI, `scripts/build-mota.sh`, `build-bl.sh`, `seeder.sh`, `publish.sh` |
| `motatool` | `.mota` build, deltas, verify, serve |
| `incident` | Field bug / outage postmortems → `docs/incidents/` (see also `ops/.cursor/skills/incident/SKILL.md`) |

## Incidents

Postmortems live in [`docs/incidents/`](docs/incidents/). Index:

| Date | Slug | Status |
|------|------|--------|
| 2026-08-13 | [remote-admin-advert-lockup](docs/incidents/2026-08-13-remote-admin-advert-lockup.md) | Fixed on bench; upstream PR prep |

## Active threads

<!-- In-flight work only; delete when done -->
- **P0 field (operator, 2026-07-31): advert lockup** — **root cause confirmed 2026-08-13** (RX-path stack overflow); fix `processPendingRemoteCli`. Postmortem: `docs/incidents/2026-08-13-remote-admin-advert-lockup.md`. Re-enable field adverts after flash. Ops: `initiatives/envyos-field-stability.md`.
- **Bench (2026-08-13): EndF self-locate on nRF52** — CC310 flash-hash fix + **EndF RAM cache** + **chunked merkle self-serve** (`OTA_SELF_BLOCKS_PER_TICK=1`); **remote admin CLI deferred** out of RX.
- **Watchdog:** port from meshcore [#1417](https://github.com/meshcore-dev/MeshCore/pull/1417), [#2405](https://github.com/meshcore-dev/MeshCore/pull/2405), [#1962](https://github.com/meshcore-dev/MeshCore/pull/1962); note [#2952](https://github.com/meshcore-dev/MeshCore/pull/2952) merged (power-saving feed change).
- **Hop retry / mcsim:** [#2980](https://github.com/meshcore-dev/MeshCore/pull/2980) — usrflo mcsim ACK regression; keep **hop.retry=0** on fleet. Doc: `ops/docs/2026-07-31-meshcore-pr-2980-mcsim-discussion.md`.
- **Mota matrix:** `build-mota.sh` emits `delta_from_<B>.mota` for every prior version B that has base hex for that slug (new targets skip older bases).
- meshcore-dev PRs (sync `feature/*` + `envyos/main` while open): [#2980](https://github.com/meshcore-dev/MeshCore/pull/2980) next-hop retry, [#2991](https://github.com/meshcore-dev/MeshCore/pull/2991) log tail, [#3012](https://github.com/meshcore-dev/MeshCore/pull/3012) boot fsck (draft — pending bench verify of recovery path; root cause: corrupt lfs + lazy `lfs_deorphan` on first FS write → freeze; corruption source incl. repeater `.mota` staging over ExtraFS 0xD4000 then re-role to companion)
- vk496 PRs open for role-aware OTA staging ceiling (`feature/ota-stage-ceiling` → merged on MeshEnvy `envyos/main`; pending on vk496): MeshCore #3, motatool #1, OTAFIX #2
- vk496 MeshCore #4 (stacked on #3): slim RAK4631 repeater role (`feature/ota-slim-repeater` → merged on MeshEnvy `envyos/main`)
- vk496 MeshCore [#5](https://github.com/vk496/MeshCore/pull/5) (stacked on `feature/ota-lora`): SD superseeder (`feature/ota-superseeder` → merged on MeshEnvy `envyos/main`; generalized to `OTA_SUPERSEEDER` + SD/QSPI backends, **deltas-only + allowlist**; SenseCAP NOR mini-superseeder added; bench pending)
- **Direction (operator, 2026-07-23): firmware superseeders (SD warehouse + SenseCAP NOR mini) replace `motatool serve` as the seeding path** — "being tethered to an external device is a chronic failure point." Don't invest further in serve-based seeding; motatool remains for pack/verify/delta. Enterprise context: `ops/initiatives/regional-ingestors.md`.
- **Candidate enhancement (operator, 2026-07-25): compressed-full codec (heatshrink) for self-serve** — firmware produces a heatshrink `.mota` of its own running image (like motatool would), closing the ~55 KB gap that stops same-target peers from staging a full slim image (~426 KB mota vs ~372 KB headroom). Enables laptop-free epidemic full-image seeding between identical repeaters. Scope: new codec in OtaFormat + motatool parity + decode in the apply path (OTAFIX applies staged motas, so the bootloader is in scope too). Greenfield rules apply. **Not a showstopper — delta seeder covers today's need**; candidate for pre-Orlando OTA polish or later.
- **Candidate feature (operator, 2026-07-23): MeshCore MQTT client** — publish/subscribe channel messages ↔ broker topics, incl. parsing Meshtastic JSON topics for cross-mesh bridging. Likely home is **Lotato** (`lobbs/lotato/lotato/` — has WiFi/batching/dedup; today HTTP-POSTs to PotatoMesh), not EnvyOS; EnvyOS relevance is if the feature later lands in the distro. Consumers: ingestor edge, Burning Mesh bridge (~Aug 16), Elko interop. Context: `ops/initiatives/regional-ingestors.md`.
