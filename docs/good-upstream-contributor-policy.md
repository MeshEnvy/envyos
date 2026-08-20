# EnvyOS Good Upstream Contributor Policy (GUCP)

EnvyOS ships on **`envyos/main`**, but upstreamable work also lives on pure **`feature/<name>`** branches and cross-fork PRs. **GUCP** is the per-distro registry and release gate: every upstreamable change is classified, extracted, and submitted before a distro tag ships.

Each **distro release** lists upstreamable work shipped in that bundle. `./envyos publish finalize` fails until every row that is not `envyos-only` or `declined` is **`submitted`** (PR open) or **`merged`**.

Skill: [`.cursor/skills/envyos-good-upstream-contributor/SKILL.md`](../.cursor/skills/envyos-good-upstream-contributor/SKILL.md). Verify: `./envyos gucp check vX.Y.Z`.

**Status values**

| Status | Meaning | Blocks finalize? |
|--------|---------|------------------|
| `candidate` | Upstreamable; not extracted yet | yes |
| `extracting` | Pure branch / PR prep in progress | yes |
| `submitted` | Cross-fork PR open (draft OK) | no |
| `merged` | Upstream merged | no |
| `envyos-only` | MeshEnvy integration glue; no upstream PR | no |
| `declined` | Decided not to upstream (note why in Feature col) | no |

**Columns:** Feature · Repo (`envycore` / `bootloader` / `motatool`) · Branch on MeshEnvy fork · Upstream target (`owner/repo` + base branch) · PR link or `—` · Status

Mirror the release block in `CHANGELOG.md` under `### Upstream PRs` before finalize.

**Lifecycle:** register upstreamable work as **`candidate`** when it lands on `envyos/main` (same change set as the commit batch). Open cross-fork PRs and move to **`submitted`** during release prep, before `./envyos publish finalize`.

---

## Unreleased

Work on `envyos/main` not yet tied to a distro tag. Assign rows to `## Release vX.Y.Z` when cutting that release.

| Feature | Repo | Branch | Upstream target | PR | Status |
|---------|------|--------|-----------------|-----|--------|
| Multi-volume FS CLI naming (v0.3.0) | envycore | TBD | meshcore-dev/MeshCore `dev` | — | candidate |

---

## Release v0.2.0

**Pending** — next publish (`ENVYOS_VERSIONS` `distro=0.2.0`). Bundles WDT work and v0.1.3 internal dev. Not on [GitHub Releases](https://github.com/MeshEnvy/envyos/releases) yet. Upstream rows below are prep; finalize runs `./envyos gucp check v0.2.0`.

| Feature | Repo | Branch | Upstream target | PR | Status |
|---------|------|--------|-----------------|-----|--------|
| Next-hop retry | envycore | `feature/next-hop-retry` | meshcore-dev/MeshCore `dev` | [#2980](https://github.com/meshcore-dev/MeshCore/pull/2980) | submitted |
| Log tail serial | envycore | `feature/log-tail-serial` | meshcore-dev/MeshCore `dev` | [#2991](https://github.com/meshcore-dev/MeshCore/pull/2991) | submitted |
| Defer remote admin CLI (advert lockup fix) | envycore | `feature/defer-remote-cli` | meshcore-dev/MeshCore `dev` | [#3196](https://github.com/meshcore-dev/MeshCore/pull/3196) | submitted |
| Boot-time fsck (companion corrupt LFS) | envycore | `feature/fs-corruption-check` | meshcore-dev/MeshCore `dev` | [#3012](https://github.com/meshcore-dev/MeshCore/pull/3012) | submitted |
| OTA role-aware staging ceiling | envycore | `feature/ota-stage-ceiling` | vk496/MeshCore `feature/ota-lora` | [vk496#3](https://github.com/vk496/MeshCore/pull/3) | submitted |
| OTAFIX scan ceiling | bootloader | `feature/ota-stage-ceiling` | vk496/Adafruit_nRF52_Bootloader_OTAFIX `feature/ota-delta-apply` | [vk496#2](https://github.com/vk496/Adafruit_nRF52_Bootloader_OTAFIX/pull/2) | submitted |
| Slim RAK4631 repeater role | envycore | `feature/ota-slim-repeater` | vk496/MeshCore `feature/ota-lora` | [vk496#4](https://github.com/vk496/MeshCore/pull/4) | submitted |
| SD / NOR superseeder | envycore | `feature/ota-superseeder` | vk496/MeshCore `feature/ota-lora` | [vk496#5](https://github.com/vk496/MeshCore/pull/5) | submitted |
| EnvyBoot WDT feed | bootloader | `envyos/main` | vk496/Adafruit_nRF52_Bootloader_OTAFIX `feature/ota-delta-apply` | — | envyos-only |
| Disable OTA self-serve (fleet policy) | envycore | `envyos/main` | — | — | envyos-only |
| Debug repeater twins (`*-debug` builds) | envycore | `envyos/main` | — | — | envyos-only |
| Atomic saves (prefs/ACL/regions/blobs) | envycore | `feature/atomic-fs-save` | meshcore-dev/MeshCore `dev` | [#3254](https://github.com/meshcore-dev/MeshCore/pull/3254) | submitted |
| FS save error replies (stacked on #3254) | envycore | `feature/fs-save-errors` | meshcore-dev/MeshCore `dev` | [#3253](https://github.com/meshcore-dev/MeshCore/pull/3253) | submitted |
| Doctor CLI (stacked on #3253) | envycore | `feature/doctor` | meshcore-dev/MeshCore `dev` | [#3252](https://github.com/meshcore-dev/MeshCore/pull/3252) | submitted |
| nRF52 repeater hardware WDT | envycore | `feature/nrf52-watchdog` | meshcore-dev/MeshCore `dev` | [#3210](https://github.com/meshcore-dev/MeshCore/pull/3210) | submitted |
| EndF restamp firmware version on rebuild | envycore | `feature/endf-restamp` | vk496/MeshCore `feature/ota-lora` | [vk496#6](https://github.com/vk496/MeshCore/pull/6) | submitted |
| FirmwareIdentity codegen (incremental build stamps) | envycore | `envyos/main` | — | — | envyos-only |

---

## Release v0.1.2

Retrospective — predates GUCP gate. PRs opened after ship where applicable.

| Feature | Repo | Branch | Upstream target | PR | Status |
|---------|------|--------|-----------------|-----|--------|
| Distro publish pipeline | ota monorepo | `envyos/main` | — | — | envyos-only |
| LoRa OTA stack (overlay) | envycore | multiple | vk496/MeshCore `feature/ota-lora` | vk496 stack | submitted |
| Next-hop retry | envycore | `feature/next-hop-retry` | meshcore-dev/MeshCore `dev` | [#2980](https://github.com/meshcore-dev/MeshCore/pull/2980) | submitted |
| Log tail serial | envycore | `feature/log-tail-serial` | meshcore-dev/MeshCore `dev` | [#2991](https://github.com/meshcore-dev/MeshCore/pull/2991) | submitted |

---

## Release v0.1.0

First fleet release — retrospective.

| Feature | Repo | Branch | Upstream target | PR | Status |
|---------|------|--------|-----------------|-----|--------|
| LoRa OTA (`.mota`, superseeder) | envycore | vk496 overlay | vk496/MeshCore `feature/ota-lora` | vk496 stack | submitted |
| Next-hop retry | envycore | `feature/next-hop-retry` | meshcore-dev/MeshCore `dev` | [#2980](https://github.com/meshcore-dev/MeshCore/pull/2980) | submitted |
| Log tail serial | envycore | `feature/log-tail-serial` | meshcore-dev/MeshCore `dev` | [#2991](https://github.com/meshcore-dev/MeshCore/pull/2991) | submitted |
| Slim repeater / SD superseeder | envycore | vk496 features | vk496/MeshCore `feature/ota-lora` | vk496 stack | submitted |
