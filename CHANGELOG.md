# Changelog

EnvyOS distro release notes. Versions match git tags (`v0.1.x`).

## [Unreleased]

Targets **v0.1.3** (hotfix test before tag).

### Changed

- **tooling:** `./envyos build` orchestrates bootloader, motatool (all platforms), firmware/.mota, optional peaky, and populates `build/<distro>/release/`.
- **tooling:** Pre-release builds use `main` HEAD; component git tags happen on publish only.
- **tooling:** Build layout is `build/<distro>/bench/` (uncompressed) + `build/<distro>/release/` (gzipped GitHub upload set).
- **tooling:** `./envyos restore` hydrates `build/<ver>/bench/{firmware,bootloader}` from GitHub. Auto-migrates legacy `build/firmware/`, `build/bootloader/`, and `envycore/build/motas/` trees.
