# Change management policy

Every distro release must say **exactly what changed in each distro package**. This document defines where changes are recorded, how release notes are assembled, and what `./envyos publish finalize` enforces.

## Published vs internal

| Kind | Git tag | GitHub Release | `RELEASED_DISTROS` | Example |
|------|---------|----------------|--------------------|---------|
| **Published distro** | `vX.Y.Z` | yes | listed | [v0.1.2](https://github.com/MeshEnvy/envyos/releases/tag/v0.1.2) — latest fleet ship |
| **Internal dev cycle** | none | no | not listed | v0.1.3 — bench work between published distros |
| **In progress** | none yet | no | not listed | v0.2.0 — `ENVYOS_VERSIONS` dev HEAD, changelog in `Unreleased` |

Internal cycles still bump component semver (`firmware`, `bootloader`) on the bench. Those bumps land in package changelogs but do not get a distro tag until `./envyos publish finalize` + `upload`. When a distro ships, append its bundle pins to [`docs/release-manifests.md`](release-manifests.md) (same change set as `RELEASED_DISTROS`).

## Packages

| Package | Version source | Changelog (system of record) |
|---------|----------------|------------------------------|
| **firmware** | `ENVYOS_VERSIONS` `firmware=` (mirrors `envycore/envyos/VERSION`) | [`envycore/envyos/CHANGELOG.md`](../envycore/envyos/CHANGELOG.md) |
| **bootloader** (EnvyBoot) | `ENVYOS_VERSIONS` `bootloader=` | [`bootloader/CHANGELOG.md`](../bootloader/CHANGELOG.md) |
| **motatool** | `ENVYOS_VERSIONS` `motatool=` (`motatool/Cargo.toml`) | [`motatool/CHANGELOG.md`](../motatool/CHANGELOG.md) |
| **tooling** (ota repo: scripts, `./envyos`, publish, bench) | distro version | root [`CHANGELOG.md`](../CHANGELOG.md) directly |

All changelogs follow [Keep a Changelog](https://keepachangelog.com/en/1.1.0/): `## [Unreleased]` accumulates work; sections promote to `## [X.Y.Z] - YYYY-MM-DD` when that package version ships in a distro. EnvyOS-owned changes only — upstream MeshCore / Adafruit / vk496 changes are linked, never copied.

## Two levels of record

1. **Package changelogs** own the full per-package detail. A change to firmware behavior belongs in `envycore/envyos/CHANGELOG.md` under that firmware version, in the same change set as the code.
2. **Root `CHANGELOG.md`** is the distro release narrative: user-visible highlights across packages, the **Packages** version-delta table, and **Upstream PRs**. It links to package changelogs for detail; it does not replace them.

## Rules per change set

- Code change in a package → entry in that **package's changelog** `## [Unreleased]`, same commit/PR. No orphan changes.
- Root `CHANGELOG.md` bullets are **tagged** with their package: `**firmware:**`, `**bootloader:**`, `**motatool:**`, `**tooling:**`. One change may appear in both the package changelog (detail) and root (highlight); root may omit minor internal changes that the package changelog still records.
- Version bump (`./envyos bump <level> <component>`) → promote that package changelog's `Unreleased` to `## [X.Y.Z]` in the same change set, or at latest before distro finalize.
- Upstreamable work additionally gets a GUCP row (`docs/good-upstream-contributor-policy.md`, see `envyos-good-upstream-contributor` skill).

## Distro release section (root CHANGELOG.md)

Each `## [vX.Y.Z]` must contain, in order:

1. One-line release summary.
2. **`### Packages`** — version delta table:

```markdown
### Packages

| Package | Version | Changes |
|---------|---------|---------|
| firmware | v0.1.2 → v0.2.0 | [firmware changelog](envycore/envyos/CHANGELOG.md) |
| bootloader | 0.1.2 → 0.2.0 | [EnvyBoot changelog](bootloader/CHANGELOG.md) |
| motatool | 0.1.0 → 0.1.1 | [motatool changelog](motatool/CHANGELOG.md) |
```

Unchanged packages keep a row (`0.1.1 (unchanged)`) so every release states the full bundle.

3. Keep-a-Changelog sections (`### Fixed` / `### Added` / `### Changed` / `### Improved`) with **package-tagged** bullets.
4. **`### Upstream PRs`** — mirror of `docs/good-upstream-contributor-policy.md` for this release.

GitHub Release notes are generated from this section plus the component table (`release_notes_for_distro`).

## Enforcement

`./envyos publish finalize` (and `./envyos changelog check [vX.Y.Z]` standalone) fails unless:

1. Root `CHANGELOG.md` has `## [vX.Y.Z]` (existing gate).
2. That section contains a `### Packages` table with a row for each of firmware, bootloader, motatool.
3. Every package whose version **changed since the previous released distro** (or all packages, on the first release) has a matching `## [<version>]` section in its package changelog.
4. GUCP gate passes (`./envyos gucp check`).

`./envyos changelog delta [vX.Y.Z]` prints the package version deltas (previous release → this release) to author the Packages table from.

## Release checklist

```text
- [ ] Package changelogs: promote Unreleased → ## [X.Y.Z] for every bumped package
- [ ] Root CHANGELOG.md: promote Unreleased → ## [vX.Y.Z] - YYYY-MM-DD
- [ ] ./envyos changelog delta   # author ### Packages table from output
- [ ] ### Upstream PRs (mirror docs/good-upstream-contributor-policy.md)
- [ ] ./envyos changelog check vX.Y.Z
- [ ] ./envyos gucp check vX.Y.Z
- [ ] ./envyos publish finalize
```

## History note

Releases before v0.2.0 predate this policy; their root sections are untagged and firmware history before 0.2.0 lives only in the root changelog. Do not backfill.
