#!/usr/bin/env bash
# Build the vk-otafix nRF52 bootloader (MOTA in-place apply) via Docker.
#
# Usage:
#   ./build-bl.sh [BOARD]
#
# Default BOARD=wismesh_tag
# UF2: vk-otafix/_build/build-<board>/update-<board>_bootloader-*_nosd.uf2
# Also copied to ./motas/bootloader/ for the bench.
#
# Requires: Docker. Submodules under vk-otafix/ are initialized if needed.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
OTAFIX="$ROOT/vk-otafix"
BOARD="${1:-wismesh_tag}"
IMAGE="vk-otafix-build"
OUT="$ROOT/motas/bootloader"

[[ -d "$OTAFIX" ]] || { echo "error: missing $OTAFIX" >&2; exit 1; }

echo "==> bootloader BOARD=$BOARD"

(
  cd "$OTAFIX"
  if [[ ! -f lib/nrfx/nrfx.h ]] || [[ ! -f lib/tinyusb/src/tusb.h ]] || [[ ! -f lib/uf2/utils/uf2conv.py ]]; then
    echo "    git submodule update --init --recursive"
    git submodule update --init --recursive
  fi
  if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
    echo "    docker build -t $IMAGE ."
    docker build -t "$IMAGE" .
  fi
  echo "    docker run … make BOARD=$BOARD all"
  docker run --rm -v "$PWD":/src -w /src "$IMAGE" make "BOARD=$BOARD" all
)

BUILD_DIR="$OTAFIX/_build/build-$BOARD"
UF2="$(ls -1 "$BUILD_DIR"/update-*_nosd.uf2 2>/dev/null | head -1 || true)"
[[ -n "$UF2" && -f "$UF2" ]] || { echo "error: no update-*_nosd.uf2 in $BUILD_DIR" >&2; exit 1; }

mkdir -p "$OUT"
cp -f "$UF2" "$OUT/"
# merged zip (full BL+SD) if present — useful for recovery
ZIP="$(ls -1 "$BUILD_DIR"/*_s140_*.zip 2>/dev/null | head -1 || true)"
[[ -n "$ZIP" && -f "$ZIP" ]] && cp -f "$ZIP" "$OUT/"

echo "==> done"
echo "    UF2: $UF2"
echo "    copy: $OUT/$(basename "$UF2")"
ls -la "$OUT"
