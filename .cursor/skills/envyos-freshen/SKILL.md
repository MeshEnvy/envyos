---
name: envyos-freshen
description: >-
  Refresh envyos/main and vendor/otafix onto latest upstream release tags plus
  vk496 OTA stacks, preserving EnvyOS overlay commits. Use when the user says
  /freshen or asks to update, sync, or rebase envyos and otafix from upstream.
disable-model-invocation: true
---

# EnvyOS freshen (`/freshen`)

Rebuild **`envyos/main`** and **`vendor/otafix`** (`origin/master`) from three layers each. Run **both** submodules every `/freshen` unless the user scopes to one.

| Submodule | Layer 1 — upstream pin | Layer 2 — vk496 OTA | Layer 3 — EnvyOS overlay |
|-----------|----------------------|---------------------|--------------------------|
| `envyos/` | Latest `companion-v*` on `meshcore` | `vk496/feature/ota-lora` | `envyos/FRESHEN.lock` |
| `vendor/otafix/` | Latest `0.9.2-OTAFIX*` tag on `upstream` | `vk496/feature/ota-delta-apply` | `vendor/otafix/FRESHEN.lock` |

Manifests: `envyos/FRESHEN.lock`, `vendor/otafix/FRESHEN.lock`.

Also see `envyos-meshcore` for remotes, feature-branch workflow, and upstream PR targets.

## Remotes (verify on each freshen)

**envyos/**

| Remote | Repository |
|--------|------------|
| `meshcore` | `meshcore-dev/MeshCore` |
| `vk496` | `vk496/MeshCore` |
| `origin` | `MeshEnvy/meshcore-firmware` |

**vendor/otafix/**

| Remote | Repository |
|--------|------------|
| `upstream` | `oltaco/Adafruit_nRF52_Bootloader_OTAFIX` |
| `vk496` | `vk496/Adafruit_nRF52_Bootloader_OTAFIX` |
| `origin` | `MeshEnvy/Adafruit_nRF52_Bootloader_OTAFIX` |

Add missing remotes before fetching. Do **not** default to `vk496/ota` (MeshCore) or `vk496/mota` (otafix) — divergent legacy lines.

---

## Part A — envyos

### Tag policy

1. `git fetch meshcore --tags`
2. Newest **`companion-v*`** tag → record in `envyos/FRESHEN.lock` → `upstream_tag`.

If companion and repeater tags diverge, stop and ask.

### Overlay tracking (`envyos/FRESHEN.lock`)

Do **not** use `envyos/main --not TAG --not VK` alone — hundreds of upstream merges.

Collect topic-branch tips merged into `envyos/main`:

```bash
cd envyos
git fetch meshcore vk496 origin --tags
TAG=$(git tag -l 'companion-v*' --sort=-v:refname | head -1)
VK=vk496/feature/ota-lora

for topic in origin/feature/next-hop-retry origin/fix/ota-ls-start-at-n; do
  git log --oneline --no-merges "$topic" --not "$TAG" --not "$VK"
done

git log --oneline --no-merges envyos/main --grep='^(feat|chore)\(envyos\)' --not "$TAG" --not "$VK"
```

Curate into `FRESHEN.lock`: drop commits now in the new tag; append new topic work; vk496-only → layer 2.

### Procedure

```bash
cd envyos
git fetch meshcore vk496 origin --tags
TAG=$(git tag -l 'companion-v*' --sort=-v:refname | head -1)
WORK=envyos/freshen/${TAG}
VK=vk496/feature/ota-lora

git checkout -B "$WORK" "$TAG"
git merge --no-ff "$VK" -m "freshen: merge vk496 OTA onto $TAG"
# resolve conflicts (matrix below)

# Replay overlay commits from FRESHEN.lock (in order)
git cherry-pick <sha>   # repeat; resolve failures before continuing

git checkout envyos/main
git merge --ff-only "$WORK"
git push origin envyos/main
```

Update `envyos/FRESHEN.lock` (tag, vk496 sha, overlay list, date).

### Conflict resolution (envyos)

| Path / area | Prefer |
|-------------|--------|
| `src/helpers/ota/**`, `test/test_ota/**` | vk496 / EnvyOS overlay |
| `Mesh.cpp`, routing, hop retry | EnvyOS overlay if present; else upstream |
| `CommonCLI.*`, `platformio.ini` | Upstream structure + re-apply EnvyOS/OTA flags |
| Variant `platformio.ini` `ENABLE_OTA` | Keep OTA enabled where vk496/EnvyOS had it |
| Upstream API renames | Take upstream names; port OTA call sites |

---

## Part B — otafix

### Tag policy

1. `git fetch upstream vk496 origin --tags`
2. Newest **`0.9.2-OTAFIX*`** tag (e.g. `0.9.2-OTAFIX2.3-BP1.3`) → `vendor/otafix/FRESHEN.lock` → `upstream_tag`.

**Note:** the 2.3 tag and `vk496/feature/ota-delta-apply` both add in-place apply via **different implementations**. EnvyOS firmware (`OtaFlashLayout_nrf52.h`) must stay byte-identical with `vendor/otafix/src/ota_layout.h` — on conflict in OTA apply paths, **keep the vk496/EnvyOS detools stack**, port board/BLE fixes from the tag.

### Overlay tracking (`vendor/otafix/FRESHEN.lock`)

```bash
cd vendor/otafix
git fetch upstream vk496 origin --tags
TAG=$(git tag -l '0.9.2-OTAFIX*' --sort=-v:refname | head -1)
VK=vk496/feature/ota-delta-apply

for topic in origin/feature/docker-build; do
  git log --oneline --no-merges "$topic" --not "$TAG" --not "$VK"
done
```

Docker build merged into vk496 — overlay is often empty. Append only MeshEnvy-only commits not yet on the vk branch.

### Procedure

Head branch is **`master`** on `origin` (not detached submodule SHA long-term).

```bash
cd vendor/otafix
git fetch upstream vk496 origin --tags
TAG=$(git tag -l '0.9.2-OTAFIX*' --sort=-v:refname | head -1)
WORK=envyos/freshen/${TAG}
VK=vk496/feature/ota-delta-apply

git checkout -B "$WORK" "$TAG"
git merge --no-ff "$VK" -m "freshen: merge vk496 OTA delta apply onto $TAG"
# resolve conflicts (matrix below)

# Replay overlay commits from FRESHEN.lock

git checkout master
git merge --ff-only "$WORK"
git push origin master
```

Update `vendor/otafix/FRESHEN.lock`. Bump **`vendor/otafix`** submodule pointer in the ota repo.

### Conflict resolution (otafix)

| Path / area | Prefer |
|-------------|--------|
| `src/ota_*.c/h`, `src/ota_layout.h`, `lib/detools/**` | vk496 / EnvyOS overlay (layer 2+3) |
| `test/readback_test.c`, apply-sim harness | vk496 / overlay |
| Board defs (`src/boards/**`), BLE TX, softdevice | Upstream tag |
| Official 2.3 in-place apply vs vk496 detools stack | **vk496 stack** — re-port tag fixes around it |

After merge, verify layout sync:

```bash
diff -u vendor/otafix/src/ota_layout.h \
  <(grep -A999 'OTA_FLASH' envyos/src/helpers/ota/OtaFlashLayout_nrf52.h | head -40)
# Or compare documented constants — must match for in-place OTA
```

---

## Validation (both submodules)

**envyos:**

```bash
cd envyos
pio test -e native -f test_ota
pio run -e RAK_WisMesh_Tag_repeater
```

**otafix:**

```bash
./scripts/build-bl.sh wismesh_tag
```

From ota repo root (optional): `./scripts/build-mota.sh --target wismesh-tag-repeater`

---

## Ota repo submodule bump

After both parts pass:

```bash
cd /path/to/ota
git add envyos vendor/otafix
# commit only when user asks (/commit)
```

---

## Report template

```markdown
## Freshen report

### envyos
- **Upstream tag:** companion-vX.Y.Z (+N on meshcore/main since tag)
- **vk496:** feature/ota-lora @ <sha>
- **Overlay replayed:** …
- **Tests/build:** …

### otafix
- **Upstream tag:** 0.9.2-OTAFIX2.x-BPx.x
- **vk496:** feature/ota-delta-apply @ <sha>
- **Overlay replayed:** …
- **Layout sync:** ok / drift — …
- **build-bl.sh:** pass / fail

### Follow-ups
- …
```

## Do not

- Freshen envyos without otafix (unless user explicitly scopes)
- Merge `meshcore/dev` or `meshcore/main` tip when user asked for **latest tagged release**
- Use `vk496/mota` or `vk496/ota` as default vk branches
- Accept `ota_layout.h` drift between otafix and envyos
- Commit freshen WIP without tests passing
