# EnvyOS — agent memory

MeshEnvy's **mesh-utility distro** (Linux-shaped): firmware, host tools, and clients, pinned and bundled together. MeshCore/OTA is the current stack, not the whole product. **Distro repo** — `./envyos` CLI, `MANIFEST.json`, `packages-meta/`, publish/verify. Upstream forks live under **`packages/`** (gitignored checkouts). Overlay inventory + evN notes live on the meshcore fork (`README.md` § EnvyOS overlay, `CHANGELOG.md`).

## Layout

| Path | Role |
|------|------|
| `packages/` | Gitignored workbenches — `meshcore`, `adafruit-nrf52-bootloader`, `motatool`, `mcmt-gateway`, `meshcore-open` |
| `packages-meta/<pkg>/` | Tracked recipe — `PACKAGE`, **`build.sh`**, `VERSION` (`upstream` + `ev`), `CHANGELOG.md` (pointer/fallback), `RELEASES`, `BACKLOG.md` (meshcore) |
| `scripts/` | Shared distro machinery — `envyos` CLI, `version.sh`, `build-lib.sh`, `build-all.sh`, `publish.sh`, `targets.txt` (recipes live in `packages-meta/<pkg>/build.sh`) |
| `build/` | Bench (`build/<branch>/bench/…`) and immutable `build/vX.Y.Z/` after publish |
| `MANIFEST.json` | `releases.next` (bench head) + `releases[vX.Y.Z]` (immutable publish snapshots) |
| `peaky_finders/` | Workspace sibling — GitHub Release binaries when `peaky=` pinned (`0.5.0`) |
| `../envybot/` | Workspace sibling — wheel when `envybot=` pinned |
| `packages/meshcore-open/` | Flutter MeshCore client workbench (`MeshEnvy/meshcore-open`; `./envyos fetch meshcore-open`) |

Doctrine: [`docs/distro-packaging.md`](docs/distro-packaging.md).

## Branch model

| Repo | Release | Integration |
|------|---------|-------------|
| envyos | `main` | `dev` |
| `packages/*` forks | `envyos/main` | `envyos/dev` |

Bench day-to-day: checkout **`dev`** on envyos and **`envyos/dev`** on package forks. Publish cherry-picks to release branches.

Policy: [`docs/package-release-policy.md`](docs/package-release-policy.md). Packaging: [`docs/distro-packaging.md`](docs/distro-packaging.md) (replaces retired package-maintainer guide).

## Git remotes (`packages/meshcore`)

| Remote | Repository | Role |
|--------|------------|------|
| `origin` | `MeshEnvy/meshcore-firmware` | EnvyOS fork — push features here |
| `vk496` | `vk496/MeshCore` | OTA / vk496 stack |
| `meshcore` | `meshcore-dev/MeshCore` | Upstream MeshCore |

## Git remotes (`packages/adafruit-nrf52-bootloader`)

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
| **Distro integration** | `dev` (envyos) / `envyos/dev` (packages) | MeshEnvy fork | Bench WIP |
| **Distro release** | `main` / `envyos/main` | Same | Published pins in `MANIFEST.json` |

**PR bases** (not the same as `envyos/main`):

| Package | Remote | PR base branch | Example PR branch |
|-----------|--------|----------------|-------------------|
| `packages/meshcore` | `meshcore-dev/MeshCore` | `dev` | `feature/next-hop-retry`, `feature/log-tail-serial` |
| `packages/meshcore` | `vk496/MeshCore` | `feature/ota-lora` | `feature/ota-stage-ceiling` |
| motatool (external) | `vk496/motatool` | `main` | … |
| `packages/adafruit-nrf52-bootloader` | `vk496/Adafruit_nRF52_Bootloader_OTAFIX` | `feature/ota-delta-apply` | … |

Workflow: branch `feature/<name>` from PR base → implement → open cross-fork PR → merge into **`envyos/dev`**. Lock SHAs in `MANIFEST.json` at distro publish.

Skill: `.cursor/skills/envyos-meshcore/SKILL.md`.

## Open upstream PRs (`packages/meshcore`)

MeshEnvy fork: `origin` → `MeshEnvy/meshcore-firmware`. Cross-fork PRs use `--head MeshEnvy:feature/<name>`.

| Feature | PR branch | Upstream repo | PR | Base | Also on `envyos/dev` |
|---------|-----------|---------------|-----|------|------------------------|
| Next-hop retry (echo-primary) | `feature/next-hop-retry` | [meshcore-dev/MeshCore](https://github.com/meshcore-dev/MeshCore) | [#2980](https://github.com/meshcore-dev/MeshCore/pull/2980) | `dev` | yes |
| Log tail serial | `feature/log-tail-serial` | [meshcore-dev/MeshCore](https://github.com/meshcore-dev/MeshCore) | [#2991](https://github.com/meshcore-dev/MeshCore/pull/2991) | `dev` | yes |
| FS corruption boot fsck (companion) | `feature/fs-corruption-check` | [meshcore-dev/MeshCore](https://github.com/meshcore-dev/MeshCore) | [#3012](https://github.com/meshcore-dev/MeshCore/pull/3012) (draft) | `dev` | yes |
| ConfigSerializer `rd_len` uint16_t | `fix/config-serializer-rd-len` | [meshcore-dev/MeshCore](https://github.com/meshcore-dev/MeshCore) | [#3322](https://github.com/meshcore-dev/MeshCore/pull/3322) | `dev` | yes |

**Sync rule:** while a PR is open, commits for that feature go to **`envyos/dev` and the PR branch** (push both). Unrelated features stay separate. See skill § Open PR sync policy.

vk496 / motatool / otafix PRs: see **Active threads** below and `envyos-meshcore` skill PR table.

Sibling checkouts live at ``packages/{meshcore,adafruit-nrf52-bootloader,motatool,mcmt-gateway,meshcore-open}` (+ peaky + envybot siblings)`.

## Released versions (immutable)

| Version | Status | Canonical artifacts |
|---------|--------|---------------------|
| **v0.1.0** | **Released** — frozen, do not rebuild or delete | [GitHub Release](https://github.com/MeshEnvy/envyos/releases/tag/v0.1.0) · **`firmware-v0.1.0.zip`** · **`build/motas/v0.1.0/`** |
| **v0.1.1** | **Released** — frozen, do not rebuild or delete | [GitHub Release](https://github.com/MeshEnvy/envyos/releases/tag/v0.1.1) · **`firmware-v0.1.1.zip`** · **`build/motas/v0.1.1/`** |

**Next distro tag (operator 2026-09-04): `v0.2.0`.** Minor bump for **EC-001** MeshCore **companion-v1.17.1** on `envyos/main`. v1.17 migrates settings to **JSON**; **no safe rollback to 1.16** after upgrade. Ops: `initiatives/envyos-backlog.md` § Next release. Release notes draft: `meshenvy.org/blog/envyos-0-2-0/`.

- Listed in **`MANIFEST.json` `releases`** (keyed by fleet tag, each with a `packages` snapshot); released package trees (`.released` markers) are immutable.
- **`./scripts/publish.sh [version]`** — promote bench → `build/vX.Y.Z/`, lock SHAs, record release snapshot, GitHub Release (`RELEASE.md` asset + description). `--dry-run` writes `build/<slot>/release/RELEASE.md`.
- **`MANIFEST.json`** — `releases.next` (WIP bench pins) + shipped `releases[vX.Y.Z]`. `packages-meta/*/RELEASES` holds package semver history for deltas.
- **Dev bench path:** `build/<git-branch>/bench/{meshcore,adafruit-nrf52-bootloader,motatool}-<ver>/` (not `build/<distro>/`).
- **Dev release preview:** `build/<git-branch>/release/` (gzipped GitHub-shaped set). Full `./envyos build` always stages this after bench packages; a later package failure does not skip it. Refresh: `./envyos build --release-only`.
- **Published path:** `build/vX.Y.Z/` (immutable after lock — no rebuild/delete). **Rename-only** apply-identity mota names (`scripts/rename-motas.sh`) are allowed; bytes stay the same.
- `meshcore` in `MANIFEST.json` → `packages-meta/meshcore/VERSION`; built by **`packages-meta/meshcore/build.sh`** → **`build/<branch>/bench/meshcore-<ver>/`**. GitHub hex/uf2 `meshcore-<slug>-<ver>.*`. Motas `fw-<slug>-<ver>-full|delta-hwid.<hw>-[from.<old>-]to.<body>-mid.<mid>.mota`. CLI aliases `firmware`, `fw`. **Remake wipes slug `*.mota` before repack** (one full + fresh deltas; hex/uf2 stay for incremental skip). **`./envyos build --clean`** wipes `build/<slot>/bench/` + `release/` for the branch slot, then rebuilds every package from scratch (scoped `--*-only` builds use per-package `--clean` only).
- `adafruit-nrf52-bootloader` (CLI aliases `bootloader`, `bl`) → **`build/<branch>/bench/adafruit-nrf52-bootloader-<ver>/`**. GitHub assets `adafruit-nrf52-bootloader-<board>-<ver>.uf2`. On-device `get bootloader.ver` / `EnvyBoot` UF2 stamp is packages-meta `0.9.2-evN` (`ENVYBOOT_VERSION`), not `git describe` or OTAFIX-BP tags. Shipped `releases[v0.1.x]` keep the `bootloader` key.
- `motatool` → **`build/<branch>/bench/motatool-<ver>/`** (artifact); working copy under bench motatool tree
- `peaky` → GitHub Release cache when pinned (`peaky-<ver>-<target>.tar.gz`; `0.5.0`). Publish notes read sibling `peaky_finders/CHANGELOG.md` `## [v0.5.0]`.
- `envybot` → sibling `uv build` wheel when pinned (`envybot-<ver>-py3-none-any.whl`; `0.1.0`, unpublished)
- `mcmt-gateway` → `packages/mcmt-gateway` `uv build` wheel when pinned (`mcmt_gateway-<ver>-py3-none-any.whl`, GPL-3.0)
- **Firmware build:** `./envyos build meshcore` (dispatches to `packages-meta/meshcore/build.sh`). Requires staged **`motatool`** on PATH (`./envyos build motatool`) or **`MOTATOOL=`** override.

## OTA targets (`scripts/targets.txt`)

| Slug | PlatformIO env | Role |
|------|----------------|------|
| `wismesh-tag-repeater` | `RAK_WisMesh_Tag_repeater` | WisMesh Tag repeater (bench DUT) |
| `rak4631-repeater` | `RAK_4631_repeater` | RAK4631 repeater |
| `rak4631-repeater-slim` | `RAK_4631_repeater_slim` | RAK4631 slim repeater — no OLED/sensors/BLE (`BLE_DFU_DISABLED`; MCU temp only). **Own full `.mota` fits** in `[0x26000, 0xED000)`. Measured: v0.1.3 slack ~24 KB; 1.17.1-ev1 slack ~90 KB (max mota **454656** B). WisMesh Tag / companion still do not. Apply still rejects `CODEC_FULL`. |
| `heltec-t096-repeater-slim` | `Heltec_t096_repeater_slim` | Heltec T096 slim repeater — no TFT/GPS/sensors/BLE (`BLE_DFU_DISABLED`; MCU temp only). **09-03:** `begin()` drives `GPS_EN` inactive + TFT backlight off. `powersaving` / FEM LNA are book apply prefs, not slim defaults. Same S140 v6 / `rak4631_hw` OTA as RAK4631. Same-size full **stages** (1.17.1-ev1 slack ~89 KB; max mota **450560** B). OTAFIX board `heltec_t096` (oltaco PR #42, landed on MeshEnvy `envyos/main`) |
| `rak4631-superseeder` | `RAK_4631_superseeder` | RAK4631 slim + RAK15002 SD — field superseeder (`OTA_SD_SEEDER`; promiscuous capture to `/motas/` on SD, serve all; flash staging reserved for self-update) |
| `rak4631-client-ble` | `RAK_4631_companion_radio_ble` | RAK4631 companion (BLE) |
| `wismesh-tag-client-ble` | `RAK_WisMesh_Tag_companion_radio_ble` | WisMesh Tag companion (BLE) |

Add a line to `targets.txt` to ship another board/role.

**Parked (not in `targets.txt`):** SenseCAP P1-Pro — PIO `SenseCap_Solar_repeater_slim` / `SenseCap_Solar_superseeder` exist; OTAFIX `sensecap_solar_p1` (S140 v7, app @ `0x27000`). EnvyBoot **0.9.2-ev1** built 2026-08-30 (`packages-meta/adafruit-nrf52-bootloader/build.sh sensecap_solar_p1`). Slim firmware deferred until NOR/mota layout (EC-016).

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

**Self-serve (any OTA node, no `.mota` file needed):** at announce time (`Mesh.cpp`) a node auto-runs `ota_serve_self()` — scans its app region for the EndF trailer (target/version/hw_id), builds merkle leaves + a synthetic full **unsigned** manifest, and serves its own running firmware from memory-mapped flash. Full image only, **uncompressed** (`CODEC_FULL` payload == raw image; only detools delta codecs are CRLE-compressed). **Slim same-target peers can stage that full** (measured 09-02). **EC-021 (not built):** keep this path; never fetch a second copy of the running image; serve the stage slot across reboot. WisMesh Tag repeater / companion still cannot. nRF52 `ota install` still refuses `CODEC_FULL` (`not an in-place delta`). Firmware seeders still filter fulls (`ota_seeder_is_delta`); doctrine is they **must admit signed fulls** on slim (EC-019). Unsigned self-serve may land on SD; do not advertise it as a release. Manual `ota install` accepts unsigned (merkle+hash integrity still enforced); auto-install requires signed+allowlisted.

Bench: laptop seeder advertises → superseeder captures (`ota sd` shows files) → detach laptop → DUT fetches/installs from superseeder alone (real version bump).

## Build commands

```bash
./envyos build                             # pinned packages (motatool before meshcore)
./envyos build --bootloader-only
./envyos build --mota-only --target rak4631-repeater-slim
./envyos build bootloader
./envyos build meshcore                    # firmware only → bench firmware tree (pin from releases.next)
./envyos build meshcore --list-targets
ENVYOS_BUILD_SLOT=heltec-bl-test ./envyos build meshcore --target heltec-t096-repeater-slim
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
| `envyos-package` | Legacy package harness (retired — see `distro-packaging`) |
| `envyos-freshen` | `/integrate` / `/freshen` — companion merge; `/freshen dev` spike only |
| `envyos-meshcore` | Git remotes, feature branches, upstream PRs |
| `envyos-ota` | OTA protocol, device CLI, codecs, bench roles |
| `ota-greenfield` | OTA format/protocol/tooling changes — no legacy or migration paths |
| `envyos-scripts` | `./envyos build`, `packages-meta/*/build.sh` recipes, `publish.sh` |
| `motatool` | `.mota` build, deltas, verify, serve |

## Active threads

<!-- In-flight work only; delete when done -->
- **Signed mota / fleet-key reject (08-30):** `ops/initiatives/signed-mota-deltas.md`; EC-012 P1; publish still unsigned; field seeders must not serve unsigned.
- **Meshcore backlog split (2026-08-25):** EC-002–EC-009 still on `feature/*`; canonical queue `packages-meta/meshcore/BACKLOG.md`. **EC-001 merged_main (2026-08-29):** `companion-v1.17.1` on `envyos/main` @ `3881ceb1` (integrate `2cf4a528`). Native + slim passed. Not published. Monolith tag `envyos/dev-pre-split`.
- **P0 (operator, 2026-07-31): advert lockup on `rak4631-repeater-slim`** — admin settings change then advert → freeze; **adverts disabled in field**. Ops: `initiatives/envyos-field-stability.md`.
- **Watchdog:** port from meshcore [#1417](https://github.com/meshcore-dev/MeshCore/pull/1417), [#2405](https://github.com/meshcore-dev/MeshCore/pull/2405), [#1962](https://github.com/meshcore-dev/MeshCore/pull/1962); note [#2952](https://github.com/meshcore-dev/MeshCore/pull/2952) merged (power-saving feed change).
- **Hop retry / mcsim:** [#2980](https://github.com/meshcore-dev/MeshCore/pull/2980) — usrflo mcsim ACK regression; keep **hop.retry=0** on fleet. Doc: `ops/docs/2026-07-31-meshcore-pr-2980-mcsim-discussion.md`.
- **Slim full-mota (09-02, locked):** signed fulls first-class on RAK/T096 slim. Superseeder library = latest signed full + `delta_from_*` matrix. nRF52 still cannot **apply** `CODEC_FULL`; seeders still reject fulls. EC-019. **Idea:** app updates BL, BL updates app (field new OTAFIX via app delta + BL mota). Ops: `initiatives/ota-rollout.md`.
- **OTA target names (09-02):** drop `OtaTargets.h` from the image. Status prints hex. Envybot maps id→env. EC-020. Ops: `initiatives/ota-target-name-client.md`.
- **OTA serve self + slot (09-02):** keep synthetic. Never fetch a second copy of the running image. Serve the stage slot across reboot. EC-021. EC-005 disable superseded. Ops: `initiatives/ota-serve-self-and-slot.md`.
- **`ota ls` installable-only (09-02):** list only applyable fulls (hw+target) and deltas (matching base_hash). Apply-identity tokens, not PIO env / `1n` / `99999s`. Later pages content-only. EC-006. Ops: `initiatives/envyos-backlog.md`.
- meshcore-dev PRs (sync `feature/*` + `envyos/main` while open): [#2980](https://github.com/meshcore-dev/MeshCore/pull/2980) next-hop retry, [#2991](https://github.com/meshcore-dev/MeshCore/pull/2991) log tail, [#3012](https://github.com/meshcore-dev/MeshCore/pull/3012) boot fsck (draft — pending bench verify of recovery path; root cause: corrupt lfs + lazy `lfs_deorphan` on first FS write → freeze; corruption source incl. repeater `.mota` staging over ExtraFS 0xD4000 then re-role to companion), [#3322](https://github.com/meshcore-dev/MeshCore/pull/3322) ConfigSerializer `rd_len` uint16_t
- vk496 OTA PRs (contribution target; merged on `envyos/main`): MeshCore #3 staging ceiling, motatool #1, OTAFIX #2, #4 slim, [#5](https://github.com/vk496/MeshCore/pull/5) superseeder
- **Direction (operator, 2026-07-23): firmware SD superseeders (32 GB cards) replace `motatool serve` as the seeding path** — "being tethered to an external device is a chronic failure point." Don't invest further in serve-based seeding; motatool remains for pack/verify/delta. Enterprise context: `ops/initiatives/regional-ingestors.md`.
- **Candidate enhancement (operator, 2026-07-25): compressed-full codec (heatshrink)** — WisMesh Tag / companion only (same-size full still does not stage). Slim uncompressed full already stages; epidemic slim roll waits on EC-019 apply + seeder admit.
- **Candidate feature (operator, 2026-07-23): MeshCore MQTT client** — publish/subscribe channel messages ↔ broker topics, incl. parsing Meshtastic JSON topics for cross-mesh bridging. Likely home is **Lotato** (`lobbs/lotato/lotato/` — has WiFi/batching/dedup; today HTTP-POSTs to PotatoMesh), not EnvyOS; EnvyOS relevance is if the feature later lands in the distro. Consumers: ingestor edge, Burning Mesh bridge (~Aug 16), Elko interop. Context: `ops/initiatives/regional-ingestors.md`.
