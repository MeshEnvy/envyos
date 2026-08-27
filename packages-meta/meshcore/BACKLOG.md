# Envycore backlog

Canonical queue for **MeshEnvy firmware work** in this repo. Each item gets its own `feature/<name>` branch, its own bench gate, and merges to `envyos/main` **only when you explicitly pull it from the backlog**. Distro semver is chosen at publish time in `envyos/`.

Enterprise index: `ops/initiatives/envyos-backlog.md` (summary rows only).

## How to use

| Column | Meaning |
|--------|---------|
| **ID** | Stable backlog ID (`EC-###`) |
| **Priority** | P0 field blocker; P1 high leverage; P2 polish; Icebox deferred |
| **Effort** | S / M / L / XL desk or bench days |
| **Depends** | Other EC IDs whose branch must merge to `envyos/main` first |
| **Status** | `backlog` · `in_progress` · `bench` · `merged_main` · `published` · `icebox` |

**`merged_main` means git-merged to `envyos/main` only.** It is not field flash, not a distro publish, and not an upstream PR merge.

## Backlog

| ID | Item | Branch | Priority | Effort | Depends | Bench gate | Status |
|----|------|--------|----------|--------|---------|------------|--------|
| EC-001 | MeshCore companion-v1.17 upgrade | `feature/companion-v1.17` | P1 | L | EC-000 | slim repeater build; native tests; FRESHEN.lock v2 | backlog |
| EC-002 | nRF52 hardware WDT + EnvyBoot gate | `feature/nrf52-watchdog` | P1 | M | EC-001 | WDT trip/recover; OTA apply with EnvyBoot WDT feed | backlog |
| EC-003 | EndF version restamp on rebuild | `feature/endf-restamp` | P2 | S | EC-001 | Rebuild same version — EndF trailer matches | backlog |
| EC-004 | doctor CLI + atomic prefs | `feature/doctor` | P1 | M | EC-001 | `doctor check`; atomic prefs save under low FS space | backlog |
| EC-005 | OTA self-serve policy (merkle bench + disable) | `feature/ota-self-serve-policy` | P2 | S | EC-001 | No self-serve hash traffic at boot | backlog |
| EC-006 | OTA catalog filter + cache layout | `feature/ota-catalog-filter` | P2 | M | EC-001 | `ota ls` filtered to own target | backlog |
| EC-007 | Firmware identity codegen | `feature/firmware-identity-codegen` | P2 | S | EC-001 | Release rebuild only touches generated identity | backlog |
| EC-008 | Bench `-debug` target twins | `feature/debug-targets` | P2 | S | EC-001 | `-debug` twin builds and boots with log tail | backlog |
| EC-009 | Release tooling + changelog docs | `chore/release-tooling` | P2 | S | EC-001 | `./envyos` + CHANGELOG + publish skeleton | in_progress |
| EC-011 | Repeater `stealth_mode` — minimize discovery-plane leaks | `feature/stealth-mode` | P2 | M | EC-001 | Stealth slim: no self-advert/anon/discover/OTA beacon; still relays | backlog |
| EC-012 | OTA release provenance — signed distro motas + fleet allowlist | `feature/ota-provenance` | P2 | M | EC-001 | Release mota verifies + applies with allowlisted signer; rejects unknown signer | backlog |

EC-001 is the first integrate under [`integration-policy.md`](../../envyos/docs/integration-policy.md) v2: merge companion into `envyos/main`, no vk496 OTA replay.

### Source commits (from `envyos/dev-pre-split` monolith)

| ID | Cherry-pick SHAs |
|----|------------------|
| EC-001 | merge `origin/envyos/freshen/companion-v1.17.0` + `80766f40` + `9e71d50f` |
| EC-002 | `589c8db6`, `3674c1b7`, `aaa6e583` |
| EC-003 | `163dc2c3` |
| EC-004 | `f79f12d1`, `ad4b1265`, `62a48440` (+ native guard from split session if needed) |
| EC-005 | `e15e986d`, `5b06eb74` |
| EC-006 | `56dc37ac` |
| EC-007 | `165e7277` |
| EC-008 | `830ffa4d` |
| EC-009 | `ac4a48db`, `c79c9029` (skip duplicate `918c7ad8` if changelog already on branch) |

EC-001 includes freshen overlay: SenseCAP slim OTA env, NOR/SD seeder allow CLI.

## Icebox

| ID | Item | Notes |
|----|------|-------|
| EC-010 | Companion FS wedge | Deferred to v0.3.0 per dev monolith changelog |

## Done

| ID | Item | Date | SHA / version |
|----|------|------|---------------|
| EC-000 | defer-remote-cli lockup fix | 2026-08-13 | `a2a13e18` on `envyos/main` (v0.1.3 hotfix) |

### Upstream PR branches (pure track — optional, not merged to main)

| ID | Branch | PR base | Notes |
|----|--------|---------|-------|
| EC-000 | `feature/defer-remote-cli-upstream` | meshcore-dev `dev` | On origin; open cross-fork PR when ready |

## Log

| Date | Note |
|------|------|
| 2026-08-25 | Opened backlog; split `envyos/dev-pre-split` monolith into feature branches. **`envyos/main` stays on v1.16 + 0.1.3 hotfix** until items are pulled deliberately. |
| 2026-08-25 | Reverted mistaken merge of EC-001–EC-009 to `envyos/main`. Feature branches only. |
| 2026-08-25 | EC-011: repeater `stealth_mode` — gate self-adverts, anon owner/region/clock, node discover, OTA beacons; path hash on relay remains. |
| 2026-08-25 | EC-012: OTA release provenance — sign published motas, fleet `ota key` allowlist, apply trust separate from discovery (EC-011). |
