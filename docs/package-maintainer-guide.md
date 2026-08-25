# EnvyOS package maintainer guide

Guide for **component repo maintainers**: implement the EnvyOS package harness in your repo, then wire it into the **distro** ([MeshEnvy/envyos](https://github.com/MeshEnvy/envyos)) when the fleet should ship your release.

Normative contract: [`.cursor/skills/envyos-package/SKILL.md`](.cursor/skills/envyos-package/SKILL.md) (agent skill). Human-oriented summary below.

Related: [`docs/component-release-policy.md`](component-release-policy.md), [`docs/integration-policy.md`](integration-policy.md), [`docs/distro-semver.md`](distro-semver.md).

---

## Part 1 — Implement the package harness

### What you are building

Each EnvyOS **component** is a standalone repo with its own semver, changelog, GitHub Releases, and a root **`./envyos`** CLI. The distro repo does **not** compile your code for release. It pins tested versions and bundles published assets.

```
Your repo                         Distro (envyos17)
─────────                         ─────────────────
./envyos build      dev           (optional bench consume)
./envyos prepare    full release  fetch GH assets at distro publish
./envyos publish    tag + upload
```

### Workspace layout

Component repos are **siblings** under a common parent (MeshEnvy bench):

```
$MESHENVY_ROOT/
  envyos/envyos17/     ← distro orchestration
  envycore/            ← firmware (meshcore-firmware)
  motatool/
  bootloader/
  …
```

Branch model on component forks: **`envyos/main`** (release), **`envyos/dev`** (integration). Distro uses **`main`** / **`dev`**.

### Core doctrine (required)

Two keys, never mixed on the CLI:

| Concept | Source | Used for |
|---------|--------|----------|
| **Branch slot** | Sanitized git branch (e.g. `envyos-main`) | `build` and `prepare` **output paths** |
| **Version** | One canonical file in **your** repo | Asset filenames, changelog, git tag, `RELEASED_VERSIONS` |

| Command | Takes version arg? | Responsibility |
|---------|-------------------|----------------|
| **`build`** | **No** | Fast local dev → `build/<branch-slot>/…` (package defines scope: one target, host only, …) |
| **`prepare`** | **No** | Full release artifact set → `build/<branch-slot>/…` + `dist/<branch-slot>/…` |
| **`bump`** | level only (`rc`, `patch`, `minor`, `major`) | **Only** command that mutates the version file |
| **`publish`** | Optional (defaults to version file) | Verify prepare, upload to GitHub, lock, tag |

Rules:

- **`build` and `prepare` never accept `vX.Y.Z`** on the command line. Set version with **`bump`** (or edit the version file), then `prepare`.
- Re-run **`prepare`** until artifacts look right. **`publish`** is the one-way door (upload, lock, tag).
- **No tag-triggered release CI.** Local `prepare` + `publish` (+ optional `ci.yml` for tests only).
- Pre-releases (`v0.1.2-rc0`) are first-class. Use **`bump rc`** to iterate `-rcN`.

Typical release in **your** repo:

```bash
./envyos bump rc              # or patch | minor | major
# promote CHANGELOG.md → ## [vX.Y.Z] - date; fresh ## [Unreleased]

./envyos prepare              # full set → dist/<branch-slot>/
./envyos publish --yes        # gh release + RELEASED_VERSIONS + tag
git push origin envyos/main
git push origin vX.Y.Z
```

### Adoption checklist (your repo)

| # | Item | Notes |
|---|------|--------|
| 1 | **`./envyos`** | Thin wrapper → `scripts/envyos` |
| 2 | **`scripts/envyos`** | Dispatches: `info`, `build`, `prepare`, `publish`, `bump`, `changelog` |
| 3 | **`scripts/build.sh`** | Local dev only; writes **branch slot**; rejects semver args |
| 4 | **`scripts/prepare.sh`** | Full release; writes **branch slot**; reads version from version file |
| 5 | **`scripts/publish.sh`** | Verify `.prepared` in `dist/<slot>/`; upload; lock; tag |
| 6 | **`scripts/version.sh`** | `read_build_slot`, semver normalize (incl. pre-releases), paths |
| 7 | **`scripts/changelog.sh`** | Shared pattern (copy from envycore or motatool) |
| 8 | **`scripts/package-lib.sh`** | `gh release create`, `verify_prepared_release`, … |
| 9 | **Version file** | `Cargo.toml`, `VERSION`, `envyboot/VERSION`, … (one canonical source) |
| 10 | **`CHANGELOG.md`** | Keep a Changelog; `## [Unreleased]` day-to-day |
| 11 | **`docs/change-management.md`** | Commit vs changelog rules |
| 12 | **`RELEASED_VERSIONS`** | One line per shipped `vX.Y.Z` (immutable after publish) |
| 13 | **`.cursor/skills/<pkg>-release/SKILL.md`** | Agent/workflow doc for your repo |
| 14 | **`.github/workflows/ci.yml`** | Tests only (optional) |

**Reference implementations**

| Package | Repo | Notes |
|---------|------|--------|
| Firmware | [envycore](https://github.com/MeshEnvy/meshcore-firmware) | PlatformIO; `VERSION`; motas + zip |
| CLI tool | [motatool](https://github.com/MeshEnvy/motatool) | Rust; `Cargo.toml`; multi-platform tarballs |

Copy structure from the closest peer, then adapt `prepare` (what “full release” means for your artifact types).

### Output layout (your repo)

```
build/<branch-slot>/     ← build + prepare (dev and release trees)
dist/<branch-slot>/      ← prepare release zips/tarballs (filenames include semver from version file)
build/…/vX.Y.Z/          ← optional immutable copy at publish lock (envycore motas)
dist/…/vX.Y.Z/           ← not used; dist stays on branch slot until publish
```

**Prepared marker:** `dist/<branch-slot>/.prepared` must record at least `version=` and match the version file when you run `publish`.

### GitHub Release assets (register early)

Distro publish **downloads by asset name** from your GitHub Release. Pick stable names and document them in both this file (after merge) and `envyos-package` skill.

| Package | Primary asset pattern | Example |
|---------|---------------------|---------|
| firmware | `firmware-vX.Y.Z.zip` | `firmware-v0.1.4.zip` |
| bootloader | `bootloader-vX.Y.Z.zip` | `bootloader-v0.1.2.zip` |
| motatool | `motatool-<ver>-<target>.tar.gz` per platform | `motatool-0.1.2-rc0-x86_64-unknown-linux-gnu.tar.gz` |
| mcmt-gateway | `mcmt-gateway-vX.Y.Z.zip` | (when bundled) |
| peaky | `peaky-vX.Y.Z.zip` | (when bundled) |

Your `publish` script must upload assets that match what the distro expects (or you add a distro-side fetch adapter when integrating).

### Consuming siblings (optional)

If another package invokes your binary at dev time (envycore → motatool), resolve **`../<sibling>/build/<branch-slot>/…`**, not version-keyed paths. Override env var (e.g. `MOTATOOL=`) for exceptions.

---

## Part 2 — Add the package to the EnvyOS distro

Do this when the fleet should **ship and pin** your component in a distro release. Components that are tracked but not bench-tested stay **out** of the bundle ([`component-release-policy.md`](component-release-policy.md)).

### Prerequisites

1. **At least one GitHub Release** cut from your repo via `./envyos publish` (assets on the tag you want to pin).
2. **Bench validation** on `envyos/dev` / distro `dev` with that version (OTA, CLI, hardware, … as applicable).
3. Agreement on **manifest key** name (usually the repo short name: `motatool`, `mcmt-gateway`, `peaky`).

### Distro files to touch

| File | Purpose |
|------|---------|
| **`ENVYOS_VERSIONS`** | Semver pin per component (`motatool=0.1.2`, …) plus `distro=` fleet tag |
| **`COMPONENTS.lock`** | Git SHAs for pinned component repos at publish |
| **`scripts/version.sh`** | `read_<pkg>_version`, `list_release_component_ids`, `component_build_dir`, … |
| **`scripts/build-lib.sh`** | Stage/download release assets into bench tree (if not already generic) |
| **`CHANGELOG.md`** (distro) | User-facing note when adding or bumping bundled component |
| **`.cursor/skills/envyos-package/SKILL.md`** | Registered asset names table |

### Step-by-step (distro maintainer)

#### A. First-time inclusion (new bundled component)

1. **Ship your component release** (Part 1) and confirm assets on GitHub.
2. **Add manifest key** to `ENVYOS_VERSIONS` on distro `dev`:
   ```ini
   my-tool=0.1.0
   ```
3. **Extend `list_release_component_ids()`** in `scripts/version.sh` if the component is optional (see `mcmt-gateway`, `peaky` gating). Core trio today: `firmware`, `bootloader`, `motatool`.
4. **Wire version read** in `scripts/version.sh`:
   - `read_my_tool_version` → reads `ENVYOS_VERSIONS` or your pin file
   - `component_version_at_publish` case arm
   - `component_build_dir` case arm (where bench cache lives)
   - `component_zip_basename` / download path if distro expects a zip wrapper
5. **Implement or extend fetch** in `scripts/build-lib.sh` (or reuse `materialize_release_download`) so `./envyos build` / publish can pull your GH Release assets into `build/<branch-slot>/bench/…`.
6. **Set sibling path** if needed (e.g. `MY_TOOL_ROOT` default `$MESHENVY_ROOT/my-tool`).
7. **Bench test** full `./envyos build` on distro `dev` with the new pin.
8. **Document** in distro `CHANGELOG.md` under `## [Unreleased]` (added bundled component …).
9. **Distro publish** when ready: `./envyos semver suggest` → `./envyos publish vX.Y.Z --yes`. That refreshes `COMPONENTS.lock`, sets `distro=`, and uploads the fleet bundle.

#### B. Routine pin bump (already bundled)

1. Cut new release in **your** repo (`bump` → changelog → `prepare` → `publish`).
2. On distro `dev`, bump the pin in **`ENVYOS_VERSIONS`**:
   ```bash
   ./envyos bump patch my-tool    # or edit the file
   ```
3. Run **`./envyos build`** (or targeted component build) to stage the new GH assets.
4. Validate on bench.
5. Distro **`./envyos publish`** when the fleet is ready. Semver rules: [`distro-semver.md`](distro-semver.md) (component patch → distro patch; new component or minor upstream → distro minor).

#### C. `COMPONENTS.lock`

At distro publish, record your repo’s git SHA:

```ini
my_tool_repo=MeshEnvy/my-tool
my_tool_sha=<full sha at pinned release tag>
```

Follow existing `firmware_sha` / `bootloader_sha` pattern in [`COMPONENTS.lock`](../COMPONENTS.lock).

### Inclusion rule

> A component appears in the **distro GitHub Release bundle** only when it is **bench-gated** and listed in `list_release_component_ids` for that distro version.

Optional tools can ship releases from their own repos without being in every EnvyOS tag.

### Verification checklist

- [ ] `./envyos info` in **your** repo shows slot, version, prepared dist status
- [ ] `./envyos prepare` + `./envyos publish` produces GH assets with registered names
- [ ] Distro `./envyos build` stages your assets under `build/<branch-slot>/bench/…`
- [ ] `ENVYOS_VERSIONS` pin matches your published tag
- [ ] Distro `./envyos publish --dry-run` lists your component in the release manifest
- [ ] `COMPONENTS.lock` SHA matches the tag you intend to pin

---

## Quick reference

| Layer | Version lives in | Build output | Release cut |
|-------|------------------|--------------|-------------|
| **Component** | `Cargo.toml` / `VERSION` / … | `build/<branch-slot>/`, `dist/<branch-slot>/` | `./envyos publish` |
| **Distro** | `ENVYOS_VERSIONS` | `build/<branch-slot>/bench/…` | `./envyos publish` (fleet tag) |

Questions or new component types: extend [`envyos-package` SKILL](.cursor/skills/envyos-package/SKILL.md) and this doc in the same PR.
