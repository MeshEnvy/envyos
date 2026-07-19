# EnvyOS — agent memory

MeshEnvy's MeshCore distro: OTA over LoRa, routing improvements, and repeater enhancements. Firmware lives in `envyos/` (submodule); this repo (`ota`) holds build tooling, `.mota` artifacts, and the bench workflow.

## Repo layout

| Path | Role |
|------|------|
| `envyos/` | MeshCore firmware submodule (`MeshEnvy/meshcore-firmware`); branch **`envyos/main`** is distro head |
| `VERSION` | Canonical distro semver (e.g. `0.1.0`) — **not** upstream MeshCore tags |
| `motas/` | Built firmware + `.mota` outputs (`motas/<version>/`) |
| `vendor/motatool/` | Rust CLI — pack/serve `.mota`, USB serial to companion |
| `vendor/detools/` | Delta/diff encoding library (in-place `.mota` patches) |
| `vendor/otafix/` | nRF52 OTAFIX bootloader — in-place delta apply (`origin` MeshEnvy, `vk496`, `oltaco`) |
| `scripts/` | Bench scripts — `build-mota.sh`, `build-bl.sh`, `run-mota.sh`, `targets.txt` |

## Git remotes (`envyos/`)

| Remote | Repository | Role |
|--------|------------|------|
| `origin` | `MeshEnvy/meshcore-firmware` | EnvyOS fork — push features here |
| `vk496` | `vk496/MeshCore` | OTA / vk496 stack |
| `meshcore` | `meshcore-dev/MeshCore` | Upstream MeshCore |

## Git remotes (`vendor/otafix/`)

| Remote | Repository | Role |
|--------|------------|------|
| `origin` | `MeshEnvy/Adafruit_nRF52_Bootloader_OTAFIX` | EnvyOS fork — head **`master`** |
| `vk496` | `vk496/Adafruit_nRF52_Bootloader_OTAFIX` | OTA delta apply — **`feature/ota-delta-apply`** |
| `oltaco` | `oltaco/Adafruit_nRF52_Bootloader_OTAFIX` | Official OTAFIX releases (`0.9.2-OTAFIX*` tags) |

**`envyos/main`** = merged union of shipped EnvyOS features. Feature branches merge here even while upstream PRs are open. See `.cursor/skills/envyos-meshcore/SKILL.md` for workflow detail.

## Versioning

- Canonical: **`VERSION`** at repo root (e.g. `0.1.0`) → git tags `v0.1.0`, `v0.1.1`, … → **`motas/<version>/`**
- **Earns an EnvyOS version:** only a **release freshen** bundle — `companion-v*` + `vk496/feature/ota-lora` + EnvyOS overlay (`envyos/FRESHEN.lock`). Not companion tag alone; not `meshcore/dev`.
- **Not** upstream `companion-v1.17.x` — record companion tag in `FRESHEN.lock` for traceability
- Helpers: **`scripts/version.sh`** — `read_version_file`, `normalize_version`, `previous_patch_version`
- `./scripts/build-mota.sh` reads `VERSION`; run only after release freshen passes validation
- Override: `./scripts/build-mota.sh v0.1.1` (without editing `VERSION`)
- Stock MeshCore (no EndF/OTA): `./scripts/build-mota.sh --hex-only` → hex/uf2 only, no `.mota`
- `-DFIRMWARE_VERSION` stamped via `PLATFORMIO_BUILD_FLAGS` in `build-mota.sh`

## OTA targets (`scripts/targets.txt`)

| Slug | PlatformIO env | Role |
|------|----------------|------|
| `wismesh-tag-repeater` | `RAK_WisMesh_Tag_repeater` | WisMesh Tag repeater (bench DUT) |
| `rak4631-repeater` | `RAK_4631_repeater` | RAK4631 repeater |
| `rak4631-client-ble` | `RAK_4631_companion_radio_ble` | RAK4631 companion (BLE) |
| `wismesh-tag-client-ble` | `RAK_WisMesh_Tag_companion_radio_ble` | WisMesh Tag companion (BLE) |

Add a line to `targets.txt` to ship another board/role.

## Mesh / next-hop retry

Direct-path repeaters: after forward, next hop sends zero-hop **`HOP_ACK`** (control `0xA0`, ~10 B). Upstream waits (`hop.retry.ms`, default 1500 ms) then retries (`hop.retry`, default 2). **Retry only for next hops that previously sent HOP_ACK** (runtime capability table; stock repeaters stay single-shot). CLI: `set hop.retry`, `set hop.retry.ms`. Branch: `feature/next-hop-retry` → upstream PR to `meshcore-dev/MeshCore`.

## OTA bench (WisMesh Tag)

| Tag | Role | Bootloader |
|-----|------|------------|
| A (seeder) | OTA-capable build + `OTA_FOLDER_SERIAL`; USB to laptop | stock OK |
| B (router) | `wismesh-tag-repeater` — device under test | **vendor/otafix required** |
| C (client) | `wismesh-tag-client-ble` — remote `ota` CLI over mesh | stock OK |

Flow: `motatool serve --dir ./motas/<ver> --serial …` → Tag A advertises `.mota` over LoRa → Tag B fetch/install → Tag C remote admin.

## Build commands

```bash
./scripts/build-bl.sh                    # OTAFIX UF2 → motas/bootloader/
./scripts/build-mota.sh --list-targets     # show scripts/targets.txt
./scripts/build-mota.sh                    # all targets → motas/<VERSION>/<slug>/
./scripts/build-mota.sh v0.1.1             # override + in-place deltas from prior patch if present
./scripts/build-mota.sh --target wismesh-tag-repeater
./scripts/build-mota.sh --hex-only         # stock MeshCore branch, no OTA
./scripts/run-mota.sh /dev/cu.usbmodem1444301
./scripts/run-mota.sh /dev/cu.… ./motas/v0.1.1   # serves all .mota under dir (recursive)
```

## Conflict hotspots

When merging upstream into `envyos/main`: `Mesh.cpp`, `CommonCLI.*`, `platformio.ini`, OTA test mocks.

## Freshen (`/freshen`)

**Fleet policy:** `companion-v*` + `vk496/feature/ota-lora` + EnvyOS overlay → bump **`VERSION`**, `./scripts/build-mota.sh`, tag **`v0.1.x`**. Merging vk496 includes vk's frozen dev snapshot (not pure upstream tag). When OTA lands upstream, drop vk496 layer.

| Command | Purpose | EnvyOS version? |
|---------|---------|-----------------|
| `/freshen` | Release bundle + otafix | **Yes** |
| `/freshen dev` | `meshcore/dev` integration | **No** |

Manifest: `envyos/FRESHEN.lock`. Otafix: `0.9.2-OTAFIX*` + `vk496/feature/ota-delta-apply`. Skill: `.cursor/skills/envyos-freshen/SKILL.md`.

## OTA greenfield

Pre-deployment — **no production fleet, no field migrations**. Breaking `.mota`/protocol/EndF changes are OK; rebuild artifacts and update docs instead of compat shims. Skill: `.cursor/skills/ota-greenfield/SKILL.md`.

## Agent skills

| Skill | When to load |
|-------|----------------|
| `envyos-freshen` | `/freshen` — release bundle earns VERSION; `/freshen dev` integration only |
| `envyos-meshcore` | Git remotes, feature branches, upstream PRs |
| `envyos-ota` | OTA protocol, device CLI, codecs, bench roles |
| `ota-greenfield` | OTA format/protocol/tooling changes — no legacy or migration paths |
| `envyos-scripts` | `scripts/build-mota.sh`, `build-bl.sh`, `run-mota.sh` |
| `motatool` | `.mota` build, deltas, verify, serve |

## Active threads

<!-- In-flight work only; delete when done -->
