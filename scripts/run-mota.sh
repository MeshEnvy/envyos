#!/usr/bin/env bash
# Serve build/motas to a MeshCore seeder over USB serial (motatool serve).
#
# Usage:
#   ./scripts/run-mota.sh /dev/cu.usbmodem1444301
#   ./scripts/run-mota.sh usbmodem1444301              # → /dev/cu.usbmodem1444301
#   ./scripts/run-mota.sh /dev/cu.usbmodem1444301 ./build/motas/v0.1.1
#
# Requires: motatool on PATH or ./motatool/ built with cargo.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/version.sh
source "$ROOT/scripts/version.sh"
DIR="${2:-$MOTAS_ROOT}"

usage() {
  cat >&2 <<EOF
usage: $0 <serial-device> [motas-dir]

  serial-device   USB serial port, e.g. /dev/cu.usbmodem1444301
  motas-dir       folder of .mota files (default: ./build/motas)

examples:
  $0 /dev/cu.usbmodem1444301
  $0 usbmodem1444301 ./build/motas/v0.1.1
EOF
  exit 2
}

[[ $# -ge 1 && $# -le 2 ]] || usage

resolve_serial() {
  local dev="$1"
  if [[ "$dev" == /* ]]; then
    printf '%s' "$dev"
    return
  fi
  if [[ -e "/dev/cu.$dev" ]]; then
    printf '/dev/cu.%s' "$dev"
    return
  fi
  if [[ -e "/dev/tty.$dev" ]]; then
    printf '/dev/tty.%s' "$dev"
    return
  fi
  printf '/dev/cu.%s' "$dev"
}

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
  local rel="$ROOT/motatool/target/release/motatool"
  if [[ -x "$rel" ]]; then
    echo "$rel"
    return
  fi
  if [[ -d "$ROOT/motatool" ]]; then
    local cargo_bin cargo_dir
    cargo_bin="$(find_cargo)"
    cargo_dir="$(dirname "$cargo_bin")"
    echo "building motatool (release) with $cargo_bin …" >&2
    (cd "$ROOT/motatool" && PATH="$cargo_dir:$PATH" "$cargo_bin" build --release)
    [[ -x "$rel" ]] || { echo "error: motatool build did not produce $rel" >&2; exit 1; }
    echo "$rel"
    return
  fi
  echo "error: motatool not found (install or clone into $ROOT/motatool)" >&2
  exit 1
}

SERIAL="$(resolve_serial "$1")"
[[ -e "$SERIAL" ]] || {
  echo "error: serial device not found: $SERIAL" >&2
  exit 1
}
[[ -d "$DIR" ]] || {
  echo "error: motas dir not found: $DIR" >&2
  exit 1
}

MT="$(motatool_bin)"
exec "$MT" serve --dir "$DIR" --serial "$SERIAL" -v
