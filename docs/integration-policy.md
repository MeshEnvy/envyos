# EnvyOS upstream integration policy

How MeshEnvy keeps pace with [MeshCore](https://github.com/meshcore-dev/MeshCore) releases while preserving EnvyOS customizations (OTA, hop retry, slim roles, bench tooling).

**Canonical skill:** [`.cursor/skills/envyos-freshen/SKILL.md`](../.cursor/skills/envyos-freshen/SKILL.md) (`/freshen`, `/integrate`).

## Summary

| Concern | Remote / target | Role |
|---------|-----------------|------|
| **Release integration** | `meshcore` companion tags → merge into `envyos/main` | Normal flow |
| **Mesh / protocol features** | `meshcore-dev/MeshCore` (`dev` base) | Upstream PR target |
| **OTA patches** (not in meshcore mainline) | `vk496/MeshCore`, `vk496/motatool`, `vk496/Adafruit_nRF52_Bootloader_OTAFIX` | Upstream PR target only |
| **Fleet ship head** | `MeshEnvy/*/envyos/main` | Bench builds, tags, releases |

**vk496 is not an integration remote.** Do not freshen from `vk496/feature/ota-lora`, replay vk496 OTA commit lists, or merge vk496 wholesale into `envyos/main`. The OTA stack from vk496 is already on `envyos/main` (integrated 2026-07). Cherry-pick individual vk496 SHAs only when a specific fix is needed.

**OTA still goes upstream to vk496** until meshcore-dev absorbs LoRa OTA. Open cross-fork PRs there; merge the same commits to `envyos/main` without waiting for vk merge.

## Two-layer integration (current)

An EnvyOS firmware release is **`envyos/main` at a tested SHA**, not a replay of vk496 history.

```text
meshcore companion-vX.Y.Z     ← merge into integration branch
  + envyos/main overlay         ← OTA, hop retry, slim/superseeder, build glue (already on branch)
  = bench gate → envycore tag v0.1.N → distro bundle
```

Day-to-day EnvyOS work does **not** require freshen: merge `feature/*` → `envyos/main` per [`envycore/BACKLOG.md`](../../envycore/BACKLOG.md).

**Companion bump** (e.g. v1.16 → v1.17): periodic `/integrate` — see skill. EC-001 is the first integration under this policy.

## Legacy three-layer freshen (retired 2026-08)

Before 2026-08, fleet bootstrap used:

```text
companion-v* + cherry-pick vk496/feature/ota-lora ota: commits + overlay
```

That path is **historical only**. `envycore/scripts/cherry-pick-envyos-overlay.sh` and `FRESHEN.lock` `ota_commits` document the bootstrap recipe; do not re-run on companion bumps. See `FRESHEN.lock` `policy_version`.

## Upstream PR routing

| Change type | Branch from | PR to | Also merge to |
|-------------|-------------|-------|----------------|
| Core mesh, companion UX, protocol | `meshcore/dev` | `meshcore-dev/MeshCore` | `envyos/main` |
| OTA firmware, `.mota`, device CLI | `vk496/feature/ota-lora` | `vk496/MeshCore` | `envyos/main` |
| motatool | `vk496/main` | `vk496/motatool` | `envyos/main` (MeshEnvy/motatool) |
| OTAFIX delta apply | `vk496/feature/ota-delta-apply` | `vk496/Adafruit_nRF52_Bootloader_OTAFIX` | `envyos/main` (MeshEnvy fork) |
| EnvyOS-only (version helpers, targets) | `envyos/main` | none | `envyos/main` |

While an upstream PR is open, feature-specific commits land on **`envyos/main` and the PR branch** (see `envyos-meshcore` skill). Fleet does not wait on upstream merge.

## Conflict resolution (companion integrate)

| Path / area | Prefer on integrate |
|-------------|---------------------|
| `src/helpers/ota/**`, `test/test_ota/**` | **EnvyOS** (`envyos/main`) |
| EnvyOS overlay (hop retry, log tail, slim, superseeder) | **EnvyOS** |
| `envyos/`, build scripts, shipped targets | **EnvyOS** |
| `Mesh.cpp`, routing tables | **meshcore** companion (unless open meshcore-dev PR says otherwise) |
| `CommonCLI.*`, `platformio.ini` | companion structure + re-apply EnvyOS OTA flags |
| Variant `ENABLE_OTA` | keep enabled on EnvyOS boards |

## Bootloader

`envyos/main` already includes vk496 delta-apply. Normal flow: merge **oltaco** `0.9.2-OTAFIX*` bumps when needed; preserve EnvyOS `envyos/main` delta. Do not re-merge `vk496/feature/ota-delta-apply` on every companion cycle. OTA bootloader fixes still PR to vk496 until upstream absorbs them.

## Manifest (`envycore/FRESHEN.lock`)

Record each companion integrate:

```yaml
policy_version: 2
mode: integrate          # release | dev (spike only)
meshcore_tag: companion-v1.17.0
meshcore_sha: abc1234
envyos_main_sha: def5678   # after merge to envyos/main
last_integrate: YYYY-MM-DD
notes: optional
```

Legacy `ota_commits` blocks (policy v1) are archive only.

## Versioning

- **meshcore** tags (`companion-v1.17.0`): upstream provenance — input to integrate, not fleet semver.
- **envycore** tags (`v0.1.x`): firmware release semver — tag `envyos/main` after bench (future: component GH release).
- **envyos** distro tags (`v0.1.x`): tested component matrix — see [`distro-semver.md`](distro-semver.md).

## Related docs

- Package CLI contract: [`.cursor/skills/envyos-package/SKILL.md`](../.cursor/skills/envyos-package/SKILL.md)
- Git workflow: [`.cursor/skills/envyos-meshcore/SKILL.md`](../.cursor/skills/envyos-meshcore/SKILL.md)
- Component releases: [`component-release-policy.md`](component-release-policy.md)
- Backlog: [`envycore/BACKLOG.md`](../../envycore/BACKLOG.md)
