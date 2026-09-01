#!/usr/bin/env bash
# EnvyOS full bench build — bootloader + firmware/.mota + optional peaky + release tree.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPTS="$ROOT/scripts"
META="$ROOT/packages-meta"

# shellcheck source=scripts/version.sh
source "$SCRIPTS/version.sh"

usage() {
  cat >&2 <<EOF
usage: envyos build [options] [build-mota options…]

  (default)         Bootloader + motatool (all platforms) + firmware/.mota + peaky/envybot/mcmt (if pinned) + release/
  --bootloader-only Bootloader only
  --firmware-only   Firmware/.mota only (aliases: --mota-only, --no-bootloader)
  --motatool-only   motatool release binaries (all platforms)
  --peaky-only      Peaky host binary only
  --envybot-only    Envybot wheel only
  --mcmt-only       mcmt-gateway wheel only
  --release-only    Refresh build/<branch>/release/ from bench (no builds)
  --clean           Wipe bench output trees and force full rebuild
  --no-release      Skip release/ after build
  --no-peaky        Skip peaky even when peaky= is pinned
  --no-envybot      Skip envybot even when envybot= is pinned
  --no-mcmt         Skip mcmt-gateway even when mcmt-gateway= is pinned
  --list-versions   Print MANIFEST.json and exit
  --list-targets    Print scripts/targets.txt and exit
  --list-boards     Print otafix boards from targets.txt and exit

  Other flags (--target, --hex-only, --base, …) forward to packages-meta/meshcore/build.sh.
EOF
  exit 2
}

BUILD_BL=1
BUILD_MOTATOOL=1
BUILD_FIRMWARE=1
BUILD_PEAKY=1
BUILD_ENVYBOT=1
BUILD_MCMT=1
BUILD_RELEASE=1
BUILD_CLEAN=0
BUILD_FAILED=0
MOTA_ARGS=()

run_step() {
  local label=$1
  shift
  if "$@"; then
    return 0
  fi
  echo "error: $label failed (continuing so release/ can still stage from bench)" >&2
  BUILD_FAILED=1
}

while (($# > 0)); do
  case "$1" in
    --clean)
      BUILD_CLEAN=1
      shift
      ;;
    --bootloader-only)
      BUILD_MOTATOOL=0
      BUILD_FIRMWARE=0
      BUILD_PEAKY=0
      BUILD_ENVYBOT=0
      BUILD_MCMT=0
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
      exec "$META/motatool/build.sh" "$@"
      ;;
    --peaky-only)
      shift
      exec "$META/peaky/build.sh" "$@"
      ;;
    --envybot-only)
      shift
      exec "$META/envybot/build.sh" "$@"
      ;;
    --mcmt-only)
      shift
      exec "$META/mcmt-gateway/build.sh" "$@"
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
    --no-envybot)
      BUILD_ENVYBOT=0
      shift
      ;;
    --no-mcmt)
      BUILD_MCMT=0
      shift
      ;;
    --list-versions)
      list_manifest
      exit 0
      ;;
    --list-targets)
      exec "$META/meshcore/build.sh" --list-targets "${@:2}"
      ;;
    --list-boards)
      exec "$META/adafruit-nrf52-bootloader/build.sh" --list-boards "${@:2}"
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
      if is_build_version_arg "$1"; then
        die_build_version_arg "$1"
      fi
      MOTA_ARGS+=("$1")
      shift
      ;;
  esac
done

if ((BUILD_BL == 0 && BUILD_MOTATOOL == 0 && BUILD_FIRMWARE == 0 && BUILD_PEAKY == 0 && BUILD_ENVYBOT == 0 && BUILD_MCMT == 0 && BUILD_RELEASE == 0)); then
  echo "error: nothing to build" >&2
  exit 1
fi

distro_ver="$(read_bench_tree_key)"
maybe_migrate_version_bench_to_slot "$distro_ver"
bench_root="$(distro_bench_root "$distro_ver")"
release_root="$(distro_release_root "$distro_ver")"

if ((BUILD_BL == 1 || BUILD_MOTATOOL == 1 || BUILD_FIRMWARE == 1 || BUILD_PEAKY == 1 || BUILD_ENVYBOT == 1 || BUILD_MCMT == 1)); then
  echo "==> EnvyOS build (slot: $distro_ver$( ((BUILD_CLEAN == 1)) && printf ', clean'))"
  list_manifest | sed 's/^/    /'
  export ENVYOS_SKIP_RELEASE=1
fi

if ((BUILD_BL == 1)); then
  echo ""
  bl_ver="$(read_bootloader_version)"
  echo "==> bootloader ($bl_ver)"
  if ((BUILD_CLEAN == 1)); then
    run_step bootloader "$META/adafruit-nrf52-bootloader/build.sh" --clean
  else
    run_step bootloader "$META/adafruit-nrf52-bootloader/build.sh"
  fi
fi

if ((BUILD_MOTATOOL == 1)); then
  echo ""
  mt_ver="$(read_motatool_version)"
  echo "==> motatool ($mt_ver, all platforms)"
  if ((BUILD_CLEAN == 1)); then
    run_step motatool "$META/motatool/build.sh" --clean
  else
    run_step motatool "$META/motatool/build.sh"
  fi
fi

if ((BUILD_FIRMWARE == 1)); then
  echo ""
  fw_ver="$(read_firmware_version)"
  echo "==> firmware + .mota ($fw_ver)"
  if ((BUILD_CLEAN == 1)); then
    if ((${#MOTA_ARGS[@]} > 0)); then
      run_step meshcore "$META/meshcore/build.sh" --clean "${MOTA_ARGS[@]}"
    else
      run_step meshcore "$META/meshcore/build.sh" --clean
    fi
  elif ((${#MOTA_ARGS[@]} > 0)); then
    run_step meshcore "$META/meshcore/build.sh" "${MOTA_ARGS[@]}"
  else
    run_step meshcore "$META/meshcore/build.sh"
  fi
fi

if ((BUILD_PEAKY == 1)) && ver="$(read_optional_manifest_key peaky 2>/dev/null)"; then
  echo ""
  echo "==> peaky ($ver)"
  run_step peaky "$META/peaky/build.sh"
fi

if ((BUILD_ENVYBOT == 1)) && ver="$(read_optional_manifest_key envybot 2>/dev/null)"; then
  echo ""
  echo "==> envybot ($ver)"
  run_step envybot "$META/envybot/build.sh"
fi

if ((BUILD_MCMT == 1)) && ver="$(read_optional_manifest_key mcmt-gateway 2>/dev/null)"; then
  echo ""
  echo "==> mcmt-gateway ($ver)"
  run_step mcmt-gateway "$META/mcmt-gateway/build.sh"
fi

unset ENVYOS_SKIP_RELEASE

if ((BUILD_RELEASE == 1)); then
  echo ""
  run_step release populate_distro_release "$distro_ver"
fi

if ((BUILD_BL == 1 || BUILD_MOTATOOL == 1 || BUILD_FIRMWARE == 1 || BUILD_PEAKY == 1 || BUILD_ENVYBOT == 1 || BUILD_MCMT == 1)); then
  echo ""
  echo "==> EnvyOS build complete"
  if ((BUILD_BL == 1)); then
    echo "    bench/bootloader: $(bootloader_bench_root "$distro_ver" "$(read_bootloader_version)")/"
  fi
  if ((BUILD_MOTATOOL == 1)); then
    echo "    bench/motatool:   $(motatool_bench_root "$distro_ver" "$(read_motatool_version)")/"
  fi
  if ((BUILD_FIRMWARE == 1)); then
    echo "    bench/meshcore:   $(firmware_bench_root "$distro_ver" "$(read_firmware_version)")/"
  fi
  if ((BUILD_PEAKY == 1)) && ver="$(read_optional_manifest_key peaky 2>/dev/null)"; then
    echo "    bench/peaky:      $(peaky_bench_root "$distro_ver" "$ver")/"
  fi
  if ((BUILD_ENVYBOT == 1)) && ver="$(read_optional_manifest_key envybot 2>/dev/null)"; then
    echo "    bench/envybot:    $(envybot_bench_root "$distro_ver" "$ver")/"
  fi
  if ((BUILD_MCMT == 1)) && ver="$(read_optional_manifest_key mcmt-gateway 2>/dev/null)"; then
    echo "    bench/mcmt:       $(mcmt_gateway_bench_root "$distro_ver" "$ver")/"
  fi
  if ((BUILD_RELEASE == 1)); then
    echo "    release:          $release_root/"
  fi
fi

if ((BUILD_FAILED != 0)); then
  echo "error: one or more build steps failed" >&2
  exit 1
fi
