# EnvyOS distro packaging

EnvyOS is the **distro repo**: it owns package recipes, versioning, changelogs, builds, and releases. Upstream forks under `packages/` are patch workbenches and upstream-PR vehicles only.

## Layout

```
envyos/
  packages/           # gitignored — full git checkouts (meshcore, bootloader, motatool, mcmt-gateway)
  packages-meta/      # tracked — per-package recipe (build.sh, PACKAGE, VERSION, CHANGELOG, RELEASED)
  scripts/            # shared machinery — envyos CLI, version.sh, build-lib.sh, build-all.sh, publish.sh, targets.txt
  build/              # bench + published artifact trees
  ENVYOS_VERSIONS     # pinned package versions for the current integration head
  COMPONENTS.lock     # fork SHAs at publish
```

Peaky remains a workspace sibling (`peaky_finders/`); the distro consumes its GitHub releases when pinned.

## Package classes

| Class | Packages | Version form |
|-------|----------|--------------|
| **Patched upstream** | meshcore, bootloader, motatool | `<upstream>-evN` (e.g. `1.16.0-ev1`) |
| **Native** | mcmt-gateway, peaky | own semver, no `-evN` |

`-evN` means "carries EnvyOS overlay patches." Absence of `-evN` means stock upstream (overlay fully upstreamed).

## evN semantics

- **Per-package** overlay revision counter; monotonic, never reused.
- **Carries** across an upstream bump when the overlay is unchanged (`1.17.0-ev5` → `1.18.0-ev5`).
- **Bumps** when the overlay changes (feature added, patch dropped because upstream merged it, etc.).
- **Dropped** when the overlay is empty (pure upstream).
- **Release notes** for an ev bump live in `packages-meta/<pkg>/CHANGELOG.md`.

Firmware stamps `FIRMWARE_VERSION` as packed `a.b.c.ev` (fourth byte = ev). Delta `.mota` bases are **hash-keyed** (`base_hash` == running image body hash); evN does not affect delta mechanics.

## Releases

**Fleet consumes distro GitHub Releases only.** Component forks get no new releases after this pivot. `./envyos publish vX.Y.Z` is the sole publish path.

The **distro tag** is the compatibility claim: bench-tested manifest of `(package, upstream-evN, fork SHA)`.

## Delta base retention

Shipped distro releases define which base hex archives are kept under `build/bases/`. New deltas are built against every field-deployed base for that target slug.

## Fork role

| Fork | Role |
|------|------|
| `packages/meshcore` | Merge workbench (`envyos/main`), upstream PR vehicle |
| `packages/bootloader` | Same |
| `packages/motatool` | Same (vk496 PR base) |

No `./envyos` harness, no VERSION/CHANGELOG/RELEASED in package repos.

## CLI

```bash
./envyos build                     # all pinned packages (dependency order)
./envyos build motatool meshcore   # subset
./envyos build meshcore --target rak4631-repeater-slim
./envyos bump-ev meshcore          # bump packages-meta ev counter
./envyos fetch meshcore            # materialize packages/<pkg> at locked SHA
./envyos info
./envyos publish vX.Y.Z
```

## packages-meta/

Each bundled package has:

| File | Purpose |
|------|---------|
| `PACKAGE` | class, upstream repo, PR bases, artifact basename |
| `build.sh` | the package recipe — how EnvyOS builds/stages this package |
| `VERSION` | `upstream=X.Y.Z`, `ev=N` (patched) or `version=X.Y.Z` (native) |
| `CHANGELOG.md` | user-facing overlay/release notes |
| `RELEASED` | shipped package versions (immutable after publish) |
| build support (optional) | recipe-owned infra, e.g. `motatool/docker/` (cross-build image), `motatool/docker-lib.sh` — never committed to the package fork |

`./envyos build <pkg>` dispatches generically to `packages-meta/<pkg>/build.sh`; adding a package = adding a meta dir with a recipe. Recipes source `scripts/version.sh` for shared helpers; distro-wide inputs (`targets.txt`, `targets-lib.sh`) stay in `scripts/`.

Replaces the old per-repo harness documented in `package-maintainer-guide.md` (retired).
