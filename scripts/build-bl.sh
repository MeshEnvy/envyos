#!/usr/bin/env bash
# Build EnvyBoot nRF52 bootloaders (in-place .mota apply) via Docker.
#
# Usage:
#   ./scripts/build-bl.sh [version] [--targets-file <path>] [--list-boards]
#   ./scripts/build-bl.sh [version] BOARD [BOARD…]
#
# version defaults to ENVYOS_VERSIONS bootloader (e.g. v0.1.3).
# With no BOARD args, board profiles are inferred from scripts/targets.txt.
#
# UF2: bootloader/_build/build-<board>/<board>_bootloader-<ver>.uf2
# Recovery: bootloader/_build/build-<board>/<board>_bootloader-*.recovery.zip
# Output: build/<ver>/bench/bootloader/
#
# Requires: Docker. Submodules under bootloader/ are initialized if needed.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OTAFIX="$BOOTLOADER_SRC"
TARGETS_FILE="$ROOT/scripts/targets.txt"
IMAGE="vk-otafix-build"

# shellcheck source=scripts/version.sh
source "$ROOT/scripts/version.sh"

usage() {
  cat >&2 <<EOF
usage: $0 [version] [--targets-file <path>] [--list-boards]
       $0 [version] BOARD [BOARD…]

  version         Optional override; default is ENVYOS_VERSIONS bootloader (e.g. v0.1.0)
  (no BOARD args) Build otafix bootloaders for base boards in targets.txt
  BOARD…          Build explicit otafix board name(s) instead
  --list-boards   Print inferred otafix boards from targets file and exit
  --targets-file  Target map (default: scripts/targets.txt)
EOF
  exit 2
}

LIST_BOARDS=0
POSITIONAL=()

while (($# > 0)); do
  case "$1" in
    --targets-file)
      [[ $# -ge 2 ]] || usage
      TARGETS_FILE=$2
      shift 2
      ;;
    --list-boards)
      LIST_BOARDS=1
      shift
      ;;
    -h | --help)
      usage
      ;;
    --*)
      echo "error: unknown option: $1" >&2
      usage
      ;;
    *)
      POSITIONAL+=("$1")
      shift
      ;;
  esac
done

[[ -d "$OTAFIX" ]] || { echo "error: missing $OTAFIX" >&2; exit 1; }

if ((LIST_BOARDS == 1)); then
  otafix_boards_from_targets_file "$TARGETS_FILE"
  exit 0
fi

VER=""
EXPLICIT_BOARDS=()
if ((${#POSITIONAL[@]} > 0)); then
  if VER="$(normalize_version "${POSITIONAL[0]}" 2>/dev/null)"; then
    EXPLICIT_BOARDS=("${POSITIONAL[@]:1}")
  else
    EXPLICIT_BOARDS=("${POSITIONAL[@]}")
  fi
fi

if [[ -z "$VER" ]]; then
  VER="$(read_bootloader_version_file)" || usage
fi

OUT="$(bootloader_bench_root "$VER")"
assert_component_tree_not_released bootloader "$VER"

BOARDS=()
if ((${#EXPLICIT_BOARDS[@]} > 0)); then
  BOARDS=("${EXPLICIT_BOARDS[@]}")
else
  while IFS= read -r board; do
    [[ -n "$board" ]] && BOARDS+=("$board")
  done < <(otafix_boards_from_targets_file "$TARGETS_FILE")
fi

ensure_otafix_ready() {
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
  )
}

build_board() {
  local board=$1
  local git_version="${VER#v}"
  echo "==> bootloader $VER  BOARD=$board"

  (
    cd "$OTAFIX"
    echo "    docker run … make BOARD=$board ENVYBOOT_VERSION=$git_version all"
    docker run --rm -v "$PWD":/src -w /src "$IMAGE" make "BOARD=$board" "ENVYBOOT_VERSION=$git_version" all
  )

  local build_dir="$OTAFIX/_build/build-$board"
  local uf2
  uf2="$(ls -1t "$build_dir"/"${board}"_bootloader-"${git_version}".uf2 2>/dev/null | head -1 || true)"
  if [[ -z "$uf2" ]]; then
    uf2="$(ls -1t "$build_dir"/*_bootloader-*.uf2 2>/dev/null | head -1 || true)"
  fi
  [[ -n "$uf2" && -f "$uf2" ]] || { echo "error: no *_bootloader-*.uf2 in $build_dir" >&2; exit 1; }

  mkdir -p "$OUT"
  cp -f "$uf2" "$OUT/"
  # recovery zip (break-glass BL+SD) if present
  local zip
  zip="$(ls -1t "$build_dir"/"${board}"_bootloader-"${git_version}".recovery.zip 2>/dev/null | head -1 || true)"
  if [[ -z "$zip" ]]; then
    zip="$(ls -1t "$build_dir"/*_bootloader-*.recovery.zip 2>/dev/null | head -1 || true)"
  fi
  [[ -n "$zip" && -f "$zip" ]] && cp -f "$zip" "$OUT/"

  echo "    UF2: $uf2"
  echo "    copy: $OUT/$(basename "$uf2")"
  [[ -n "${zip:-}" && -f "${zip:-}" ]] && echo "    recovery: $OUT/$(basename "$zip")"
}

if ((${#EXPLICIT_BOARDS[@]} > 0)); then
  echo "==> otafix boards: ${BOARDS[*]} (explicit)"
else
  echo "==> otafix boards: ${BOARDS[*]} (from $TARGETS_FILE)"
fi

rm -rf "$OUT"
mkdir -p "$OUT"
printf '%s\n' "$VER" >"$OUT/version.txt"

ensure_otafix_ready

for board in "${BOARDS[@]}"; do
  build_board "$board"
done

echo "==> done $VER"
ls -la "$OUT"
maybe_populate_distro_release
