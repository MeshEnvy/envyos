#!/usr/bin/env bash
# EnvyOS bench orchestration — bootloader (sibling repo) + firmware/.mota (envycore).
#
# Usage:
#   ./scripts/build.sh                         # bootloader + envycore firmware build
#   ./scripts/build.sh --bootloader-only
<<<<<<< HEAD
#   ./scripts/build.sh --mota-only             # firmware + .mota (skip bootloader)
#   ./scripts/build.sh --no-bootloader         # same as --mota-only
#   ./scripts/build.sh v0.1.1                  # override firmware version for mota step
=======
#   ./scripts/build.sh --firmware-only
#   ./scripts/build.sh --mota-only             # alias for --firmware-only
#   ./scripts/build.sh --no-bootloader
>>>>>>> hotfix/v0.1.3
#   ./scripts/build.sh --list-versions
#   ./scripts/build.sh --list-targets
#   ./scripts/build.sh --list-boards

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPTS="$ROOT/scripts"

# shellcheck source=scripts/version.sh
source "$SCRIPTS/version.sh"

usage() {
  cat >&2 <<EOF
usage: $0 [options] [firmware-version] [build-mota options…]

<<<<<<< HEAD
  (default)         Build bootloader + firmware/.mota + motatool (all platforms)
  --bootloader-only OTAFIX bootloaders only → build/bootloader/<bootloader>/
  --mota-only       Firmware + .mota only (skip bootloader)
  --no-bootloader   Alias for --mota-only
=======
  (default)         Build bootloader + envycore firmware/.mota
  --bootloader-only OTAFIX bootloaders only → bootloader/build/<bootloader>/
  --firmware-only   envycore/scripts/build-mota.sh only (aliases: --mota-only, --no-bootloader)
>>>>>>> hotfix/v0.1.3
  --list-versions   Print ENVYOS_VERSIONS and exit
  --list-targets    Print envycore/scripts/targets.txt and exit
  --list-boards     Print otafix boards inferred from targets.txt and exit
  -h, --help        Show this help

<<<<<<< HEAD
  firmware-version  Optional override for build-mota (default: ENVYOS_VERSIONS firmware)

  Other flags (--target, --hex-only, --base, --release, --debug, --mota-jobs, --targets-file, …) are forwarded to
  build-mota.sh.

examples:
  $0
  $0 --bootloader-only
  $0 --target rak4631-repeater-slim
  $0 --release
  $0 --debug
  $0 v0.1.1 --base v0.1.0
  $0 --hex-only
=======
  Other flags (--target, --hex-only, --base, …) forward to envycore/scripts/build-mota.sh.
>>>>>>> hotfix/v0.1.3
EOF
  exit 2
}

BUILD_BL=1
<<<<<<< HEAD
BUILD_MOTA=1
BUILD_MOTATOOL=1
=======
BUILD_FIRMWARE=1
>>>>>>> hotfix/v0.1.3
MOTA_ARGS=()

while (($# > 0)); do
  case "$1" in
    --bootloader-only)
<<<<<<< HEAD
      BUILD_MOTA=0
      BUILD_MOTATOOL=0
=======
      BUILD_FIRMWARE=0
>>>>>>> hotfix/v0.1.3
      shift
      ;;
    --firmware-only | --mota-only | --no-bootloader)
      BUILD_BL=0
      BUILD_MOTATOOL=0
      shift
      ;;
    --list-versions)
      list_envyos_versions
      exit 0
      ;;
    --list-targets)
      exec "$ENVYCORE_ROOT/scripts/build-mota.sh" --list-targets "${@:2}"
      ;;
    --list-boards)
      exec "$BOOTLOADER_SRC/scripts/build-bl.sh" --list-boards "${@:2}"
      ;;
    -h | --help)
      usage
      ;;
    --)
      shift
      if (($# > 0)); then
        MOTA_ARGS+=("$@")
      fi
      break
      ;;
    *)
      MOTA_ARGS+=("$1")
      shift
      ;;
  esac
done

if ((BUILD_BL == 0 && BUILD_FIRMWARE == 0)); then
  echo "error: nothing to build" >&2
  exit 1
fi

echo "==> EnvyOS build"
list_envyos_versions | sed 's/^/    /'

if ((BUILD_BL == 1)); then
  echo ""
  bl_ver="$(read_bootloader_version)"
  echo "==> bootloader ($bl_ver)"
  export ENVYOS_ROOT="$ROOT"
  "$BOOTLOADER_SRC/scripts/build-bl.sh"
fi

if ((BUILD_FIRMWARE == 1)); then
  echo ""
  echo "==> firmware + .mota (envycore/scripts/build-mota.sh)"
  export ENVYOS_ROOT="$ROOT"
  if ((${#MOTA_ARGS[@]} > 0)); then
<<<<<<< HEAD
    if normalize_version "${MOTA_ARGS[0]}" >/dev/null 2>&1; then
      echo "==> firmware + .mota ($(normalize_version "${MOTA_ARGS[0]}"))"
    else
      echo "==> firmware + .mota ($(read_firmware_version))"
    fi
  else
    echo "==> firmware + .mota ($(read_firmware_version))"
  fi
  if ((${#MOTA_ARGS[@]} > 0)); then
    "$SCRIPTS/build-mota.sh" "${MOTA_ARGS[@]}"
  else
    "$SCRIPTS/build-mota.sh"
=======
    "$ENVYCORE_ROOT/scripts/build-mota.sh" "${MOTA_ARGS[@]}"
  else
    "$ENVYCORE_ROOT/scripts/build-mota.sh"
>>>>>>> hotfix/v0.1.3
  fi
fi

if ((BUILD_MOTATOOL == 1)); then
  echo ""
  echo "==> motatool (all release platforms)"
  "$SCRIPTS/build-motatool.sh"
fi

echo ""
echo "==> EnvyOS build complete"
if ((BUILD_BL == 1)); then
  echo "    bootloader: $BOOTLOADER_ROOT/$(read_bootloader_version)/"
fi
<<<<<<< HEAD
if ((BUILD_MOTA == 1)); then
  fw_ver="${MOTA_ARGS[0]:-}"
  if [[ -n "$fw_ver" ]] && fw_ver="$(normalize_version "$fw_ver" 2>/dev/null || true)"; then
    :
  else
    fw_ver="$(read_firmware_version)"
  fi
  echo "    firmware:   $FIRMWARE_ROOT/$fw_ver/"
fi
if ((BUILD_MOTATOOL == 1 || BUILD_MOTA == 1)); then
  if [[ -d "$MOTATOOL_ROOT/$(read_motatool_version)" ]]; then
    mt_plat="$(list_staged_motatool_platforms "$(read_motatool_version)" | paste -sd, -)"
    echo "    motatool:   $MOTATOOL_ROOT/$(read_motatool_version)/ (${mt_plat})"
  fi
=======
if ((BUILD_FIRMWARE == 1)); then
  echo "    motas:      $MOTAS_ROOT/$(read_firmware_version_file 2>/dev/null || read_distro_version)/"
>>>>>>> hotfix/v0.1.3
fi
