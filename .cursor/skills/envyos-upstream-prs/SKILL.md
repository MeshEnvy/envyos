---
name: envyos-upstream-prs
description: >-
  Track upstreamable EnvyOS work per distro release: classify features,
  extract pure PR branches, open cross-fork PRs, mirror rows in CHANGELOG.md
  and docs/upstream-prs.md, and gate ./envyos publish finalize until every
  upstreamable row is submitted. Use when shipping features, cutting a distro
  release, opening upstream PRs, or auditing open PR debt.
---

# EnvyOS upstream PR tracking

EnvyOS ships on **`envyos/main`**. Upstreamable pieces also live on pure **`feature/<name>`** branches and cross-fork PRs. A **distro release is not complete** until every upstreamable row for that release is **`submitted`** (PR open; draft OK) or **`merged`**.

Registry: [`docs/upstream-prs.md`](../../../docs/upstream-prs.md). Git workflow: [`.cursor/skills/envyos-meshcore/SKILL.md`](../envyos-meshcore/SKILL.md). Open PR sync: [`.cursor/rules/upstream-pr-sync.mdc`](../../rules/upstream-pr-sync.mdc).

## When to load

- Starting or reviewing a **feature** (classify upstreamability before merge to `envyos/main`)
- **Cutting a distro release** (`./envyos publish finalize`)
- Opening, updating, or closing **upstream PRs**
- Auditing **PR debt** for a shipped version

## Classify at feature start

For each logical change, decide:

| Class | Upstream? | Action |
|-------|-----------|--------|
| **Core mesh / repeater behavior** | Usually yes → meshcore-dev `dev` | Pure `feature/<name>` from `meshcore/dev` |
| **OTA firmware / EndF / staging** | Usually yes → vk496 `feature/ota-lora` | Pure branch from vk496 base |
| **OTAFIX / bootloader apply** | Usually yes → vk496 `feature/ota-delta-apply` | Pure branch on `bootloader/` |
| **motatool** | Optional (MeshEnvy-canonical since 0.1.1) | `envyos-only` unless vk496 still wants it |
| **EnvyOS overlay glue** (version stamps, fleet policy, `-debug` twins) | No | `envyos-only` |
| **Product-specific** (SenseCAP-only wiring, MeshEnvy branding) | Often no | `envyos-only` or `declined` with reason |

Add a row to **`docs/upstream-prs.md` § Unreleased** in the same change set as the feature lands on `envyos/main`:

```markdown
| My feature | envycore | `feature/my-feature` | meshcore-dev/MeshCore `dev` | — | candidate |
```

## Extract and submit

1. Branch **`feature/<name>`** from the correct **PR base** (not from `envyos/main`).
2. Cherry-pick or replay **only** commits that belong in that PR.
3. Push to MeshEnvy fork → open cross-fork PR (`--head MeshEnvy:feature/<name>`).
4. Merge the feature into **`envyos/main`** for bench builds (even while PR is open).
5. Update registry row: Status → **`extracting`** then **`submitted`**; fill PR link.
6. While PR stays open: sync fixes to **both** `envyos/main` and `feature/<name>` (see upstream-pr-sync rule).

```bash
gh pr create -R meshcore-dev/MeshCore \
  --draft --base dev --head MeshEnvy:feature/my-feature \
  --title "..." --body "..."
```

## Release checklist

Before **`./envyos publish finalize`** for `vX.Y.Z`:

```text
- [ ] Package changelogs promoted for bumped packages (see docs/change-management.md)
- [ ] Promote CHANGELOG.md Unreleased → ## [vX.Y.Z] - YYYY-MM-DD (+ ### Packages table)
- [ ] Add CHANGELOG ### Upstream PRs (mirror registry release table)
- [ ] Move/adjust rows in docs/upstream-prs.md → ## Release vX.Y.Z
- [ ] Every upstreamable row: submitted or merged (no candidate / extracting)
- [ ] ./envyos changelog check vX.Y.Z      # must pass
- [ ] ./envyos upstream-prs check vX.Y.Z   # must pass
- [ ] ./envyos publish --dry-run
- [ ] ./envyos publish finalize
```

### CHANGELOG mirror

Under the release heading, after user-facing sections:

```markdown
### Upstream PRs

- [meshcore-dev#2980](https://github.com/meshcore-dev/MeshCore/pull/2980) — next-hop retry (`feature/next-hop-retry`)
- [meshcore-dev#3196](https://github.com/meshcore-dev/MeshCore/pull/3196) — defer remote admin CLI (`feature/defer-remote-cli`)
- EnvyOS-only: WDT feed branding, debug twins (no upstream PR)
```

List every **submitted/merged** PR. Summarize **`envyos-only`** / **`declined`** rows in one line each.

## Verify

```bash
./envyos upstream-prs check              # next distro from ENVYOS_VERSIONS
./envyos upstream-prs check v0.2.0       # explicit version
./envyos upstream-prs list               # all release sections + blockers
```

Finalize runs the same check automatically.

## After upstream merge

1. Registry status → **`merged`**; note merge date in PR column if useful.
2. Rebase/pull upstream base into `envyos/main`; archive `feature/<name>`.
3. Remove row from MEMORY.md **Active threads** if it was duplicated there.

## Agent checklist (new feature)

- [ ] Upstreamability decided per sub-change (not one blanket label for a large feature)
- [ ] Row in `docs/upstream-prs.md` § Unreleased
- [ ] If upstreamable: PR base + branch name recorded before or with first merge to `envyos/main`
- [ ] If `candidate` at release time → **block finalize** until `submitted`

## Do not

- Ship upstreamable work only on `envyos/main` with no registry row
- Mark **`submitted`** without an open PR URL
- Fold unrelated features onto one PR branch
- Treat **`merged`** upstream PRs as optional changelog entries — list them under `### Upstream PRs`
