# EnvyOS distro packaging

EnvyOS is the **distro repo**: it owns package recipes, versioning, changelogs, builds, and releases. Upstream forks under `packages/` are patch workbenches and upstream-PR vehicles only.

## Layout

```
envyos/
  packages/           # gitignored — full git checkouts (meshcore, adafruit-nrf52-bootloader, motatool, mcmt-gateway, meshcore-open)
  packages-meta/      # tracked — per-package recipe (build.sh, PACKAGE, VERSION, CHANGELOG, RELEASES)
  scripts/            # shared machinery — envyos CLI, version.sh, manifest.py, build-lib.sh, publish.sh
  build/              # bench + published artifact trees
  MANIFEST.json       # releases.next (bench) + releases[vX.Y.Z] (shipped)
```

Peaky and envybot remain workspace siblings (`peaky_finders/`, `envybot/`). The distro consumes their artifacts when pinned.

## MANIFEST.json

Single registry for the current integration head and shipped fleet tags:

```json
{
  "releases": {
    "next": {
      "packages": {
        "meshcore": { "repo": "...", "version": "1.16.0-ev1", "sha": "..." }
      }
    },
    "v0.1.3": {
      "published": "2026-08-27",
      "packages": {
        "meshcore": { "repo": "...", "version": "0.1.3", "sha": "..." }
      }
    }
  }
}
```

| Key | Role | Updated when |
|-----|------|--------------|
| **`releases.next`** | Bench integration head (WIP toward next publish) | `bump-ev`, pin edits, `./envyos publish` (sha lock on `next` before snapshot) |
| **`releases[vX.Y.Z]`** | Immutable shipped fleet release | `./envyos publish` (`releases record` copies locked `next` → tag) |
| **`releases[tag].packages`** | Exact version + sha for that release | Frozen at publish time |

CLI verbs `get`, `list`, `set-version`, `lock` operate on **`releases.next.packages`**. Shipped tags (`v0.1.0`, …) never include `next` in `releases list` / `releases latest`.

`packages-meta/<pkg>/VERSION` (structured `upstream` + `ev`) feeds `-evN` bumps; `./envyos bump-ev` syncs version into `releases.next`. A copy of `MANIFEST.json` lands at `build/vX.Y.Z/MANIFEST.json`; `RELEASE_MANIFEST` remains a human-readable key=value snapshot in the build tree.

Package semver history for delta bases: **`packages-meta/*/RELEASES`**.

## Package classes

| Class | Packages | Version form |
|-------|----------|--------------|
| **Patched upstream** | meshcore, adafruit-nrf52-bootloader, motatool | `<upstream>-evN` (e.g. `1.16.0-ev1`) |
| **Native** | mcmt-gateway, peaky, envybot | own semver, no `-evN` |

`-evN` means "carries EnvyOS overlay patches." Absence of `-evN` means stock upstream (overlay fully upstreamed).

## evN semantics

- **Per-package** overlay revision counter; monotonic, never reused.
- **Carries** across an upstream bump when the overlay is unchanged (`1.17.0-ev5` → `1.18.0-ev5`).
- **Bumps** when the overlay changes (feature added, patch dropped because upstream merged it, etc.).
- **Dropped** when the overlay is empty (pure upstream).
- **Release notes** for an ev bump live in the fork `CHANGELOG.md` (meshcore: `packages/meshcore/CHANGELOG.md`). `packages-meta/<pkg>/CHANGELOG.md` is a pointer or fallback when the fork file is absent.

Firmware stamps `FIRMWARE_VERSION` as packed `a.b.c.ev` (fourth byte = ev). Delta `.mota` bases are **hash-keyed** (`base_hash` == running image body hash); evN does not affect delta mechanics.

## Releases

**Fleet consumes distro GitHub Releases only.** `./envyos publish vX.Y.Z` is the sole publish path. Notes ship as `release/RELEASE.md` (asset) and as the GitHub Release description.

The **distro tag** is the compatibility claim: bench-tested manifest of `(package, upstream-evN, fork SHA)`.

## Delta base retention

Shipped distro releases define which base hex archives are kept under `build/bases/`. New deltas are built against every field-deployed base for that target slug.

## Fork role

| Fork | Role |
|------|------|
| `packages/meshcore` | Merge workbench (`envyos/main`), upstream PR vehicle |
| `packages/adafruit-nrf52-bootloader` | Same (nRF52 / OTAFIX; CLI aliases `bootloader`, `bl`) |
| `packages/motatool` | Same (vk496 PR base) |
| `packages/meshcore-open` | Flutter client workbench (`MeshEnvy/meshcore-open`; upstream `zjs81/meshcore-open`) |

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
| `PACKAGE` | class, `title` (human name), `fork_repo` / `repo`, optional `homepage=`, PR bases, artifact basename |
| `build.sh` | the package recipe — how EnvyOS builds/stages this package |
| `VERSION` | `upstream=X.Y.Z`, `ev=N` (patched) or `version=X.Y.Z` (native) |
| `CHANGELOG.md` | pointer / fallback. Overlay notes: fork `CHANGELOG.md` |
| `RELEASES` | shipped package versions (immutable after publish; semver and `-evN`) |

`./envyos build <pkg>` dispatches generically to `packages-meta/<pkg>/build.sh`.
