#!/usr/bin/env bash
# EnvyOS consolidated build — bootloader + firmware/.mota (wraps build-bl.sh + build-mota.sh).
#
# Usage:
#   ./scripts/build.sh                         # full build from ENVYOS_VERSIONS
#   ./scripts/build.sh --bootloader-only
#   ./scripts/build.sh --mota-only             # firmware + .mota (skip bootloader)
#   ./scripts/build.sh --no-bootloader         # same as --mota-only
#   ./scripts/build.sh v0.1.1                  # override distro version for mota step
#   ./scripts/build.sh --list-versions
#   ./scripts/build.sh --list-targets
#   ./scripts/build.sh --list-boards
#
# Remaining flags are passed to build-mota.sh (--target, --hex-only, --base, …).

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPTS="$ROOT/scripts"

# shellcheck source=scripts/version.sh
source "$SCRIPTS/version.sh"

usage() {
  cat >&2 <<EOF
usage: $0 [options] [distro-version] [build-mota options…]

  (default)         Build bootloader + firmware/.mota (ENVYOS_VERSIONS)
  --bootloader-only OTAFIX bootloaders only → build/bootloader/<bootloader>/
  --mota-only       Firmware + .mota only (skip bootloader)
  --no-bootloader   Alias for --mota-only
  --list-versions   Print ENVYOS_VERSIONS and exit
  --list-targets    Print targets.txt and exit
  --list-boards     Print otafix boards inferred from targets.txt and exit
  -h, --help        Show this help

  distro-version    Optional override for build-mota (default: ENVYOS_VERSIONS distro)

  Other flags (--target, --hex-only, --base, --targets-file, …) are forwarded to
  build-mota.sh.

examples:
  $0
  $0 --bootloader-only
  $0 --target rak4631-repeater-slim
  $0 v0.1.1 --base v0.1.0
  $0 --hex-only
EOF
  exit 2
}

BUILD_BL=1
BUILD_MOTA=1
MOTA_ARGS=()

while (($# > 0)); do
  case "$1" in
    --bootloader-only)
      BUILD_MOTA=0
      shift
      ;;
    --mota-only | --no-bootloader)
      BUILD_BL=0
      shift
      ;;
    --list-versions)
      list_envyos_versions
      exit 0
      ;;
    --list-targets)
      exec "$SCRIPTS/build-mota.sh" --list-targets "${@:2}"
      ;;
    --list-boards)
      exec "$SCRIPTS/build-bl.sh" --list-boards "${@:2}"
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

if ((BUILD_BL == 0 && BUILD_MOTA == 0)); then
  echo "error: nothing to build (use default, --bootloader-only, or --mota-only)" >&2
  exit 1
fi

echo "==> EnvyOS build"
list_envyos_versions | sed 's/^/    /'

if ((BUILD_BL == 1)); then
  echo ""
  bl_ver="$(read_bootloader_version)"
  echo "==> bootloader ($bl_ver)"
  "$SCRIPTS/build-bl.sh"
fi

if ((BUILD_MOTA == 1)); then
  echo ""
  if ((${#MOTA_ARGS[@]} > 0)); then
    if normalize_version "${MOTA_ARGS[0]}" >/dev/null 2>&1; then
      echo "==> firmware + .mota ($(normalize_version "${MOTA_ARGS[0]}"))"
    else
      echo "==> firmware + .mota ($(read_distro_version))"
    fi
  else
    echo "==> firmware + .mota ($(read_distro_version))"
  fi
  if ((${#MOTA_ARGS[@]} > 0)); then
    "$SCRIPTS/build-mota.sh" "${MOTA_ARGS[@]}"
  else
    "$SCRIPTS/build-mota.sh"
  fi
fi

echo ""
echo "==> EnvyOS build complete"
if ((BUILD_BL == 1)); then
  echo "    bootloader: $BOOTLOADER_ROOT/$(read_bootloader_version)/"
fi
if ((BUILD_MOTA == 1)); then
  mota_ver="${MOTA_ARGS[0]:-}"
  if [[ -n "$mota_ver" ]] && mota_ver="$(normalize_version "$mota_ver" 2>/dev/null || true)"; then
    :
  else
    mota_ver="$(read_distro_version)"
  fi
  echo "    motas:      $MOTAS_ROOT/$mota_ver/"
  if [[ -d "$MOTATOOL_ROOT/$(read_motatool_version)" ]]; then
    echo "    motatool:   $MOTATOOL_ROOT/$(read_motatool_version)/motatool"
  fi
fi
