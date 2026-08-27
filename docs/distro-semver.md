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

The **distro tag** is the fleet contract. **`releases.next`** is the bench integration head; **`releases[vX.Y.Z]`** is the immutable snapshot at publish.

| Bump | When |
|------|------|
| **Major** | Remove a bundled package from the release manifest, or ship a breaking fleet migration (mandatory bootloader reflash, incompatible OTA, no safe path from the previous tag). |
| **Minor** | Add a bundled package, a component **minor/major** pin change (e.g. `0.1.x` → `0.2.0`), or expand shipped targets/platforms in a user-visible way. |
| **Patch** | Same bundle membership; component **patch** pin changes only (`0.1.1` → `0.1.3` within the same major.minor line). Fleet-safe hotfixes. Requires OTA deltas from the immediate predecessor tag. |

Pre-1.0 (`0.y.z`): policy still applies for operator clarity; `1.0.0` can mark a stable bundle contract.

## Publish workflow

```bash
./envyos build                    # writes build/<branch>/bench/
./envyos semver suggest           # CHANGELOG + bundle → proposed vX.Y.Z
./envyos publish                  # prompt for tag (or --yes)
./envyos publish v0.1.3 --yes     # explicit tag
./envyos publish --dry-run        # full publish plan (no promote/upload)
```

At publish, `./envyos` locks SHAs on `releases.next`, records `releases[vX.Y.Z]` from that snapshot, and writes `build/vX.Y.Z/RELEASE_MANIFEST`. GitHub Release notes include the component matrix, `CHANGELOG.md` **`## [Unreleased]`** body (until promoted), and the asset manifest.

## CHANGELOG

User-facing notes live in repo-root `CHANGELOG.md` under `## [Unreleased]`. `./envyos semver suggest` reads Unreleased bullets plus bundle diffs vs the **last published git tag** (and `MANIFEST.json` `releases`). Missing local manifests fall back to the GitHub Release component table.

See also: [`component-release-policy.md`](component-release-policy.md).
