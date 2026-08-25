---
name: envyos-package
description: >-
  Adopt a repo into the EnvyOS component family: ./envyos CLI (info, build,
  prepare, publish), CHANGELOG, release skill. Template for envycore, bootloader, motatool.
  Distro repo uses a slim bundle-oriented CLI — see envyos-scripts skill.
---

# EnvyOS package CLI

Canonical contract for **component repos** (firmware, bootloader, motatool, …). The **distro** repo (`envyos17`) bundles component releases; it does not replace per-package `./envyos`.

**Reference implementations:** [`envycore`](../../../envycore/) (firmware), [`motatool`](../../../motatool/) (Rust CLI).

**Integration policy:** [`docs/integration-policy.md`](../../docs/integration-policy.md). **Distro coupling:** [`docs/component-release-policy.md`](../../docs/component-release-policy.md). **Maintainer guide:** [`docs/package-maintainer-guide.md`](../../docs/package-maintainer-guide.md).

## Adoption checklist

When a repo joins the EnvyOS stack:

1. **Root CLI** — `./envyos` → `scripts/envyos`
2. **Scripts** — `build.sh`, `prepare.sh`, `publish.sh`, `changelog.sh`, `version.sh` (+ `package-lib.sh` if publish is non-trivial)
3. **`CHANGELOG.md`** — Keep a Changelog; `## [Unreleased]` for day-to-day
4. **`docs/change-management.md`** — commit vs changelog rules
5. **Version file** — one canonical source (`VERSION`, `Cargo.toml`, `envyboot/VERSION`)
6. **`RELEASED_VERSIONS`** — immutable shipped semver list (one line per `vX.Y.Z`, including pre-releases)
7. **`.cursor/skills/<pkg>-release/SKILL.md`** — cut workflow for agents
8. **GitHub Release asset name** — register in this skill's table below; distro `bundle` fetches by name

Optional: `.github/workflows/ci.yml` for tests. **No release CI** — local prepare + publish only.

## Core doctrine

### Branch slot vs version

| Concept | Source | Used for |
|---------|--------|----------|
| **Branch slot** | Sanitized git branch (`envyos-main`, …) | **`build`** and **`prepare`** output paths |
| **Version** | Package version file (`Cargo.toml`, `VERSION`, …) | Asset names, changelog, git tag, `RELEASED_VERSIONS` |

**`build` and `prepare` never take a version argument.** They always write under `build/<branch-slot>/…` and `dist/<branch-slot>/…`.

**`bump` is the only `./envyos` command that mutates the version file** (package defines how: semver, `-rcN`, etc.).

**`publish`** reads the version from the version file (optional CLI arg must match). It uploads from `dist/<branch-slot>/`, locks `RELEASED_VERSIONS`, copies to immutable `build/…/vX.Y.Z/` where needed (envycore motas), and tags.

### Command split (required)

| Command | Scope | Output | Version arg? |
|---------|-------|--------|--------------|
| **`build`** | Local dev — fast, partial | `build/<branch-slot>/…` | **No** |
| **`prepare`** | Full release artifact set | `build/<branch-slot>/…` + `dist/<branch-slot>/…` | **No** |
| **`bump`** | Mutate version file | `Cargo.toml` / `VERSION` / … | level only (`rc`, `patch`, …) |
| **`publish`** | Upload + lock + tag | Reads branch slot; locks version tree | Optional (defaults to version file) |

**`build` semantics are package-defined** (single target vs all targets, host-only vs PlatformIO, …). **`prepare` always builds the full release set.**

| Package | `build` | `prepare` |
|---------|---------|-----------|
| **motatool** | Host binary only | All platform tarballs in `dist/<slot>/` |
| **envycore** | Branch-slot motas; optional `--target` | All targets + delta matrix + zip in `dist/<slot>/` |
| **bootloader** | TBD | TBD |

### Pre-releases

Semver pre-releases (`v0.1.2-rc0`, …) are first-class. **`bump rc`** increments `-rcN` (or adds `-rc0`). Promote in CHANGELOG; **`publish`** tags the exact version string.

### Rules

- Re-run **`prepare`** freely until **`publish`** locks.
- **`publish`** does not compile unless `--skip-prepare` and `.prepared` marker exists for current branch slot.
- Prepared marker must record `version=` matching the version file at prepare time.
- Sibling consumers (envycore → motatool) resolve **`build/<branch-slot>/`**, not version trees.

## Standard commands

| Command | Purpose |
|---------|---------|
| `info` | Version file, branch slot, git HEAD, artifact status |
| `path` | Print resolved dev binary path (optional; motatool) |
| `build [args…]` | Local dev → `build/<branch-slot>/` |
| `prepare [options]` | Full release → `dist/<branch-slot>/` (+ build tree) |
| `publish [vX.Y.Z]` | Verify prepare, upload, lock, tag |
| `bump rc\|patch\|minor\|major` | **Only** way to change version file via CLI |
| `changelog check\|notes vX.Y.Z` | Release notes helpers |

### Standard `publish` flags

| Flag | Meaning |
|------|---------|
| `--dry-run` | Plan only |
| `--no-tag` | Skip local git tag |
| `--no-release` | Skip GitHub upload |
| `--yes` | Non-interactive |
| `--skip-prepare` | Use existing branch-slot dist |
| `--release-only` | Re-upload for locked version |

## Output layout

| Phase | Path |
|-------|------|
| Dev / prepare build | `build/<branch-slot>/…` |
| Prepare dist | `dist/<branch-slot>/…` (filenames include version from version file) |
| After publish lock | `build/…/vX.Y.Z/` immutable copy (envycore motas; optional elsewhere) |

| Package | Dev/prepare build | Dist artifact |
|---------|-------------------|---------------|
| envycore | `build/motas/<branch-slot>/` | `dist/<slot>/firmware-vX.Y.Z.zip` |
| motatool | `build/<branch-slot>/motatool` (siblings); `./envyos build` also writes host tarball | `dist/<slot>/motatool-X.Y.Z-<target>.tar.gz` |

## Publish flow

All components: **local prepare + publish**. No tag-triggered CI.

1. `./envyos bump …` + changelog promote
2. `./envyos prepare` — review `dist/<branch-slot>/`
3. `./envyos publish --yes` — upload, lock, tag

## Registered release assets

| Package | GitHub repo | Primary asset |
|---------|-------------|---------------|
| firmware | `MeshEnvy/meshcore-firmware` | `firmware-vX.Y.Z.zip` |
| bootloader | `MeshEnvy/Adafruit_nRF52_Bootloader_OTAFIX` | `bootloader-vX.Y.Z.zip` |
| motatool | `MeshEnvy/motatool` | `motatool-*-<ver>.tar.gz` (per platform) |

## Agent workflow (component release)

1. User-facing changes in `CHANGELOG.md` under `## [Unreleased]`
2. `./envyos bump rc` (or patch/minor/major)
3. Promote changelog → `## [vX.Y.Z] - date`; fresh Unreleased
4. `./envyos prepare` — review `dist/<branch-slot>/`
5. `./envyos publish --yes`
6. Commit version file, CHANGELOG, RELEASED_VERSIONS; push branch and tag
7. When bundled: bump pins in envyos `ENVYOS_VERSIONS`

Load the package's `<pkg>-release` skill for repo-specific gates.
