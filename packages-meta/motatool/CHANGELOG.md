# Changelog

User-facing release narrative for motatool. Policy: [`docs/change-management.md`](docs/change-management.md).

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions match git tags (`v0.1.2`, …).

- Add user-visible work under **`## [Unreleased]`** in the same change set as the code.
- At release, promote Unreleased to `## [vX.Y.Z] - YYYY-MM-DD`, then open a fresh empty Unreleased.
- GitHub Release bodies come from this file (`./scripts/changelog.sh notes`), not commit subjects.

Upstream origin: [vk496/motatool](https://github.com/vk496/motatool). Do not copy upstream notes here.

## [Unreleased]

- `.mota` filenames are apply-identity:
  `…-full-hwid.<hw>-to.<new-body16>-mid.<mid8>.mota` and
  `…-delta-hwid.<hw>-from.<old-body16>-to.<new-body16>-mid.<mid8>.mota`.
  Empty `hw_id` is `none`. `motatool name` prints that basename (deltas need `--fw`).
  Dropped `--base-version`.
- Name `Heltec_t096_repeater_slim` and `Heltec_t096_seeder` in `src/targets.rs`.

## [v0.1.2-rc0] - 2026-08-25

Pre-release: EnvyOS package harness (`./envyos build`, `prepare`, `publish`); local cross-platform dist, no CI release workflow.

### Added

- **`./envyos` harness** — branch-slot dev builds, `prepare` for release tarballs, `publish` via `gh release create`.

### Changed

- Sync `src/targets.rs` with firmware OTA env table (cache/storage slugs; drop `*_superseeder`).

### Improved

- `motatool serve -v`: split `[host]` (seeder protocol) vs `[tag]` (firmware serial); `DESCRIBE` logs mid/target/version/codec for each registered index.

## [v0.1.1] - 2026-08-14

Declared MeshEnvy-canonical (`repository` → MeshEnvy/motatool). Binary name unchanged.

### Improved

- In-place encode builds one suffix array of the shifted base and filters it per segment (same patch bytes as v0.1.0).
- Auto `memory_size` returns the converged patch instead of encoding a third time.

## [v0.1.0] - 2026-08-03

First EnvyOS-tracked motatool. Shipped with EnvyOS distro v0.1.2.
