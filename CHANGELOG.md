# Changelog

EnvyOS-owned changes only. When a release rebases onto a new MeshCore companion tag, link that tag's GitHub notes. Do not copy upstream MeshCore entries here.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions match distro tags (`v0.1.x`).

Add user-visible EnvyOS work under **Unreleased** in the same change set. Before `./envyos publish finalize`, promote that section to `## [vX.Y.Z] - YYYY-MM-DD`. Publish fails without it.

## [Unreleased]

### Fixed

- nRF52 watchdog gate: block only when bootloader advertises mota-apply (`MOTABLDR`) but lacks `MOTA_BL_FEAT_WDT_FEED`. Stock / non-mota bootloaders no longer blocked.

- Remote admin + Send Advert lockup on RAK4631 slim (RX-path stack overflow). Remote CLI now runs deferred off the packet RX handler. [Incident](docs/incidents/2026-08-13-remote-admin-advert-lockup.md).

### Added

- SenseCAP P1-Pro NOR mini-superseeder (`sensecap-p1pro-superseeder`).
- Firmware `ver` stamp includes envycore SHA and UTC build date (`v0.1.3-<sha> (Build: … UTC)`).
- **EnvyBoot 0.1.3** (interim submodule pin; not in distro bundle) — see [`bootloader/CHANGELOG.md`](bootloader/CHANGELOG.md).
- **EnvyBoot 0.2.0** — WDT feed in bootloader; repeater `watchdog` CLI gated on `MOTA_BL_FEAT_WDT_FEED` — see [`bootloader/CHANGELOG.md`](bootloader/CHANGELOG.md).
- nRF52 repeater hardware WDT (30 s default, prefs + CLI); companions excluded.

### Changed

- MeshCore base: [companion-v1.17.0](https://github.com/meshcore-dev/MeshCore/releases/tag/companion-v1.17.0).
- EnvyBoot upstream freshen + overlay: [`bootloader/CHANGELOG.md`](bootloader/CHANGELOG.md) (OTAFIX 2.3-BP1.3 pin).

### Improved

- OTA self-serve merkle on nRF52 (EndF RAM cache, chunked merkle).

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
