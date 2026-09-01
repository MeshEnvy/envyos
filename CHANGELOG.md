# Changelog

EnvyOS distro release notes. Versions match git tags (`v0.1.x`).

## [Unreleased]

### Added

- **envybot:** Native host package pinned at 0.1.0 (unpublished). `./envyos build envybot` stages `envybot-<ver>-py3-none-any.whl`. Book stays private.
- **mcmt-gateway:** Native host package pinned at 0.1.0 (`Imperator4422/mcmt-gateway`, GPL-3.0). `./envyos build mcmt-gateway` stages `mcmt_gateway-<ver>-py3-none-any.whl` via `uv build`.
- **peaky:** Native host package pinned at 0.5.0. `./envyos build peaky` stages `peaky-<ver>-<target>.tar.gz` from the GitHub Release cache (`MeshEnvy/peaky-finders`).

### Fixed

- **tooling:** Overlay meshcore builds also emit in-place deltas from other pins already on disk (any slot), not only shipped `v0.1.x`.
- **tooling:** Hex-unchanged skip still packs missing in-place deltas (`--base` or a newly visible pin). Previously a second `./envyos build meshcore --base …` was a no-op.
- **tooling:** MeshCore `FIRMWARE_BUILD_DATE` is the package commit date, not wall-clock or per-slot. Same pin + SHA keeps PlatformIO flags stable across `ENVYOS_BUILD_SLOT`s.
- **tooling:** `./envyos build meshcore` with `ENVYOS_BUILD_SLOT` reuses motatool from the git-branch bench (or `MOTATOOL=`) instead of requiring a per-slot rebuild.
- **tooling:** Full `./envyos build` stages `build/<branch>/release/` even if a later pinned package fails. Exit is still non-zero. Refresh without rebuild: `./envyos build --release-only`.
- **tooling:** Native package pins (envybot, peaky, mcmt-gateway) use package semver (`0.1.0`), not distro `vX.Y.Z`. Bench dirs are `envybot-0.1.0`, not `envybot-v0.1.0`.

### Changed

- **tooling:** `./envyos build` no longer takes a version argument. MeshCore pin is `MANIFEST.json` `releases.next`. Slot is git branch or `ENVYOS_BUILD_SLOT`. Distro tag is still chosen at `./envyos publish`.
- **tooling:** Distro GitHub Release notes include each package `CHANGELOG.md` pin section (meshcore overlay, peaky/envybot siblings) plus distro `CHANGELOG.md`. `./envyos changelog check` requires those headings. `./envyos publish --dry-run` writes `RELEASE.md` to `build/<slot>/release/` (and a published `build/vX.Y.Z/release/` if that tree exists). Publish uploads that file as an asset and uses it as the GitHub Release description. The package table uses `PACKAGE` `title=` (MeshCore, Peaky Finders, …) linked to the package home.
- **tooling:** Distro vocabulary is **package** (not component). Helpers, docs, and release notes use `package` throughout.
- **tooling:** Adafruit nRF52 bootloader package id is `adafruit-nrf52-bootloader` (aliases `bootloader`, `bl`). Bench and GitHub assets use `adafruit-nrf52-bootloader-<board>-<ver>.uf2`. CLI aliases `bootloader`, `bl`.
- **tooling:** MeshCore bench dir and GitHub assets use `meshcore-<slug>-<ver>.*`. CLI aliases `firmware`, `fw`.

- **tooling:** Distro-owned packaging (`packages-meta/`, upstream-evN pins, `./envyos build <pkg>`).
- **tooling:** Bench artifacts live under `build/<git-branch>/bench/`; published releases under `build/vX.Y.Z/` (promoted at `./envyos publish`).
- **tooling:** `./envyos publish` suggests the next tag from CHANGELOG + bundle policy (`./envyos semver suggest`; see `docs/distro-semver.md`).
- **tooling:** `./envyos build` orchestrates bootloader, motatool (all platforms), firmware/.mota, optional peaky, and populates `build/<branch>/release/` preview.
- **tooling:** Pre-release builds use integration branch HEAD; package git tags happen on publish only.
- **tooling:** `./envyos restore` hydrates `build/<ver>/bench/{meshcore,adafruit-nrf52-bootloader}-<ver>/` from GitHub.

## [v0.1.3] - 2026-08-23

### Changed

- **tooling:** `./envyos build` orchestrates bootloader, motatool (all platforms), firmware/.mota, and populates `build/<distro>/release/`.
- **tooling:** Pre-release builds use branch HEAD; component git tags happen on publish only.
- **tooling:** Build layout is `build/<distro>/bench/` (uncompressed) + `build/<distro>/release/` (gzipped GitHub upload set).
- **tooling:** `./envyos restore` hydrates released firmware/bootloader trees from GitHub.

### Fixed

- **motatool:** Source-build all four release platform binaries in the distro bundle (v0.1.1).
