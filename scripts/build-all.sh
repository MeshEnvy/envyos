#!/usr/bin/env bash
# EnvyOS full bench build — bootloader + firmware/.mota + optional peaky + release tree.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPTS="$ROOT/scripts"

# shellcheck source=scripts/version.sh
source "$SCRIPTS/version.sh"

usage() {
  cat >&2 <<EOF
usage: envyos build [options] [firmware-version] [build-mota options…]

  (default)         Bootloader + motatool (all platforms) + firmware/.mota + peaky (if pinned) + release/
  --bootloader-only Bootloader only
  --firmware-only   Firmware/.mota only (aliases: --mota-only, --no-bootloader)
  --motatool-only   motatool release binaries (all platforms)
  --peaky-only      Peaky host binary only
  --release-only    Refresh build/<distro>/release/ from bench (no builds)
  --no-release      Skip release/ after build
  --no-peaky        Skip peaky even when peaky= is pinned
  --list-versions   Print ENVYOS_VERSIONS and exit
  --list-targets    Print scripts/targets.txt and exit
  --list-boards     Print otafix boards from targets.txt and exit

  Other flags (--target, --hex-only, --base, …) forward to scripts/build-mota.sh.
EOF
  exit 2
}

BUILD_BL=1
BUILD_MOTATOOL=1
BUILD_FIRMWARE=1
BUILD_PEAKY=1
BUILD_RELEASE=1
MOTA_ARGS=()

while (($# > 0)); do
  case "$1" in
    --bootloader-only)
      BUILD_MOTATOOL=0
      BUILD_FIRMWARE=0
      BUILD_PEAKY=0
      BUILD_RELEASE=0
      shift
      ;;
    --firmware-only | --mota-only | --no-bootloader)
      BUILD_BL=0
      BUILD_MOTATOOL=0
      shift
      ;;
    --motatool-only)
      shift
      exec "$SCRIPTS/build-motatool.sh" "$@"
      ;;
    --peaky-only)
      shift
      exec "$SCRIPTS/build-peaky.sh" "$@"
      ;;
    --release-only | --stage-only)
      shift
      populate_distro_release "$@"
      exit 0
      ;;
    --no-release | --no-stage)
      BUILD_RELEASE=0
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

if ((BUILD_BL == 0 && BUILD_MOTATOOL == 0 && BUILD_FIRMWARE == 0 && BUILD_PEAKY == 0 && BUILD_RELEASE == 0)); then
  echo "error: nothing to build" >&2
  exit 1
fi

distro_ver="$(read_distro_version)"
bench_root="$(distro_bench_root "$distro_ver")"
release_root="$(distro_release_root "$distro_ver")"

if ((BUILD_BL == 1 || BUILD_MOTATOOL == 1 || BUILD_FIRMWARE == 1 || BUILD_PEAKY == 1)); then
  echo "==> EnvyOS build"
  list_envyos_versions | sed 's/^/    /'
  export ENVYOS_SKIP_RELEASE=1
fi

if ((BUILD_BL == 1)); then
  echo ""
  bl_ver="$(read_bootloader_version)"
  echo "==> bootloader ($bl_ver)"
  "$SCRIPTS/build-bl.sh"
fi

if ((BUILD_MOTATOOL == 1)); then
  echo ""
  mt_ver="$(read_motatool_version)"
  echo "==> motatool ($mt_ver, all platforms)"
  "$SCRIPTS/build-motatool.sh"
fi

if ((BUILD_FIRMWARE == 1)); then
  echo ""
  fw_ver="$(read_firmware_version)"
  echo "==> firmware + .mota ($fw_ver)"
  if ((${#MOTA_ARGS[@]} > 0)); then
    "$SCRIPTS/build-mota.sh" "${MOTA_ARGS[@]}"
  else
    "$SCRIPTS/build-mota.sh"
  fi
fi

if ((BUILD_PEAKY == 1)) && ver="$(read_optional_envyos_version_key peaky 2>/dev/null)"; then
  echo ""
  echo "==> peaky ($ver)"
  "$SCRIPTS/build-peaky.sh"
fi

unset ENVYOS_SKIP_RELEASE

if ((BUILD_RELEASE == 1)); then
  echo ""
  populate_distro_release "$distro_ver"
fi

if ((BUILD_BL == 1 || BUILD_MOTATOOL == 1 || BUILD_FIRMWARE == 1 || BUILD_PEAKY == 1)); then
  echo ""
  echo "==> EnvyOS build complete"
  if ((BUILD_BL == 1)); then
    echo "    bench/bootloader: $(bootloader_bench_root "$(read_bootloader_version)")/"
  fi
  if ((BUILD_MOTATOOL == 1)); then
    echo "    bench/motatool:   $(motatool_bench_root "$distro_ver")/"
  fi
  if ((BUILD_FIRMWARE == 1)); then
    echo "    bench/firmware:   $(firmware_bench_root "$(read_firmware_version)")/"
  fi
  if ((BUILD_PEAKY == 1)) && ver="$(read_optional_envyos_version_key peaky 2>/dev/null)"; then
    echo "    bench/peaky:      $(peaky_bench_root "$distro_ver")/"
  fi
  if ((BUILD_RELEASE == 1)); then
    echo "    release:          $release_root/"
  fi
fi
