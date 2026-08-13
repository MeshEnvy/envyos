#!/usr/bin/env bash
# Build firmware (+ optional .mota) for targets listed in scripts/targets.txt.
#
# Usage:
#   ./scripts/build-mota.sh                    # firmware version from ./ENVYOS_VERSIONS
#   ./scripts/build-mota.sh v0.1.1             # override version (output + FIRMWARE_VERSION stamp)
#   ./scripts/build-mota.sh --target wismesh-tag-repeater
#   ./scripts/build-mota.sh v0.1.2 --base v0.1.0   # delta from one base only
#   ./scripts/build-mota.sh --hex-only         # stock MeshCore (no EndF / OTA)
#   ./scripts/build-mota.sh --list-targets
#
# Requires: PlatformIO (`pio`). Full .mota packaging also needs ./motatool/ (built via cargo if needed).

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MC="$ROOT/envycore"
# shellcheck source=scripts/version.sh
source "$ROOT/scripts/version.sh"
OUT_ROOT="$FIRMWARE_ROOT"
TARGETS_FILE="$ROOT/scripts/targets.txt"

TARGET_SLUGS=()
TARGET_ENVS=()
TARGET_DESCS=()

usage() {
  cat >&2 <<EOF
usage: $0 [version] [--target <slug>]… [--base <version>] [--hex-only] [--targets-file <path>]
       $0 --list-targets [--targets-file <path>]

  version         Optional override for output dir and -DFIRMWARE_VERSION (default: ENVYOS_VERSIONS firmware)
  --target        Build one target slug (repeatable; default: all in targets file)
  --base          Build delta from one base only (default: all prior versions with base hex)
  --hex-only      Build hex/uf2 only — skip .mota packaging (stock MeshCore without EndF/OTA)
  --targets-file  Target map (default: scripts/targets.txt)
  --list-targets  Print configured targets and exit

examples:
  $0
  $0 v0.1.1
  $0 --target wismesh-tag-repeater --target rak4631-repeater
  $0 v0.1.2 --base v0.1.0
  $0 --hex-only
  $0 --list-targets
EOF
  exit 2
}

load_targets() {
  local file="$1"
  [[ -f "$file" ]] || {
    echo "error: targets file not found: $file" >&2
    exit 1
  }

  TARGET_SLUGS=()
  TARGET_ENVS=()
  TARGET_DESCS=()

  local line slug env desc
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    [[ -n "$line" ]] || continue

    read -r slug env desc <<<"$line"
    [[ -n "$slug" && -n "$env" ]] || {
      echo "error: bad targets line (want: slug env [description]): $line" >&2
      exit 1
    }

    TARGET_SLUGS+=("$slug")
    TARGET_ENVS+=("$env")
    TARGET_DESCS+=("${desc:-}")
  done <"$file"

  [[ ${#TARGET_SLUGS[@]} -gt 0 ]] || {
    echo "error: no targets in $file" >&2
    exit 1
  }
}

list_targets() {
  local file="$1"
  load_targets "$file"
  local i
  printf '%-24s  %-36s  %s\n' "SLUG" "PLATFORMIO_ENV" "DESCRIPTION"
  for i in "${!TARGET_SLUGS[@]}"; do
    printf '%-24s  %-36s  %s\n' "${TARGET_SLUGS[$i]}" "${TARGET_ENVS[$i]}" "${TARGET_DESCS[$i]}"
  done
}

target_index() {
  local want="$1"
  local i
  for i in "${!TARGET_SLUGS[@]}"; do
    if [[ "${TARGET_SLUGS[$i]}" == "$want" ]]; then
      printf '%s' "$i"
      return 0
    fi
  done
  return 1
}

# Homebrew's ~/.cargo/bin/cargo can be a broken rustup-init shim; prefer the real toolchain binary.
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
  local mt_ver path
  mt_ver="$(read_motatool_version)"
  verify_motatool_version_sync "$mt_ver"

  if path="$(resolve_motatool_bin "$mt_ver" 2>/dev/null)"; then
    echo "$path"
    return
  fi

  local rel="$ROOT/motatool/target/release/motatool"
  if [[ -x "$rel" ]]; then
    stage_motatool_binary "$rel" "$(host_motatool_platform_slug)"
    resolve_motatool_bin "$mt_ver"
    return
  fi
  if [[ -d "$ROOT/motatool" ]]; then
    local cargo_bin cargo_dir platform
    cargo_bin="$(find_cargo)"
    cargo_dir="$(dirname "$cargo_bin")"
    platform="$(host_motatool_platform_slug)"
    echo "building motatool (release) for $platform with $cargo_bin …" >&2
    (cd "$ROOT/motatool" && PATH="$cargo_dir:$PATH" "$cargo_bin" build --release)
    [[ -x "$rel" ]] || { echo "error: motatool build did not produce $rel" >&2; exit 1; }
    stage_motatool_binary "$rel" "$platform"
    resolve_motatool_bin "$mt_ver"
    return
  fi
  echo "error: motatool not found (init submodule: git submodule update --init motatool)" >&2
  exit 1
}

build_target() {
  local slug="$1"
  local env_name="$2"
  local out="$OUT_ROOT/$VER/$slug"
  local build_dir="$MC/.pio/build/$env_name"
  local mt=""

  echo "==> $VER  target=$slug  env=$env_name"

  assert_version_not_released "$VER"
  rm -rf "$out"
  mkdir -p "$out"

  local mota_tid pio_flags
  mota_tid="$(mota_target_id_for_env "$env_name")"
  pio_flags="${PLATFORMIO_BUILD_FLAGS:-} -DMOTA_TARGET_ID=${mota_tid}"

  (
    cd "$MC"
    export PLATFORMIO_BUILD_FLAGS="$pio_flags"
    pio run -e "$env_name"
    pio run -e "$env_name" -t create_uf2
  )

  local hex="$build_dir/firmware.hex"
  local uf2="$build_dir/firmware.uf2"
  local zip="$build_dir/firmware.zip"

  [[ -f "$hex" ]] || { echo "error: missing $hex" >&2; exit 1; }

  cp -f "$hex" "$out/firmware.hex"
  [[ -f "$uf2" ]] && cp -f "$uf2" "$out/firmware.uf2"
  [[ -f "$zip" ]] && cp -f "$zip" "$out/firmware.zip"
  write_mota_version_txt "$out" "$VER" "$BUILD_STAMP" "$GIT_SHA"

  echo "    saved $out/firmware.hex (+ uf2/zip if present)"

  if [[ "$HEX_ONLY" -eq 1 ]]; then
    echo "    (--hex-only: skipping .mota packaging)"
  else
    mt="$(motatool_bin)"
    echo "==> packaging .mota ($slug) with $mt"

    "$mt" build --fw "$out/firmware.hex" --out-dir "$out"
    echo "    full .mota → $out/"

    local base_versions=()
    if [[ -n "$BASE_VER" ]]; then
      base_versions=("$BASE_VER")
    else
      while IFS= read -r bv || [[ -n "$bv" ]]; do
        [[ -n "$bv" ]] || continue
        base_versions+=("$bv")
      done < <(list_delta_base_versions "$VER")
    fi

    local base_ver base_hex delta_out
    for base_ver in "${base_versions[@]}"; do
      if ! base_hex="$(resolve_base_hex "$slug" "$base_ver")"; then
        echo "    skip delta $base_ver → $VER ($slug): no base hex" >&2
        continue
      fi
      delta_out="$out/delta_from_${base_ver}.mota"
      echo "==> in-place delta ($slug) $base_ver → $VER"
      echo "    base: $base_hex"
      echo "    fw:   $out/firmware.hex"
      "$mt" build --base "$base_hex" --fw "$out/firmware.hex" --patch-type in-place --out "$delta_out"
      echo "    delta: $delta_out"
    done
  fi

  echo "==> done $VER/$slug"
  ls -la "$out"
}

LIST_ONLY=0
HEX_ONLY=0
VER=""
VER_EXPLICIT=0
BASE_VER=""
SELECTED=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --hex-only)
      HEX_ONLY=1
      shift
      ;;
    --list-targets)
      LIST_ONLY=1
      shift
      ;;
    --targets-file)
      [[ $# -ge 2 ]] || usage
      TARGETS_FILE="$2"
      shift 2
      ;;
    --target)
      [[ $# -ge 2 ]] || usage
      SELECTED+=("$2")
      shift 2
      ;;
    --base)
      [[ $# -ge 2 ]] || usage
      BASE_VER="$(normalize_version "$2")" || usage
      shift 2
      ;;
    -h | --help)
      usage
      ;;
    -*)
      usage
      ;;
    *)
      [[ -z "$VER" ]] || usage
      VER="$(normalize_version "$1")" || usage
      VER_EXPLICIT=1
      shift
      ;;
  esac
done

if [[ "$LIST_ONLY" -eq 1 ]]; then
  list_targets "$TARGETS_FILE"
  exit 0
fi

if [[ -z "$VER" ]]; then
  VER="$(read_firmware_version)" || usage
fi

FW_VER="$VER"
if [[ "$VER_EXPLICIT" -eq 1 ]]; then
  verify_firmware_version_sync "$FW_VER" || {
    echo "note: FIRMWARE_VERSION=$FW_VER (envycore/envyos/VERSION differs; bump on /freshen)" >&2
  }
else
  verify_firmware_version_sync "$FW_VER"
fi

load_targets "$TARGETS_FILE"

BUILD_SLUGS=()
BUILD_ENVS=()
if [[ ${#SELECTED[@]} -eq 0 ]]; then
  BUILD_SLUGS=("${TARGET_SLUGS[@]}")
  BUILD_ENVS=("${TARGET_ENVS[@]}")
else
  local_slug=""
  local_idx=""
  for local_slug in "${SELECTED[@]}"; do
    local_idx="$(target_index "$local_slug")" || {
      echo "error: unknown target '$local_slug' (see --list-targets)" >&2
      exit 1
    }
    BUILD_SLUGS+=("${TARGET_SLUGS[$local_idx]}")
    BUILD_ENVS+=("${TARGET_ENVS[$local_idx]}")
  done
fi

OUT="$OUT_ROOT/$VER"
assert_version_not_released "$VER"
if [[ ${#SELECTED[@]} -eq 0 ]]; then
  rm -rf "$OUT"
fi
mkdir -p "$OUT"
BUILD_STAMP="$(format_firmware_build_date)"
GIT_SHA="$(git_short_sha "$MC")"
FW_VER_LABEL="${FW_VER}-${GIT_SHA}"
write_mota_version_txt "$OUT" "$VER" "$BUILD_STAMP" "$GIT_SHA"

if [[ "$HEX_ONLY" -eq 1 ]]; then
  echo "mode: hex-only (no .mota)"
else
  MT="$(motatool_bin)"
  echo "motatool: $MT"
fi
echo "version: $VER  label: $FW_VER_LABEL  envycore: $GIT_SHA  build: $BUILD_STAMP"
echo "targets: ${BUILD_SLUGS[*]}"

export PLATFORMIO_BUILD_FLAGS="${PLATFORMIO_BUILD_FLAGS:-} -DFIRMWARE_VERSION='\"${FW_VER_LABEL}\"' -DFIRMWARE_BUILD_DATE='\"${BUILD_STAMP}\"'"

i=0
for i in "${!BUILD_SLUGS[@]}"; do
  build_target "${BUILD_SLUGS[$i]}" "${BUILD_ENVS[$i]}"
done

echo "==> all done $VER (${#BUILD_SLUGS[@]} target(s))"
ls -la "$OUT"
