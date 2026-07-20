---
name: envyos-meshcore
description: >-
  EnvyOS distro git workflow: envyos/main on all MeshEnvy forks (firmware,
  motatool, otafix), vk496 PR bases, feature branches, merge-back, and monorepo
  submodule pins. Use when working on envyos/main, motatool, bootloader,
  vk496 remotes, upstream PRs, or submodule bumps.
---

# EnvyOS MeshCore distro

EnvyOS is MeshEnvy's integration distro of [MeshCore](https://github.com/meshcore-dev/MeshCore). **`envyos/main` is the integration head on every MeshEnvy fork** in the OTA stack — firmware, motatool, and otafix — even when open vk496 PRs use different base branches.

Firmware lives in `envycore/`; `motatool/` and `bootloader/` at repo root — all in the `ota` monorepo. EnvyOS versioning is **independent** of upstream MeshCore release tags (see `ENVYOS_VERSIONS` at ota repo root).

## Distro repos and remotes

| Submodule | MeshEnvy fork (`origin`) | vk496 remote | vk496 PR base |
|-----------|--------------------------|--------------|---------------|
| `envycore/` | `MeshEnvy/meshcore-firmware` | `vk496/MeshCore` | `feature/ota-lora` |
| `motatool/` | `MeshEnvy/motatool` (`meshenvy` remote in submodule) | `vk496/motatool` | `main` |
| `bootloader/` | `MeshEnvy/Adafruit_nRF52_Bootloader_OTAFIX` | `vk496/Adafruit_nRF52_Bootloader_OTAFIX` | `feature/ota-delta-apply` |

All three MeshEnvy forks use **`envyos/main`** as the GitHub default branch and distro integration head.

## Git remotes (firmware — `envycore/`)

| Remote | Repository | Role |
|--------|------------|------|
| `origin` | `MeshEnvy/meshcore-firmware` | EnvyOS fork — push feature branches here |
| `vk496` | `vk496/MeshCore` | vk496's MeshCore fork — OTA and vk-specific work |
| `meshcore` | `meshcore-dev/MeshCore` | Upstream MeshCore — core protocol/features |

Verify: `git remote -v`

## Branches

| Branch | Purpose |
|--------|---------|
| **`envyos/main`** | **Distro integration head** — union of all EnvyOS features merged together. Default branch on MeshEnvy forks. **Bench builds** (`./scripts/build.sh`) and day-to-day dev use this. |
| **`feature/<name>`** | **One upstream PR** — single-purpose; branched from that PR's base (see table below). Push to `origin` for the cross-fork PR only. |
| **`fix/<name>`** | Small targeted fix for one upstream PR |

### Two tracks (always)

Every feature has **two separate tracks**:

| Track | Branch | Contains |
|-------|--------|----------|
| **Distro** | `envyos/main` | Hop retry + log tail + OTA overlay + everything shipped on the bench |
| **Upstream PR** | `feature/<name>` | **Only** commits that belong in that one PR — no other EnvyOS features |

```text
meshcore/dev ──► feature/next-hop-retry ──► PR #2980 → meshcore-dev/MeshCore
                      │                         (hop retry only — pure base)
                      │
feature/log-tail ──► (separate PR, when opened)
                      │
                      └── both merge ──► envyos/main (all features together)
```

**Rules for `feature/<name>` PR branches:**

- Branch from the **PR base** (e.g. `meshcore/dev` for core mesh, `vk496/feature/ota-lora` for OTA).
- Keep the branch **pure**: only commits intended for that upstream PR.
- **Do not** cherry-pick or merge **other** features onto a PR branch (log tail onto `feature/next-hop-retry`, etc.).
- After opening the PR, **merge the feature into `envyos/main`**. While the PR stays open, **keep the PR branch in sync** with feature-specific fixes (see [Open PR sync](#open-pr-sync-policy) below).

Never treat a feature branch as the distro head. Never flash/build bench firmware from a PR branch unless explicitly testing that PR in isolation.

### Open PR sync policy

While an upstream PR is **open**, every commit that belongs to that feature must land on **both** tracks:

1. **`envyos/main`** — distro integration (bench builds).
2. **`feature/<name>`** on MeshEnvy `origin` — the PR head the upstream repo watches.

```bash
# After committing on envyos/main (or on the feature branch):
cd envycore
git checkout feature/<name>
git cherry-pick <sha>    # or merge/rebase from envyos/main if safe
git push origin feature/<name>
```

| Situation | Where it goes |
|-----------|----------------|
| Bugfix / improvement for feature X | `envyos/main` **and** `feature/<x>` (push both) |
| New unrelated EnvyOS feature Y | `envyos/main` only; separate `feature/<y>` when PR opened |
| Cross-feature mistake | **Never** — do not put feature Y on `feature/<x>` |

When the upstream PR **merges**, stop pushing to the feature branch; rebase/pull the new base into `envyos/main` and delete or archive the feature branch.

### Dual-track: distro vs vk496 / meshcore PR

A feature often exists on **two tracks**:

1. **`feature/<name>`** — branched from the vk496 or meshcore PR base; opened as cross-fork PR (`MeshEnvy:feature/<name>`). **Single-purpose.**
2. **`envyos/main`** — MeshEnvy integration; merge every shipped feature here **even while upstream PRs are open**.

These diverge by design: `envyos/main` accumulates the full EnvyOS stack; each PR branch stays rebasable on its upstream base. When an upstream PR merges, pull/rebase that base into `envyos/main` if needed.

The **`ota` monorepo** pins submodule commits (not branch names). Bump pointers at release freshen or when intentionally advancing; local `envycore/` checkout should be **`envyos/main`** for bench builds.

## Feature workflow

For each feature:

1. **Choose the vk496 PR base** — branch from the remote that owns the target:
   - Core mesh / repeater behavior → `meshcore/dev` (PR to meshcore-dev)
   - OTA firmware → `vk496/feature/ota-lora`
   - motatool → `vk496/main`
   - otafix → `vk496/feature/ota-delta-apply`
2. **Implement on a focused branch** — e.g. `feature/ota-stage-ceiling`
3. **Push to MeshEnvy `origin`** (or `meshenvy` for motatool) — `git push -u origin feature/<name>`
4. **Open vk496 PR** — cross-fork: `--head MeshEnvy:feature/<name>`
5. **Merge into `envyos/main`** on the MeshEnvy fork — even while the vk496 PR is open
6. **Push `envyos/main`** — `git push origin envyos/main`

```text
meshcore/dev ──► feature/foo ──► PR → meshcore-dev/MeshCore
                      │
                      └── merge ──► envyos/main (origin)
```

### PR targets (examples)

| Feature | PR branch (`origin`) | PR base | PR repo | On `envyos/main`? |
|---------|----------------------|---------|---------|-------------------|
| Next-hop retry | `feature/next-hop-retry` | `dev` | `meshcore-dev/MeshCore` [#2980](https://github.com/meshcore-dev/MeshCore/pull/2980) | yes (hop retry only on PR branch) |
| Log tail serial | `feature/log-tail-serial` | `dev` | `meshcore-dev/MeshCore` [#2991](https://github.com/meshcore-dev/MeshCore/pull/2991) | yes |
| OTA ls pagination | `fix/ota-ls-start-at-n` | `feature/ota-lora` | `vk496/MeshCore` | yes |
| OTA staging ceiling | `feature/ota-stage-ceiling` | `feature/ota-lora` | `vk496/MeshCore` | yes |
| motatool delta layout | `meshenvy/feature/ota-stage-ceiling` | `main` | `vk496/motatool` | yes |
| otafix scan ceiling | `feature/ota-stage-ceiling` | `feature/ota-delta-apply` | `vk496/Adafruit_nRF52_Bootloader_OTAFIX` | yes |
| EnvyOS-only glue | n/a | n/a | no upstream PR | `envyos/main` only |

Cross-fork PR when you lack write access to the target:

```bash
gh pr create -R meshcore-dev/MeshCore \
  --draft --base dev --head MeshEnvy:feature/next-hop-retry \
  --title "..." --body "..."
```

```bash
gh pr create -R vk496/MeshCore \
  --base feature/ota-lora --head MeshEnvy:fix/ota-ls-start-at-n \
  --title "..." --body "..."
```

### Merge into envyos/main

Same pattern in each submodule (`envycore/`, `motatool/`, `bootloader/`):

```bash
cd envycore   # or motatool, bootloader
git checkout envyos/main
git pull origin envyos/main
git merge feature/<name>   # resolve conflicts
git push origin envyos/main
```

Conflict hotspots when merging upstream features into EnvyOS: `Mesh.cpp`, `CommonCLI.*`, `platformio.ini`, test mocks (OTA vs upstream API changes).

## Versioning

EnvyOS version is **not** upstream MeshCore's `companion-v1.16.0` tag scheme.

- **Canonical file:** `ENVYOS_VERSIONS` at ota repo root (`distro`, `firmware`, `bootloader`, `motatool`)
- **Build:** `./scripts/build-mota.sh` reads `distro` → `build/motas/v0.1.0/`; `./scripts/build-mota.sh v0.1.1` overrides for one-off builds and auto-deltas from prior patch if present
- **Firmware stamp:** `-DFIRMWARE_VERSION` via `PLATFORMIO_BUILD_FLAGS` in `build-mota.sh`
- **Explicit delta base:** `./scripts/build-mota.sh v0.1.2 --base v0.1.0`

Bump `ENVYOS_VERSIONS` at repo root for distro milestones. Use patch tags (`v0.1.0`, `v0.1.1`, …) for bench iterations.

## Agent checklist

When shipping EnvyOS work:

- [ ] Feature branch based on correct **PR base** (meshcore/dev, vk496 base, etc.)
- [ ] PR branch contains **only** that feature's commits (no cross-feature cherry-picks)
- [ ] Pushed to MeshEnvy fork (`origin` / `meshenvy`)
- [ ] Upstream PR opened (if upstreamable)
- [ ] Merged into **`envyos/main`** on MeshEnvy fork and pushed
- [ ] **Open PR:** feature-specific follow-ups pushed to **`feature/<name>`** as well as `envyos/main`
- [ ] Bench builds use **`envyos/main`** checkout in `envycore/`, not a PR branch
- [ ] Version references use EnvyOS `v0.1.x`, not upstream `v1.17.x`
- [ ] Monorepo submodule pins bumped when cutting a release (not required for every feature merge)

## Do not

- Push feature work only to vk496/meshcore without also landing it on MeshEnvy **`envyos/main`**
- **Cherry-pick or merge unrelated features onto a PR branch** (e.g. log tail onto `feature/next-hop-retry`)
- **Land feature-specific fixes only on `envyos/main`** while the matching upstream PR is still open — push to **`feature/<name>`** too
- Build bench firmware from a PR branch when you need the full EnvyOS stack (log tail + hop retry + OTA, etc.)
- Clone a **second otafix checkout** outside the submodule — only **`bootloader/`**
- Treat vk496 PR base branches (`feature/ota-lora`, etc.) as the MeshEnvy distro head — that's **`envyos/main`**
- Open PRs on `MeshEnvy/meshcore-firmware` when the target owner is `vk496` or `meshcore-dev`
- Confuse upstream MeshCore version tags with EnvyOS distro version
