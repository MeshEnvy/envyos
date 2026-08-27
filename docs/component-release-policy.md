# EnvyOS component release policy

Canonical contract for every EnvyOS distro component repo (envycore, bootloader, motatool, mcmt-gateway, peaky-finders).

## Optional bundle components

| Component | Manifest key | When bundled |
|-----------|--------------|--------------|
| mcmt-gateway | `mcmt-gateway=` | Distro ≥ v0.2.0 |
| peaky | `peaky=` | When pinned in `ENVYOS_VERSIONS` (bench-gated) |

Peaky and mcmt keep **independent semver** (like motatool). EnvyOS `publish.sh` mirrors their GitHub Release binaries into the distro zip; tags still land on each component repo.

## Two layers

| Layer | Purpose |
|-------|---------|
| **Git commits** | Conventional Commits for history, review, bisect. |
| **`CHANGELOG.md`** | User-facing bullets grouped by release (Keep a Changelog). |

User-visible changes go under **`## [Unreleased]`** in the same change set as the code. At release, promote to **`## [vX.Y.Z] - YYYY-MM-DD`**, open a fresh Unreleased, run `./scripts/changelog.sh check vX.Y.Z`, tag and push.

GitHub Release bodies come from `CHANGELOG.md`, not commit subjects.

## Distro coupling

[MeshEnvy/envyos](https://github.com/MeshEnvy/envyos) owns the **tested version matrix** (`ENVYOS_VERSIONS`) and **one-stop release assets**. Dev builds use **`build/<branch>/bench/`**; publish promotes to **`build/vX.Y.Z/`**. See [`distro-semver.md`](distro-semver.md).

After cutting a component release, bump `ENVYOS_VERSIONS` and `COMPONENTS.lock` in envyos when that version ships in a bundle.

## Inclusion rule

A component is bundled in a distro release only when it is **bench-gated**. Tracked-but-untested tools stay out of the manifest.

## Per-repo reference

New component? Start with [`docs/package-maintainer-guide.md`](package-maintainer-guide.md) (harness + distro wiring).

| Repo | Policy doc | Release skill |
|------|------------|---------------|
| motatool | [motatool/docs/change-management.md](https://github.com/MeshEnvy/motatool/blob/envyos/main/docs/change-management.md) | `.cursor/skills/motatool-release/` |
| envycore | `docs/change-management.md` | `.cursor/skills/envycore-release/` · `./envyos` |
| bootloader | `docs/change-management.md` | `.cursor/skills/bootloader-release/` |
| mcmt-gateway | `docs/change-management.md` | `.cursor/skills/mcmt-release/` |
| peaky-finders | [peaky_finders/docs/change-management.md](https://github.com/MeshEnvy/peaky-finders/blob/main/docs/change-management.md) | `peaky_finders/.cursor/skills/peaky-release/` |

Branch model on forks: **`envyos/main`** = release line, **`envyos/dev`** = integration (envyos uses **`main`** / **`dev`**).

Upstream integration: [`integration-policy.md`](integration-policy.md).
