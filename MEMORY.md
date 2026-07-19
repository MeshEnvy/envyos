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
| `origin` | `MeshEnvy/Adafruit_nRF52_Bootloader_OTAFIX` | EnvyOS fork — head **`master`** |
| `vk496` | `vk496/Adafruit_nRF52_Bootloader_OTAFIX` | OTA delta apply — **`feature/ota-delta-apply`** |
| `upstream` | `oltaco/Adafruit_nRF52_Bootloader_OTAFIX` | Official OTAFIX releases (`0.9.2-OTAFIX*` tags) |

**`envyos/main`** = merged union of shipped EnvyOS features. Feature branches merge here even while upstream PRs are open. See `.cursor/skills/envyos-meshcore/SKILL.md` for workflow detail.

## Versioning

- Canonical: **`VERSION`** at repo root (e.g. `0.1.0`) → tags `v0.1.0`, `v0.1.1`, …
- Helpers: **`scripts/version.sh`** — `read_version_file`, `normalize_version`, `previous_patch_version`
- **Not** upstream `companion-v1.17.x` scheme
- `./scripts/build-mota.sh` → reads `VERSION`, builds all `scripts/targets.txt` → `motas/v0.1.0/<slug>/`
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

Rebuild **both** submodules in three layers each:

| Submodule | Tag pin | vk496 branch | Manifest |
|-----------|---------|--------------|----------|
| `envyos/` → `envyos/main` | `companion-v*` | `feature/ota-lora` | `envyos/FRESHEN.lock` |
| `vendor/otafix/` → `master` | `0.9.2-OTAFIX*` | `feature/ota-delta-apply` | `vendor/otafix/FRESHEN.lock` |

OTAFIX 2.3 tag and vk496 delta-apply diverge on in-place apply — keep vk496 detools stack; `ota_layout.h` must match `OtaFlashLayout_nrf52.h`. Skill: `.cursor/skills/envyos-freshen/SKILL.md`.

## Agent skills

| Skill | When to load |
|-------|----------------|
| `envyos-freshen` | `/freshen` — sync envyos to latest MeshCore tag + vk496 OTA |
| `envyos-meshcore` | Git remotes, feature branches, upstream PRs |
| `envyos-ota` | OTA protocol, device CLI, codecs, bench roles |
| `envyos-scripts` | `scripts/build-mota.sh`, `build-bl.sh`, `run-mota.sh` |
| `motatool` | `.mota` build, deltas, verify, serve |

## Active threads

<!-- In-flight work only; delete when done -->
