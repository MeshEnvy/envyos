---
name: envyos-meshcore
description: >-
  EnvyOS MeshCore distro workflow: envyos/main integration branch, git remotes
  (origin/vk496/meshcore), upstream feature isolation, PR submission to each
  remote owner, and merge-back. Use when working on envyos/main, MeshEnvy
  meshcore-firmware, vk496/MeshCore, meshcore-dev/MeshCore, distro versioning,
  or contributing features upstream.
---

# EnvyOS MeshCore distro

EnvyOS is MeshEnvy's integration distro of [MeshCore](https://github.com/meshcore-dev/MeshCore). **`envyos/main` is the head branch** — it always contains the merged union of EnvyOS features, even when those features also exist as open PRs upstream.

Firmware lives in `envyos/` inside the `ota` repo. EnvyOS versioning is **independent** of upstream MeshCore release tags (see `envyos/envyos/VERSION`).

## Git remotes

Configure remotes in `envyos/` like this:

| Remote | Repository | Role |
|--------|------------|------|
| `origin` | `MeshEnvy/meshcore-firmware` | EnvyOS fork — push feature branches here |
| `vk496` | `vk496/MeshCore` | vk496's MeshCore fork — OTA and vk-specific work |
| `meshcore` | `meshcore-dev/MeshCore` | Upstream MeshCore — core protocol/features |

Verify: `git remote -v`

## Branches

| Branch | Purpose |
|--------|---------|
| `envyos/main` | **Integration head** — merge every shipped EnvyOS feature here |
| `feature/<name>` | Isolated feature work for upstream PR |
| `fix/<name>` | Small targeted fixes for upstream PR |

Never treat a feature branch as the distro head. After upstream PR work, **always merge into `envyos/main`**.

## Feature workflow

For each feature:

1. **Choose the upstream base** — branch from the remote that owns the target:
   - Core mesh / repeater behavior → `meshcore/dev`
   - OTA-over-LoRa / vk496 stack → `vk496/feature/ota-lora` (or relevant vk496 branch)
2. **Implement on a focused branch** — e.g. `feature/next-hop-retry`
3. **Push to `origin`** — `git push -u origin feature/<name>`
4. **Open a PR on the target repo** — cross-fork if needed (`MeshEnvy:feature/<name>`)
5. **Merge into `envyos/main`** — even while the upstream PR is open/draft
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

```bash
cd envyos
git checkout envyos/main
git pull origin envyos/main
git merge feature/<name>   # resolve conflicts; keep OTA + upstream API renames aligned
git push origin envyos/main
```

Conflict hotspots when merging upstream features into EnvyOS: `Mesh.cpp`, `CommonCLI.*`, `platformio.ini`, test mocks (OTA vs upstream API changes).

## Versioning

EnvyOS version is **not** upstream MeshCore's `companion-v1.16.0` tag scheme.

- **Canonical file:** `envyos/envyos/VERSION` (currently `0.1.0`)
- **Build by tag:** `./scripts/build-mota.sh v0.1.0` → `motas/v0.1.0/`; `./scripts/build-mota.sh v0.1.1` auto-deltas from `v0.1.0` if present
- **PlatformIO default:** `-DFIRMWARE_VERSION='"v0.1.0"'` in `envyos/platformio.ini`
- **Explicit delta base:** `./scripts/build-mota.sh v0.1.2 --base v0.1.0`

Bump `envyos/envyos/VERSION` for distro milestones. Use patch tags (`v0.1.0`, `v0.1.1`, …) for bench iterations.

## Agent checklist

When shipping EnvyOS work:

- [ ] Feature branch based on correct upstream base
- [ ] Pushed to `origin`
- [ ] Draft/open PR on the owning remote (if upstreamable)
- [ ] Merged into `envyos/main` and pushed
- [ ] Version references use EnvyOS `v0.1.x`, not upstream `v1.17.x`

## Do not

- Push feature work only to `vk496` without also landing it on `envyos/main`
- Open PRs on `MeshEnvy/meshcore-firmware` when the target owner is `vk496` or `meshcore-dev`
- Confuse upstream MeshCore version tags with EnvyOS distro version
