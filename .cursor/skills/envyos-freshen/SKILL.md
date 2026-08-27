---
name: envyos-freshen
description: >-
  MeshCore companion integrate + EnvyOS overlay preservation; OTA PRs still go
  to vk496. /freshen and /integrate are aliases. Also /freshen dev spike.
  Policy: docs/integration-policy.md.
disable-model-invocation: true
---

# EnvyOS integrate (`/freshen`, `/integrate`)

**Policy:** [`docs/integration-policy.md`](../../docs/integration-policy.md).

## Fleet policy (canonical)

**Ship head:** `envyos/main` on each MeshEnvy fork. Tag firmware `v0.1.x` on envycore after bench; distro bundles pinned releases.

**Companion integrate** (periodic — e.g. companion v1.16 → v1.17):

```text
meshcore companion-vX.Y.Z
  + merge envyos/main overlay (OTA + EnvyOS customizations already on branch)
  = bench → bump MANIFEST.json / tag when publishing
```

**Not** in normal flow:

- Cherry-pick replay of `vk496/feature/ota-lora` (bootstrap retired — OTA already on `envyos/main`)
- Wholesale merge of vk496 branches
- `meshcore/dev` tip to fleet (`/freshen dev` is spike-only)

**vk496 remains** the **OTA upstream PR target** until meshcore-dev absorbs LoRa OTA. Send OTA patches there; merge the same commits to `envyos/main`. Do not wait on vk merge to ship.

**Day-to-day:** feature branches → `envyos/main` via [`envycore/BACKLOG.md`](../../../envycore/BACKLOG.md). No freshen required.

Record companion integrates in `envycore/FRESHEN.lock` (`policy_version: 2`).

---

## Commands

| Command | Purpose | Earns EnvyOS version? |
|---------|---------|------------------------|
| `/integrate` or `/freshen` | Merge new `companion-v*` into `envyos/main` | **After** bench + publish workflow |
| `/freshen dev` | Spike: merge `meshcore/dev` preview | **No** |

Run envycore integrate unless scoped. Bootloader: only when otafix base tag bumps — see Part B.

---

## Part A — envycore (companion integrate)

### Prerequisites

```bash
cd envycore
git fetch meshcore --tags && git fetch origin --tags
# vk496 fetch only when opening/syncing an OTA PR — not required for integrate
```

### Procedure

```bash
cd envycore
BASE=$(git tag -l 'companion-v*' --sort=-v:refname | head -1)
WORK=envyos/integrate/${BASE}

git checkout -B "$WORK" "meshcore/${BASE}"
git merge envyos/main -m "integrate: ${BASE} + EnvyOS overlay"
# resolve conflicts — see integration-policy.md conflict table

# validation (required before merging to main)
pio test -e native -f test_ota
pio run -e RAK_4631_repeater_slim   # or EC-001 bench gate

git checkout envyos/main
git merge --no-ff "$WORK" -m "integrate: ${BASE}"
git push origin envyos/main
```

Update `envycore/FRESHEN.lock`:

```yaml
policy_version: 2
mode: integrate
meshcore_tag: companion-v1.17.0
meshcore_sha: <short>
envyos_main_sha: <short after merge>
last_integrate: YYYY-MM-DD
```

Then publish path (envyos repo): bump `MANIFEST.json`, `./envyos build`, component tags/releases as ready — see `component-release-policy.md`.

### EC-001 pattern

First v1.17 integrate may use an existing branch (`origin/envyos/freshen/companion-v1.17.0`) plus explicit commits — same merge semantics, not vk496 replay.

### Dev spike (`/freshen dev`)

```bash
WORK=envyos/integrate/dev-$(date +%Y%m%d)
git checkout -B "$WORK" meshcore/dev
git merge envyos/main -m "spike: meshcore/dev + overlay"
```

Preview API drift only. **Do not** bump `MANIFEST.json` or ship motas.

### Conflict resolution

See [`docs/integration-policy.md`](../../docs/integration-policy.md) § Conflict resolution.

---

## Part B — bootloader (otafix base bump only)

When oltaco ships a new `0.9.2-OTAFIX*` tag:

```bash
cd bootloader
git fetch oltaco --tags && git fetch origin --tags
TAG=$(git tag -l '0.9.2-OTAFIX*' --sort=-v:refname | head -1)
WORK=envyos/integrate/${TAG}

git checkout -B "$WORK" "oltaco/${TAG}"
git merge envyos/main -m "integrate: ${TAG} + EnvyOS overlay"
# preserve delta-apply stack from envyos/main; do not re-merge vk496 wholesale

git checkout envyos/main
git merge --no-ff "$WORK"
git push origin envyos/main
```

OTA bootloader **patches** still PR to `vk496/feature/ota-delta-apply` and merge to `envyos/main`.

---

## Validation (required before fleet bump)

```bash
cd packages/meshcore && pio test -e native -f test_ota && pio run -e RAK_WisMesh_Tag_repeater
./envyos build bootloader wismesh_tag    # when bootloader touched
./envyos build meshcore
```

---

## Report template

```markdown
## Integrate report

### meshcore
- **MeshCore base:** companion-vX.Y.Z @ <sha>
- **envyos/main after merge:** <sha>
- **vk496 replay:** no
- **Tests/build:** …
- **FRESHEN.lock updated:** policy_version 2

### bootloader (if run)
- **oltaco tag:** …
- **bootloader recipe:** …
```

## Do not

- Replay `FRESHEN.lock` `ota_commits` or run `cherry-pick-envyos-overlay.sh` on companion bumps (legacy bootstrap)
- Use vk496 as integrate base or merge `vk496/feature/ota-lora` wholesale
- Skip merging OTA fixes to `envyos/main` while waiting on vk496 PR merge
- Send **OTA** patches only to meshcore-dev (not in mainline yet — use vk496)
- Deploy `/freshen dev` or `meshcore/dev` output to fleet
- Rebuild or delete released `build/motas/v0.1.0/` trees (immutable — `MANIFEST.json releases`)
- Commit integrate WIP without tests passing

## Legacy bootstrap (reference only)

2026-07 freshen: reset to `companion-v1.16.0`, cherry-pick vk496 `ota:` commits + overlay. Documented in `FRESHEN.lock` `ota_commits` and `envycore/scripts/cherry-pick-envyos-overlay.sh`. **Retired** — see `integration-policy.md`.
