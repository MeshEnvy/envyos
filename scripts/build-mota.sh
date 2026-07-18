#!/usr/bin/env bash
# Build firmware (+ optional .mota) for targets listed in scripts/targets.txt.
#
# Usage:
#   ./scripts/build-mota.sh                    # version from ./VERSION
#   ./scripts/build-mota.sh v0.1.1             # override version for this build
#   ./scripts/build-mota.sh --target wismesh-tag-repeater
#   ./scripts/build-mota.sh v0.1.2 --base v0.1.0
#   ./scripts/build-mota.sh --hex-only         # stock MeshCore (no EndF / OTA)
#   ./scripts/build-mota.sh --list-targets
#
# Requires: PlatformIO (`pio`). Full .mota packaging also needs motatool on PATH or ./vendor/motatool/.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MC="$ROOT/envyos"
OUT_ROOT="$ROOT/motas"
TARGETS_FILE="$ROOT/scripts/targets.txt"
# shellcheck source=scripts/version.sh
source "$ROOT/scripts/version.sh"

TARGET_SLUGS=()
TARGET_ENVS=()
TARGET_DESCS=()

usage() {
  cat >&2 <<EOF
usage: $0 [version] [--target <slug>]… [--base <version>] [--hex-only] [--targets-file <path>]
       $0 --list-targets [--targets-file <path>]

  version         Optional override; default is ./VERSION (e.g. v0.1.0 or 0.1.0)
  --target        Build one target slug (repeatable; default: all in targets file)
  --base          Optional hex base for in-place deltas (default: previous patch if present)
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
  if command -v motatool >/dev/null 2>&1; then
    echo motatool
    return
  fi
  local rel="$ROOT/vendor/motatool/target/release/motatool"
  if [[ -x "$rel" ]]; then
    echo "$rel"
    return
  fi
  if [[ -d "$ROOT/vendor/motatool" ]]; then
    local cargo_bin cargo_dir
    cargo_bin="$(find_cargo)"
    cargo_dir="$(dirname "$cargo_bin")"
    echo "building motatool (release) with $cargo_bin …" >&2
    (cd "$ROOT/vendor/motatool" && PATH="$cargo_dir:$PATH" "$cargo_bin" build --release)
    [[ -x "$rel" ]] || { echo "error: motatool build did not produce $rel" >&2; exit 1; }
    echo "$rel"
    return
  fi
  echo "error: motatool not found (install or clone into $ROOT/vendor/motatool)" >&2
  exit 1
}

resolve_base_hex() {
  local slug="$1"
  local base_ver="$2"
  local candidates=(
    "$OUT_ROOT/$base_ver/$slug/firmware.hex"
  )
  if [[ "$slug" == "wismesh-tag-repeater" ]]; then
    candidates+=(
      "$OUT_ROOT/$base_ver/repeater/firmware.hex"
      "$OUT_ROOT/$base_ver/firmware.hex"
    )
  fi
  local p
  for p in "${candidates[@]}"; do
    if [[ -f "$p" ]]; then
      printf '%s' "$p"
      return 0
    fi
  done
  return 1
}

build_target() {
  local slug="$1"
  local env_name="$2"
  local out="$OUT_ROOT/$VER/$slug"
  local build_dir="$MC/.pio/build/$env_name"
  local mt=""

  echo "==> $VER  target=$slug  env=$env_name"

  rm -rf "$out"
  mkdir -p "$out"

  (
    cd "$MC"
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
  printf '%s\n' "$VER" >"$out/version.txt"

  echo "    saved $out/firmware.hex (+ uf2/zip if present)"

  if [[ "$HEX_ONLY" -eq 1 ]]; then
    echo "    (--hex-only: skipping .mota packaging)"
  else
    mt="$(motatool_bin)"
    echo "==> packaging .mota ($slug) with $mt"

    "$mt" build --fw "$out/firmware.hex" --out-dir "$out"
    echo "    full .mota → $out/"

    local base_ver="$BASE_VER"
    if [[ -z "$base_ver" ]]; then
      PREV="$(previous_patch_version "$VER" || true)"
      if [[ -n "$PREV" ]] && resolve_base_hex "$slug" "$PREV" >/dev/null; then
        base_ver="$PREV"
      fi
    fi

    if [[ -n "$base_ver" ]]; then
      local base_hex
      base_hex="$(resolve_base_hex "$slug" "$base_ver")" || {
        echo "error: need base hex for $slug delta ($base_ver) — build $base_ver first or pass --base" >&2
        exit 1
      }
      local delta_out="$out/delta_from_${base_ver}.mota"
      echo "==> in-place delta ($slug) $base_ver → $VER"
      echo "    base: $base_hex"
      echo "    fw:   $out/firmware.hex"
      "$mt" build --base "$base_hex" --fw "$out/firmware.hex" --patch-type in-place --out "$delta_out"
      echo "    delta: $delta_out"
    fi
  fi

  echo "==> done $VER/$slug"
  ls -la "$out"
}

LIST_ONLY=0
HEX_ONLY=0
VER=""
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
      shift
      ;;
  esac
done

if [[ "$LIST_ONLY" -eq 1 ]]; then
  list_targets "$TARGETS_FILE"
  exit 0
fi

if [[ -z "$VER" ]]; then
  VER="$(read_version_file)" || usage
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
if [[ ${#SELECTED[@]} -eq 0 ]]; then
  rm -rf "$OUT"
fi
mkdir -p "$OUT"
printf '%s\n' "$VER" >"$OUT/version.txt"

if [[ "$HEX_ONLY" -eq 1 ]]; then
  echo "mode: hex-only (no .mota)"
else
  MT="$(motatool_bin)"
  echo "motatool: $MT"
fi
echo "targets: ${BUILD_SLUGS[*]}"

export PLATFORMIO_BUILD_FLAGS="${PLATFORMIO_BUILD_FLAGS:-} -DFIRMWARE_VERSION='\"${VER}\"'"

i=0
for i in "${!BUILD_SLUGS[@]}"; do
  build_target "${BUILD_SLUGS[$i]}" "${BUILD_ENVS[$i]}"
done

echo "==> all done $VER (${#BUILD_SLUGS[@]} target(s))"
ls -la "$OUT"
