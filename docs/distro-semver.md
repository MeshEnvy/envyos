# EnvyOS distro semver and build layout

## Build layout

| Phase | Path | Key |
|-------|------|-----|
| Dev / bench | `build/<branch-slot>/bench/` | Git branch (`dev`, `main`, `feature-foo`) |
| Dev release preview | `build/<branch-slot>/release/` | Same slot |
| Published release | `build/vX.Y.Z/` | Git tag `vX.Y.Z` |

Override slot: `ENVYOS_BUILD_SLOT=my-slot ./envyos build`

**Publish** promotes `build/<branch>/bench/` → `build/vX.Y.Z/bench/`, refreshes `release/`, locks artifacts, tags, and uploads. Version tag is chosen at publish time (not inferred from the build path).

## Distro tag policy

The **distro tag** is the fleet contract. Component lines in `ENVYOS_VERSIONS` (`firmware`, `bootloader`, `motatool`, optional `peaky`, `mcmt-gateway`) are the tested matrix pinned at publish.

| Bump | When |
|------|------|
| **Major** | Remove a bundled package from the release manifest, or ship a breaking fleet migration (mandatory bootloader reflash, incompatible OTA, no safe path from the previous tag). |
| **Minor** | Add a bundled package, upgrade a bundled component version in the manifest, or expand shipped targets/platforms in a user-visible way. |
| **Patch** | Same bundle membership, fleet-safe hotfix (firmware-only pin changes are common). Requires OTA deltas from the immediate predecessor tag. |

Pre-1.0 (`0.y.z`): policy still applies for operator clarity; `1.0.0` can mark a stable bundle contract.

## Publish workflow

```bash
./envyos build                    # writes build/<branch>/bench/
./envyos semver suggest           # CHANGELOG + bundle → proposed vX.Y.Z
./envyos publish                  # prompt for tag (or --yes)
./envyos publish v0.1.3 --yes     # explicit tag
./envyos publish --dry-run        # recommendation only
```

At publish, `./envyos` sets `distro=` and `firmware=` in `ENVYOS_VERSIONS` to the chosen tag. Other component keys stay as pinned for that release.

## CHANGELOG

User-facing notes live in repo-root `CHANGELOG.md` under `## [Unreleased]`. `./envyos semver suggest` reads Unreleased bullets plus bundle diffs vs the last entry in `RELEASED_VERSIONS`.

See also: [`component-release-policy.md`](component-release-policy.md).
