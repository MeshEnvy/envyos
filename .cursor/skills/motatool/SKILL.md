---
name: motatool
description: >-
  motatool CLI (motatool/): build/verify/inspect/serve .mota containers, full images
  and detools deltas (sequential + in-place). Use when packaging firmware, producing diff
  patches, serving a seeder folder, or validating .mota files.
---

# motatool

Rust CLI at **`motatool/`** (MeshEnvy fork of `vk496/motatool`; canonical **`envyos/main`** on `MeshEnvy/motatool`, **0.1.1**). Byte-compatible with MeshCore's on-wire `.mota` format. vk496 PRs are optional.

Build: `./envyos build motatool` (linux targets via **`docker/motatool-build/`**; darwin native on macOS)  
Staged as **`build/motatool/<ver>/motatool-<platform>`** (e.g. `motatool-darwin-aarch64`).  
Release matrix: darwin-aarch64, darwin-x86_64, linux-aarch64, linux-x86_64 (no Windows).  
Bench scripts resolve the **host** platform binary automatically.

**Runtime:** pure Rust — no Python/detools needed for `build`, `verify`, `inspect`, `serve`.  
detools is **test-oracle only** (`make dev-setup` in motatool repo for delta unit tests).

Spec: `envycore/docs/ota_protocol.md` · Implementation: `motatool/src/`

## Commands

```bash
# Full image from firmware (reads EndF trailer for target_id, version, hw_id)
motatool build --fw firmware.hex --out-dir ./build/firmware/v0.1.0/wismesh-tag-repeater
motatool build --fw firmware.bin --sign signer.key --out-dir ./out

# Delta patches (--base MUST be device's running image with EndF)
motatool build --base old.hex --fw new.hex --out-dir ./out                    # sequential (ESP32)
motatool build --base old.hex --fw new.hex --patch-type in-place --out delta.mota  # in-place (nRF52)

# Validate
motatool verify ./build/firmware/**/*.mota
motatool verify signed.mota --pub signer.key.pub

# Inspect manifest
motatool inspect ./build/firmware/**/fw_*_full_*.mota

# Ed25519 keypair
motatool keygen --out signer.key

# Serve folder to node (USB or WiFi TCP)
motatool serve --dir ./motas --serial /dev/cu.usbmodem1444301 -v
motatool serve --dir ./motas --tcp 192.168.1.50:5001 -v
```

Or via bench wrapper: **`./scripts/seeder.sh <serial> [dir]`**

## `build` — full `.mota`

- Input: `.hex` (Intel HEX parsed to flat image) or `.bin`, or `https://` URL
- Identity from **EndF trailer** (override with `--target-env`, `--target-id`, `--fw-version`, `--hw-id`)
- Output naming: `{stem}-full-{mid8}.mota` / `{stem}-delta-from-{basever}-{base8}.mota` (`--name-stem`, `--base-version`)
- Produces merkle tree (1024-byte blocks default), manifest, optional Ed25519 signature

## `build --base` — delta patches

Produces a **small `.mota`** whose payload is a **detools patch** (`--compression crle`), not the full image.

| `--patch-type` | Codec | Use |
|----------------|-------|-----|
| `sequential` (default) | detools-sequential | ESP32: read base random, write to inactive slot |
| `in-place` | detools-in-place | nRF52: patch app region in place via OTAFIX bootloader |

**Requirements:**

- `--base` = **exact** running firmware image (with EndF) — typically `build/firmware/v0.1.0/<slug>/firmware.hex` from prior `build-mota.sh`
- `--fw` = new build's hex
- Manifest `base_hash` = base image's `EndF.body_hash` (motatool computes this)

EnvyOS bench (`build-mota.sh`) always uses **`--patch-type in-place`** for WisMesh Tag.

Optional in-place tuning: `--inplace-memory` (override; default derives from target staging ceiling + patch size), `--segment-size`.

### Correctness model

A delta is valid when the **on-device detools C decoder** reconstructs the target byte-for-byte — not when patch bytes match detools Python output. motatool's encoder (`src/encode.rs`) is proven against the detools oracle in tests. In-place encode builds one suffix array of the shifted base and filters it per segment (same matches, much faster). Frozen on-wire bytes live in `motatool/tests/fixtures/` (`tests/golden.rs`).

## `serve`

Two roles on one link:

1. **Relay** — indexes every valid `*.mota` under `--dir` (recursive by default); node addresses them by index (`DESCRIBE`, `READ_BLOCK`, …)
2. **Capture** — when node runs `ota pull N folder`, writes `<mid>.mota.part` → `<mid>.mota` in `--dir`

On USB serial, auto-sends **`ota folder on`** at start (disable with `--no-enable`).

**Warm-start capture:** `motatool serve --dir ./cap --seed similar.mota …` then node: `ota pull N folder validate` — fetches only merkle-differing blocks (see `envyos-ota` skill).

Flags: `--baud`, `--no-recursive`, `-v` (log requests), `--seed <file>`.

## `verify` / `inspect`

- Checks magic, manifest, block hashes, merkle root, `image_hash`, signature if present
- `inspect` dumps all manifest fields (target_id, codec, block count, sizes, signed flag)

## Integration with EnvyOS scripts

`build-mota.sh` calls:

```bash
motatool build --fw "$OUT/fw-<slug>-<ver>.hex" --fw-version … --name-stem "fw-<slug>-<ver>" --out-dir "$OUT"
motatool build --base "$BASE" --fw "$OUT/fw-<slug>-<ver>.hex" --patch-type in-place \
  --name-stem "fw-<slug>-<ver>" --base-version "$BASE_VER" --out-dir "$OUT"
```

Names: `fw-<slug>-<ver>-full-<mid8>.mota` and `fw-<slug>-<ver>-delta-from-<base>-<base8>.mota`. `serve` indexes by content, not filename.

Serve step is separate: `seeder.sh` → `motatool serve --dir … --serial … -v`

## Target IDs

`src/targets.rs` mirrors firmware `OtaTargets.h` (`target_id = sha256:4(env_name)`). Regenerate when OTA env set changes (`envycore/tools/mota/gen_targets.py`).

## Related skills

- Device-side OTA flow → `envyos-ota`
- Script orchestration → `envyos-scripts`
