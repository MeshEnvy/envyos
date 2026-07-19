---
name: motatool
description: >-
  motatool CLI (motatool/): build/verify/inspect/serve .mota containers, full images
  and detools deltas (sequential + in-place). Use when packaging firmware, producing diff
  patches, serving a seeder folder, or validating .mota files.
---

# motatool

Rust CLI at **`motatool/`** (submodule: `vk496/motatool`). Byte-compatible with MeshCore's on-wire `.mota` format.

Build: `cargo build --release` → `motatool/target/release/motatool`  
Bench scripts auto-build or use `motatool` on PATH.

**Runtime:** pure Rust — no Python/detools needed for `build`, `verify`, `inspect`, `serve`.  
detools is **test-oracle only** (`make dev-setup` in motatool repo for delta unit tests).

Spec: `envycore/docs/ota_protocol.md` · Implementation: `motatool/src/`

## Commands

```bash
# Full image from firmware (reads EndF trailer for target_id, version, hw_id)
motatool build --fw firmware.hex --out-dir ./build/motas/v0.1.0/wismesh-tag-repeater
motatool build --fw firmware.bin --sign signer.key --out-dir ./out

# Delta patches (--base MUST be device's running image with EndF)
motatool build --base old.hex --fw new.hex --out-dir ./out                    # sequential (ESP32)
motatool build --base old.hex --fw new.hex --patch-type in-place --out delta.mota  # in-place (nRF52)

# Validate
motatool verify ./build/motas/**/*.mota
motatool verify signed.mota --pub signer.key.pub

# Inspect manifest
motatool inspect ./build/motas/**/fw_*_full_*.mota

# Ed25519 keypair
motatool keygen --out signer.key

# Serve folder to node (USB or WiFi TCP)
motatool serve --dir ./motas --serial /dev/cu.usbmodem1444301 -v
motatool serve --dir ./motas --tcp 192.168.1.50:5001 -v
```

Or via bench wrapper: **`./scripts/run-mota.sh <serial> [dir]`**

## `build` — full `.mota`

- Input: `.hex` (Intel HEX parsed to flat image) or `.bin`, or `https://` URL
- Identity from **EndF trailer** (override with `--target-env`, `--target-id`, `--fw-version`, `--hw-id`)
- Output naming: `fw_<target_id>_<version>_full_<mid>.mota`
- Produces merkle tree (1024-byte blocks default), manifest, optional Ed25519 signature

## `build --base` — delta patches

Produces a **small `.mota`** whose payload is a **detools patch** (`--compression crle`), not the full image.

| `--patch-type` | Codec | Use |
|----------------|-------|-----|
| `sequential` (default) | detools-sequential | ESP32: read base random, write to inactive slot |
| `in-place` | detools-in-place | nRF52: patch app region in place via OTAFIX bootloader |

**Requirements:**

- `--base` = **exact** running firmware image (with EndF) — typically `build/motas/v0.1.0/<slug>/firmware.hex` from prior `build-mota.sh`
- `--fw` = new build's hex
- Manifest `base_hash` = base image's `EndF.body_hash` (motatool computes this)

EnvyOS bench (`build-mota.sh`) always uses **`--patch-type in-place`** for WisMesh Tag.

Optional in-place tuning: `--inplace-memory` (override; default derives from target staging ceiling + patch size), `--segment-size`.

### Correctness model

A delta is valid when the **on-device detools C decoder** reconstructs the target byte-for-byte — not when patch bytes match detools Python output. motatool's encoder (`src/encode.rs`) is proven against the detools oracle in tests.

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
motatool build --fw "$OUT/firmware.hex" --out-dir "$OUT"
motatool build --base "$BASE_HEX" --fw "$OUT/firmware.hex" --patch-type in-place --out "$DELTA_OUT"
```

Serve step is separate: `run-mota.sh` → `motatool serve --dir … --serial … -v`

## Target IDs

`src/targets.rs` mirrors firmware `OtaTargets.h` (`target_id = sha256:4(env_name)`). Regenerate when OTA env set changes (`envycore/tools/mota/gen_targets.py`).

## Related skills

- Device-side OTA flow → `envyos-ota`
- Script orchestration → `envyos-scripts`
