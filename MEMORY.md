# EnvyOS — agent memory

MeshEnvy's MeshCore distro: OTA over LoRa, routing improvements, and repeater enhancements. Firmware lives in `envycore/` (submodule); this repo (`ota`) holds build tooling, `.mota` artifacts, and the bench workflow.

## Repo layout

| Path | Role |
|------|------|
| `envycore/` | MeshCore firmware submodule (`MeshEnvy/meshcore-firmware`); **`envyos/main`** is distro head |
| `ENVYOS_VERSIONS` | Dev HEAD semver — independent `distro`, `firmware`, `bootloader`, `motatool` (**v0.2.0** in progress; not on GitHub) |
| `CHANGELOG.md` | Distro release narrative — package-tagged bullets, `### Packages` delta table, `### Upstream PRs`. Package detail: `envycore/envyos/CHANGELOG.md`, `bootloader/CHANGELOG.md`, `motatool/CHANGELOG.md`. Policy: [`docs/change-management.md`](docs/change-management.md); PR registry: [`docs/upstream-prs.md`](docs/upstream-prs.md). |
| `envyos` | CLI symlink → `scripts/envyos` — `./envyos build|bump|publish|restore|info|upstream-prs|changelog` |
| `build/` | Local build outputs (gitignored) — `build/firmware/<firmware>/`, `build/bootloader/<bootloader>/`, `build/motatool/<motatool>/` (dev); **`build/releases/<distro>/`** (published bundle snapshot) |
| `motatool/` | Rust CLI — pack/verify/delta `.mota` (`MeshEnvy/motatool`; **`envyos/main`**, **0.1.1**; MeshEnvy-canonical fork of vk496; binary name unchanged) |
| `vendor/detools/` | Delta/diff encoding library (in-place `.mota` patches) |
| `bootloader/` | **EnvyBoot** nRF52 bootloader submodule (`MeshEnvy/Adafruit_nRF52_Bootloader_OTAFIX`; **`envyos/main`**, **0.2.0** WDT; fleet ships **0.1.2** in **v0.1.2**); release notes [`bootloader/CHANGELOG.md`](bootloader/CHANGELOG.md) |
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
| `origin` | `MeshEnvy/Adafruit_nRF52_Bootloader_OTAFIX` | **EnvyBoot** fork — head **`envyos/main`**, tags `v0.1.x` |
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
| `motatool/` | `vk496/motatool` (origin only) | n/a — MeshEnvy-canonical as of **0.1.1** | optional |
| `bootloader/` | `vk496/Adafruit_nRF52_Bootloader_OTAFIX` | `feature/ota-delta-apply` | … |

Workflow: branch `feature/<name>` from PR base → implement → open cross-fork PR → **merge into `envyos/main`** (do not fold other features into the PR branch). Monorepo pins submodule SHAs at release; day-to-day `envycore/` checkout = `envyos/main`.

Skill: `.cursor/skills/envyos-meshcore/SKILL.md`. Upstream PR registry + release gate: [`docs/upstream-prs.md`](docs/upstream-prs.md), `.cursor/skills/envyos-upstream-prs/SKILL.md`.

## Open upstream PRs (`envycore/`)

**Registry:** [`docs/upstream-prs.md`](docs/upstream-prs.md) is the per-distro source of truth. `./envyos upstream-prs check vX.Y.Z` gates finalize. Summary below; edit the registry in the same change set.

MeshEnvy fork: `origin` → `MeshEnvy/meshcore-firmware`. Cross-fork PRs use `--head MeshEnvy:feature/<name>`.

| Feature | PR branch | Upstream repo | PR | Base | Also on `envyos/main` |
|---------|-----------|---------------|-----|------|------------------------|
| Next-hop retry (echo-primary) | `feature/next-hop-retry` | [meshcore-dev/MeshCore](https://github.com/meshcore-dev/MeshCore) | [#2980](https://github.com/meshcore-dev/MeshCore/pull/2980) | `dev` | yes |
| Log tail serial | `feature/log-tail-serial` | [meshcore-dev/MeshCore](https://github.com/meshcore-dev/MeshCore) | [#2991](https://github.com/meshcore-dev/MeshCore/pull/2991) | `dev` | yes |
| Defer remote admin CLI | `feature/defer-remote-cli` | [meshcore-dev/MeshCore](https://github.com/meshcore-dev/MeshCore) | [#3196](https://github.com/meshcore-dev/MeshCore/pull/3196) (draft) | `dev` | yes |
| FS corruption boot fsck (companion) | `feature/fs-corruption-check` | [meshcore-dev/MeshCore](https://github.com/meshcore-dev/MeshCore) | [#3012](https://github.com/meshcore-dev/MeshCore/pull/3012) (draft) | `dev` | yes |
| Atomic saves (prefs/ACL/regions/blobs) | `feature/atomic-fs-save` | [meshcore-dev/MeshCore](https://github.com/meshcore-dev/MeshCore) | [#3254](https://github.com/meshcore-dev/MeshCore/pull/3254) (draft) | `dev` | yes |
| FS save error replies (stacked on #3254) | `feature/fs-save-errors` | [meshcore-dev/MeshCore](https://github.com/meshcore-dev/MeshCore) | [#3253](https://github.com/meshcore-dev/MeshCore/pull/3253) (draft) | `dev` | yes |
| Doctor CLI (stacked on #3253) | `feature/doctor` | [meshcore-dev/MeshCore](https://github.com/meshcore-dev/MeshCore) | [#3252](https://github.com/meshcore-dev/MeshCore/pull/3252) (draft) | `dev` | yes |
| nRF52 repeater hardware WDT | `feature/nrf52-watchdog` | [meshcore-dev/MeshCore](https://github.com/meshcore-dev/MeshCore) | [#3210](https://github.com/meshcore-dev/MeshCore/pull/3210) | `dev` | yes |

**Sync rule:** while a PR is open, commits for that feature go to **`envyos/main` and the PR branch** (push both). Unrelated features stay separate. See skill § Open PR sync policy.

vk496 / motatool / otafix PRs: see **Active threads** below and `envyos-meshcore` skill PR table.

**Do not** clone a standalone otafix checkout — only the **`bootloader/`** submodule.

## Released versions (immutable)

**Published distros** ([GitHub Releases](https://github.com/MeshEnvy/envyos/releases)): git tag `v<distro>` + flat asset bundle. **Internal dev cycles** (e.g. v0.1.3 bench work) have no distro tag and are not listed here.

| Version | Status | Canonical artifacts |
|---------|--------|---------------------|
| **v0.1.0** | **Published** | [GitHub Release](https://github.com/MeshEnvy/envyos/releases/tag/v0.1.0) · **`build/firmware/v0.1.0/`** |
| **v0.1.1** | **Published** | [GitHub Release](https://github.com/MeshEnvy/envyos/releases/tag/v0.1.1) · **`build/firmware/v0.1.1/`** |
| **v0.1.2** | **Published** — **latest fleet ship**; bootloader **0.1.2** | [GitHub Release](https://github.com/MeshEnvy/envyos/releases/tag/v0.1.2) · **`build/releases/v0.1.2/`** |
| **v0.1.3** | **Internal only** — bench/dev cycle between v0.1.2 and v0.2.0; no git tag, no GitHub Release | — |
| **v0.2.0** | **In progress** — `ENVYOS_VERSIONS` dev HEAD; finalize + upload pending | local **`build/firmware/v0.2.0/`** (not released) |

EnvyBoot **0.1.3** / **0.2.0** are interim bootloader submodule pins accumulated during the v0.1.3 internal cycle and v0.2.0 dev. Fleet on **v0.1.2** still ships EnvyBoot **0.1.2**. **0.2.0** adds WDT feed; **WDT trip/recover confirmed on RAK4631 slim (2026-08-14)**. LoRa mota apply **not retested** against WDT-feed BL + lockup-fix (operator: no expected regression).

- **Notes:** [`CHANGELOG.md`](CHANGELOG.md) — EnvyOS-owned only. MeshCore companion bumps link upstream. Finalize gates: `## [vX.Y.Z]` section, **`./envyos changelog check`** (`### Packages` table + package changelog sections; [`docs/change-management.md`](docs/change-management.md)), **`./envyos upstream-prs check`** ([`docs/upstream-prs.md`](docs/upstream-prs.md)).
- Distro tags in **`RELEASED_DISTROS`**; firmware trees in **`RELEASED_FIRMWARE`**; bootloader trees in **`RELEASED_BOOTLOADER`**. Hydrate missing released trees with **`./envyos restore`** (GitHub Releases).
- **Canonical local bundle:** `build/releases/<distro>/` — flat release files (GitHub uploads), local `ASSETS` manifest, `RELEASE_MANIFEST` after lock.
- **Canonical off-machine copy:** GitHub Release on **`v<distro>`** — flat files from `build/releases/<distro>/`.
- Delta bases read prior **released firmware** trees (`build/firmware/v0.1.0/`, …). Hydrate missing version dirs with **`./envyos restore firmware`** (skipped when `build/firmware/vX.Y.Z/` already exists; delete that folder or **`--force`** to re-download). Local flash: `fw-<slug>-<ver>.{hex,uf2,zip}`. Motas (local + GitHub v0.2.0+): `fw-<slug>-<ver>-full-<mid8>.mota` and `fw-<slug>-<ver>-delta-from-<base>-<base8>.mota` (`base8` = merkle of that base packed as a full mota). v0.1.2 restore still accepts `fw-<slug>-full-<ver>.mota` / `fw-<slug>-delta-from-<base>.mota`. `motatool serve` indexes any valid `*.mota` by content, not filename.
- **`./envyos publish --dry-run`** — verify + list planned assets (no writes)
- **`./envyos publish stage`** → **`finalize`** → **`upload v<distro>`** — stepwise publish
- **`./envyos publish`** — full publish. Does **not** change `ENVYOS_VERSIONS`.
- **Legacy migration:** if `build/motas/` exists, `mv build/motas build/firmware`.

## Versioning

- **`ENVYOS_VERSIONS`** — dev HEAD; components bump independently via **`./envyos bump patch|minor|major <component>`**:
  - `distro` → next bundle to publish (git tag `v<distro>`); bump via **`./envyos bump patch distro`**
  - `firmware` → device `ver` / `FirmwareIdentity.generated.cpp` and **`build/firmware/<firmware>/`** (must match `envycore/envyos/VERSION`). Not `distro`, even when the numbers match.
  - `bootloader` → **`build/bootloader/<bootloader>/`**
  - `motatool` → `motatool/Cargo.toml` (**0.1.1**; first tracked **0.1.0**), **`build/motatool/<motatool>/motatool-<platform>`** — default build stages all four release platforms; **linux-* via `docker/motatool-build/`**, **darwin-* native on macOS**; publish requires all four. vk496 PRs optional.
- **Build identity:** `./scripts/build-mota.sh` reads **`firmware=`** (not `distro=`), writes **`src/helpers/FirmwareIdentity.generated.cpp`** with **`v<firmware>-<envycore-sha>`**, UTC build date, and MOTA target id (incremental builds recompile only that TU). Device `ver` → `v0.2.0-abc1234 (Build: 15 Aug 2026 05:00 UTC)`. Host copy: **`build/firmware/<firmware>/<slug>/version.txt`** (semver, stamp, sha).
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
| `sensecap-p1pro-repeater-slim` | `SenseCap_Solar_repeater_slim` | SenseCAP Solar P1-Pro slim repeater — no GPS/sensors/BLE; S140 v7 app @ `0x27000`; EnvyBoot `sensecap_solar_p1`. ~384 KB app → ~416 KB staging headroom (full `.mota` ~386 KB fits) |
| `sensecap-p1pro-superseeder` | `SenseCap_Solar_superseeder` | SenseCAP P1-Pro mini-superseeder — slim + 2 MB QSPI NOR LittleFS (`OTA_SUPERSEEDER` + `OTA_SUPERSEEDER_QSPI`); allowlisted **deltas only** to `/motas/`; flash staging for self-update |
| `rak4631-superseeder` | `RAK_4631_superseeder` | RAK4631 slim + RAK15002 SD — field superseeder (`OTA_SUPERSEEDER` + `OTA_SUPERSEEDER_SD`); allowlisted **deltas only** to `/motas/` on SD; flash staging for self-update |
| `rak4631-client-ble` | `RAK_4631_companion_radio_ble` | RAK4631 companion (BLE) |
| `wismesh-tag-client-ble` | `RAK_WisMesh_Tag_companion_radio_ble` | WisMesh Tag companion (BLE) |

**Debug twins** (`<slug>-debug` / `*_debug` PIO env): `LOG_TAIL_ON_BOOT` + `OTA_DEBUG` + `ADMIN_DEBUG`. Distinct MOTA `target_id` (env-name hash). Not published. Every `targets.txt` release slug has a `-debug` row. Default `./envyos build firmware` builds field + debug. `./envyos build firmware --release` or `--debug` limits to one set.

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

Repeater USB debug: `log start` → `log tail on` mirrors packet log lines to serial (CRLF); `log tail off` or Ctrl+C stops. `log tail on` also enables logging if not already on. `*-debug` builds turn this on at boot.

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
| B (DUT) | `wismesh-tag-repeater` — device under test | **EnvyBoot required** (WisMesh Tag BL beeps 3× on DFU entry) |
| C (companion) | `wismesh-tag-client-ble` — remote `ota` CLI over mesh | stock OK |
| D (companion) | `wismesh-tag-client-ble` — second companion on deck | stock OK |

Flow: `motatool serve --dir ./build/firmware/<firmware> --serial …` → Tag A advertises `.mota` over LoRa → Tag B fetch/install → Tag C/D remote admin.

## OTA field superseeder (SD or NOR)

| Node | Role | Build | Bootloader |
|------|------|-------|------------|
| SD superseeder | RAK4631 + RAK15002 SD | `RAK_4631_superseeder` | EnvyBoot if self-update needed |
| NOR mini-superseeder | SenseCAP P1-Pro (2 MB QSPI) | `SenseCap_Solar_superseeder` | EnvyBoot if self-update needed |
| DUT | slim repeater in mesh | `*_repeater_slim` | EnvyBoot required |
| Laptop seeder (optional) | USB `motatool serve` + `ota folder on` | `wismesh-tag-repeater` or any OTA repeater | stock OK |

Superseeder auto-queries heard beacons and captures **deltas only** to external FS (`/motas/<midhex>.mota` on SD or QSPI LittleFS). Full snapshots are never stored (self-serve / USB bootstrap cover those). Default target filter is **all targets**; narrow with `ota seed allow add|rm|list|clear|reset` (persisted). `clear` = empty filter (admit none); `reset`/`defaults` = admit all. CLI: `ota seed` (alias `ota sd`). Flash staging below `MOTA_STAGE_CEILING` is for this node's own update only.

**Self-serve (removed v0.3.0):** disabled in **v0.2.0** (`OTA_SELF_SERVE=0` in `OtaFormat.h`). Was: `ota announce` → `ota_serve_self()` — EndF scan, merkle leaves, synthetic full unsigned manifest from flash. Fleet path: **delta superseeders** + origin for rare full images. `ota self` (EndF identity) unchanged.

Bench: laptop seeder advertises → superseeder captures (`ota seed` shows files) → detach laptop → DUT fetches/installs from superseeder alone (real version bump).

## Build commands

```bash
./envyos info
./envyos build                             # bootloader + firmware + motatool (all platforms)
./envyos build motatool --host-only        # bench: host platform only
./envyos build firmware --target rak4631-repeater-slim
./envyos build firmware --release          # field slugs only
./envyos build firmware --debug            # *-debug twins only
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
| `envyos-upstream-prs` | Feature upstreamability, PR extraction, release finalize, PR debt audit |
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
- **P0 field (operator, 2026-07-31): advert lockup** — **root cause confirmed 2026-08-13** (RX-path stack overflow); fix `processPendingRemoteCli`. **WDT trip/recover ✅ RAK4631 (08-14).** No field freezes (adverts disabled). Re-enable field adverts after flash. Ops: `initiatives/envyos-field-stability.md`.
- **Bench (2026-08-19): wedged InternalFS** — Doc: `envycore/docs/envyos_cli_extensions.md`. `doctor` admin namespace (`stat|gc|check|ls|probe|dump`); no `doctor fix` or `doctor fs` nesting. Upstream 3-PR stack: [#3254](https://github.com/meshcore-dev/MeshCore/pull/3254) atomic saves → [#3253](https://github.com/meshcore-dev/MeshCore/pull/3253) FS errors → [#3252](https://github.com/meshcore-dev/MeshCore/pull/3252) doctor. Boot fsck stays in [#3012](https://github.com/meshcore-dev/MeshCore/pull/3012) (independent of FS error bubbling).
- **Hop retry / mcsim:** [#2980](https://github.com/meshcore-dev/MeshCore/pull/2980) — usrflo mcsim ACK regression; keep **hop.retry=0** on fleet. Doc: `ops/docs/2026-07-31-meshcore-pr-2980-mcsim-discussion.md`.
- **Mota matrix:** `build-mota.sh` writes `fw-<slug>-<ver>-full-<mid8>.mota` and `fw-<slug>-<ver>-delta-from-<base>-<base8>.mota` (`--name-stem` / `--base-version`). One delta per prior base with an image. Full + delta jobs pipelined after each target's pio (`--mota-jobs` / `$ENVYOS_MOTA_JOBS`, default CPU count).
- meshcore-dev PRs (sync `feature/*` + `envyos/main` while open): [#2980](https://github.com/meshcore-dev/MeshCore/pull/2980) next-hop retry, [#2991](https://github.com/meshcore-dev/MeshCore/pull/2991) log tail, [#3012](https://github.com/meshcore-dev/MeshCore/pull/3012) boot fsck (draft — pending bench verify of recovery path; root cause: corrupt lfs + lazy `lfs_deorphan` on first FS write → freeze; corruption source incl. repeater `.mota` staging over ExtraFS 0xD4000 then re-role to companion)
- vk496 PRs open for role-aware OTA staging ceiling (`feature/ota-stage-ceiling` → merged on MeshEnvy `envyos/main`; pending on vk496): MeshCore #3, OTAFIX #2. **motatool is MeshEnvy-canonical (0.1.1)** — no required vk496 sync; historical motatool #1 can stay open or close.
- vk496 MeshCore #4 (stacked on #3): slim RAK4631 repeater role (`feature/ota-slim-repeater` → merged on MeshEnvy `envyos/main`)
- vk496 MeshCore [#5](https://github.com/vk496/MeshCore/pull/5) (stacked on `feature/ota-lora`): SD superseeder (`feature/ota-superseeder` → merged on MeshEnvy `envyos/main`; generalized to `OTA_SUPERSEEDER` + SD/QSPI backends, **deltas-only + allowlist**; SenseCAP NOR mini-superseeder added; bench pending)
- vk496 MeshCore [#6](https://github.com/vk496/MeshCore/pull/6) (draft, `feature/endf-restamp` → `feature/ota-lora`): EndF restamp on incremental rebuild (`tools/mota/pio_endf.py`; merged on MeshEnvy `envyos/main`)
- **Direction (operator, 2026-07-23): firmware superseeders (SD warehouse + SenseCAP NOR mini) replace `motatool serve` as the seeding path** — "being tethered to an external device is a chronic failure point." Don't invest further in serve-based seeding; motatool remains for pack/verify/delta. Enterprise context: `ops/initiatives/regional-ingestors.md`.
- **Candidate enhancement (operator, 2026-07-25): compressed-full codec** — **deprioritized** (self-serve removed; fleet is deltas-only). Was: heatshrink full mota for same-target slim staging gap.
- **Candidate feature (operator, 2026-07-23): MeshCore MQTT client** — publish/subscribe channel messages ↔ broker topics, incl. parsing Meshtastic JSON topics for cross-mesh bridging. Likely home is **Lotato** (`lobbs/lotato/lotato/` — has WiFi/batching/dedup; today HTTP-POSTs to PotatoMesh), not EnvyOS; EnvyOS relevance is if the feature later lands in the distro. Consumers: ingestor edge, Burning Mesh bridge (~Aug 16), Elko interop. Context: `ops/initiatives/regional-ingestors.md`.
- **v0.3.0 (2026-08-19): multi-volume FS CLI naming + companion FS wedge** — virtual-root ids (`int0`/`int1`); WisMesh companion `EXTRAFS=1` + `doctor` on serial path (deferred from v0.2.0). Doc: [`docs/planned/v0.3.0.md`](docs/planned/v0.3.0.md).
