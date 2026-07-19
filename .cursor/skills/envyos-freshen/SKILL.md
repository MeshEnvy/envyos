---
name: envyos-freshen
description: >-
  Fleet policy: companion tag + vk496 OTA + EnvyOS overlay earns an EnvyOS
  version (VERSION / v0.1.x / motas/). /freshen builds that bundle; /freshen dev
  is integration-only. Also refreshes vendor/otafix.
disable-model-invocation: true
---

# EnvyOS freshen (`/freshen`)

## Fleet policy (canonical)

An **EnvyOS version** (`VERSION` at ota repo root → `v0.1.x` git tag → `motas/<version>/`) is earned **only** by this three-layer bundle:

```text
companion-v*          (latest official MeshCore release tag)
  + vk496/feature/ota-lora   (whole branch — OTA + vk's dev snapshot)
  + EnvyOS overlay           (FRESHEN.lock topic commits)
  = fleet release            → bump VERSION, build motas, tag v0.1.x
```

**Not** official MeshCore alone — no OTA until upstream merges vk496.

**Not** `meshcore/dev` tip — too bleeding-edge for fleet.

Merging vk496 onto the companion tag does **not** produce a pure upstream release. vk496 tracks `meshcore/dev` to stay mergeable, so the vk496 branch carries a **frozen dev snapshot** (whatever vk last absorbed). That snapshot ships as part of the bundle until OTA lands upstream.

When OTA merges upstream (or is rejected): drop the vk496 layer; policy becomes **companion tag + EnvyOS overlay**.

Record the exact SHAs in `envyos/FRESHEN.lock` after each release freshen.

---

## Commands

| Command | Purpose | Earns EnvyOS version? |
|---------|---------|------------------------|
| `/freshen` | Release bundle (default) | **Yes** — after tests pass |
| `/freshen dev` | Integration with `meshcore/dev` tip | **No** |

Run **both** `envyos` and `vendor/otafix` unless scoped.

`envyos/main` may contain extra dev work between releases — fine for development. **Only** a completed release freshen + VERSION bump + `./scripts/build-mota.sh` ships to fleet.

**Feature branches:** branch from `envyos/main`, never from `meshcore/dev`.

---

## Layers

| Submodule | Layer 1 | Layer 2 — vk496 | Layer 3 — overlay |
|-----------|---------|-----------------|-------------------|
| `envyos/` | `companion-v*` | `vk496/feature/ota-lora` | `envyos/FRESHEN.lock` |
| `vendor/otafix/` | `0.9.2-OTAFIX*` (`oltaco`) | `vk496/feature/ota-delta-apply` | `vendor/otafix/FRESHEN.lock` |

Otafix follows the same pattern: oltaco tag + vk496 delta apply (+ overlay if any).

## Remotes

**envyos/** — `meshcore`, `vk496`, `origin`

**vendor/otafix/** — `oltaco`, `vk496`, `origin`

```bash
git fetch meshcore --tags && git fetch vk496 && git fetch origin --tags
```

Do **not** default to `vk496/ota` (MeshCore) or `vk496/mota` (otafix).

---

## Part A — envyos (release — `/freshen`)

### Refresh overlay list

```bash
cd envyos
git fetch meshcore --tags && git fetch vk496 && git fetch origin --tags
BASE=$(git tag -l 'companion-v*' --sort=-v:refname | head -1)
VK=vk496/feature/ota-lora

for topic in origin/feature/next-hop-retry origin/fix/ota-ls-start-at-n; do
  git log --oneline --no-merges "$topic" --not "$BASE" --not "$VK"
done

git log --oneline --no-merges envyos/main --grep='^(feat|chore)\(envyos\)' --not "$BASE" --not "$VK"
```

Curate into `FRESHEN.lock`. vk496-only work → layer 2, not overlay.

### Procedure

```bash
cd envyos
git fetch meshcore --tags && git fetch vk496 && git fetch origin --tags
BASE=$(git tag -l 'companion-v*' --sort=-v:refname | head -1)
WORK=envyos/freshen/${BASE}
VK=vk496/feature/ota-lora

git checkout -B "$WORK" "$BASE"
git merge --no-ff "$VK" -m "freshen: merge vk496 OTA onto ${BASE}"
# resolve conflicts (matrix below)

git cherry-pick <overlay shas from FRESHEN.lock>   # in order

git checkout envyos/main
git merge --no-ff "$WORK" -m "freshen: release pin ${BASE}"
git push origin envyos/main
```

Update `envyos/FRESHEN.lock`, then **ota repo**:

1. Bump **`VERSION`** (patch unless milestone)
2. `./scripts/build-mota.sh`
3. Git tag **`v0.1.x`** on ota repo
4. Bump `envyos` / `vendor/otafix` submodule pointers if needed

```yaml
mode: release
companion_tag: companion-v1.16.0
companion_sha: <short sha>
vk496_ref: feature/ota-lora
vk496_sha: <short sha>
overlay_commits: [...]
last_freshen: YYYY-MM-DD
```

### Dev integration (`/freshen dev`)

Same procedure but `BASE=meshcore/dev`, `WORK=envyos/freshen/dev-$(date +%Y%m%d)`, `mode: dev` in lock file. Preview upstream API drift and vk496 conflicts. **Do not bump VERSION or build fleet motas.**

### Conflict resolution (envyos)

| Path / area | Prefer |
|-------------|--------|
| `src/helpers/ota/**`, `test/test_ota/**` | vk496 / EnvyOS overlay |
| `Mesh.cpp`, `MeshTables`, core routing | **companion tag** on release freshen — e.g. `wasSeen` not vk496's stale `hasSeen` |
| EnvyOS overlay (hop retry, etc.) | overlay commits |
| `CommonCLI.*`, `platformio.ini` | companion tag structure + re-apply OTA flags |
| Variant `ENABLE_OTA` | keep enabled where vk496/EnvyOS had it |

**Narrow take** when vk496 merge is noisy: vk496 for `src/helpers/ota/**` only; companion tag for everything else.

---

## Part B — otafix (always with release `/freshen`)

```bash
cd vendor/otafix
git fetch oltaco --tags && git fetch vk496 && git fetch origin --tags
TAG=$(git tag -l '0.9.2-OTAFIX*' --sort=-v:refname | head -1)
WORK=envyos/freshen/${TAG}
VK=vk496/feature/ota-delta-apply

git checkout -B "$WORK" "$TAG"
git merge --no-ff "$VK" -m "freshen: merge vk496 OTA delta apply onto $TAG"
# resolve; cherry-pick overlay

git checkout master
git merge --ff-only "$WORK"
git push origin master
```

Keep vk496 detools stack on in-place apply conflicts; `ota_layout.h` ↔ `OtaFlashLayout_nrf52.h`.

---

## Validation (required before VERSION bump)

```bash
cd envyos && pio test -e native -f test_ota && pio run -e RAK_WisMesh_Tag_repeater
./scripts/build-bl.sh wismesh_tag
./scripts/build-mota.sh   # only after release freshen passes
```

---

## Report template

```markdown
## Freshen report

### envyos (mode: release | dev)
- **Bundle:** companion-vX.Y.Z @ <sha> + vk496/feature/ota-lora @ <sha> + N overlay commits
- **Earns EnvyOS version:** yes (release) / no (dev)
- **Tests/build:** …
- **VERSION bump:** v0.1.x (release only)

### otafix
- **Bundle:** oltaco tag @ <sha> + vk496/feature/ota-delta-apply @ <sha>
- **build-bl.sh:** …
```

## Do not

- Tag `v0.1.x` or ship `motas/` without the full release bundle (companion + vk496 + overlay)
- Treat companion tag alone as fleet-ready (no OTA)
- Deploy **`meshcore/dev`** or `/freshen dev` output to fleet
- Assume `envyos/main` equals the last release bundle — check `FRESHEN.lock`
- Branch EnvyOS features from `meshcore/dev`
- Freshen envyos without otafix (unless scoped)
- Commit freshen WIP without tests passing
