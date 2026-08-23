#!/usr/bin/env bash
# EnvyOS bench orchestration — bootloader (sibling repo) + firmware/.mota (envycore).
#
# Usage:
#   ./scripts/build.sh                         # bootloader + envycore firmware build
#   ./scripts/build.sh --bootloader-only
#   ./scripts/build.sh --firmware-only
#   ./scripts/build.sh --mota-only             # alias for --firmware-only
#   ./scripts/build.sh --no-bootloader
#   ./scripts/build.sh --list-versions
#   ./scripts/build.sh --list-targets
#   ./scripts/build.sh --peaky-only
#   ./scripts/build.sh --no-peaky          # skip peaky when pinned in ENVYOS_VERSIONS

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPTS="$ROOT/scripts"

# shellcheck source=scripts/version.sh
source "$SCRIPTS/version.sh"

usage() {
  cat >&2 <<EOF
usage: $0 [options] [firmware-version] [build-mota options…]

  (default)         Build bootloader + envycore firmware/.mota
  --bootloader-only OTAFIX bootloaders only → bootloader/build/<bootloader>/
  --firmware-only   envycore/scripts/build-mota.sh only (aliases: --mota-only, --no-bootloader)
  --list-versions   Print ENVYOS_VERSIONS and exit
  --list-targets    Print envycore/scripts/targets.txt and exit
  --list-boards     Print otafix boards inferred from targets.txt and exit
  --peaky-only      Build pinned peaky into peaky_finders/dist/<ver>/ (local cargo)
  --no-peaky        Skip peaky even when peaky= is pinned
  -h, --help        Show this help

  Other flags (--target, --hex-only, --base, …) forward to envycore/scripts/build-mota.sh.
EOF
  exit 2
}

BUILD_BL=1
BUILD_FIRMWARE=1
BUILD_PEAKY=1
MOTA_ARGS=()

while (($# > 0)); do
  case "$1" in
    --bootloader-only)
      BUILD_FIRMWARE=0
      BUILD_PEAKY=0
      shift
      ;;
    --firmware-only | --mota-only | --no-bootloader)
      BUILD_BL=0
      shift
      ;;
    --peaky-only)
      BUILD_BL=0
      BUILD_FIRMWARE=0
      shift
      ;;
    --no-peaky)
      BUILD_PEAKY=0
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

if ((BUILD_BL == 0 && BUILD_FIRMWARE == 0 && BUILD_PEAKY == 0)); then
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
    "$ENVYCORE_ROOT/scripts/build-mota.sh" "${MOTA_ARGS[@]}"
  else
    "$ENVYCORE_ROOT/scripts/build-mota.sh"
  fi
fi

if ((BUILD_PEAKY == 1)) && ver="$(read_optional_envyos_version_key peaky 2>/dev/null)"; then
  echo ""
  echo "==> peaky ($ver)"
  verify_peaky_version_sync "${ver#v}" || exit 1
  ensure_peaky_release_cache "$ver"
fi

echo ""
echo "==> EnvyOS build complete"
if ((BUILD_BL == 1)); then
  echo "    bootloader: $BOOTLOADER_ROOT/$(read_bootloader_version)/"
fi
if ((BUILD_FIRMWARE == 1)); then
  echo "    motas:      $MOTAS_ROOT/$(read_firmware_version_file 2>/dev/null || read_distro_version)/"
fi
if ((BUILD_PEAKY == 1)) && ver="$(read_optional_envyos_version_key peaky 2>/dev/null)"; then
  echo "    peaky:      $PEAKY_DIST_ROOT/$ver/"
fi
