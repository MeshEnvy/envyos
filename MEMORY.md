# EnvyOS — agent memory

MeshEnvy's MeshCore distro: OTA over LoRa, routing improvements, and repeater enhancements. Firmware lives in `vk496-ota/`; this repo (`ota`) holds build tooling, `.mota` artifacts, and the bench workflow.

## Repo layout

| Path | Role |
|------|------|
| `vk496-ota/` | MeshCore firmware (git submodule/worktree); branch **`envyos/main`** is distro head |
| `envyos/` | Distro version (`VERSION`, `version.sh`) — **not** upstream MeshCore tags |
| `motas/` | Built firmware + `.mota` outputs (`motas/<version>/`) |
| `motatool/` | Rust CLI — pack/serve `.mota`, USB serial to companion |
| `vk-otafix/` | nRF52 bootloader with in-place delta apply (OTAFIX) |
| `build-mota.sh` | Build WisMesh Tag repeater + full/delta `.mota` |
| `build-bl.sh` | Build OTAFIX bootloader → `motas/bootloader/` |

## Git remotes (`vk496-ota/`)

| Remote | Repository | Role |
|--------|------------|------|
| `origin` | `MeshEnvy/meshcore-firmware` | EnvyOS fork — push features here |
| `vk496` | `vk496/MeshCore` | OTA / vk496 stack |
| `meshcore` | `meshcore-dev/MeshCore` | Upstream MeshCore |

**`envyos/main`** = merged union of shipped EnvyOS features. Feature branches merge here even while upstream PRs are open. See `.cursor/skills/envyos-meshcore/SKILL.md` for workflow detail.

## Versioning

- Canonical: `envyos/VERSION` (e.g. `0.1.0`) → tags `v0.1.0`, `v0.1.1`, …
- **Not** upstream `companion-v1.17.x` scheme
- `./build-mota.sh v0.1.0` → `motas/v0.1.0/`; patch builds auto-delta from previous patch if present
- PlatformIO: `-DFIRMWARE_VERSION='"v0.1.0"'` in `vk496-ota/platformio.ini`

## OTA bench (WisMesh Tag)

| Tag | Role | Bootloader |
|-----|------|------------|
| A (seeder) | OTA-capable build + `OTA_FOLDER_SERIAL`; USB to laptop | stock OK |
| B (router) | `RAK_WisMesh_Tag_repeater` — device under test | **vk-otafix required** |
| C (client) | Companion — remote `ota` CLI over mesh | stock OK |

Flow: `motatool serve --dir ./motas/<ver> --serial …` → Tag A advertises `.mota` over LoRa → Tag B fetch/install → Tag C remote admin.

## Build commands

```bash
./build-bl.sh                    # OTAFIX UF2 → motas/bootloader/
./build-mota.sh v0.1.0           # full build → motas/v0.1.0/
./build-mota.sh v0.1.1           # + in-place delta from v0.1.0
motatool serve --dir ./motas/v0.1.1 --serial /dev/cu.… -v
```

## Conflict hotspots

When merging upstream into `envyos/main`: `Mesh.cpp`, `CommonCLI.*`, `platformio.ini`, OTA test mocks.

## Active threads

<!-- In-flight work only; delete when done -->
