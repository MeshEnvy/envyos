# EnvyOS component release policy

Canonical contract for every EnvyOS distro component repo (envycore, bootloader, motatool, mcmt-gateway, peaky-finders, envybot).

## Optional bundle components

| Component | Manifest key | When bundled |
|-----------|--------------|--------------|
| mcmt-gateway | `mcmt-gateway=` | Distro ≥ v0.2.0 |
| peaky | `peaky=` | When pinned in `MANIFEST.json` (bench-gated) |
| envybot | `envybot=` | When pinned in `MANIFEST.json` (`releases.next` has 0.1.0) |

Peaky and mcmt keep **independent semver** (like motatool). EnvyOS `publish.sh` mirrors their GitHub Release binaries into the distro zip; tags still land on each component repo.

## Two layers

| Layer | Purpose |
|-------|---------|
| **Git commits** | Conventional Commits for history, review, bisect. |
| **`CHANGELOG.md`** | Distro notes in `envyos/`. Overlay notes on patched-upstream forks (meshcore) when upstream has no changelog. |

User-visible **distro** changes go under **`## [Unreleased]`** in `envyos/CHANGELOG.md`. Overlay work goes under **`## [Unreleased]`** in the fork `CHANGELOG.md` (promote into the open `evN` heading until that pin ships). GitHub Release bodies come from those files, not commit subjects.

## Distro coupling

[MeshEnvy/envyos](https://github.com/MeshEnvy/envyos) owns the **tested version matrix** (`MANIFEST.json`) and **one-stop release assets**. Dev builds use **`build/<branch>/bench/`**; publish promotes to **`build/vX.Y.Z/`**. See [`distro-semver.md`](distro-semver.md).

After cutting a component release, bump `MANIFEST.json` in envyos when that version ships in a bundle.

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
| envybot | sibling `CHANGELOG.md` | (wheel via `packages-meta/envybot/build.sh`) |

Branch model on forks: **`envyos/main`** = release line, **`envyos/dev`** = integration (envyos uses **`main`** / **`dev`**).

Upstream integration: [`integration-policy.md`](integration-policy.md).
