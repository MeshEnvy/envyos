---
name: envyos-good-upstream-contributor
description: >-
  EnvyOS Good Upstream Contributor Policy (GUCP): classify upstreamable work,
  extract pure PR branches, open cross-fork PRs, mirror rows in CHANGELOG.md
  and docs/good-upstream-contributor-policy.md, sync meshenvy.org/open-source,
  and gate ./envyos publish finalize until every upstreamable row is submitted.
  Use when shipping features, cutting a distro release, opening upstream PRs,
  auditing open PR debt, or verifying draft/merged status on the public page.
---

# EnvyOS Good Upstream Contributor Policy (GUCP)

EnvyOS ships on **`envyos/main`**. Upstreamable pieces also live on pure **`feature/<name>`** branches and cross-fork PRs. A **distro release is not complete** until every upstreamable row for that release is **`submitted`** (PR open; draft OK) or **`merged`**.

Registry: [`docs/good-upstream-contributor-policy.md`](../../../docs/good-upstream-contributor-policy.md). Git workflow: [`.cursor/skills/envyos-meshcore/SKILL.md`](../envyos-meshcore/SKILL.md). Open PR sync: [`.cursor/rules/upstream-pr-sync.mdc`](../../rules/upstream-pr-sync.mdc). Public page: [`meshenvy.org/.cursor/skills/open-source-page/SKILL.md`](../../../../meshenvy.org/.cursor/skills/open-source-page/SKILL.md).

## When to load

- **After envycore / bootloader / motatool commits** (post-commit GUCP triage)
- Starting or reviewing a **feature** (classify upstreamability before merge to `envyos/main`)
- **Release prep** — extract pure branches, open PRs, move `candidate` → `submitted`
- **Cutting a distro release** (`./envyos publish finalize`)
- Opening, updating, or closing **upstream PRs**
- Auditing **PR debt** for a shipped version
- **Periodic open-source audit** (monthly or before finalize)

## Post-commit triage (required)

**Trigger:** any commit batch that touches `envycore/`, `bootloader/`, or `motatool/` on `envyos/main`.

This is the step that was missing. Do not wait for release or PR extraction.

1. **Split the batch** into logical upstream units (one row per extractable PR, not one row per commit).
2. **Classify** each unit (table below). When unsure, default to **`candidate`** and note why in the Feature column.
3. **Register** in `docs/good-upstream-contributor-policy.md`:
   - Target the **next distro release** section when CHANGELOG `[Unreleased]` already names that version (e.g. v0.2.0 work → `## Release v0.2.0`, not only § Unreleased).
   - Otherwise § **Unreleased**.
4. Set status **`candidate`** — PR branches and cross-fork PRs happen at **release prep**, not at commit time.
5. Record planned **`feature/<name>`** branch even if it does not exist yet.

```bash
./envyos gucp audit              # candidates + recent envycore commits
./envyos gucp audit v0.2.0       # focus on one release section
```

**Commit skill:** agents run this triage in the same session as envycore/bootloader/motatool commits (update GUCP before marking done).

## Release prep (candidate → submitted)

Before `./envyos publish finalize`:

1. Run `./envyos gucp audit vX.Y.Z` — every **`candidate`** / **`extracting`** row must be handled.
2. For each upstreamable row: extract pure `feature/<name>` branch → open cross-fork PR (draft OK) → status **`submitted`**.
3. `./envyos gucp check vX.Y.Z` must pass (no blocking candidates left).

PR creation is **manual**; GUCP's job at commit time is **flagging**, not opening PRs.

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

Add a row to **`docs/good-upstream-contributor-policy.md`** in the same change set as the feature lands on `envyos/main` (§ Unreleased, or the target release section if CHANGELOG already tracks that distro):

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
7. **Public mirror:** add or update the row in `meshenvy.org/src/data/open-source.ts` (`area: 'EnvyOS'`). Run `bun run open-source:verify` in `meshenvy.org` and bump `upstreamContributionsLastVerified`.

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
- [ ] Add CHANGELOG ### Upstream PRs (mirror GUCP release table)
- [ ] Move/adjust rows in docs/good-upstream-contributor-policy.md → ## Release vX.Y.Z
- [ ] Every upstreamable row: submitted or merged (no candidate / extracting)
- [ ] meshenvy.org `upstreamContributions` synced for EnvyOS PR rows
- [ ] `bun run open-source:verify` in meshenvy.org (passes; `upstreamContributionsLastVerified` = today)
- [ ] ./envyos changelog check vX.Y.Z      # must pass
- [ ] ./envyos gucp check vX.Y.Z           # must pass
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
./envyos gucp check              # next distro from ENVYOS_VERSIONS
./envyos gucp check v0.2.0       # explicit version
./envyos gucp list               # all release sections + blockers
./envyos gucp audit              # triage aid: candidates + recent envycore commits
./envyos gucp audit v0.2.0
```

Finalize runs the same check automatically.

## After upstream merge

1. Registry status → **`merged`**; note merge date in PR column if useful.
2. Rebase/pull upstream base into `envyos/main`; archive `feature/<name>`.
3. Update `meshenvy.org/src/data/open-source.ts`: `lifecycle: 'merged'`, `mergedAt`, clear `isDraft`. Run `bun run open-source:verify`.
4. Remove row from MEMORY.md **Active threads** if it was duplicated there.

## Periodic open-source audit

At least **monthly**, and always before **`./envyos publish finalize`**:

```bash
cd meshenvy.org
bun run open-source:verify
bun run open-source:verify -- --fix-hint   # optional: suggested field values
```

Fix drift in `src/data/open-source.ts`, bump `upstreamContributionsLastVerified`, commit in `meshenvy.org`. EnvyOS-only GUCP rows stay off the public table.

## Agent checklist (new feature)

- [ ] Upstreamability decided per sub-change (not one blanket label for a large feature)
- [ ] Row in GUCP registry (Unreleased or target release section)
- [ ] If upstreamable: PR base + branch name recorded; status **`candidate`** until release prep
- [ ] If `candidate` at finalize → **block finalize** until `submitted`

## Agent checklist (after commit batch)

- [ ] Ran post-commit triage for every touched submodule (`envycore/`, `bootloader/`, `motatool/`)
- [ ] GUCP rows added/updated in the same session (not deferred to release)
- [ ] `./envyos gucp audit` shows no obvious untriaged envycore commits for this batch
- [ ] If a row now has a PR link: meshenvy.org open-source row synced (or deferred only when no PR yet)

## Do not

- Ship upstreamable work only on `envyos/main` with no GUCP row
- Mark **`submitted`** without an open PR URL
- Fold unrelated features onto one PR branch
- Treat **`merged`** upstream PRs as optional changelog entries — list them under `### Upstream PRs`
- Leave meshenvy.org `/open-source` stale after GUCP PR status changes
