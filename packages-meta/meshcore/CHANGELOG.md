# Changelog

User-facing firmware release notes. Versions match git tags (`v0.1.x`).

## [Unreleased]

### Fixed

- **nRF `get bootloader.ver`** — recognize EnvyOS `EnvyBoot ` INFO_UF2 marker (Adafruit `UF2 Bootloader ` still works). Empty `bootloader_version` on v0.1.3 EnvyBoot nodes was this miss.

### Added

- **`./envyos` package CLI** — `info`, `build`, `publish`, `bump`, `changelog` (see `docs/change-management.md`).
- **`VERSION`** at repo root (was `envyos/VERSION`).
