#!/usr/bin/env bash
# Build WisMesh Tag repeater firmware + .mota for the LoRa OTA bench.
#
# Usage:
#   ./scripts/build-mota.sh v0.1.0                    # motas/v0.1.0/  (hex, uf2, full .mota)
#   ./scripts/build-mota.sh v0.1.1                    # motas/v0.1.1/  + in-place delta from v0.1.0 (if present)
#   ./scripts/build-mota.sh v0.1.2 --base v0.1.0      # explicit delta base (skip intermediate)
#
# Requires: PlatformIO (`pio`), and either `motatool` on PATH or ./vendor/motatool/ built with cargo.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MC="$ROOT/envyos"
ENV_NAME="RAK_WisMesh_Tag_repeater"
OUT_ROOT="$ROOT/motas"
# shellcheck source=envyos/envyos/version.sh
source "$MC/envyos/version.sh"

usage() {
  cat >&2 <<EOF
usage: $0 <version> [--base <version>]

  version   EnvyOS firmware tag, e.g. v0.1.0 or 0.1.0
  --base    Optional hex base for an in-place delta (default: previous patch if present)

examples:
  $0 v0.1.0
  $0 v0.1.1
  $0 v0.1.2 --base v0.1.0
EOF
  exit 2
}

[[ $# -ge 1 && $# -le 3 ]] || usage

VER="$(normalize_version "$1")" || usage
BASE_VER=""
if [[ $# -eq 3 ]]; then
  [[ "$2" == "--base" ]] || usage
  BASE_VER="$(normalize_version "$3")" || usage
fi

OUT="$OUT_ROOT/$VER"
BUILD_DIR="$MC/.pio/build/$ENV_NAME"

# Homebrew's ~/.cargo/bin/cargo can be a broken rustup-init shim; prefer the real toolchain binary.
find_cargo() {
  local c
  if command -v rustup >/dev/null 2>&1; then
    c="$(rustup which cargo 2>/dev/null || true)"
    if [[ -n "$c" && -x "$c" ]] && "$c" --version >/dev/null 2>&1; then
      echo "$c"
      return
    fi
  fi
  c="$(ls -1d "$HOME"/.rustup/toolchains/stable-*/bin/cargo 2>/dev/null | head -1 || true)"
  if [[ -n "$c" && -x "$c" ]] && "$c" --version >/dev/null 2>&1; then
    echo "$c"
    return
  fi
  if command -v cargo >/dev/null 2>&1 && cargo --version 2>/dev/null | grep -q '^cargo '; then
    command -v cargo
    return
  fi
  echo "error: no working cargo (fix rustup: rustup which cargo)" >&2
  exit 1
}

motatool_bin() {
  if command -v motatool >/dev/null 2>&1; then
    echo motatool
    return
  fi
  local rel="$ROOT/vendor/motatool/target/release/motatool"
  if [[ -x "$rel" ]]; then
    echo "$rel"
    return
  fi
  if [[ -d "$ROOT/vendor/motatool" ]]; then
    local cargo_bin cargo_dir
    cargo_bin="$(find_cargo)"
    cargo_dir="$(dirname "$cargo_bin")"
    echo "building motatool (release) with $cargo_bin …" >&2
    (cd "$ROOT/vendor/motatool" && PATH="$cargo_dir:$PATH" "$cargo_bin" build --release)
    [[ -x "$rel" ]] || { echo "error: motatool build did not produce $rel" >&2; exit 1; }
    echo "$rel"
    return
  fi
  echo "error: motatool not found (install or clone into $ROOT/vendor/motatool)" >&2
  exit 1
}

echo "==> $VER  env=$ENV_NAME"

mkdir -p "$OUT"
rm -f "$OUT"/* 2>/dev/null || true

export PLATFORMIO_BUILD_FLAGS="${PLATFORMIO_BUILD_FLAGS:-} -DFIRMWARE_VERSION='\"${VER}\"'"

(
  cd "$MC"
  pio run -e "$ENV_NAME"
  pio run -e "$ENV_NAME" -t create_uf2
)

HEX="$BUILD_DIR/firmware.hex"
UF2="$BUILD_DIR/firmware.uf2"
ZIP="$BUILD_DIR/firmware.zip"

[[ -f "$HEX" ]] || { echo "error: missing $HEX" >&2; exit 1; }

cp -f "$HEX" "$OUT/firmware.hex"
[[ -f "$UF2" ]] && cp -f "$UF2" "$OUT/firmware.uf2"
[[ -f "$ZIP" ]] && cp -f "$ZIP" "$OUT/firmware.zip"
printf '%s\n' "$VER" >"$OUT/version.txt"

echo "    saved $OUT/firmware.hex (+ uf2/zip if present)"

MT="$(motatool_bin)"
echo "==> packaging .mota with $MT"

"$MT" build --fw "$OUT/firmware.hex" --out-dir "$OUT"
echo "    full .mota → $OUT/"

if [[ -z "$BASE_VER" ]]; then
  PREV="$(previous_patch_version "$VER" || true)"
  if [[ -n "$PREV" && -f "$OUT_ROOT/$PREV/firmware.hex" ]]; then
    BASE_VER="$PREV"
  fi
fi

if [[ -n "$BASE_VER" ]]; then
  BASE_HEX="$OUT_ROOT/$BASE_VER/firmware.hex"
  [[ -f "$BASE_HEX" ]] || {
    echo "error: need $BASE_HEX for delta — build $BASE_VER first or pass --base" >&2
    exit 1
  }
  DELTA_OUT="$OUT/delta_from_${BASE_VER}.mota"
  echo "==> in-place delta $BASE_VER → $VER"
  echo "    base: $BASE_HEX"
  echo "    fw:   $OUT/firmware.hex"
  "$MT" build --base "$BASE_HEX" --fw "$OUT/firmware.hex" --patch-type in-place --out "$DELTA_OUT"
  echo "    delta: $DELTA_OUT  ← motatool serve --dir $OUT"
fi

echo "==> done $VER"
ls -la "$OUT"
