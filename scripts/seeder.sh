#!/usr/bin/env bash
# Serve build/motas to a MeshCore seeder over USB serial (motatool serve).
#
# Usage:
#   ./scripts/seeder.sh /dev/cu.usbmodem1444301
#   ./scripts/seeder.sh usbmodem1444301              # → /dev/cu.usbmodem1444301
#   ./scripts/seeder.sh /dev/cu.usbmodem1444301 ./build/motas/v0.1.1
#
# Requires: build/motatool/<motatool>/motatool (from build-mota.sh / build.sh).

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

motatool_bin() {
  local ver bin
  ver="$(read_motatool_version)"
  bin="$MOTATOOL_ROOT/$ver/motatool"
  if [[ -x "$bin" ]]; then
    echo "$bin"
    return
  fi
  echo "error: motatool not found at $bin (run ./scripts/build-mota.sh or ./scripts/build.sh first)" >&2
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
