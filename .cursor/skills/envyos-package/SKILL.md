---
name: envyos-package
description: >-
  Adopt a repo into the EnvyOS component family: ./envyos CLI (info, build,
  prepare, publish), CHANGELOG, release skill. Template for envycore, bootloader, motatool.
  Distro repo uses a slim bundle-oriented CLI — see envyos-scripts skill.
---

# EnvyOS package CLI

Canonical contract for **component repos** (firmware, bootloader, motatool, …). The **distro** repo (`envyos`) bundles component releases; it does not replace per-package `./envyos`.

**Reference implementations:** [`envycore`](../../../envycore/) (firmware), [`motatool`](../../../motatool/) (Rust CLI).

**Integration policy:** [`docs/integration-policy.md`](../../docs/integration-policy.md). **Distro coupling:** [`docs/component-release-policy.md`](../../docs/component-release-policy.md). **Maintainer guide:** [`docs/package-maintainer-guide.md`](../../docs/package-maintainer-guide.md).

## Adoption checklist

When a repo joins the EnvyOS stack:

1. **Root CLI** — `./envyos` → `scripts/envyos`
2. **Scripts** — `build.sh`, `prepare.sh`, `publish.sh`, `changelog.sh`, `version.sh` (+ `package-lib.sh` if publish is non-trivial)
3. **`CHANGELOG.md`** — Keep a Changelog; `## [Unreleased]` for day-to-day
4. **`docs/change-management.md`** — commit vs changelog rules
5. **Version file** — one canonical source (`VERSION`, `Cargo.toml`, `envyboot/VERSION`)
6. **`MANIFEST.json releases`** — immutable shipped semver list (one line per `vX.Y.Z`, including pre-releases)
7. **`.cursor/skills/<pkg>-release/SKILL.md`** — cut workflow for agents
8. **GitHub Release asset name** — register in this skill's table below; distro `bundle` fetches by name

Optional: `.github/workflows/ci.yml` for tests. **No release CI** — local prepare + publish only.

## Core doctrine

### Branch slot vs version

| Concept | Source | Used for |
|---------|--------|----------|
| **Branch slot** | Sanitized git branch (`envyos-main`, …) | **`build`** and **`prepare`** output paths |
| **Version** | Package version file (`Cargo.toml`, `VERSION`, …) | Asset names, changelog, git tag, `MANIFEST.json releases` |

**`build` and `prepare` never take a version argument.** They always write under `build/<branch-slot>/…` and `dist/<branch-slot>/…`.

**`bump` is the only `./envyos` command that mutates the version file** (package defines how: semver, `-rcN`, etc.).

**`publish`** reads the version from the version file (optional CLI arg must match). It uploads from `dist/<branch-slot>/`, locks `MANIFEST.json releases`, copies to immutable `build/…/vX.Y.Z/` where needed (envycore motas), and tags.

### Command split (required)

| Command | Scope | Output | Version arg? |
|---------|-------|--------|--------------|
| **`build`** | Local dev — fast, partial | Same **artifact names** as prepare, host/subset only → `dist/<branch-slot>/…` | **No** |
| **`prepare`** | Full release artifact set | Full set, same names → `dist/<branch-slot>/…` | **No** |
| **`bump`** | Mutate version file | `Cargo.toml` / `VERSION` / … | level only (`rc`, `patch`, …) |
| **`publish`** | Upload + lock + tag | Reads branch slot; locks version tree | Optional (defaults to version file) |

**`build` and `prepare` share one naming convention.** Difference is scope (which artifacts), not filename pattern. Both write shippable files to `dist/<branch-slot>/` using the registered `{package}-{version}[-{variant}].{ext}` pattern from the table below. `build/<branch-slot>/` holds intermediates and unpacked working copies keyed by the same artifact stem (for sibling tools).

**`build` semantics are package-defined** (single target vs all targets, host-only vs PlatformIO, …). **`prepare` always builds the full release set.**

| Package | `build` | `prepare` |
|---------|---------|-----------|
| **motatool** | Host tarball in `dist/<slot>/` (same name as prepare) | All platform tarballs in `dist/<slot>/` |
| **envycore** | Branch-slot motas in `build/motas/<slot>/` (intermediate) | All targets + zip `dist/<slot>/firmware-vX.Y.Z.zip` |
| **bootloader** | TBD | TBD |

### Pre-releases

Semver pre-releases (`v0.1.2-rc0`, …) are first-class. **`bump rc`** increments `-rcN` (or adds `-rc0`). Promote in CHANGELOG; **`publish`** tags the exact version string.

### Rules

- Re-run **`prepare`** freely until **`publish`** locks.
- **`publish`** does not compile unless `--skip-prepare` and `.prepared` marker exists for current branch slot.
- Prepared marker must record `version=` matching the version file at prepare time.
- Sibling consumers (envycore → motatool) resolve the **unpacked working copy** at `build/<branch-slot>/<artifact-stem>/…`, keyed to the same name as the dist tarball. Override env var (e.g. `MOTATOOL=`) for exceptions.

### Docker and cross-platform build caches

When `prepare` or distro bench builds use **Docker** for non-host targets (Linux gnu from macOS, etc.), mount caches so repeat runs do not re-fetch dependencies.

| Cache | Scope | Host | Container mount |
|-------|-------|------|-----------------|
| **Crate registry** | Global (all projects/targets) | `$CARGO_HOME/registry` (default `~/.cargo/registry`) | `/usr/local/cargo/registry` |
| **Git dependencies** | Global | `$CARGO_HOME/git` | `/usr/local/cargo/git` |
| **Build artifacts** | Per-project, per triple | `<repo>/target/<triple>/` | via full repo bind-mount |

Rules:

- **Always** bind-mount the project tree (`-v "$ROOT:/work"` or `/src`) so `target/` persists on the host.
- Mount **registry + git only**. Do not bind-mount host `rustup` toolchains into the container (toolchain stays in the image).
- Native host `cargo build` and Docker builds **share** the same registry/git cache on the host.
- Non-Rust toolchains (PlatformIO `.platformio`, bootloader ccache, …): document and mount package-specific global caches the same way.
- Reference impl: `packages-meta/motatool/docker-lib.sh` (`docker_run_with_rust_cache`). Overrides: `ENVYOS_DOCKER_CARGO_REGISTRY`, `ENVYOS_DOCKER_CARGO_GIT`, `CARGO_HOME`.

## Artifact naming (required)

| Layer | Rule |
|-------|------|
| **Directory** | Shippable artifacts → `dist/<branch-slot>/` |
| **Filename** | Registered pattern with version embedded (see table below) |
| **`build` vs `prepare`** | Same names; `build` emits a subset, `prepare` emits the full set |
| **`build/<branch-slot>/`** | Intermediates + unpacked mirror of dist artifact stem (not ad-hoc names like bare `motatool`) |

Implement `release_*_path()` helpers in `scripts/version.sh` so `build`, `prepare`, and `publish` never hard-code strings.

| Command | Purpose |
|---------|---------|
| `info` | Version file, branch slot, git HEAD, artifact status |
| `path` | Print resolved dev binary path (optional; motatool) |
| `build [args…]` | Local dev → `dist/<branch-slot>/` (subset; same artifact names as prepare) |
| `prepare [options]` | Full release → `dist/<branch-slot>/` (+ working tree under `build/`) |
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

| Package | Working tree (unpacked) | Dist artifact |
|---------|-------------------------|---------------|
| envycore | `build/motas/<branch-slot>/` | `dist/<slot>/firmware-vX.Y.Z.zip` |
| motatool | `build/<branch-slot>/motatool-<ver>-<target>/motatool` | `dist/<slot>/motatool-<ver>-<target>.tar.gz` |

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
| envybot | `MeshEnvy/envybot` | `envybot-<ver>-py3-none-any.whl` |

## Agent workflow (component release)

1. User-facing changes in `CHANGELOG.md` under `## [Unreleased]`
2. `./envyos bump rc` (or patch/minor/major)
3. Promote changelog → `## [vX.Y.Z] - date`; fresh Unreleased
4. `./envyos prepare` — review `dist/<branch-slot>/`
5. `./envyos publish --yes`
6. Commit version file, CHANGELOG, MANIFEST.json releases; push branch and tag
7. When bundled: bump pins in envyos `MANIFEST.json`

Load the package's `<pkg>-release` skill for repo-specific gates.
