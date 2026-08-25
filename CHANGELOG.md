# Changelog

EnvyOS distro release notes. Versions match git tags (`v0.1.x`).

## [Unreleased]

### Changed

- **tooling:** Bench artifacts live under `build/<git-branch>/bench/`; published releases under `build/vX.Y.Z/` (promoted at `./envyos publish`).
- **tooling:** `./envyos publish` suggests the next tag from CHANGELOG + bundle policy (`./envyos semver suggest`; see `docs/distro-semver.md`).
- **tooling:** `./envyos build` orchestrates bootloader, motatool (all platforms), firmware/.mota, optional peaky, and populates `build/<branch>/release/` preview.
- **tooling:** Pre-release builds use integration branch HEAD; component git tags happen on publish only.
- **tooling:** `./envyos restore` hydrates `build/<ver>/bench/{firmware,bootloader}` from GitHub. Auto-migrates legacy trees.
