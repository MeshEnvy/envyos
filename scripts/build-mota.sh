#!/usr/bin/env bash
# Build firmware (+ optional .mota) for targets listed in scripts/targets.txt.
#
# Usage:
#   ./scripts/build-mota.sh                    # firmware version from ./ENVYOS_VERSIONS
#   ./scripts/build-mota.sh v0.1.1             # override firmware version (output dir + device ver)
#   ./scripts/build-mota.sh --target wismesh-tag-repeater
#   ./scripts/build-mota.sh --debug            # *-debug twins only
#   ./scripts/build-mota.sh --release          # field slugs only (skip *-debug)
#   ./scripts/build-mota.sh v0.1.2 --base v0.1.0   # delta from one base only
#   ./scripts/build-mota.sh --hex-only         # stock MeshCore (no EndF / OTA)
#   ./scripts/build-mota.sh --list-targets
#
# Requires: PlatformIO (`pio`). Full .mota packaging also needs ./motatool/ (built via cargo if needed).

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/version.sh
source "$ROOT/scripts/version.sh"
MC="$ENVYCORE_ROOT"
TARGETS_FILE="$ROOT/scripts/targets.txt"

TARGET_SLUGS=()
TARGET_ENVS=()
TARGET_DESCS=()

default_mota_jobs() {
  local n
  n="$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || true)"
  if [[ -n "$n" && "$n" =~ ^[0-9]+$ && "$n" -gt 0 ]]; then
    printf '%s' "$n"
    return
  fi
  printf '%s' 4
}

MOTA_JOBS_LIMIT=0
MOTA_POOL_FAILED=0
MOTA_POOL_PIDS=()

reap_mota_pool() {
  local i
  if ((${#MOTA_POOL_PIDS[@]} == 0)); then
    return 0
  fi
  for i in "${!MOTA_POOL_PIDS[@]}"; do
    if ! kill -0 "${MOTA_POOL_PIDS[$i]}" 2>/dev/null; then
      wait "${MOTA_POOL_PIDS[$i]}" || MOTA_POOL_FAILED=1
      unset "MOTA_POOL_PIDS[$i]"
    fi
  done
  if ((${#MOTA_POOL_PIDS[@]} > 0)); then
    MOTA_POOL_PIDS=("${MOTA_POOL_PIDS[@]}")
  else
    MOTA_POOL_PIDS=()
  fi
}

wait_mota_pool_slot() {
  while ((${#MOTA_POOL_PIDS[@]} >= MOTA_JOBS_LIMIT)); do
    reap_mota_pool
    if ((${#MOTA_POOL_PIDS[@]} >= MOTA_JOBS_LIMIT)); then
      sleep 0.05
    fi
  done
}

spawn_mota_job() {
  wait_mota_pool_slot
  "$@" &
  MOTA_POOL_PIDS+=($!)
}

drain_mota_pool() {
  local pid
  reap_mota_pool
  if ((${#MOTA_POOL_PIDS[@]} > 0)); then
    for pid in "${MOTA_POOL_PIDS[@]}"; do
      wait "$pid" || MOTA_POOL_FAILED=1
    done
  fi
  MOTA_POOL_PIDS=()
  return "$MOTA_POOL_FAILED"
}

usage() {
  cat >&2 <<EOF
usage: $0 [version] [--target <slug>]… [--release|--debug] [--base <version>] [--hex-only] [--targets-file <path>]
       $0 [--mota-jobs <n>] [--delta-jobs <n>] --list-targets [--targets-file <path>]

  version         Optional override for ENVYOS_VERSIONS firmware (output dir + -DFIRMWARE_VERSION). Never distro.
  --target        Build one target slug (repeatable; default: all targets in targets.txt)
  --release       With no --target: field slugs only (skip *-debug)
  --debug         With no --target: *-debug twins only (does not wipe field artifacts)
  --base          Build delta from one base only (default: all prior versions with base hex)
  --mota-jobs     Max concurrent motatool jobs — full + delta (default: \$ENVYOS_MOTA_JOBS or CPU count)
  --delta-jobs    Alias for --mota-jobs
  --hex-only      Build hex/uf2 only — skip .mota packaging (stock MeshCore without EndF/OTA)
  --targets-file  Target map (default: scripts/targets.txt)
  --list-targets  Print configured targets and exit

examples:
  $0
  $0 v0.1.1
  $0 --target wismesh-tag-repeater --target rak4631-repeater
  $0 --release
  $0 --debug
  $0 --target rak4631-repeater-slim-debug
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
  printf '%-40s  %-42s  %s\n' "SLUG" "PLATFORMIO_ENV" "DESCRIPTION"
  for i in "${!TARGET_SLUGS[@]}"; do
    printf '%-40s  %-42s  %s\n' "${TARGET_SLUGS[$i]}" "${TARGET_ENVS[$i]}" "${TARGET_DESCS[$i]}"
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

delta_base_versions_for_build() {
  if [[ -n "$BASE_VER" ]]; then
    printf '%s\n' "$BASE_VER"
    return
  fi
  list_delta_base_versions "$VER"
}

collect_delta_jobs_for_slug() {
  local slug="$1"
  local base_ver base_hex

  while IFS= read -r base_ver || [[ -n "$base_ver" ]]; do
    [[ -n "$base_ver" ]] || continue
    if ! base_hex="$(resolve_base_image "$slug" "$base_ver")"; then
      echo "    skip delta $base_ver → $VER ($slug): no base hex" >&2
      continue
    fi
    printf '%s|%s|%s\n' "$slug" "$base_ver" "$base_hex"
  done < <(delta_base_versions_for_build)
}

run_full_mota_job() {
  local mt="$1"
  local slug="$2"
  local out="$3"
  local fw_sem="${FW_VER#v}"
  local fw_image

  fw_image="$(resolve_firmware_image_in_dir "$out" "$slug" "$VER")" || {
    echo "error: no firmware image in $out" >&2
    return 1
  }

  echo "==> full .mota ($slug)"
  "$mt" build --fw "$fw_image" --fw-version "$fw_sem" \
    --name-stem "fw-${slug}-${VER}" --out-dir "$out"
}

run_one_delta_job() {
  local mt="$1"
  local job="$2"
  local slug base_ver base_hex fw_hex out

  IFS='|' read -r slug base_ver base_hex <<<"$job"
  out="$(firmware_slug_dir "$VER" "$slug")"
  fw_hex="$(resolve_firmware_image_in_dir "$out" "$slug" "$VER")" || {
    echo "error: no firmware image for $slug $VER" >&2
    return 1
  }
  echo "==> in-place delta ($slug) $base_ver → $VER"
  echo "    base: $base_hex"
  echo "    fw:   $fw_hex"
  "$mt" build --base "$base_hex" --fw "$fw_hex" --fw-version "${FW_VER#v}" \
    --patch-type in-place --name-stem "fw-${slug}-${VER}" --base-version "$base_ver" \
    --out-dir "$out"
}

queue_mota_jobs_for_slug() {
  local mt="$1"
  local slug="$2"
  local out="$3"
  local job

  spawn_mota_job run_full_mota_job "$mt" "$slug" "$out"
  while IFS= read -r job || [[ -n "$job" ]]; do
    [[ -n "$job" ]] || continue
    spawn_mota_job run_one_delta_job "$mt" "$job"
  done < <(collect_delta_jobs_for_slug "$slug")
}

motatool_bin() {
  local mt_ver path
  mt_ver="$(read_motatool_version)"
  verify_motatool_version_sync "$mt_ver"

  if path="$(resolve_motatool_bin "$mt_ver" 2>/dev/null)"; then
    echo "$path"
    return
  fi

  local rel="$MOTATOOL_ROOT/target/release/motatool"
  if [[ -x "$rel" ]]; then
    stage_motatool_binary "$rel" "$(host_motatool_platform_slug)"
    resolve_motatool_bin "$mt_ver"
    return
  fi
  if [[ -d "$MOTATOOL_ROOT" ]]; then
    local cargo_bin cargo_dir platform
    cargo_bin="$(find_cargo)"
    cargo_dir="$(dirname "$cargo_bin")"
    platform="$(host_motatool_platform_slug)"
    echo "building motatool (release) for $platform with $cargo_bin …" >&2
    (cd "$MOTATOOL_ROOT" && PATH="$cargo_dir:$PATH" "$cargo_bin" build --release)
    [[ -x "$rel" ]] || { echo "error: motatool build did not produce $rel" >&2; exit 1; }
    stage_motatool_binary "$rel" "$platform"
    resolve_motatool_bin "$mt_ver"
    return
  fi
  echo "error: motatool not found (init submodule: git submodule update --init motatool)" >&2
  exit 1
}

build_target_firmware() {
  local slug="$1"
  local env_name="$2"
  local out
  out="$(firmware_slug_dir "$VER" "$slug")"
  local build_dir="$MC/.pio/build/$env_name"
  local mota_tid identity_cpp

  echo "==> $VER  target=$slug  env=$env_name"

  assert_version_not_released "$VER"
  rm -rf "$out"
  mkdir -p "$out"

  mota_tid="$(mota_target_id_for_env "$env_name")"
  identity_cpp="$MC/src/helpers/FirmwareIdentity.generated.cpp"
  python3 "$MC/tools/mota/gen_firmware_identity.py" \
    --out "$identity_cpp" \
    --version "$FW_VER_LABEL" \
    --build-date "$BUILD_STAMP" \
    --target-id "$mota_tid" \
    --pio-env "$env_name"

  (
    cd "$MC"
    export ENVYOS_FIRMWARE_VERSION="$FW_VER_LABEL"
    export ENVYOS_FIRMWARE_BUILD_DATE="$BUILD_STAMP"
    export ENVYOS_MOTA_TARGET_ID="$mota_tid"
    pio run -e "$env_name"
    pio run -e "$env_name" -t create_uf2
  )

  local hex="$build_dir/firmware.hex"
  local uf2="$build_dir/firmware.uf2"
  local zip="$build_dir/firmware.zip"
  local dest_hex dest_uf2 dest_zip

  [[ -f "$hex" ]] || { echo "error: missing $hex" >&2; exit 1; }

  dest_hex="$out/$(firmware_artifact_name "$slug" "$VER" hex)"
  dest_uf2="$out/$(firmware_artifact_name "$slug" "$VER" uf2)"
  dest_zip="$out/$(firmware_artifact_name "$slug" "$VER" zip)"
  cp -f "$hex" "$dest_hex"
  [[ -f "$uf2" ]] && cp -f "$uf2" "$dest_uf2"
  [[ -f "$zip" ]] && cp -f "$zip" "$dest_zip"
  write_mota_version_txt "$out" "$VER" "$BUILD_STAMP" "$GIT_SHA"

  echo "    saved $dest_hex"

  if [[ "$HEX_ONLY" -eq 1 ]]; then
    echo "    (--hex-only: skipping .mota packaging)"
  else
    echo "    queue motatool jobs for $slug"
    queue_mota_jobs_for_slug "$MT" "$slug" "$out"
  fi

  echo "==> pio done $VER/$slug"
}

LIST_ONLY=0
HEX_ONLY=0
TARGET_SET=all
VER=""
VER_EXPLICIT=0
BASE_VER=""
MOTA_JOBS="${ENVYOS_MOTA_JOBS:-${ENVYOS_DELTA_JOBS:-}}"
SELECTED=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --hex-only)
      HEX_ONLY=1
      shift
      ;;
    --debug)
      [[ "$TARGET_SET" == release ]] && {
        echo "error: --debug and --release are mutually exclusive" >&2
        exit 1
      }
      TARGET_SET=debug
      shift
      ;;
    --release)
      [[ "$TARGET_SET" == debug ]] && {
        echo "error: --debug and --release are mutually exclusive" >&2
        exit 1
      }
      TARGET_SET=release
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
    --mota-jobs | --delta-jobs)
      [[ $# -ge 2 ]] || usage
      MOTA_JOBS="$2"
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
  local_idx=""
  for local_idx in "${!TARGET_SLUGS[@]}"; do
    if [[ "$TARGET_SET" == release ]]; then
      is_debug_target_slug "${TARGET_SLUGS[$local_idx]}" && continue
    elif [[ "$TARGET_SET" == debug ]]; then
      is_debug_target_slug "${TARGET_SLUGS[$local_idx]}" || continue
    fi
    BUILD_SLUGS+=("${TARGET_SLUGS[$local_idx]}")
    BUILD_ENVS+=("${TARGET_ENVS[$local_idx]}")
  done
  [[ ${#BUILD_SLUGS[@]} -gt 0 ]] || {
    echo "error: no matching targets in $TARGETS_FILE" >&2
    exit 1
  }
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

OUT="$(firmware_bench_root "$VER")"
OUT_ROOT="$OUT"
assert_version_not_released "$VER"
if [[ ${#SELECTED[@]} -eq 0 && "$TARGET_SET" != debug ]]; then
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
  if [[ -z "$MOTA_JOBS" ]]; then
    MOTA_JOBS="$(default_mota_jobs)"
  elif ! [[ "$MOTA_JOBS" =~ ^[0-9]+$ ]] || [[ "$MOTA_JOBS" -lt 1 ]]; then
    echo "error: --mota-jobs must be a positive integer (got: $MOTA_JOBS)" >&2
    exit 1
  fi
  MOTA_JOBS_LIMIT="$MOTA_JOBS"
  echo "mota jobs: $MOTA_JOBS_LIMIT (full + delta, pipelined after each pio build)"
fi
echo "version: $VER  label: $FW_VER_LABEL  envycore: $GIT_SHA  build: $BUILD_STAMP"
if [[ ${#SELECTED[@]} -eq 0 ]]; then
  echo "target set: $TARGET_SET"
fi
echo "targets: ${BUILD_SLUGS[*]}"

export ENVYOS_FIRMWARE_VERSION="$FW_VER_LABEL"
export ENVYOS_FIRMWARE_BUILD_DATE="$BUILD_STAMP"

if [[ "$HEX_ONLY" -eq 0 ]]; then
  ensure_firmware_bases_for_build "$VER" "${BUILD_SLUGS[@]}"
fi

i=0
for i in "${!BUILD_SLUGS[@]}"; do
  build_target_firmware "${BUILD_SLUGS[$i]}" "${BUILD_ENVS[$i]}"
done

if [[ "$HEX_ONLY" -eq 0 ]]; then
  echo "==> waiting for motatool jobs"
  if ! drain_mota_pool; then
    echo "error: one or more motatool jobs failed" >&2
    exit 1
  fi
fi

echo "==> all done $VER (${#BUILD_SLUGS[@]} target(s))"
ls -la "$OUT"
maybe_populate_distro_release
