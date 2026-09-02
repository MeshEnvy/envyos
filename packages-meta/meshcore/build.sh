#!/usr/bin/env bash
# meshcore recipe — build firmware (+ optional .mota) for targets in scripts/targets.txt.
#
# Usage (via ./envyos build meshcore [args…]):
#   ./envyos build meshcore                    # pin from MANIFEST.json releases.next
#   ./envyos build meshcore --target wismesh-tag-repeater
#   ./envyos build meshcore --debug            # *-debug twins only
#   ./envyos build meshcore --release          # field slugs only (skip *-debug)
#   ./envyos build meshcore --base v0.1.0      # delta from one base only
#   ./envyos build meshcore --hex-only         # stock MeshCore (no EndF / OTA)
#   ./envyos build meshcore --list-targets
# Slot is git branch or ENVYOS_BUILD_SLOT. Pin is never a CLI version arg.
#
# Requires: PlatformIO (`pio`). Full .mota packaging also needs staged motatool.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=../../scripts/version.sh
source "$ROOT/scripts/version.sh"
MC="$MESHCORE_ROOT"
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
usage: $0 [--target <slug>]… [--release|--debug] [--base <version>] [--hex-only] [--targets-file <path>]
       $0 [--mota-jobs <n>] [--delta-jobs <n>] --list-targets [--targets-file <path>]

  Pin is MANIFEST.json releases.next (packages-meta/meshcore/VERSION). Slot is git branch or ENVYOS_BUILD_SLOT.
  --target        Build one target slug (repeatable; default: all targets in targets.txt)
  --release       With no --target: field slugs only (skip *-debug)
  --debug         With no --target: *-debug twins only (does not wipe field artifacts)
  --base          Build delta from one base only (default: all prior versions with base hex)
  --mota-jobs     Max concurrent motatool jobs — full + delta (default: \$ENVYOS_MOTA_JOBS or CPU count)
  --delta-jobs    Alias for --mota-jobs
  --hex-only      Build hex/uf2 only — skip .mota packaging (stock MeshCore without EndF/OTA)
  --clean         Wipe bench output trees and force full rebuild (default: incremental)
  --targets-file  Target map (default: scripts/targets.txt)
  --list-targets  Print configured targets and exit

examples:
  $0
  $0 --target wismesh-tag-repeater --target rak4631-repeater
  $0 --release
  $0 --debug
  $0 --target rak4631-repeater-slim-debug
  $0 --base v0.1.0
  $0 --hex-only
  $0 --list-targets
  ENVYOS_BUILD_SLOT=heltec-bl-test $0 --target heltec-t096-repeater-slim
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
  local fw_image

  fw_image="$(resolve_firmware_image_in_dir "$out" "$slug" "$VER")" || {
    echo "error: no firmware image in $out" >&2
    return 1
  }

  echo "==> full .mota ($slug)"
  "$mt" build --fw "$fw_image" --fw-version "$FW_STAMP" \
    --name-stem "$(mota_name_stem "$slug" "$VER")" --out-dir "$out"
}

run_one_delta_job() {
  local mt="$1"
  local job="$2"
  local slug base_ver base_hex fw_hex out

  IFS='|' read -r slug base_ver base_hex <<<"$job"
  out="$(firmware_slug_dir "$DISTRO_VER" "$VER" "$slug")"
  fw_hex="$(resolve_firmware_image_in_dir "$out" "$slug" "$VER")" || {
    echo "error: no firmware image for $slug $VER" >&2
    return 1
  }
  echo "==> in-place delta ($slug) $base_ver → $VER"
  echo "    base: $base_hex"
  echo "    fw:   $fw_hex"
  "$mt" build --base "$base_hex" --fw "$fw_hex" --fw-version "$FW_STAMP" \
    --patch-type in-place --name-stem "$(mota_name_stem "$slug" "$VER")" \
    --out-dir "$out"
}

delta_mota_present() {
  local dir=$1 slug=$2 ver=$3 base_ver=$4
  local f base_label
  base_label="${base_ver#v}"
  shopt -s nullglob
  for f in \
    "$dir"/fw-"${slug}"-"${ver}"-delta-*.mota \
    "$dir"/fw-"${slug}"-*-delta-*.mota \
    "$dir"/meshcore-"${slug}"-"${ver}"-delta-from-"${base_ver}"-*.mota \
    "$dir"/meshcore-"${slug}"-"${ver}"-delta-from-"${base_label}"-*.mota \
    "$dir"/meshcore-"${slug}"-delta-from-"${base_ver}"-*.mota \
    "$dir"/meshcore-"${slug}"-delta-from-"${base_label}"-*.mota; do
    [[ -f "$f" ]] && { shopt -u nullglob; return 0; }
  done
  shopt -u nullglob
  return 1
}

# Incremental skip is valid only when slug dir has one full .mota (not stale remakes).
slug_has_single_full_mota() {
  local slug="$1"
  local dir=$2
  local f count=0
  shopt -s nullglob
  for f in "$dir"/*-full-*.mota "$dir"/*_full_*.mota; do
    [[ -f "$f" ]] || continue
    ((count++)) || true
    if ((count > 1)); then
      shopt -u nullglob
      return 1
    fi
  done
  shopt -u nullglob
  ((count == 1))
}

# Hex-unchanged skip must not drop --base / newly visible pins.
slug_missing_delta_mota() {
  local slug="$1"
  local job base_ver base_hex out
  out="$(firmware_slug_dir "$DISTRO_VER" "$VER" "$slug")"
  while IFS= read -r job || [[ -n "$job" ]]; do
    [[ -n "$job" ]] || continue
    IFS='|' read -r _ base_ver base_hex <<<"$job"
    if ! delta_mota_present "$out" "$slug" "$VER" "$base_ver"; then
      return 0
    fi
  done < <(collect_delta_jobs_for_slug "$slug")
  return 1
}

queue_mota_jobs_for_slug() {
  local mt="$1"
  local slug="$2"
  local out="$3"
  local job

  rm -f "$out"/*.mota
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
  if path="$(resolve_motatool_bin "$mt_ver")"; then
    echo "$path"
    return
  fi
  echo "error: motatool not staged for $(host_motatool_platform_slug) — run ./envyos build motatool (or full ./envyos build)" >&2
  exit 1
}

build_target_firmware() {
  local slug="$1"
  local env_name="$2"
  local out
  out="$(firmware_slug_dir "$DISTRO_VER" "$VER" "$slug")"
  local build_dir="$MC/.pio/build/$env_name"
  local identity_gen="$MC/tools/mota/gen_firmware_identity.py"
  local mota_tid identity_cpp dest_hex dest_uf2 dest_zip hex uf2 zip hex_sha cached_sha

  echo "==> $VER  target=$slug  env=$env_name"

  assert_version_not_released "$VER"
  if ((CLEAN == 1)); then
    rm -rf "$out"
  fi
  mkdir -p "$out"

  dest_hex="$out/$(firmware_artifact_name "$slug" "$VER" hex)"
  dest_uf2="$out/$(firmware_artifact_name "$slug" "$VER" uf2)"
  dest_zip="$out/$(firmware_artifact_name "$slug" "$VER" zip)"
  mkdir -p "$out"
  cached_sha=""
  if [[ -f "$out/.hex-sha256" ]]; then
    cached_sha="$(tr -d '[:space:]' <"$out/.hex-sha256")"
  fi

  if [[ -f "$identity_gen" ]]; then
    mota_tid="$(mota_target_id_for_env "$env_name")"
    identity_cpp="$MC/src/helpers/FirmwareIdentity.generated.cpp"
    python3 "$identity_gen" \
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
  else
    (
      cd "$MC"
      export PLATFORMIO_BUILD_FLAGS="${PLATFORMIO_BUILD_FLAGS:-} -DFIRMWARE_VERSION='\"${FW_STAMP}\"' -DFIRMWARE_BUILD_DATE='\"${BUILD_STAMP}\"'"
      pio run -e "$env_name"
      pio run -e "$env_name" -t create_uf2
    )
  fi

  hex="$build_dir/firmware.hex"
  uf2="$build_dir/firmware.uf2"
  zip="$build_dir/firmware.zip"

  [[ -f "$hex" ]] || { echo "error: missing $hex" >&2; exit 1; }

  cp -f "$hex" "$dest_hex"
  [[ -f "$uf2" ]] && cp -f "$uf2" "$dest_uf2"
  [[ -f "$zip" ]] && cp -f "$zip" "$dest_zip"
  write_mota_version_txt "$out" "$VER" "$BUILD_STAMP" "$GIT_SHA"

  hex_sha="$(shasum -a 256 "$dest_hex" | awk '{print $1}')"
  printf '%s\n' "$hex_sha" >"$out/.hex-sha256"

  echo "    saved $dest_hex"

  if [[ "$HEX_ONLY" -eq 1 ]]; then
    echo "    (--hex-only: skipping .mota packaging)"
  elif [[ "$CLEAN" -eq 0 && -n "$cached_sha" && "$cached_sha" == "$hex_sha" ]] &&
    ! slug_missing_delta_mota "$slug" && slug_has_single_full_mota "$slug" "$out"; then
    echo "    skip motatool ($slug): firmware hex unchanged (use --clean to repack)"
  else
    echo "    queue motatool jobs for $slug"
    queue_mota_jobs_for_slug "$MT" "$slug" "$out"
  fi

  echo "==> pio done $VER/$slug"
}

LIST_ONLY=0
HEX_ONLY=0
CLEAN=0
TARGET_SET=all
BASE_VER=""
MOTA_JOBS="${ENVYOS_MOTA_JOBS:-${ENVYOS_DELTA_JOBS:-}}"
SELECTED=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --hex-only)
      HEX_ONLY=1
      shift
      ;;
    --clean)
      CLEAN=1
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
      BASE_VER="$(normalize_package_version "$2")" || usage
      shift 2
      ;;
    -h | --help)
      usage
      ;;
    -*)
      usage
      ;;
    *)
      echo "error: unexpected argument '$1' (meshcore pin is releases.next; slot is git branch or ENVYOS_BUILD_SLOT)" >&2
      usage
      ;;
  esac
done

if [[ "$LIST_ONLY" -eq 1 ]]; then
  list_targets "$TARGETS_FILE"
  exit 0
fi

VER="$(read_firmware_version)" || usage
FW_VER="$VER"
FW_STAMP="$(firmware_stamp_from_version "$FW_VER")"

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

DISTRO_VER="$(read_bench_tree_key)"
OUT="$(firmware_bench_root "$DISTRO_VER" "$FW_VER")"
assert_version_not_released "$FW_VER"
export DISTRO_VER
OUT_ROOT="$OUT"
if ((CLEAN == 1)); then
  if [[ ${#SELECTED[@]} -eq 0 && "$TARGET_SET" != debug ]]; then
    rm -rf "$OUT"
  fi
fi
mkdir -p "$OUT"
GIT_SHA="$(git_short_sha "$MC")"
BUILD_STAMP="$(format_firmware_build_date "$MC")"
if ((CLEAN == 0)); then
  echo "incremental: build stamp $BUILD_STAMP (meshcore $GIT_SHA; PlatformIO cache in $MC/.pio/build/)"
fi
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
echo "version: $VER  stamp: $FW_STAMP  label: $FW_VER_LABEL  meshcore: $GIT_SHA  build: $BUILD_STAMP"
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
