#!/usr/bin/env bash
# Serve build/firmware to a MeshCore seeder over USB serial (motatool serve).
#
# Usage:
#   ./scripts/seeder.sh /dev/cu.usbmodem1444301
#   ./scripts/seeder.sh usbmodem1444301              # → /dev/cu.usbmodem1444301
#   ./scripts/seeder.sh /dev/cu.usbmodem1444301 ./build/firmware/v0.1.1
#
# Requires: build/motatool/<motatool>/motatool-<platform> (from build-motatool / build).

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/version.sh
source "$ROOT/scripts/version.sh"
DEFAULT_DIR="$FIRMWARE_ROOT/$(read_firmware_version)"
DIR="${2:-$DEFAULT_DIR}"

usage() {
  cat >&2 <<EOF
usage: $0 <serial-device> [firmware-dir]

  serial-device   USB serial port, e.g. /dev/cu.usbmodem1444301
  firmware-dir  folder of .mota files (default: build/firmware/<firmware>)

examples:
  $0 /dev/cu.usbmodem1444301
  $0 usbmodem1444301 ./build/firmware/v0.1.1
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

SERIAL="$(resolve_serial "$1")"
[[ -e "$SERIAL" ]] || {
  echo "error: serial device not found: $SERIAL" >&2
  exit 1
}
[[ -d "$DIR" ]] || {
  echo "error: firmware dir not found: $DIR" >&2
  exit 1
}

MT="$(resolve_motatool_bin)"
exec "$MT" serve --dir "$DIR" --serial "$SERIAL" -v
