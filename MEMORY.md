# EnvyOS — agent memory

MeshEnvy's MeshCore distro: OTA over LoRa, routing improvements, and repeater enhancements. Firmware lives in `envyos/` (submodule); this repo (`ota`) holds build tooling, `.mota` artifacts, and the bench workflow.

## Repo layout

| Path | Role |
|------|------|
| `envyos/` | MeshCore firmware submodule (`MeshEnvy/meshcore-firmware`); branch **`envyos/main`** is distro head |
| `envyos/envyos/` | Distro version (`VERSION`, `version.sh`) — **not** upstream MeshCore tags |
| `motas/` | Built firmware + `.mota` outputs (`motas/<version>/`) |
| `vendor/motatool/` | Rust CLI — pack/serve `.mota`, USB serial to companion |
| `vendor/detools/` | Delta/diff encoding library (in-place `.mota` patches) |
| `vendor/otafix/` | nRF52 OTAFIX bootloader — in-place delta apply (`origin` MeshEnvy, `vk496` upstream) |
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
| `origin` | `MeshEnvy/Adafruit_nRF52_Bootloader_OTAFIX` | EnvyOS fork |
| `vk496` | `vk496/Adafruit_nRF52_Bootloader_OTAFIX` | vk496 OTAFIX stack |

**`envyos/main`** = merged union of shipped EnvyOS features. Feature branches merge here even while upstream PRs are open. See `.cursor/skills/envyos-meshcore/SKILL.md` for workflow detail.

## Versioning

- Canonical: `envyos/envyos/VERSION` (e.g. `0.1.0`) → tags `v0.1.0`, `v0.1.1`, …
- **Not** upstream `companion-v1.17.x` scheme
- `./scripts/build-mota.sh v0.1.0` → `motas/v0.1.0/<slug>/` for each line in `scripts/targets.txt`; patch builds auto-delta per target from previous patch if present
- PlatformIO: `-DFIRMWARE_VERSION='"v0.1.0"'` in `envyos/platformio.ini`

## OTA targets (`scripts/targets.txt`)

| Slug | PlatformIO env | Role |
|------|----------------|------|
| `wismesh-tag-repeater` | `RAK_WisMesh_Tag_repeater` | WisMesh Tag repeater (bench DUT) |
| `rak4631-repeater` | `RAK_4631_repeater` | RAK4631 repeater |
| `rak4631-client-ble` | `RAK_4631_companion_radio_ble` | RAK4631 companion (BLE) |
| `wismesh-tag-client-ble` | `RAK_WisMesh_Tag_companion_radio_ble` | WisMesh Tag companion (BLE) |

Add a line to `targets.txt` to ship another board/role.

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
./scripts/build-mota.sh v0.1.0             # all targets → motas/v0.1.0/<slug>/
./scripts/build-mota.sh v0.1.1             # + in-place deltas from v0.1.0 (per target)
./scripts/build-mota.sh v0.1.0 --target wismesh-tag-repeater
./scripts/run-mota.sh /dev/cu.usbmodem1444301
./scripts/run-mota.sh /dev/cu.… ./motas/v0.1.1   # serves all .mota under dir (recursive)
```

## Conflict hotspots

When merging upstream into `envyos/main`: `Mesh.cpp`, `CommonCLI.*`, `platformio.ini`, OTA test mocks.

## Agent skills

| Skill | When to load |
|-------|----------------|
| `envyos-meshcore` | Git remotes, feature branches, upstream PRs |
| `envyos-ota` | OTA protocol, device CLI, codecs, bench roles |
| `envyos-scripts` | `scripts/build-mota.sh`, `build-bl.sh`, `run-mota.sh` |
| `motatool` | `.mota` build, deltas, verify, serve |

## Active threads

<!-- In-flight work only; delete when done -->
