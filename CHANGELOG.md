# Changelog

EnvyOS distro release notes. Versions match git tags (`v0.1.x`).

## [Unreleased]

### Changed

- **tooling:** Distro GitHub Release notes include each package fork `CHANGELOG.md` pin section (meshcore overlay) plus distro `CHANGELOG.md`. `./envyos publish --dry-run` prints the full notes body.
- **tooling:** Distro-owned packaging (`packages-meta/`, upstream-evN pins, `./envyos build <pkg>`).
- **tooling:** Bench artifacts live under `build/<git-branch>/bench/`; published releases under `build/vX.Y.Z/` (promoted at `./envyos publish`).
- **tooling:** `./envyos publish` suggests the next tag from CHANGELOG + bundle policy (`./envyos semver suggest`; see `docs/distro-semver.md`).
- **tooling:** `./envyos build` orchestrates bootloader, motatool (all platforms), firmware/.mota, optional peaky, and populates `build/<branch>/release/` preview.
- **tooling:** Pre-release builds use integration branch HEAD; component git tags happen on publish only.
- **tooling:** `./envyos restore` hydrates `build/<ver>/bench/{firmware,bootloader}` from GitHub. Auto-migrates legacy trees.

## [v0.1.3] - 2026-08-23

### Changed

- **tooling:** `./envyos build` orchestrates bootloader, motatool (all platforms), firmware/.mota, and populates `build/<distro>/release/`.
- **tooling:** Pre-release builds use branch HEAD; component git tags happen on publish only.
- **tooling:** Build layout is `build/<distro>/bench/` (uncompressed) + `build/<distro>/release/` (gzipped GitHub upload set).
- **tooling:** `./envyos restore` hydrates released firmware/bootloader trees from GitHub.

### Fixed

- **motatool:** Source-build all four release platform binaries in the distro bundle (v0.1.1).
