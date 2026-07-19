---
name: envyos-meshcore
description: >-
  EnvyOS distro git workflow: envyos/main on all MeshEnvy forks (firmware,
  motatool, otafix), vk496 PR bases, feature branches, merge-back, and monorepo
  submodule pins. Use when working on envyos/main, vendor/motatool, vendor/otafix,
  vk496 remotes, upstream PRs, or submodule bumps.
---

# EnvyOS MeshCore distro

EnvyOS is MeshEnvy's integration distro of [MeshCore](https://github.com/meshcore-dev/MeshCore). **`envyos/main` is the integration head on every MeshEnvy fork** in the OTA stack — firmware, motatool, and otafix — even when open vk496 PRs use different base branches.

Firmware lives in `envyos/`; motatool and otafix live under `vendor/` in the `ota` monorepo. EnvyOS versioning is **independent** of upstream MeshCore release tags (see `VERSION` at ota repo root).

## Distro repos and remotes

| Submodule | MeshEnvy fork (`origin`) | vk496 remote | vk496 PR base |
|-----------|--------------------------|--------------|---------------|
| `envyos/` | `MeshEnvy/meshcore-firmware` | `vk496/MeshCore` | `feature/ota-lora` |
| `vendor/motatool/` | `MeshEnvy/motatool` (`meshenvy` remote in submodule) | `vk496/motatool` | `main` |
| `vendor/otafix/` | `MeshEnvy/Adafruit_nRF52_Bootloader_OTAFIX` | `vk496/Adafruit_nRF52_Bootloader_OTAFIX` | `feature/ota-delta-apply` |

All three MeshEnvy forks use **`envyos/main`** as the GitHub default branch and distro integration head.

## Git remotes (firmware — `envyos/`)

| Remote | Repository | Role |
|--------|------------|------|
| `origin` | `MeshEnvy/meshcore-firmware` | EnvyOS fork — push feature branches here |
| `vk496` | `vk496/MeshCore` | vk496's MeshCore fork — OTA and vk-specific work |
| `meshcore` | `meshcore-dev/MeshCore` | Upstream MeshCore — core protocol/features |

Verify: `git remote -v`

## Branches

| Branch | Purpose |
|--------|---------|
| `envyos/main` | **Distro integration head** on every MeshEnvy fork — merge every shipped feature here |
| `feature/<name>` | Isolated work; often branched from vk496 PR base, then merged to `envyos/main` |
| `fix/<name>` | Small targeted fixes for upstream PR |

Never treat a feature branch as the distro head. After feature work (and opening a vk496 PR if applicable), **always merge into `envyos/main`** on the MeshEnvy fork.

### Dual-track: distro vs vk496 PR

A feature often exists on **two tracks**:

1. **`feature/<name>`** — branched from the vk496 PR base; opened as cross-fork PR to vk496 (`MeshEnvy:feature/<name>`).
2. **`envyos/main`** — MeshEnvy integration; merge the feature here **even while the vk496 PR is open**.

These diverge by design: `envyos/main` accumulates EnvyOS overlay (FRESHEN, next-hop, etc.); the vk496 PR stays rebasable on vk's base. When a vk496 PR merges, pull/rebase that base into `envyos/main` if needed.

The **`ota` monorepo** pins submodule commits (not branch names). Bump pointers at release freshen or when intentionally advancing; submodule checkouts can be on `envyos/main` locally.

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

| Feature | Push to | PR base | PR repo |
|---------|---------|---------|---------|
| Next-hop retry | `origin/feature/next-hop-retry` | `dev` | `meshcore-dev/MeshCore` |
| OTA ls pagination | `origin/fix/ota-ls-start-at-n` | `feature/ota-lora` | `vk496/MeshCore` |
| OTA staging ceiling | `origin/feature/ota-stage-ceiling` | `feature/ota-lora` | `vk496/MeshCore` |
| motatool delta layout | `meshenvy/feature/ota-stage-ceiling` | `main` | `vk496/motatool` |
| otafix scan ceiling | `origin/feature/ota-stage-ceiling` | `feature/ota-delta-apply` | `vk496/Adafruit_nRF52_Bootloader_OTAFIX` |
| EnvyOS-only glue | `origin/...` | n/a | no upstream PR needed |

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

Same pattern in each submodule (`envyos/`, `vendor/motatool/`, `vendor/otafix/`):

```bash
cd envyos   # or vendor/motatool, vendor/otafix
git checkout envyos/main
git pull origin envyos/main
git merge feature/<name>   # resolve conflicts
git push origin envyos/main
```

Conflict hotspots when merging upstream features into EnvyOS: `Mesh.cpp`, `CommonCLI.*`, `platformio.ini`, test mocks (OTA vs upstream API changes).

## Versioning

EnvyOS version is **not** upstream MeshCore's `companion-v1.16.0` tag scheme.

- **Canonical file:** `VERSION` at ota repo root (e.g. `0.1.0`)
- **Build:** `./scripts/build-mota.sh` reads `VERSION` → `motas/v0.1.0/`; `./scripts/build-mota.sh v0.1.1` overrides for one-off builds and auto-deltas from prior patch if present
- **Firmware stamp:** `-DFIRMWARE_VERSION` via `PLATFORMIO_BUILD_FLAGS` in `build-mota.sh`
- **Explicit delta base:** `./scripts/build-mota.sh v0.1.2 --base v0.1.0`

Bump `VERSION` at repo root for distro milestones. Use patch tags (`v0.1.0`, `v0.1.1`, …) for bench iterations.

## Agent checklist

When shipping EnvyOS work:

- [ ] Feature branch based on correct **vk496 PR base** (table above)
- [ ] Pushed to MeshEnvy fork (`origin` / `meshenvy`)
- [ ] vk496 PR opened (if upstreamable)
- [ ] Merged into **`envyos/main`** on MeshEnvy fork and pushed
- [ ] Version references use EnvyOS `v0.1.x`, not upstream `v1.17.x`
- [ ] Monorepo submodule pins bumped when cutting a release (not required for every feature merge)

## Do not

- Push feature work only to vk496 without also landing it on MeshEnvy **`envyos/main`**
- Clone **`otafix/` at repo root** — only `vendor/otafix` submodule
- Treat vk496 PR base branches (`feature/ota-lora`, etc.) as the MeshEnvy distro head — that's **`envyos/main`**
- Open PRs on `MeshEnvy/meshcore-firmware` when the target owner is `vk496` or `meshcore-dev`
- Confuse upstream MeshCore version tags with EnvyOS distro version
