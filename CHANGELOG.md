# Changelog

Distro release narrative — what shipped in each EnvyOS release, per package. Policy: [`docs/change-management.md`](docs/change-management.md). EnvyOS-owned changes only; MeshCore companion bumps link upstream notes.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions match distro tags (`v0.1.x`).

- Bullets are **package-tagged**: `**firmware:**` / `**bootloader:**` / `**motatool:**` / `**tooling:**`. Full per-package detail lives in the package changelogs ([firmware](envycore/envyos/CHANGELOG.md), [EnvyBoot](bootloader/CHANGELOG.md), [motatool](motatool/CHANGELOG.md)); update those in the same change set as the code.
- Add user-visible work under **Unreleased** in the same change set. Before finalize, promote to `## [vX.Y.Z] - YYYY-MM-DD` with a **`### Packages`** version-delta table and **`### Upstream PRs`** (mirror [`docs/upstream-prs.md`](docs/upstream-prs.md)).
- `./envyos publish finalize` fails without the release section, the Packages table, package changelog sections for every bumped package (`./envyos changelog check`), and the upstream PR gate (`./envyos upstream-prs check`).

Releases before v0.2.0 predate this policy (untagged, no Packages table) — do not backfill.

## [Unreleased]

Targets **v0.2.0** (next publish). Accumulates v0.1.3 internal dev plus ongoing bench work. Promote to `## [v0.2.0] - YYYY-MM-DD` at `./envyos publish finalize`.

### Fixed

- **firmware:** Remote admin + Send Advert lockup on RAK4631 slim (RX-path stack overflow). Remote CLI now runs deferred off the packet RX handler. [Incident](docs/incidents/2026-08-13-remote-admin-advert-lockup.md).
- **firmware:** nRF52 watchdog gate: block only when bootloader advertises mota-apply (`MOTABLDR`) but lacks `MOTA_BL_FEAT_WDT_FEED`. Stock / non-mota bootloaders no longer blocked.

### Added

- **firmware:** Bench debug twins of each shipped repeater/superseeder (`<slug>-debug`). Log tail, OTA, and admin serial on boot. Separate MOTA target id. `./envyos build firmware --debug` or `--target <slug>-debug`. Not published.
- **firmware:** `doctor fs` / `doctor gc` recovery CLI for wedged InternalFS; atomic prefs save.
- **firmware:** SenseCAP P1-Pro NOR mini-superseeder (`sensecap-p1pro-superseeder`).
- **firmware:** `ver` stamp includes envycore SHA and UTC build date (`v0.2.0-<sha> (Build: … UTC)`).
- **bootloader:** EnvyBoot 0.2.0 — WDT feed during mota apply/DFU; repeater `watchdog` CLI gated on `MOTA_BL_FEAT_WDT_FEED`.
- **firmware:** nRF52 repeater hardware WDT (30 s default, prefs + CLI); companions excluded.

### Changed

- **firmware:** OTA self-serve disabled (`OTA_SELF_SERVE=0`). Nodes no longer hash/serve their running firmware as a full `.mota`. `ota announce` beacons folder/superseeder/captured motas only. Rare full images: origin USB/motatool. **Remove self-serve code in v0.3.0.**
- **firmware:** OTA self-serve merkle no longer starts at boot. Repeaters stay quiet until `ota announce` (or `ota folder on`). Superseeder / folder catalogs still beacon if they already have files.
- **tooling:** Local flash artifacts use `fw-<slug>-vX.Y.Z.{uf2,hex,zip}`. Full `.mota` names are `fw-<slug>-vX.Y.Z-full-<mid8>.mota`. Delta names are `fw-<slug>-vX.Y.Z-delta-from-vA.B.C-<base8>.mota` (`base8` is the previous full mota's merkle). GitHub uploads use those names. v0.1.2 restore still accepts the old `fw-<slug>-full-…` / `fw-<slug>-delta-from-…` names.
- **firmware:** Device `ver` stamps `ENVYOS_VERSIONS` `firmware` (`v<firmware>-<sha>`). No longer a hardcoded `platformio.ini` define or a `-U` override that fell through to MeshCore `v1.17.0`.
- **firmware:** Field `rak4631-repeater-slim` no longer enables log tail / OTA_DEBUG / ADMIN_DEBUG at boot. Use `rak4631-repeater-slim-debug`.
- **firmware:** MeshCore base: [companion-v1.17.0](https://github.com/meshcore-dev/MeshCore/releases/tag/companion-v1.17.0).
- **bootloader:** EnvyBoot branding, artifact names, OTAFIX 2.3 freshen.

### Improved

- **motatool:** 0.1.1 — MeshEnvy-canonical fork (keep the name). In-place deltas share one suffix array across segments (same patch bytes). Auto `memory_size` reuses the converged patch instead of encoding a third time.
- **firmware:** OTA self-serve merkle on nRF52 (EndF RAM cache, chunked merkle).

### Planned (v0.3.0)

- Multi-volume FS CLI naming: replace companion `UserData`/`ExtraFS` path prefixes with a virtual root (e.g. `int0`/`int1`); unify with repeater `doctor fs` TBD. [Design notes](docs/planned/v0.3.0.md).

## [v0.1.2] - 2026-08-03

### Added

- Distro publish pipeline (`./envyos publish` stage / finalize / GitHub upload).
- Firmware build-date stamp in mota artifacts.

### Changed

- Firmware pin bump only (same EnvyOS overlay as v0.1.1).

## [v0.1.1] - 2026-08-03

### Added

- Freshen lock + cherry-pick script for companion-tag + OTA + overlay replay.

### Changed

- Firmware pin refresh (same-day follow-up to v0.1.0).

## [v0.1.0] - 2026-08-03

First fleet release.

### Added

- LoRa OTA (`.mota` full + detools deltas, OTAFIX apply, seeder / superseeder roles).
- Next-hop retry for direct-path relays (`hop.retry`, default off).
- Serial `log tail` on repeaters.
- Slim repeater roles (RAK4631, SenseCAP P1-Pro) and SD superseeder.
- Companion boot fsck for corrupt LittleFS.
